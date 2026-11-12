package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"strings"
	"sync"
	"time"
	"unicode"
	"unicode/utf8"
)

const reconnectGrace = 20 * time.Second
const roomIdleLimit = 30 * time.Minute
const inputTimeout = 350 * time.Millisecond
const clientMessageLimit = 100
const clientActionLimit = 8
const socketHeartbeatInterval = 10 * time.Second
const roomTransportIdle = socketHeartbeatInterval + 2*time.Second

// Keep kick tombstones beyond the entire reconnect window, even if the removal
// notification was lost. This is not an IP/account ban; fresh manual joins work.
const kickNoticeTTL = 2 * time.Minute
const maxKickNotices = 1024

type Player struct {
	Away   *MatchTravel // Reserved in a private lobby while playing a queue match.
	Return *MatchTravel // Only present on the travelling match identity.

	ChatTokens     float64
	ChatAt         time.Time
	Spectating     bool    // A room member without a combat seat.
	Controller     *Player // Local P2 controller may itself be spectating.
	spectatorColor string  // Preserve automatic FFA paint while the combat seat is absent.

	Kind                    string // Empty/human = remote pilot; local = second keyboard pilot; bot = server AI.
	Owner                   int    // Primary pilot whose socket controls a local pilot.
	ColorIndex              *int   // Optional FFA palette identity; owner-scoped for online humans.
	Team                    int    // 0 = individual free-for-all; 1..4 = shared side.
	Difficulty              string
	ID                      int
	Member                  uint64 // Public seat-incarnation ID; never a credential.
	Name, Token             string
	PublicToken             string `json:"-"` // Durable online callsign owner, sent only to this controller.
	Client                  *Client
	Ready                   bool
	Input                   Input
	FirePending             bool // Coalesce fire edges until the next tick; never replay a backlog.
	InputAt, DisconnectedAt time.Time
}
type Room struct {
	Queue *QueueTicket
	Match *QueueMatch

	Chat             []ChatMessage
	OpponentChat     []ChatMessage
	NextChat         uint64
	NextOpponentChat uint64
	Code             string
	Host             int
	Players          [maxTanks]*Player
	Spectators       map[int]*Player
	NextViewerID     int
	RoleVersion      int
	Game             *Game
	LastAction       time.Time
	NextMember       uint64
	Kicked           map[[32]byte]time.Time

	infinityActive     bool
	infinityPublic     bool
	infinityGeneration uint64

	state      stateScratch // reusable snapshot buffers; encoded before reuse
	stateDirty bool         // Idle snapshots are sent on room changes.
}
type Client struct {
	callsignConflicts     []callsignConflict // Admission-only metadata before the joined read loop.
	onlineOwnerToken      string             // Durable owner retained across room transitions; guarded by Hub.mu.
	ws                    *wsConn
	sourceIP              string // IPv4 address or IPv6 prefix fixed at admission.
	requireVersion        bool   // Real WebSocket clients must complete the version handshake.
	versionOK             bool
	send                  chan []byte
	updates               chan snapshotFrame // Replaceable snapshots; reliable messages stay in send.
	done                  chan struct{}
	stopOnce              sync.Once
	room                  *Room // Everything below is guarded by Hub.mu.
	player                *Player
	mapGeneration         int
	msgWindow             time.Time
	msgCount, actionCount int
	secondaryInputCount   int
	born                  time.Time
	kickedRoom            string // Terminal for this socket, protected by Hub.mu.
}

func (c *Client) stop() {
	c.stopOnce.Do(func() {
		close(c.done)
		if c.ws != nil {
			c.ws.close()
		}
	})
}
func encodePacket(v any) ([]byte, bool) { data, err := json.Marshal(v); return data, err == nil }
func (c *Client) enqueue(v any) bool {
	data, ok := encodePacket(v)
	if !ok {
		return false
	}
	return c.enqueueBytes(data)
}
func (c *Client) enqueueBytes(data []byte) bool {
	select {
	case <-c.done:
		return false
	default:
	}
	select {
	case c.send <- data:
		return true
	default:
		c.stop()
		return false
	}
}

// Keep only the newest replaceable snapshot if a connection falls behind.
// Maze-bearing snapshots use the reliable queue so coalescing cannot drop a map.
func (c *Client) enqueueState(v any, reliable bool) bool {
	data, ok := encodePacket(v)
	if !ok {
		return false
	}
	frame := snapshotFrame{data: data}
	if !reliable && c.supportsSnapshotDeflate() {
		frame = compressSnapshot(data)
	}
	return c.enqueueStateFrame(frame, reliable)
}
func (c *Client) supportsSnapshotDeflate() bool {
	return c.updates != nil && c.ws != nil && c.ws.deflate
}
func (c *Client) enqueueStateFrame(frame snapshotFrame, reliable bool) bool {
	if c.updates == nil {
		return c.enqueueBytes(frame.data)
	}
	select {
	case <-c.done:
		return false
	default:
	}
	if reliable {
		select {
		case <-c.updates:
		default:
		}
		return c.enqueueBytes(frame.data)
	}
	select {
	case <-c.updates:
	default:
	}
	select {
	case c.updates <- frame:
		return true
	default:
		return false
	}
}
func (c *Client) writeLoop() {
	defer c.stop()
	heartbeat := time.NewTicker(socketHeartbeatInterval)
	defer heartbeat.Stop()
	for {
		// Reliable room/world/control messages precede replaceable snapshots.
		select {
		case <-c.done:
			return
		case msg := <-c.send:
			if err := c.ws.writeFrame(1, msg); err != nil {
				return
			}
			continue
		default:
		}
		select {
		case <-c.done:
			return
		case msg := <-c.updates:
			flags := byte(1)
			if msg.compressed {
				flags |= wsCompressed
			}
			if err := c.ws.writeFrame(flags, msg.data); err != nil {
				return
			}
		case msg := <-c.send:
			if err := c.ws.writeFrame(1, msg); err != nil {
				return
			}
		case <-heartbeat.C:
			if err := c.ws.writeFrame(9, []byte("leqra")); err != nil {
				return
			}
		}
	}
}

