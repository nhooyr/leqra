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

// Keep kick tombstones beyond the entire reconnect window, even if the removal
// notification was lost. This is not an IP/account ban; fresh manual joins work.
const kickNoticeTTL = 2 * time.Minute
const maxKickNotices = 1024

type Player struct {
	Away   *MatchTravel // Reserved in a private lobby while playing a queue match.
	Return *MatchTravel // Only present on the travelling match identity.

	ChatTokens float64
	ChatAt     time.Time
	Spectating bool    // A room member without a combat seat.
	Controller *Player // Local P2 controller may itself be spectating.

	Kind                    string // Empty/human = remote pilot; local = second keyboard pilot; bot = server AI.
	Owner                   int    // Primary pilot whose socket controls a local pilot.
	ColorIndex              *int   // Optional FFA palette identity; owner-scoped for online humans.
	Team                    int    // 0 = individual free-for-all; 1..4 = shared side.
	Difficulty              string
	ID                      int
	Member                  uint64 // Public seat-incarnation ID; never a credential.
	Name, Token             string
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

	state stateScratch // reusable 60 Hz snapshot buffers; encoded before reuse
}
type Client struct {
	ws                    *wsConn
	send                  chan []byte
	updates               chan []byte // Replaceable snapshots; reliable messages stay in send.
	done                  chan struct{}
	stopOnce              sync.Once
	room                  *Room // Everything below is guarded by Hub.mu.
	player                *Player
	mapGeneration         int
	msgWindow             time.Time
	msgCount, actionCount int
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
	return c.enqueueStateBytes(data, reliable)
}
func (c *Client) enqueueStateBytes(data []byte, reliable bool) bool {
	if c.updates == nil {
		return c.enqueueBytes(data)
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
		return c.enqueueBytes(data)
	}
	select {
	case <-c.updates:
	default:
	}
	select {
	case c.updates <- data:
		return true
	default:
		return false
	}
}
func (c *Client) writeLoop() {
	defer c.stop()
	heartbeat := time.NewTicker(10 * time.Second)
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
			if err := c.ws.writeFrame(1, msg); err != nil {
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
	resumeRoutes map[resumeRouteKey]resumeRoute

	queues                         map[uint64]*QueueTicket
	nextQueueID                    uint64
	nextQueueScan, nextQueueStatus time.Time

	mu       sync.Mutex
	rooms    map[string]*Room
	clients  map[*Client]bool
	maxRooms int
}

func newHub(maxRooms int) *Hub {
	return &Hub{rooms: map[string]*Room{}, clients: map[*Client]bool{}, maxRooms: maxRooms, queues: map[uint64]*QueueTicket{}}
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
		s = "PILOT"
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
func (h *Hub) addClient(c *Client) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	if len(h.clients) >= h.maxRooms*(maxTanks+maxSpectators)+32 {
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
	if r.Queue != nil && r.Queue.involves(p) {
		h.cancelQueue(r, "A party member disconnected. Rejoin the queue when everyone is connected.")
	}
	p.Client = nil
	p.Ready = false
	for _, other := range r.members() {
		if other != nil && other.Kind == "local" && other.Owner == p.ID {
			other.Input = Input{}
			other.FirePending = false
		}
	}
	p.Input = Input{}
	p.FirePending = false
	p.DisconnectedAt = time.Now()
	h.electHost(r)
	h.broadcastRoom(r)
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
func canStart(r *Room) bool {
	if r.Queue != nil || r.Match != nil || r.hasAway() {
		return false
	}
	if r.Game.Phase != "lobby" && r.Game.Phase != "matchOver" {
		return false
	}
	if connectedPlayers(r) < 1 || r.Game.lineupError(r.Players) != "" {
		return false
	}
	for _, p := range r.Players {
		if p != nil && p.Client != nil && p.ID != r.Host && !p.Ready {
			return false
		}
	}
	return true
}
func (h *Hub) roomMessage(r *Room) map[string]any {
	players, viewers := []map[string]any{}, []map[string]any{}
	for _, p := range r.members() {
		score := 0
		if !p.Spectating {
			score = r.Game.Scores[p.ID]
		}
		connected := p.Client != nil
		if p.Kind == "bot" {
			connected = true
		}
		if p.Kind == "local" {
			owner := r.member(p.Owner)
			connected = owner != nil && owner.Client != nil
		}
		entry := map[string]any{"id": p.ID, "member": p.Member, "name": p.Name, "color": selectedColor(p.ID, p.Team, p.ColorIndex, r.Game.settings()), "connected": connected, "ready": !p.Spectating && (p.Ready || p.Kind == "bot" || p.Kind == "local"), "score": score, "kind": playerKind(p), "owner": p.Owner, "team": p.Team, "difficulty": p.Difficulty, "spectating": p.Spectating, "away": p.Away != nil, "hasParty": p.Return != nil}
		if r.Match != nil && r.Game.Phase == "matchOver" && r.Match.Rematch != nil {
			entry["rematch"] = r.Match.Rematch[p.Member]
		}
		if p.ColorIndex != nil && r.Game.settings().TeamMode == "ffa" {
			entry["colorIndex"] = *p.ColorIndex
		}
		if p.Spectating {
			viewers = append(viewers, entry)
		} else {
			players = append(players, entry)
		}
	}
	return map[string]any{"type": "room", "code": r.Code, "host": r.Host, "phase": r.Game.Phase, "players": players, "spectators": viewers, "canStart": canStart(r), "maxPlayers": maxTanks, "maxSpectators": maxSpectators, "rules": r.Game.settings(), "startError": r.Game.lineupError(r.Players), "sides": availableSides(r.Players), "queue": h.queueView(r.Queue), "matchmaking": matchView(r), "awayMatch": r.awayMatchCode()}
}
func (h *Hub) broadcastRoom(r *Room) {
	m := h.roomMessage(r)
	for _, p := range r.members() {
		if p.Client != nil {
			p.Client.enqueue(m)
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
	if c.room != nil {
		c.enqueue(roomError("already_joined", "Leave your current room first."))
		return
	}
	spectating := len(spectate) > 0 && spectate[0]
	if spectating && cleanCallsign(name) == "" {
		c.enqueue(roomError("bad_name", "Choose a callsign before spectating."))
		return
	}
	code = cleanCode(code)
	if !create && token != "" {
		if route, ok := h.resumeRoutes[resumeRouteKey{code, sha256.Sum256([]byte(token))}]; ok && now.Before(route.Until) && h.rooms[route.Room.Code] == route.Room {
			h.join(c, false, route.Room.Code, name, token, now, spectating)
			return
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
			if p.Client != nil {
				c.enqueue(roomError("session_active", "This pilot is already connected in another window."))
				return
			}
			if now.Sub(p.DisconnectedAt) > reconnectGrace {
				c.enqueue(roomError("resume_expired", "Your reconnect window expired. Join as a new pilot."))
				return
			}
			if spectating && !p.Spectating && len(r.Spectators) >= maxSpectators {
				c.enqueue(roomError("room_capacity", "This room's spectator gallery is full."))
				return
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
				if !p.Spectating {
					r.moveMember(p, r.viewerID(), true)
				}
			}
			c.player = p
			c.room = r
			c.mapGeneration = -1
			r.LastAction = now
			h.electHost(r)
			c.enqueue(map[string]any{"type": "welcome", "protocol": 1, "room": code, "id": p.ID, "token": p.Token, "resumed": true, "created": false, "spectating": p.Spectating, "member": p.Member})
			h.broadcastRoom(r)
			h.sendState(c, r)
			h.sendChatHistory(c, r)
			return
		}
		c.enqueue(roomError("resume_expired", "Your reconnect window expired. Join as a new pilot."))
		return
	}
	busy := r.Queue != nil || r.hasAway() || r.Match != nil
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
	r.NextMember++
	p := &Player{ID: id, Member: r.NextMember, Name: cleanName(name), Token: secret, Client: c, InputAt: now, Spectating: spectating}
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
	c.enqueue(map[string]any{"type": "welcome", "protocol": 1, "room": code, "id": id, "token": secret, "resumed": false, "created": created, "spectating": p.Spectating, "member": p.Member, "full": fallback, "busy": busy})
	h.broadcastRoom(r)
	h.sendState(c, r)
	h.sendChatHistory(c, r)
}

type clientMessage struct {
	QueueKey string `json:"queue"`
	QueueID  uint64 `json:"queueId"`
	RoomCode string `json:"room"`

	Spectating      *bool  `json:"spectating"`
	Spectator       *int   `json:"spectator"`
	SpectatorMember uint64 `json:"spectatorMember"`

	Rules      *MatchRules `json:"rules"`
	PlayerID   *int        `json:"player"`
	Kind       string      `json:"kind"`
	Difficulty string      `json:"difficulty"`
	Team       *int        `json:"team"`
	ColorIndex *int        `json:"colorIndex"`
	Roster     []SeatSpec  `json:"roster"`
	Target     *int        `json:"target"`
	Member     uint64      `json:"member"`
	Text       string      `json:"text"`
	Channel    string      `json:"channel"`
	Type       string      `json:"type"`
	Code       string      `json:"code"`
	Name       string      `json:"name"`
	Token      string      `json:"token"`
	Ready      bool        `json:"ready"`
	T          float64     `json:"t"`
	Input
}

func (h *Hub) handle(c *Client, data []byte, now time.Time) error {
	var m clientMessage
	if err := json.Unmarshal(data, &m); err != nil {
		return &wsError{1007, "Invalid JSON"}
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	if now.Sub(c.msgWindow) >= time.Second {
		c.msgWindow = now
		c.msgCount = 0
		c.actionCount = 0
	}
	c.msgCount++
	if c.msgCount > 100 {
		return &wsError{1008, "Input rate exceeded"}
	}
	if m.Type != "input" && m.Type != "ping" {
		c.actionCount++
		if c.actionCount > 8 {
			return &wsError{1008, "Action rate exceeded"}
		}
	}
	// Once kicked, an old socket cannot send inputs or rejoin behind the UI.
	if c.kickedRoom != "" {
		c.enqueue(kickedMessage(c.kickedRoom))
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
	case "chat":
		h.chat(c, m, now)
	case "rename_room":
		h.renameRoom(c, m, now)
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
		h.join(c, cleanCode(m.Code) == "", m.Code, m.Name, "", now, m.Spectating != nil && *m.Spectating)
	case "join":
		h.join(c, false, m.Code, m.Name, m.Token, now, m.Spectating != nil && *m.Spectating)
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
		p.Name = name
		if tank := r.tankFor(p); tank != nil {
			tank.Name = name
		}
		r.LastAction = now
		c.enqueue(map[string]any{"type": "renamed", "id": p.ID, "name": name})
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
			id := *m.PlayerID
			if id < 0 || id >= len(c.room.Players) || c.room.Players[id] == nil || c.room.Players[id].Kind != "local" || c.room.Players[id].Owner != p.ID {
				c.enqueue(roomError("not_owned", "You cannot control another pilot."))
				return nil
			}
			p = c.room.Players[id]
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
		if r.Game.Phase != "lobby" && r.Game.Phase != "matchOver" {
			return nil
		}
		c.player.Ready = m.Ready
		r.LastAction = now
		h.broadcastRoom(r)
	case "start":
		if c.room == nil || c.player == nil {
			return nil
		}
		r := c.room
		if c.player.ID != r.Host {
			c.enqueue(roomError("not_host", "Only the host can start the match."))
			return nil
		}
		if !canStart(r) {
			c.enqueue(roomError("not_ready", "Add at least two opposing sides and ask connected guests to ready up."))
			return nil
		}
		r.LastAction = now
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
	machineBullets [][12]float64
	pickups        []Pickup
}

type stateWire struct {
	// Field order matches encoding/json's lexicographic map-key order from the
	// canonical stateMessage so the optimized packet remains byte-for-byte stable.
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

// The 60 Hz broadcast path reuses room-owned slice capacity. JSON encoding is
// synchronous, so the buffers are never mutated while queued packet bytes use them.
func (h *Hub) stateWire(r *Room) stateWire {
	g, z := r.Game, &r.state
	z.tanks = z.tanks[:0]
	z.bullets = z.bullets[:0]
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
	wire := stateWire{Type: "state", Tick: g.Tick, Generation: g.Generation, Phase: g.Phase, PhaseTime: rounded(g.PhaseTime), Round: g.Round, RoundClock: rounded(g.Clock), Winner: g.Winner, Scores: g.Scores, Tanks: z.tanks, Bullets: z.bullets, MachineBullets: z.machineBullets, Pickups: z.pickups, Events: g.events, Rules: g.settings(), Objectives: g.Objectives}
	if g.Phase == "matchOver" && g.matchReportWire != nil {
		wire.MatchStats = g.matchReportWire
	}
	return wire
}

func (h *Hub) stateMessage(r *Room) map[string]any {
	g := r.Game
	ts := make([]Tank, 0, maxTanks)
	bs := make([]Bullet, 0, len(g.Bullets))
	ms := make([][12]float64, 0, len(g.Bullets)) // Compact Machine gun records; same authoritative samples.
	ps := make([]Pickup, 0, len(g.Pickups))
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
		// SpeedTime stays full precision: input replay must match the exact expiry tick.
		v.Recoil = rounded(v.Recoil)
		v.Track = rounded(v.Track)
		ts = append(ts, v)
	}
	for _, b := range g.Bullets {
		v := *b
		v.X = rounded(v.X)
		v.Y = rounded(v.Y)
		v.VX = rounded(v.VX)
		v.VY = rounded(v.VY)
		v.Age = rounded(v.Age)
		v.Life = rounded(v.Life)
		if v.Kind == "rapid" {
			color := tankColorIndex[v.Color]
			ms = append(ms, [12]float64{float64(v.ID), float64(v.Owner), float64(v.ShotSerial), float64(v.SpawnSerial), v.X, v.Y, v.VX, v.VY, v.Age, v.Life, float64(v.Bounces), float64(color)})
		} else {
			bs = append(bs, v)
		}
	}
	for _, p := range g.Pickups {
		v := *p
		v.Age = rounded(v.Age)
		v.Life = rounded(v.Life)
		ps = append(ps, v)
	}
	s := map[string]any{"type": "state", "tick": g.Tick, "generation": g.Generation, "phase": g.Phase, "phaseTime": rounded(g.PhaseTime), "round": g.Round, "roundClock": rounded(g.Clock), "winner": g.Winner, "scores": g.Scores, "tanks": ts, "bullets": bs, "pickups": ps, "events": g.events, "rules": g.settings(), "objectives": g.Objectives}
	if len(ms) > 0 {
		s["machineBullets"] = ms
	}
	if g.Phase == "matchOver" && g.matchReportWire != nil {
		s["matchStats"] = g.matchReportWire
	}
	return s
}
func (h *Hub) sendState(c *Client, r *Room) {
	s := h.stateMessage(r)
	if c.mapGeneration != r.Game.Generation && r.Game.Generation > 0 {
		s["world"] = r.Game.World
	}
	if c.enqueueState(s, c.mapGeneration != r.Game.Generation) {
		c.mapGeneration = r.Game.Generation
	}
}

// No per-client secrets exist in state. Encode once and share immutable bytes.
// Map-bearing packets remain reliable and always precede replaceable snapshots.
func (h *Hub) broadcastState(r *Room) {
	s := h.stateWire(r)
	data, ok := encodePacket(s)
	if !ok {
		return
	}
	var full []byte
	send := func(c *Client) bool {
		if c == nil {
			return true
		}
		reliable := c.mapGeneration != r.Game.Generation
		payload := data
		if reliable && r.Game.Generation > 0 {
			if full == nil {
				s.World = &r.Game.World
				full, ok = encodePacket(s)
				if !ok {
					return false
				}
			}
			payload = full
		}
		if c.enqueueStateBytes(payload, reliable) {
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
		for _, p := range r.members() {
			id := p.ID
			if p.Away == nil && p.Kind != "bot" && p.Kind != "local" && p.Client == nil && now.Sub(p.DisconnectedAt) > reconnectGrace {
				h.expirePlayer(r, id)
				changed = true
			}
		}
		present := 0
		for _, p := range r.members() {
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
		r.Game.step(tickDT, inputs, r.Players)
		h.finishQueueForfeit(r)
		if oldPhase != r.Game.Phase {
			changed = true
		}
		if changed {
			h.broadcastRoom(r)
		}
		if r.Game.Tick%2 == 0 {
			h.broadcastState(r)
		}
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
func (h *Hub) close() {
	h.mu.Lock()
	defer h.mu.Unlock()
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