type Hub struct {
	callsigns              *onlineCallsignRegistry
	resumeRoutes           map[resumeRouteKey]resumeRoute
	publicInfinityRequests map[*Room]*Client

	queues                         map[uint64]*QueueTicket
	nextQueueID                    uint64
	nextQueueScan, nextQueueStatus time.Time

	mu       sync.Mutex
	rooms    map[string]*Room
	clients  map[*Client]bool
	maxRooms int
	closed   bool
}

func newHub(maxRooms int) *Hub {
	return &Hub{callsigns: newOnlineCallsignRegistry(), rooms: map[string]*Room{}, clients: map[*Client]bool{}, maxRooms: maxRooms, queues: map[uint64]*QueueTicket{}}
}
func randomString(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}
func roomCode() (string, error) {
	const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // 32 symbols, no modulo bias.
	b := make([]byte, 6)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	for i := range b {
		b[i] = chars[int(b[i])%len(chars)]
	}
	return string(b), nil
}
func cleanCallsign(name string) string {
	var out []rune
	for _, r := range strings.TrimSpace(name) {
		if unicode.IsLetter(r) || unicode.IsDigit(r) || r == ' ' || r == '_' || r == '-' {
			out = append(out, r)
		}
		if len(out) >= 16 {
			break
		}
	}
	return strings.Join(strings.Fields(string(out)), " ")
}
func cleanName(name string) string {
	s := cleanCallsign(name)
	if s == "" {
		s = "Player 1"
	}
	return s
}

// Room names are arbitrary single-line UTF-8 text. A bounded length prevents
// unbounded keys/URLs; spaces, punctuation, emoji and non-Latin scripts are valid.
const maxRoomRunes = 128

func cleanCode(s string) string {
	s = strings.TrimFunc(s, func(r rune) bool { return unicode.IsSpace(r) || r == '\uFEFF' })
	// Keep the old random-code invitations case-insensitive. Other names retain
	// their exact case and spelling; never strip punctuation or URL characters.
	upper := strings.ToUpper(s)
	legacy := len(s) == 6 && len(upper) == 6
	for _, r := range upper {
		if !strings.ContainsRune("ABCDEFGHJKLMNPQRSTUVWXYZ23456789", r) {
			legacy = false
			break
		}
	}
	if legacy {
		return upper
	}
	return s
}
func validCode(s string) bool {
	if !utf8.ValidString(s) || s == "" || utf8.RuneCountInString(s) > maxRoomRunes {
		return false
	}
	visible := false
	for _, r := range s {
		if unicode.IsControl(r) || r == '\u2028' || r == '\u2029' {
			return false
		}
		if !unicode.IsSpace(r) && !unicode.Is(unicode.Cf, r) {
			visible = true
		}
	}
	return visible
}
func roomError(code, message string) map[string]any {
	return map[string]any{"type": "error", "code": code, "message": message}
}

func versionError() map[string]any {
	v := roomError("version_mismatch", fmt.Sprintf("This leqra page does not match the server. Reload the page to update to v%s.", version))
	v["action"] = "version"
	v["serverVersion"] = version
	v["protocol"] = protocolVersion
	return v
}
func (h *Hub) addClient(c *Client) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.closed || len(h.clients) >= h.maxRooms*(maxTanks+maxSpectators)+32 {
		return false
	}
	h.clients[c] = true
	return true
}
func (h *Hub) removeClient(c *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.clients, c)
	p, r := c.player, c.room
	if p == nil || r == nil || p.Client != c {
		return
	}
	h.detachController(r, p, time.Now())
	h.electHost(r)
	h.broadcastRoom(r)
}

func (h *Hub) detachController(r *Room, p *Player, now time.Time) {
	if r.Queue != nil && r.Queue.involves(p) {
		h.cancelQueue(r, "A party member disconnected. Rejoin the queue when everyone is connected.")
	}
	p.Client = nil
	p.Ready = false
	if r.Match != nil && r.Match.Rematch != nil {
		delete(r.Match.Rematch, p.Member)
	}
	for _, other := range r.members() {
		if other != nil && other.Kind == "local" && other.Owner == p.ID {
			other.Input = Input{}
			other.FirePending = false
		}
	}
	p.Input = Input{}
	p.FirePending = false
	p.DisconnectedAt = now
}
func (h *Hub) electHost(r *Room) {
	if r.Match != nil {
		r.Host = -1
		return
	}
	if p := r.member(r.Host); p != nil && p.Away != nil {
		return
	}
	if p := r.member(r.Host); p != nil && p.Client != nil {
		return
	}
	r.Host = -1
	// Prefer an active controller, then a spectator. A bot/P2 is never a host.
	for _, p := range r.members() {
		if p.Client != nil {
			r.Host = p.ID
			break
		}
	}
}
func connectedPlayers(r *Room) int {
	n := 0
	for _, p := range r.members() {
		if p.Client != nil {
			n++
		}
	}
	return n
}
func (r *Room) setupOpen() bool {
	return !r.infinityActive && (r.Game.Phase == "lobby" || r.Game.Phase == "matchOver")
}
func canStart(r *Room) bool {
	if r.Queue != nil || r.Match != nil || r.hasAway() {
		return false
	}
	if !r.setupOpen() {
		return false
	}
	if connectedPlayers(r) < 1 || r.lineupError() != "" {
		return false
	}
	infinity := r.Game.settings().Infinity
	for _, p := range r.Players {
		if p != nil && p.Client != nil && p.ID != r.Host && !p.Ready &&
			(!infinity || infinityCanPlay(p)) {
			return false
		}
	}
	return true
}
func (h *Hub) broadcastRoom(r *Room) {
	if r.Game.Phase == "lobby" || r.Game.Phase == "matchOver" {
		r.stateDirty = true
	}
	// Every controller receives the same metadata. Encode it once into immutable
	// bytes so a full spectator gallery does not repeat JSON work per socket.
	data, ok := encodePacket(h.roomWire(r))
	if !ok {
		return
	}
	for _, p := range r.members() {
		if p.Client != nil {
			p.Client.enqueueBytes(data)
		}
	}
}
func (h *Hub) expirePlayer(r *Room, id int) {
	p := r.member(id)
	if p == nil {
		return
	}
	if r.Queue != nil && r.Queue.involves(p) {
		h.cancelQueue(r, "A party member left. The party search was cancelled.")
	}
	if p.Return != nil {
		h.abandonTravel(p.Return)
	}
	for _, other := range r.members() {
		if other.Kind == "local" && other.Owner == id {
			h.expirePlayer(r, other.ID)
		}
	}
	if p.Client != nil {
		p.Client.room = nil
		p.Client.player = nil
	}
	p.Input = Input{}
	p.FirePending = false
	p.Ready = false
	p.Client = nil
	if p.Spectating {
		delete(r.Spectators, id)
	} else {
		oldTank := r.Game.Tanks[id]
		r.clearCombatSeat(id)
		r.Game.Tanks[id] = oldTank // Retain the eliminated wreck/history until the next round.
		r.Players[id] = nil
	}
	h.electHost(r)
}
func kickedMessage(code string) map[string]any {
	return map[string]any{"type": "kicked", "room": code, "message": "You were removed from the room by the host. Automatic reconnection has stopped."}
}
func (r *Room) rememberKick(token string, now time.Time) {
	if r.Kicked == nil {
		r.Kicked = make(map[[32]byte]time.Time)
	}
	for key, until := range r.Kicked {
		if !now.Before(until) {
			delete(r.Kicked, key)
		}
	}
	// Independent of room age and host churn, retained metadata is bounded.
	if len(r.Kicked) >= maxKickNotices {
		var oldest [32]byte
		var earliest time.Time
		for key, until := range r.Kicked {
			if earliest.IsZero() || until.Before(earliest) {
				oldest, earliest = key, until
			}
		}
		delete(r.Kicked, oldest)
	}
	r.Kicked[sha256.Sum256([]byte(token))] = now.Add(kickNoticeTTL)
}
func (h *Hub) kick(c *Client, target *int, member uint64, now time.Time) {
	fail := func(code, text string) {
		msg := roomError(code, text)
		msg["action"] = "kick"
		c.enqueue(msg)
	}
	r, host := c.room, c.player
	if r == nil || host == nil || host.Client != c || !r.contains(host) {
		fail("not_joined", "Join a room before managing players.")
		return
	}
	if r.Host != host.ID {
		fail("not_host", "Only the current room host can kick players.")
		return
	}
	if target == nil || *target < 0 || (*target >= maxTanks && r.member(*target) == nil) || member == 0 {
		fail("bad_target", "Choose a player from the current room roster.")
		return
	}
	if *target == host.ID {
		fail("kick_self", "You cannot kick yourself. Use Leave room instead.")
		return
	}
	p := r.member(*target)
	if p == nil || p.Member != member {
		fail("player_missing", "That player has already left. Check the updated roster.")
		return
	}
	// Scope comes only from the sender's room. Member pins the selected occupant,
	// preventing a stale confirmation from kicking a replacement in the same slot.
	h.cancelQueue(r, "The host changed the party. Join the queue again when ready.")
	removed := p.Client
	if p.Token != "" {
		r.rememberKick(p.Token, now)
	}
	h.expirePlayer(r, p.ID)
	r.LastAction = now
	if removed != nil {
		removed.kickedRoom = r.Code
		removed.born = now // Allow time for the terminal notice to flush before idle cleanup.
		removed.enqueue(kickedMessage(r.Code))
	}
	c.enqueue(map[string]any{"type": "player_kicked", "id": p.ID, "member": p.Member, "name": p.Name})
	h.broadcastRoom(r)
	for _, other := range r.members() {
		if other != nil && other.Client != nil {
			h.sendState(other.Client, r)
		}
	}
}

// Called only while Hub.mu is held. Lookup, optional creation, and assigning the
// first pilot are one transaction, including concurrent joins for the same code.
func (h *Hub) join(c *Client, create bool, code, name, token string, now time.Time, spectate ...bool) {
	h.joinRoom(c, create, code, name, token, now, len(spectate) > 0 && spectate[0], false)
}

// Publishing imports rules and all seats before the first room/state packets.
func (h *Hub) joinRoom(c *Client, create bool, code, name, token string, now time.Time, spectating, deferInitialState bool, identity ...onlineRoomIdentity) {
	if c.room != nil {
		c.enqueue(roomError("already_joined", "Leave your current room first."))
		return
	}
	if spectating && cleanCallsign(name) == "" {
		c.enqueue(roomError("bad_name", "Choose a callsign before spectating."))
		return
	}
	code = cleanCode(code)
	if !create && token != "" {
		if room := h.resumedRoom(code, token, now); room != nil {
			// Routes hold the destination room itself, whose current code already
			// follows later renames. Recursing can loop forever after A -> B -> A.
			code = room.Code
		}
	}
	var r *Room
	created := false
	if create {
		if len(h.rooms) >= h.maxRooms {
			c.enqueue(roomError("server_full", "The server is full. Try again shortly."))
			return
		}
		var err error
		for tries := 0; tries < 16; tries++ {
			code, err = roomCode()
			if err != nil || h.rooms[code] == nil {
				break
			}
		}
		if err != nil || h.rooms[code] != nil {
			c.enqueue(roomError("server_error", "Could not create a room."))
			return
		}
	} else {
		if !validCode(code) {
			c.enqueue(roomError("bad_code", "Enter a room name: 1–128 characters, on one line."))
			return
		}
		r = h.rooms[code]
		if r == nil && token != "" {
			// Background reconnects must not resurrect an empty room or silently
			// turn a revoked/expired identity into a new host. Explicit invitations
			// can retry once as a fresh join through the normal client invite flow.
			c.enqueue(roomError("room_missing", "That room has closed. Join with its code to create a new room."))
			return
		}
	}
	if r == nil {
		// The same capacity bound applies to named rooms and random-code rooms.
		// Existing rooms remain joinable when the room limit has been reached.
		if len(h.rooms) >= h.maxRooms {
			c.enqueue(roomError("server_full", "The server is full. Try again shortly."))
			return
		}
		var seed [8]byte
		if _, err := rand.Read(seed[:]); err != nil {
			c.enqueue(roomError("server_error", "Could not create a room."))
			return
		}
		r = &Room{Code: code, Host: -1, Game: newGame(int64(binary.LittleEndian.Uint64(seed[:]))), LastAction: now}
		created = true
		// Publish only after allocating the pilot below; failures leave no orphan.
	}
	// A travelling identity can reconnect with its original invite/session.
	if token != "" && r != nil {
		for _, old := range r.members() {
			if old.Token == token && old.Away != nil {
				h.join(c, false, old.Away.Battle.Code, name, token, now, spectating)
				return
			}
		}
	}
	// A resume credential is never silently converted into a fresh player.
	if token != "" {
		if until, ok := r.Kicked[sha256.Sum256([]byte(token))]; ok && now.Before(until) {
			c.kickedRoom = r.Code
			c.born = now
			c.enqueue(kickedMessage(r.Code))
			return
		}
		for _, p := range r.members() {
			if p.Token != token {
				continue
			}
			previous := p.Client
			if socketLive(p) && (previous.ws == nil || previous.ws.peerReadRecently(now, roomTransportIdle)) {
				c.enqueue(roomError("session_active", "This pilot is already connected in another window."))
				return
			}
			if previous == nil && now.Sub(p.DisconnectedAt) > reconnectGrace {
				c.enqueue(roomError("resume_expired", "Your reconnect window expired. Join as a new pilot."))
				return
			}
			becameSpectator := spectating && !p.Spectating
			if becameSpectator && len(r.Spectators) >= maxSpectators {
				c.enqueue(roomError("room_capacity", "This room's spectator gallery is full."))
				return
			}
			resumeName := p.Name
			if spectating {
				resumeName = cleanName(name)
			}
			ownerToken, ok := h.claimRoomCallsigns(c, "join", p.PublicToken, roomControllerNames(r, p, p, resumeName))
			if !ok {
				return
			}
			p.PublicToken, c.onlineOwnerToken = ownerToken, ownerToken
			if becameSpectator {
				h.cancelQueue(r, "A player changed roles. Join the queue again when the party is ready.")
			}
			// A half-open connection can still hold the seat after the browser
			// starts retrying. Replace only an authenticated, stale transport.
			if previous != nil {
				previous.stop()
				previous.room, previous.player = nil, nil
				h.detachController(r, p, now)
			}
			p.Client = c
			p.Input = Input{}
			p.FirePending = false
			if tank := r.tankFor(p); tank != nil {
				tank.Ack = 0
				tank.AckSteps = 0
			}
			p.InputAt = now
			for _, other := range r.members() {
				if other != nil && other.Kind == "local" && other.Owner == p.ID {
					other.Input = Input{}
					other.FirePending = false
					other.InputAt = now
					if t := r.tankFor(other); t != nil {
						t.Ack = 0
						t.AckSteps = 0
					}
				}
			}
			if spectating {
				p.Name = cleanName(name)
				if becameSpectator {
					r.moveMember(p, r.viewerID(), true)
					clearRosterReadiness(r)
				}
			}
			c.player = p
			c.room = r
			c.mapGeneration = -1
			r.LastAction = now
			h.electHost(r)
			c.enqueue(map[string]any{"type": "welcome", "protocol": 1, "room": code, "id": p.ID, "token": p.Token, "publicToken": p.PublicToken, "resumed": true, "created": false, "spectating": p.Spectating, "member": p.Member})
			h.broadcastRoom(r)
			h.sendState(c, r)
			h.sendChatHistory(c, r)
			return
		}
		c.enqueue(roomError("resume_expired", "Your reconnect window expired. Join as a new pilot."))
		return
	}
	busy := r.Queue != nil || r.hasAway() || r.Match != nil || r.survivalRunning()
	if busy {
		spectating = true
	}
	id := r.freeJoinSeat()
	fallback := id < 0 && !spectating
	if spectating || id < 0 {
		if len(r.Spectators) >= maxSpectators {
			c.enqueue(roomError("room_capacity", "This room has reached its spectator limit. Try again when someone leaves."))
			return
		}
		id = r.viewerID()
		spectating = true
	}
	secret, err := randomString(32)
	if err != nil {
		c.enqueue(roomError("server_error", "Could not allocate a pilot."))
		return
	}
	ownerToken, names, claimAction := c.onlineOwnerToken, []string{cleanName(name)}, "join"
	if len(identity) > 0 {
		if identity[0].token != "" {
			ownerToken = identity[0].token
		}
		if len(identity[0].names) > 0 {
			names = identity[0].names
		}
		if identity[0].action != "" {
			claimAction = identity[0].action
		}
	}
	ownerToken, ok := h.claimRoomCallsigns(c, claimAction, ownerToken, names)
	if !ok {
		return
	}
	c.onlineOwnerToken = ownerToken
	r.NextMember++
	p := &Player{ID: id, Member: r.NextMember, Name: cleanName(name), Token: secret, PublicToken: ownerToken, Client: c, InputAt: now, Spectating: spectating}
	p.Team = joinTeam(r)
	if spectating {
		r.putViewer(p)
	} else {
		r.Players[id] = p
		r.initializeSeat(p, -1)
	}
	if created {
		h.rooms[code] = r
	}
	c.room = r
	c.player = p
	c.mapGeneration = -1
	r.LastAction = now
	h.electHost(r)
	c.enqueue(map[string]any{"type": "welcome", "protocol": 1, "room": code, "id": id, "token": secret, "publicToken": ownerToken, "resumed": false, "created": created, "spectating": p.Spectating, "member": p.Member, "full": fallback, "busy": busy})
	if !deferInitialState {
		h.broadcastRoom(r)
		h.sendState(c, r)
	}
	h.sendChatHistory(c, r)
}

type clientMessage struct {
	QueueKey string `json:"queue"`
	QueueID  uint64 `json:"queueId"`
	RoomCode string `json:"room"`

	Enabled         *bool  `json:"enabled"`
	Spectating      *bool  `json:"spectating"`
	Spectator       *int   `json:"spectator"`
	SpectatorMember uint64 `json:"spectatorMember"`

	Rules       *MatchRules `json:"rules"`
	PlayerID    *int        `json:"player"`
	Kind        string      `json:"kind"`
	Difficulty  string      `json:"difficulty"`
	Team        *int        `json:"team"`
	ColorIndex  *int        `json:"colorIndex"`
	Roster      []SeatSpec  `json:"roster"`
	Target      *int        `json:"target"`
	Member      uint64      `json:"member"`
	Text        string      `json:"text"`
	Channel     string      `json:"channel"`
	Type        string      `json:"type"`
	Code        string      `json:"code"`
	Name        string      `json:"name"`
	Token       string      `json:"token"`
	PublicToken string      `json:"publicToken"`
	Ready       bool        `json:"ready"`
	T           float64     `json:"t"`
	Version     string      `json:"version"`
	Protocol    int         `json:"protocol"`
	Generation  int         `json:"generation"`
	Wave        int         `json:"wave"`
	Input
}

func (h *Hub) handle(c *Client, data []byte, now time.Time) error {
	var m clientMessage
	if err := json.Unmarshal(data, &m); err != nil {
		return &wsError{1007, "Invalid JSON"}
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	select {
	case <-c.done:
		return nil // A replaced socket can still have an already-read packet.
	default:
	}
	if now.Sub(c.msgWindow) >= time.Second {
		c.msgWindow = now
		c.msgCount = 0
		c.secondaryInputCount = 0
		c.actionCount = 0
	}
	// Give authenticated P2 controls their own budget on the shared socket.
	// Unowned seat IDs cannot bypass the primary/socket message limit.
	var secondary *Player
	count := &c.msgCount
	if m.Type == "input" && c.room != nil && c.player != nil && c.player.Client == c && m.PlayerID != nil {
		id := *m.PlayerID
		if id != c.player.ID && id >= 0 && id < len(c.room.Players) {
			if p := c.room.Players[id]; p != nil && p.Kind == "local" && p.Owner == c.player.ID {
				secondary = p
				count = &c.secondaryInputCount
			}
		}
	}
	(*count)++
	if *count > clientMessageLimit {
		return &wsError{1008, "Input rate exceeded"}
	}
	firstHandshake := m.Type == "client_hello" && !c.versionOK && m.Version == version && m.Protocol == protocolVersion
	if m.Type != "input" && m.Type != "ping" && !firstHandshake {
		c.actionCount++
		if c.actionCount > clientActionLimit {
			e := roomError("action_rate", "Too many room actions. Try again shortly.")
			e["action"] = m.Type
			if m.Type == "chat" {
				e["channel"] = m.chatChannel()
			}
			c.enqueue(e)
			return nil
		}
	}
	// Once kicked, an old socket cannot send inputs or rejoin behind the UI.
	if c.kickedRoom != "" {
		c.enqueue(kickedMessage(c.kickedRoom))
		return nil
	}
	if m.Type == "client_hello" {
		if m.Version != version || m.Protocol != protocolVersion {
			c.enqueue(versionError())
			return nil
		}
		c.versionOK = true
		c.enqueue(map[string]any{"type": "client_ready", "version": version, "protocol": protocolVersion})
		return nil
	}
	if c.requireVersion && !c.versionOK {
		c.enqueue(versionError())
		return nil
	}
	if h.guardQueueAction(c, m) {
		return nil
	}
	switch m.Type {
	case "queue_join":
		h.joinQueue(c, m, now)
	case "queue_accept":
		h.acceptQueue(c, m, now)
	case "queue_cancel":
		h.cancelQueueRequest(c, m)
	case "queue_info":
		c.enqueue(map[string]any{"type": "queue_catalog", "queues": h.queueCatalog()})
	case "return_party":
		h.returnToParty(c, now)
	case "rematch":
		h.requestQueueRematch(c, now)
	case "restart_wave":
		h.restartSurvivalWave(c, m, now)
	case "chat":
		h.chat(c, m, now)
	case "rename_room":
		h.renameRoom(c, m, now)
	case "unshare":
		h.unshareRoom(c, now)
	case "spectate":
		h.setSpectating(c, m, now)
	case "swap":
		h.swapSpectator(c, m, now)
	case "rules":
		h.setRules(c, m, now)
	case "preset":
		h.applyPreset(c, m, now)
	case "publish":
		h.publishRoom(c, m, now)
	case "paint":
		h.paintTank(c, m, now)
	case "add", "configure", "lobby":
		h.configureRoom(c, m, now)
	case "kick":
		h.kick(c, m.Target, m.Member, now)
	case "create":
		h.joinRoom(c, cleanCode(m.Code) == "", m.Code, m.Name, "", now, m.Spectating != nil && *m.Spectating, false, onlineRoomIdentity{token: m.PublicToken, action: m.Type})
	case "join":
		h.joinRoom(c, false, m.Code, m.Name, m.Token, now, m.Spectating != nil && *m.Spectating, false, onlineRoomIdentity{token: m.PublicToken, action: m.Type})
	case "rename_local":
		h.renameLocal(c, m, now)
	case "rename":
		// Identity comes only from the authenticated socket, never a supplied ID.
		if c.room == nil || c.player == nil || c.player.Client != c || !c.room.contains(c.player) {
			c.enqueue(roomError("not_joined", "Join a room before changing your callsign."))
			return nil
		}
		name := cleanCallsign(m.Name)
		if name == "" {
			c.enqueue(roomError("bad_name", "Use letters, numbers, spaces, hyphens or underscores (up to 16 characters)."))
			return nil
		}
		p, r := c.player, c.room
		ownerToken, ok := h.claimRoomCallsigns(c, "rename", p.PublicToken, roomControllerNames(r, p, p, name))
		if !ok {
			return nil
		}
		p.PublicToken, c.onlineOwnerToken = ownerToken, ownerToken
		p.Name = name
		if tank := r.tankFor(p); tank != nil {
			tank.Name = name
		}
		r.LastAction = now
		c.enqueue(map[string]any{"type": "renamed", "id": p.ID, "name": name, "publicToken": p.PublicToken})
		h.broadcastRoom(r)
	case "ping":
		if !math.IsNaN(m.T) && !math.IsInf(m.T, 0) {
			c.enqueue(map[string]any{"type": "pong", "t": m.T})
		}
	case "leave":
		if c.room != nil && c.player != nil {
			r, id := c.room, c.player.ID
			h.expirePlayer(r, id)
			r.LastAction = now
			h.broadcastRoom(r)
			c.born = now // Give the writer time to deliver the acknowledgement.
		}
		c.enqueue(map[string]any{"type": "left"})
	case "input":
		if m.RoomCode != "" && (c.room == nil || c.room.Code != m.RoomCode) {
			return nil
		}
		if c.player == nil || c.player.Client != c {
			return nil
		}
		p := c.player
		if m.PlayerID != nil && *m.PlayerID != p.ID {
			if secondary == nil {
				c.enqueue(roomError("not_owned", "You cannot control another pilot."))
				return nil
			}
			p = secondary
		}
		// A seat can change between sending and receiving an input, including
		// swaps between this controller's own P1 and P2. Do not let the old
		// occupant's sequence or fire edge enter the replacement's channel.
		// Older member-less input packets keep their existing protocol behavior.
		if m.Member != 0 && m.Member != p.Member {
			return nil
		}
		if p.Spectating {
			return nil
		} // Spectators cannot move, fire, detonate or collect.
		in := m.Input
		if math.IsNaN(in.StickX) || math.IsNaN(in.StickY) || math.IsInf(in.StickX, 0) || math.IsInf(in.StickY, 0) {
			return &wsError{1008, "Invalid controls"}
		}
		if in.Seq <= p.Input.Seq {
			return nil
		}
		in.StickX = clamp(in.StickX, -1, 1)
		in.StickY = clamp(in.StickY, -1, 1)
		mag := math.Hypot(in.StickX, in.StickY)
		if mag > 1 {
			in.StickX /= mag
			in.StickY /= mag
		}
		// Preserve even a quick press+release that both arrive between ticks.
		// FirePressed is never decoded from JSON; it is derived from button edges.
		if now.Sub(p.InputAt) > inputTimeout {
			p.FirePending = false
		}
		if in.Fire && !p.Input.Fire {
			p.FirePending = true
		}
		p.Input = in
		p.InputAt = now
		if in.Forward || in.Reverse || in.Left || in.Right || in.Fire || mag > .1 {
			c.room.LastAction = now
		}
	case "ready":
		if c.room == nil || c.player == nil || c.player.Spectating {
			return nil
		}
		r := c.room
		if !r.setupOpen() {
			return nil
		}
		c.player.Ready = m.Ready
		r.LastAction = now
		h.broadcastRoom(r)
	case "select_public_infinity":
		h.selectPublicInfinity(c, m.Enabled, now)
	case "start_public_infinity":
		h.requestPublicInfinity(c, now)
	case "start":
		if c.room == nil || c.player == nil || c.player.Client != c || !c.room.contains(c.player) {
			return nil
		}
		r := c.room
		if c.player.ID != r.Host {
			c.enqueue(roomError("not_host", "Only the host can start the match."))
			return nil
		}
		if r.infinityPublic && !r.infinityActive {
			h.requestPublicInfinity(c, now)
			return nil
		}
		if r.infinityActive {
			c.enqueue(roomError("match_active", "Infinity is already running in this room."))
			return nil
		}
		if !canStart(r) {
			message := r.lineupError()
			if message == "" {
				message = "Ask connected guests to ready up before starting the match."
			}
			c.enqueue(roomError("not_ready", message))
			return nil
		}
		r.LastAction = now
		if r.Game.settings().Infinity {
			h.startRoomInfinity(r)
			return nil
		}
		r.Game.startMatch(r.Players)
		for _, p := range r.Players {
			if p != nil {
				p.Ready = false
			}
		}
		h.broadcastRoom(r)
		for _, p := range r.members() {
			if p.Client != nil {
				h.sendState(p.Client, r)
			}
		}
	default:
		return &wsError{1008, "Unknown message type"}
	}
	return nil
}
func rounded(v float64) float64 { return math.Round(v*100) / 100 }

type stateScratch struct {
	tanks          []Tank
	bullets        []Bullet
	boostedIDs     []int
	machineBullets [][12]float64
	pickups        []Pickup
}

type stateWire struct {
	// Field order matches encoding/json's lexicographic map-key order from the
	// canonical stateMessage so the optimized packet remains byte-for-byte stable.
	BoostedBulletIDs []int `json:"boostedBulletIds,omitempty"`

	Bullets        []Bullet        `json:"bullets"`
	Events         []Event         `json:"events"`
	Generation     int             `json:"generation"`
	MachineBullets [][12]float64   `json:"machineBullets,omitempty"`
	MatchStats     json.RawMessage `json:"matchStats,omitempty"`
	Objectives     *ObjectiveState `json:"objectives"`
	Phase          string          `json:"phase"`
	PhaseTime      float64         `json:"phaseTime"`
	Pickups        []Pickup        `json:"pickups"`
	Round          int             `json:"round"`
	RoundClock     float64         `json:"roundClock"`
	Rules          MatchRules      `json:"rules"`
	Scores         [maxTanks]int   `json:"scores"`
	Tanks          []Tank          `json:"tanks"`
	Tick           int             `json:"tick"`
	Type           string          `json:"type"`
	Winner         int             `json:"winner"`
	World          *World          `json:"world,omitempty"`
}

// Direct and periodic snapshots reuse room-owned slice capacity. JSON encoding
// is synchronous under Hub.mu, so queued packets keep only immutable bytes.
func (h *Hub) stateWire(r *Room) stateWire {
	g, z := r.Game, &r.state
	z.tanks = z.tanks[:0]
	z.bullets = z.bullets[:0]
	z.boostedIDs = z.boostedIDs[:0]
	z.machineBullets = z.machineBullets[:0]
	z.pickups = z.pickups[:0]
	if cap(z.tanks) < maxTanks {
		z.tanks = make([]Tank, 0, maxTanks)
	}
	if z.bullets == nil || cap(z.bullets) < len(g.Bullets) {
		z.bullets = make([]Bullet, 0, len(g.Bullets))
	}
	if cap(z.machineBullets) < len(g.Bullets) {
		z.machineBullets = make([][12]float64, 0, len(g.Bullets))
	}
	if z.pickups == nil || cap(z.pickups) < len(g.Pickups) {
		z.pickups = make([]Pickup, 0, len(g.Pickups))
	}
	for _, t := range g.Tanks {
		if t == nil {
			continue
		}
		v := *t
		v.X = rounded(v.X)
		v.Y = rounded(v.Y)
		v.Angle = math.Round(v.Angle*10000) / 10000
		v.VX = rounded(v.VX)
		v.VY = rounded(v.VY)
		v.Cooldown = rounded(v.Cooldown)
		v.Invulnerable = rounded(v.Invulnerable)
		v.Shield = rounded(v.Shield)
		v.PowerTime = rounded(v.PowerTime)
		v.Recoil = rounded(v.Recoil)
		v.Track = rounded(v.Track)
		z.tanks = append(z.tanks, v)
	}
	for _, b := range g.Bullets {
		v := *b
		if b.boosted && !b.Dead {
			z.boostedIDs = append(z.boostedIDs, b.ID)
		}
		v.X = rounded(v.X)
		v.Y = rounded(v.Y)
		v.VX = rounded(v.VX)
		v.VY = rounded(v.VY)
		v.Age = rounded(v.Age)
		v.Life = rounded(v.Life)
		if v.Kind == "rapid" {
			color := tankColorIndex[v.Color]
			z.machineBullets = append(z.machineBullets, [12]float64{float64(v.ID), float64(v.Owner), float64(v.ShotSerial), float64(v.SpawnSerial), v.X, v.Y, v.VX, v.VY, v.Age, v.Life, float64(v.Bounces), float64(color)})
		} else {
			z.bullets = append(z.bullets, v)
		}
	}
	for _, p := range g.Pickups {
		v := *p
		v.Age = rounded(v.Age)
		v.Life = rounded(v.Life)
		z.pickups = append(z.pickups, v)
	}
	wire := stateWire{Type: "state", Tick: g.Tick, Generation: g.Generation, Phase: g.Phase, PhaseTime: rounded(g.PhaseTime), Round: g.Round, RoundClock: rounded(g.Clock), Winner: g.Winner, Scores: g.Scores, Tanks: z.tanks, Bullets: z.bullets, BoostedBulletIDs: z.boostedIDs, MachineBullets: z.machineBullets, Pickups: z.pickups, Events: g.events, Rules: g.settings(), Objectives: g.Objectives}
	if g.Phase == "matchOver" && g.matchReportWire != nil {
		wire.MatchStats = g.matchReportWire
	}
	return wire
}

func (h *Hub) sendState(c *Client, r *Room) {
	s := h.stateWire(r)
	reliable := c.mapGeneration != s.Generation
	if reliable && s.Generation > 0 {
		s.World = &r.Game.World
	}
	if c.enqueueState(s, reliable) {
		c.mapGeneration = s.Generation
	}
}

func (r *Room) hasLiveClients() bool {
	for _, p := range r.Players {
		if socketLive(p) {
			return true
		}
	}
	for _, p := range r.Spectators {
		if socketLive(p) {
			return true
		}
	}
	return false
}

// No per-client secrets exist in state. Encode once and share immutable bytes.
// Map-bearing packets remain reliable and always precede replaceable snapshots.
func (h *Hub) broadcastState(r *Room) {
	// Disconnected rooms keep simulating during reconnect grace, but have no
	// snapshot recipients. Closed sockets may still await removeClient.
	if !r.hasLiveClients() {
		return
	}
	s := h.stateWire(r)
	data, ok := encodePacket(s)
	if !ok {
		return
	}
	var full, compressed snapshotFrame
	send := func(c *Client) bool {
		if c == nil {
			return true
		}
		reliable := c.mapGeneration != r.Game.Generation
		payload := snapshotFrame{data: data}
		if reliable && r.Game.Generation > 0 {
			if full.data == nil {
				s.World = &r.Game.World
				full.data, ok = encodePacket(s)
				if !ok {
					return false
				}
			}
			payload = full
		} else if !reliable && c.supportsSnapshotDeflate() {
			if compressed.data == nil {
				compressed = compressSnapshot(data)
			}
			payload = compressed
		}
		if c.enqueueStateFrame(payload, reliable) {
			c.mapGeneration = r.Game.Generation
		}
		return true
	}
	// Snapshot delivery does not depend on spectator ordering. Avoid allocating
	// Room.members()/sorted spectator IDs on every 60 Hz broadcast.
	for _, p := range r.Players {
		if p != nil && !send(p.Client) {
			return
		}
	}
	for _, p := range r.Spectators {
		if p != nil && !send(p.Client) {
			return
		}
	}
}

func (h *Hub) tick(now time.Time) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for c := range h.clients {
		if c.room == nil && now.Sub(c.born) > 15*time.Second {
			c.stop()
		}
	}
	h.tickQueues(now)
	for code, r := range h.rooms {
		for token, until := range r.Kicked {
			if !now.Before(until) {
				delete(r.Kicked, token)
			}
		}
		changed := false
		var memberStorage [maxTanks + maxSpectators]*Player
		members := r.appendMembers(memberStorage[:0])
		for _, p := range members {
			id := p.ID
			if p.Away == nil && p.Kind != "bot" && p.Kind != "local" && p.Client == nil && now.Sub(p.DisconnectedAt) > reconnectGrace {
				h.expirePlayer(r, id)
				changed = true
			}
		}
		// Expiration may also remove a controller's P2. Refresh only after the
		// original snapshot has been consumed, so removed seats cannot keep an
		// empty room alive and expiration order remains deterministic.
		if changed {
			members = r.appendMembers(memberStorage[:0])
		}
		present := 0
		for _, p := range members {
			if p.Kind != "bot" && p.Kind != "local" {
				present++
			}
		}
		if present == 0 {
			h.cancelQueue(r, "The room closed.")
			delete(h.rooms, code)
			continue
		}
		if r.hasAway() {
			continue
		} // The private roster is reserved, not a second simulation.
		if r.Queue != nil {
			r.LastAction = now
		}
		if now.Sub(r.LastAction) > roomIdleLimit {
			for _, p := range r.members() {
				if p.Client != nil {
					p.Client.stop()
				}
			}
			for _, p := range r.members() {
				if r.contains(p) {
					h.expirePlayer(r, p.ID)
				}
			}
			delete(h.rooms, code)
			continue
		}
		var inputs [maxTanks]Input
		for id, p := range r.Players {
			if p != nil {
				// Preserve sequence chronology even when stale input becomes neutral.
				inputs[id].Seq = p.Input.Seq
				if participantAvailable(r.Players, id) && p.Kind != "bot" && now.Sub(p.InputAt) <= inputTimeout {
					inputs[id] = p.Input
					inputs[id].FirePressed = p.FirePending
				}
				p.FirePending = false
			}
		}
		oldPhase := r.Game.Phase
		oldSurvivalStatus := ""
		if s := r.Game.survivalState(); s != nil {
			oldSurvivalStatus = s.Status
		}
		r.Game.step(tickDT, inputs, r.Players)
		h.finishQueueForfeit(r)
		if oldPhase != r.Game.Phase {
			changed = true
		}
		if s := r.Game.survivalState(); s != nil && s.Status != oldSurvivalStatus {
			changed = true
		}
		if changed {
			h.broadcastRoom(r)
		}
		active := r.Game.Phase != "lobby" && r.Game.Phase != "matchOver"
		if active && r.Game.Tick%2 == 0 || !active && r.stateDirty {
			h.broadcastState(r)
		}
		r.stateDirty = false
	}
}
func (h *Hub) run(done <-chan struct{}) {
	ticker := time.NewTicker(time.Second / 60)
	defer ticker.Stop()
	last := time.Now()
	var accumulated time.Duration
	step := time.Second / 60
	for {
		select {
		case <-done:
			return
		case now := <-ticker.C:
			elapsed := now.Sub(last)
			last = now
			if elapsed < 0 {
				elapsed = 0
			}
			if elapsed > 5*step {
				elapsed = 5 * step
			}
			accumulated += elapsed
			for accumulated >= step {
				h.tick(now)
				accumulated -= step
			}
		}
	}
}
func (h *Hub) notifyShutdown() int {
	data, ok := encodePacket(map[string]any{"type": "server_shutdown", "message": "The leqra server is shutting down. Returning to the Home Screen."})
	if !ok {
		return 0
	}
	h.mu.Lock()
	clients := make([]*Client, 0, len(h.clients))
	for c := range h.clients {
		clients = append(clients, c)
	}
	h.mu.Unlock()
	sent := 0
	for _, c := range clients {
		if c.enqueueBytes(data) {
			sent++
		}
	}
	return sent
}
func (h *Hub) close() {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.closed = true
	for c := range h.clients {
		c.stop()
	}
}
func (h *Hub) roomCount() int { h.mu.Lock(); defer h.mu.Unlock(); return len(h.rooms) }
func (h *Hub) readLoop(c *Client) {
	defer c.stop()
	defer h.removeClient(c)
	for {
		data, err := c.ws.readMessage()
		if err == nil {
			err = h.handle(c, data, time.Now())
		}
		if err != nil {
			var we *wsError
			if errors.As(err, &we) {
				c.ws.writeClose(we.code, we.reason)
			}
			return
		}
	}
}
func (r *Room) String() string { return fmt.Sprintf("room(%s)", r.Code) }
