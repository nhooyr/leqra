package main

// Matchmaking owns no physics. It assembles human-only, fixed-rule games from
// consenting private-lobby parties. Every function below runs under Hub.mu,
// including admission, exact team packing, reservations and room transfers.
import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"fmt"
	mrand "math/rand"
	"sort"
	"time"
)

type QueueDefinition struct {
	Key      string `json:"key"`
	Name     string `json:"name"`
	Mode     string `json:"mode"`
	TeamSize int    `json:"teamSize"`
	Players  int    `json:"players"`
	Map      string `json:"map"`
	Cols     int    `json:"cols"`
	Rows     int    `json:"rows"`
	Target   int    `json:"target"`
	Seconds  int    `json:"seconds"`
}

var queueDefinitions = []QueueDefinition{
	{"elimination-1", "Elimination · 1v1", "elimination", 1, 2, "compact", 7, 7, 5, 75},
	{"elimination-2", "Elimination · 2v2", "elimination", 2, 4, "large", 12, 10, 5, 75},
	{"elimination-3", "Elimination · 3v3", "elimination", 3, 6, "huge", 14, 12, 5, 75},
	{"ctf-3", "Capture the Flag · 3v3", "ctf", 3, 6, "huge", 14, 12, 3, 180},
	{"koth-3", "King of the Hill · 3v3", "koth", 3, 6, "huge", 14, 12, 60, 180},
	{"ffa-8", "Free-for-all · 8 players", "elimination", 0, 8, "giant", 16, 14, 5, 120},
}

func queueDefinition(key string) (QueueDefinition, bool) {
	for _, d := range queueDefinitions {
		if d.Key == key {
			return d, true
		}
	}
	return QueueDefinition{}, false
}
func queueRules(d QueueDefinition) MatchRules {
	r := defaultRules()
	r.Mode, r.MapSize, r.ScoreTarget, r.TimeLimit = d.Mode, d.Map, d.Target, d.Seconds
	r.TeamMode = "teams"
	if d.TeamSize == 0 {
		r.TeamMode = "ffa"
	}
	r.TeamNames = []string{"Lime Squad", "Coral Squad", "Team 3", "Team 4"}
	return r
}

type resumeRouteKey struct {
	Code  string
	Token [32]byte
}
type resumeRoute struct {
	Room  *Room
	Until time.Time
}

type QueueTicket struct {
	ID                uint64
	Definition        QueueDefinition
	Room              *Room
	Leader            *Player
	Pilots            []*Player // No bots or spectators count toward the party size.
	Controllers       []*Player // Includes an observing primary who controls active P2.
	Accepted          map[*Player]bool
	Created, Enqueued time.Time
}
type QueueMatch struct {
	Definition QueueDefinition
	Started    time.Time
	Rematch    map[uint64]bool // one vote per connected controller/member
}
type MatchTravel struct {
	Home     *Room
	Original *Player // Reserved private-room identity, with its original team/seat.
	Battle   *Room
	Pilot    *Player // Separate, match-local identity with independent score/statistics.
}

func (r *Room) hasAway() bool { return r.awayMatchCode() != "" }
func (r *Room) awayMatchCode() string {
	for _, p := range r.Players {
		if p != nil && p.Away != nil {
			return p.Away.Battle.Code
		}
	}
	for _, p := range r.Spectators {
		if p.Away != nil {
			return p.Away.Battle.Code
		}
	}
	return ""
}
func matchView(r *Room) any {
	if r.Match == nil {
		return nil
	}
	return map[string]any{"queue": r.Match.Definition.Key, "name": r.Match.Definition.Name, "locked": true}
}
func queueError(c *Client, action, code, text string) {
	e := roomError(code, text)
	e["action"] = action
	c.enqueue(e)
}
func socketLive(p *Player) bool {
	if p == nil || p.Client == nil {
		return false
	}
	select {
	case <-p.Client.done:
		return false
	default:
		return true
	}
}

// Guard both ordinary host commands and forged traffic. A matched room has no
// player-host: no opponent can kick strangers, change teams, or restart a battle.
func (h *Hub) guardQueueAction(c *Client, m clientMessage) bool {
	r := c.room
	if r == nil {
		return false
	}
	admin := m.Type == "add" || m.Type == "configure" || m.Type == "rules" || m.Type == "preset" || m.Type == "start" || m.Type == "lobby" || m.Type == "swap" || m.Type == "rename_room"
	if r.Match != nil {
		if admin || m.Type == "kick" || m.Type == "ready" || m.Type == "queue_join" || m.Type == "spectate" && m.Spectating != nil && !*m.Spectating {
			queueError(c, m.Type, "match_locked", "Matchmaking teams and rules are locked. Return to your party to queue again.")
			return true
		}
	}
	if (admin || m.Type == "kick" || m.Type == "spectate" || m.Type == "ready" || m.Type == "queue_join") && r.hasAway() {
		queueError(c, m.Type, "party_away", "Your lobby is reserved while its party is in a match. Wait for everyone to return.")
		return true
	}
	if r.Queue != nil && (admin || m.Type == "ready") {
		queueError(c, m.Type, "queue_locked", "Cancel matchmaking before changing the setup. Use the queue panel to confirm this search.")
		return true
	}
	return false
}

func (h *Hub) joinQueue(c *Client, m clientMessage, now time.Time) {
	fail := func(code, text string) { queueError(c, "queue_join", code, text) }
	r, p := c.room, c.player
	if r == nil || p == nil || p.Client != c || !r.contains(p) {
		fail("not_joined", "Join or share a room before queueing.")
		return
	}
	if r.Host != p.ID {
		fail("not_host", "Only your room host can queue the party. Ask them to choose a battle.")
		return
	}
	if r.Queue != nil {
		fail("already_queued", "This room already has a search. Cancel it before choosing another queue.")
		return
	}
	if r.Match != nil || r.hasAway() || r.Game.Phase != "lobby" && r.Game.Phase != "matchOver" {
		fail("match_active", "Return everyone to your room before joining a queue.")
		return
	}
	def, ok := queueDefinition(m.QueueKey)
	if !ok {
		fail("bad_queue", "Choose one of the six supported queues.")
		return
	}
	if len(h.queues) >= 256 {
		fail("queue_full", "The matchmaking service is at its queue limit. Try again later.")
		return
	}
	pilots := []*Player{}
	controllers := []*Player{}
	seen := map[*Player]bool{}
	for _, candidate := range r.Players {
		if candidate == nil || candidate.Kind == "bot" {
			continue
		}
		controller := candidate
		if candidate.Kind == "local" {
			controller = r.member(candidate.Owner)
		}
		if !socketLive(controller) || controller.Kind == "bot" || controller.Kind == "local" {
			fail("party_disconnected", "Every participating player must be connected before queueing.")
			return
		}
		pilots = append(pilots, candidate)
		if !seen[controller] {
			seen[controller] = true
			controllers = append(controllers, controller)
		}
	}
	if len(pilots) == 0 {
		fail("no_players", "At least one real player must be playing, not spectating. Bots never fill queue slots.")
		return
	}
	if len(pilots) > 3 {
		fail("party_too_large", "Queue parties can contain at most three real players, including local Player 2. Spectate or remove extra players first.")
		return
	}
	if def.TeamSize == 0 && len(pilots) != 1 {
		fail("ffa_solo", "Eight-player Free-for-all is solo-entry. Friends cannot stay on one team in Free-for-all.")
		return
	}
	if def.TeamSize > 0 && len(pilots) > def.TeamSize {
		fail("party_too_large", "Your party is larger than a team in this queue. Choose a larger-team battle.")
		return
	}
	h.nextQueueID++
	q := &QueueTicket{ID: h.nextQueueID, Definition: def, Room: r, Leader: p, Pilots: pilots, Controllers: controllers, Accepted: map[*Player]bool{}, Created: now}
	// A host click consents for their keyboard pilots, never for remote friends.
	for _, controller := range controllers {
		q.Accepted[controller] = controller == p
	}
	r.Queue = q
	if h.queues == nil {
		h.queues = map[uint64]*QueueTicket{}
	}
	h.queues[q.ID] = q
	if r.Game.Phase == "matchOver" {
		r.Game.Phase = "lobby"
		r.Game.Tanks = [maxTanks]*Tank{}
		r.Game.Bullets = nil
		r.Game.Pickups = nil
		r.Game.Objectives = nil
		r.Game.Scores = [maxTanks]int{}
		r.Game.Winner = -1
	}
	r.LastAction = now
	h.activateQueue(q, now)
	h.broadcastRoom(r)
}
func (h *Hub) activateQueue(q *QueueTicket, now time.Time) {
	for _, c := range q.Controllers {
		if !q.Accepted[c] {
			return
		}
	}
	if q.Enqueued.IsZero() {
		q.Enqueued = now
	}
}
func (h *Hub) acceptQueue(c *Client, m clientMessage, now time.Time) {
	r := c.room
	if r == nil || r.Queue == nil {
		queueError(c, "queue_accept", "not_queued", "There is no active party invitation.")
		return
	}
	q := r.Queue
	if m.QueueID != q.ID {
		queueError(c, "queue_accept", "stale_queue", "The queue changed. Review the current invitation.")
		return
	}
	if _, ok := q.Accepted[c.player]; !ok {
		queueError(c, "queue_accept", "not_participant", "Only the party's participating controllers need to confirm.")
		return
	}
	if !m.Ready {
		h.cancelQueue(r, "A party member declined. The search was cancelled.")
		return
	}
	q.Accepted[c.player] = true
	h.activateQueue(q, now)
	r.LastAction = now
	h.broadcastRoom(r)
}
func (h *Hub) cancelQueueRequest(c *Client, m clientMessage) {
	r := c.room
	if r == nil || r.Queue == nil {
		queueError(c, "queue_cancel", "not_queued", "No search is active. A match may already have been found.")
		return
	}
	q := r.Queue
	if m.QueueID != q.ID {
		queueError(c, "queue_cancel", "stale_queue", "The search changed. Review the current queue before cancelling.")
		return
	}
	if _, ok := q.Accepted[c.player]; !ok && c.player != q.Leader {
		queueError(c, "queue_cancel", "not_participant", "Only the host or a queued participant can cancel this party's search.")
		return
	}
	h.cancelQueue(r, "Matchmaking cancelled. Your party is still together in this room.")
}
func (q *QueueTicket) involves(p *Player) bool {
	if q.Leader == p {
		return true
	}
	for _, x := range q.Pilots {
		if x == p {
			return true
		}
	}
	for _, x := range q.Controllers {
		if x == p {
			return true
		}
	}
	return false
}
func (h *Hub) cancelQueue(r *Room, message string) {
	if r == nil || r.Queue == nil {
		return
	}
	q := r.Queue
	delete(h.queues, q.ID)
	r.Queue = nil
	for _, p := range r.members() {
		if p.Client != nil {
			p.Client.enqueue(map[string]any{"type": "queue_cancelled", "queueId": q.ID, "message": message})
		}
	}
	h.broadcastRoom(r)
}
func (h *Hub) queueView(q *QueueTicket) any {
	if q == nil {
		return nil
	}
	members := []map[string]any{}
	for _, p := range q.Pilots {
		controller := p
		if p.Kind == "local" {
			controller = q.Room.member(p.Owner)
		}
		members = append(members, map[string]any{"member": p.Member, "name": p.Name, "kind": playerKind(p), "controller": controller.Member, "accepted": q.Accepted[controller]})
	}
	stage := "confirming"
	if !q.Enqueued.IsZero() {
		stage = "searching"
	}
	started := q.Created
	if !q.Enqueued.IsZero() {
		started = q.Enqueued
	}
	return map[string]any{"id": q.ID, "key": q.Definition.Key, "name": q.Definition.Name, "stage": stage, "players": len(q.Pilots), "required": q.Definition.Players, "members": members, "since": started.UnixMilli()}
}
func (h *Hub) queueCatalog() []map[string]any {
	result := []map[string]any{}
	for _, d := range queueDefinitions {
		people, parties := 0, 0
		for _, q := range h.queues {
			if q.Definition.Key == d.Key && !q.Enqueued.IsZero() {
				people += len(q.Pilots)
				parties++
			}
		}
		result = append(result, map[string]any{"definition": d, "waitingPlayers": people, "waitingParties": parties})
	}
	return result
}
func (h *Hub) queueValid(q *QueueTicket) bool {
	if q.Room.Queue != q || h.rooms[q.Room.Code] != q.Room || q.Room.hasAway() || q.Room.Game.Phase != "lobby" && q.Room.Game.Phase != "matchOver" {
		return false
	}
	for _, c := range q.Controllers {
		if !socketLive(c) || c.Client.room != q.Room || !q.Room.contains(c) {
			return false
		}
	}
	n := 0
	for _, p := range q.Room.Players {
		if p != nil && p.Kind != "bot" {
			n++
		}
	}
	if n != len(q.Pilots) {
		return false
	}
	for _, p := range q.Pilots {
		if !q.Room.contains(p) || p.Spectating || p.Kind == "bot" {
			return false
		}
	}
	return true
}

// Exact two-bin packing keeps parties whole (2+1 versus 3 is legal; three
// two-person parties cannot form 3v3). Try the oldest feasible party first;
// randomize compatible fillers and the two sides, not skill or hidden bots.
func packQueue(pool []*QueueTicket, d QueueDefinition, rng *mrand.Rand) [2][]*QueueTicket {
	var empty [2][]*QueueTicket
	sort.Slice(pool, func(i, j int) bool {
		return pool[i].Enqueued.Before(pool[j].Enqueued) || pool[i].Enqueued.Equal(pool[j].Enqueued) && pool[i].ID < pool[j].ID
	})
	if d.TeamSize == 0 {
		if len(pool) < d.Players {
			return empty
		}
		rest := append([]*QueueTicket{}, pool[1:]...)
		rng.Shuffle(len(rest), func(i, j int) { rest[i], rest[j] = rest[j], rest[i] })
		empty[0] = append([]*QueueTicket{pool[0]}, rest[:d.Players-1]...)
		return empty
	}
	// An anchor's identity does not affect packing, only its party size. If the
	// earliest anchor of a size cannot fit with the larger remaining pool, a
	// later one of that same size cannot either. This bounds failed packing to
	// at most three passes, including a queue full of incompatible two-person parties.
	total := 0
	for _, q := range pool {
		total += len(q.Pilots)
	}
	if total < d.Players {
		return empty
	}
	triedSize := [4]bool{}
	type node struct{ sides [2][]*QueueTicket }
	for anchor := 0; anchor < len(pool); anchor++ {
		first := pool[anchor]
		size := len(first.Pilots)
		if size < 1 || size > d.TeamSize || triedSize[size] {
			continue
		}
		triedSize[size] = true
		var dp [4][4]*node
		dp[size][0] = &node{sides: [2][]*QueueTicket{{first}, nil}}
		rest := append([]*QueueTicket{}, pool[anchor+1:]...)
		rng.Shuffle(len(rest), func(i, j int) { rest[i], rest[j] = rest[j], rest[i] })
		for _, q := range rest {
			n := len(q.Pilots)
			for a := d.TeamSize; a >= 0; a-- {
				for b := d.TeamSize; b >= 0; b-- {
					prev := dp[a][b]
					if prev == nil {
						continue
					}
					for side := 0; side < 2; side++ {
						x, y := a, b
						if side == 0 {
							x += n
						} else {
							y += n
						}
						if x > d.TeamSize || y > d.TeamSize || dp[x][y] != nil {
							continue
						}
						next := &node{sides: [2][]*QueueTicket{append([]*QueueTicket{}, prev.sides[0]...), append([]*QueueTicket{}, prev.sides[1]...)}}
						next.sides[side] = append(next.sides[side], q)
						dp[x][y] = next
					}
				}
			}
			if found := dp[d.TeamSize][d.TeamSize]; found != nil {
				if rng.Intn(2) == 1 {
					found.sides[0], found.sides[1] = found.sides[1], found.sides[0]
				}
				return found.sides
			}
		}
	}
	return empty
}
func (h *Hub) tickQueues(now time.Time) {
	if now.Before(h.nextQueueScan) {
		return
	}
	h.nextQueueScan = now.Add(250 * time.Millisecond)
	for key, route := range h.resumeRoutes {
		if !now.Before(route.Until) || h.rooms[route.Room.Code] != route.Room {
			delete(h.resumeRoutes, key)
		}
	}
	for _, q := range h.queues {
		if !h.queueValid(q) {
			h.cancelQueue(q.Room, "The party changed or disconnected. Join the queue again when ready.")
		} else if q.Enqueued.IsZero() && now.Sub(q.Created) > 2*time.Minute {
			h.cancelQueue(q.Room, "The party invitation expired before everyone confirmed.")
		}
	}
	if len(h.queues) == 0 {
		return
	}
	var seed [8]byte
	if _, err := rand.Read(seed[:]); err == nil {
		rng := mrand.New(mrand.NewSource(int64(binary.LittleEndian.Uint64(seed[:]))))
		made := 0
		for _, d := range queueDefinitions {
			for made < 4 && len(h.rooms) < h.maxRooms {
				pool := []*QueueTicket{}
				for _, q := range h.queues {
					if q.Definition.Key == d.Key && !q.Enqueued.IsZero() {
						pool = append(pool, q)
					}
				}
				sides := packQueue(pool, d, rng)
				if len(sides[0]) == 0 {
					break
				}
				if !h.createQueueMatch(sides, d, now) {
					break
				}
				made++
			}
		}
	}
	if !now.Before(h.nextQueueStatus) {
		h.nextQueueStatus = now.Add(time.Second)
		catalog := h.queueCatalog()
		for _, q := range h.queues {
			for _, p := range q.Room.members() {
				if p.Client != nil {
					p.Client.enqueue(map[string]any{"type": "queue_status", "queue": h.queueView(q), "queues": catalog, "capacityBlocked": len(h.rooms) >= h.maxRooms})
				}
			}
		}
	}
}

func (h *Hub) createQueueMatch(sides [2][]*QueueTicket, d QueueDefinition, now time.Time) bool {
	if len(h.rooms) >= h.maxRooms {
		return false
	}
	tickets := append(append([]*QueueTicket{}, sides[0]...), sides[1]...)
	for _, q := range tickets {
		if !h.queueValid(q) || q.Enqueued.IsZero() {
			return false
		}
	}
	// Generate every fallible resource before changing any room or player.
	code := ""
	for i := 0; i < 16; i++ {
		s, err := roomCode()
		if err != nil {
			return false
		}
		if h.rooms[s] == nil {
			code = s
			break
		}
	}
	if code == "" {
		return false
	}
	var seed [8]byte
	if _, err := rand.Read(seed[:]); err != nil {
		return false
	}
	battle := &Room{Code: code, Host: -1, Game: newGame(int64(binary.LittleEndian.Uint64(seed[:]))), LastAction: now, Match: &QueueMatch{Definition: d, Started: now}}
	battle.Game.Rules = queueRules(d)
	travels := []*MatchTravel{}
	byOriginal := map[*Player]*Player{}
	slot := 0
	for side, qs := range sides {
		for _, q := range qs {
			for _, old := range q.Pilots {
				n := *old
				n.Away = nil
				n.Return = nil
				n.ID = slot
				n.Spectating = false
				n.Team = side + 1
				if d.TeamSize == 0 {
					n.Team = 0
				} else {
					// Public team battles expose only the team paint. Preserve the
					// player's private-room FFA preference on the original member.
					n.ColorIndex = nil
				}
				n.Input = Input{}
				n.FirePending = false
				n.Ready = false
				n.InputAt = now
				n.DisconnectedAt = time.Time{}
				battle.NextMember++
				n.Member = battle.NextMember
				travel := &MatchTravel{Home: q.Room, Original: old, Battle: battle, Pilot: &n}
				n.Return = travel
				battle.Players[slot] = &n
				byOriginal[old] = &n
				travels = append(travels, travel)
				slot++
			}
		}
	}
	if slot != d.Players {
		return false
	}
	// An observing primary still supplies the active P2's socket. Likewise keep
	// a dependent local spectator attached, without using a battle tank seat.
	for _, q := range tickets {
		for _, controller := range q.Controllers {
			linked := []*Player{controller}
			for _, p := range q.Room.members() {
				if p.Kind == "local" && p.Owner == controller.ID {
					linked = append(linked, p)
				}
			}
			for _, old := range linked {
				if byOriginal[old] != nil {
					continue
				}
				n := *old
				n.Away = nil
				n.Return = nil
				n.ID = battle.viewerID()
				n.Spectating = true
				n.Input = Input{}
				n.FirePending = false
				n.Ready = false
				n.InputAt = now
				battle.NextMember++
				n.Member = battle.NextMember
				travel := &MatchTravel{Home: q.Room, Original: old, Battle: battle, Pilot: &n}
				n.Return = travel
				battle.putViewer(&n)
				byOriginal[old] = &n
				travels = append(travels, travel)
			}
		}
	}
	if len(battle.Spectators) > maxSpectators {
		return false
	}
	for _, tr := range travels {
		p, old := tr.Pilot, tr.Original
		if old.Kind == "local" {
			controller := old.Controller
			if controller == nil {
				controller = tr.Home.member(old.Owner)
			}
			p.Controller = byOriginal[controller]
			if p.Controller == nil {
				return false
			}
			p.Owner = p.Controller.ID
		}
	}
	if battle.Game.lineupError(battle.Players) != "" {
		return false
	}
	h.rooms[code] = battle
	for _, q := range tickets {
		delete(h.queues, q.ID)
		q.Room.Queue = nil
		q.Room.LastAction = now
	}
	for _, tr := range travels {
		old, p := tr.Original, tr.Pilot
		old.Away = tr
		old.Client = nil
		old.Input = Input{}
		old.FirePending = false
		old.Ready = false
		if p.Client != nil {
			p.Client.room = battle
			p.Client.player = p
			p.Client.mapGeneration = -1
		}
	}
	battle.Game.startMatch(battle.Players)
	battle.Game.PhaseTime = 4 // A shared countdown, not an invitation/readiness race.
	for _, p := range battle.members() {
		if p.Client != nil {
			h.travelWelcome(p.Client, battle, p, "match_found")
		}
	}
	h.broadcastRoom(battle)
	h.broadcastState(battle)
	for _, q := range tickets {
		h.broadcastRoom(q.Room)
	}
	return true
}
func (h *Hub) travelWelcome(c *Client, r *Room, p *Player, reason string) {
	// Drop obsolete replaceable snapshots; reliable packets stay ordered before
	// this welcome, then a forced new-world packet follows. No reconnect needed.
	if c.updates != nil {
		select {
		case <-c.updates:
		default:
		}
	}
	c.enqueue(map[string]any{"type": "welcome", "protocol": 1, "room": r.Code, "id": p.ID, "member": p.Member, "token": p.Token, "resumed": false, "created": false, "spectating": p.Spectating, "transfer": reason, "matchmaking": matchView(r)})
	h.sendChatHistory(c, r)
}

// Return the authenticated controller and its keyboard dependants, never other
// party members. Their original slots remain reserved; each friend returns at
// their own pace. A return during play forfeits those tanks, without free kills.

func (h *Hub) requestQueueRematch(c *Client, now time.Time) {
	r, p := c.room, c.player
	if r == nil || p == nil || p.Client != c || p.Return == nil || r.Match == nil {
		queueError(c, "rematch", "no_match", "This player is not part of a matchmaking battle.")
		return
	}
	if r.Game.Phase != "matchOver" {
		queueError(c, "rematch", "match_active", "A rematch can be requested after the current match ends.")
		return
	}
	// Queue matches are hostless. A rematch therefore starts only after every
	// participating network controller asks for one; local P2 never votes twice.
	activePilots := 0
	for _, pilot := range r.Players {
		if pilot != nil && pilot.Return != nil && !pilot.Spectating {
			activePilots++
		}
	}
	if activePilots != r.Match.Definition.Players {
		queueError(c, "rematch", "lineup_changed", "A player already returned to their room, so this battle cannot be rematched.")
		return
	}
	if r.Match.Rematch == nil {
		r.Match.Rematch = map[uint64]bool{}
	}
	r.Match.Rematch[p.Member] = true
	required, ready := 0, true
	for _, controller := range r.members() {
		if controller == nil || controller.Return == nil || controller.Kind == "local" {
			continue
		}
		required++
		// A socket may already be closed while removeClient is still waiting
		// for Hub.mu. Never start a rematch around a disconnected participant.
		if !socketLive(controller) || !r.Match.Rematch[controller.Member] {
			ready = false
		}
	}
	if required == 0 {
		ready = false
	}
	r.LastAction = now
	if !ready {
		h.broadcastRoom(r)
		return
	}
	r.Match.Rematch = nil
	r.Match.Started = now
	r.Game.startMatch(r.Players)
	r.Game.PhaseTime = 4
	for _, member := range r.members() {
		if member != nil {
			member.Ready = false
		}
	}
	h.broadcastRoom(r)
	h.broadcastState(r)
}

func (h *Hub) returnToParty(c *Client, now time.Time) {
	if c.room == nil || c.player == nil || c.player.Client != c || c.player.Return == nil {
		queueError(c, "return_party", "no_party", "This spectator has no reserved party in this match.")
		return
	}
	battle, p := c.room, c.player
	home := p.Return.Home
	group := []*MatchTravel{p.Return}
	for _, other := range battle.members() {
		if other.Kind == "local" && other.Controller == p && other.Return != nil {
			group = append(group, other.Return)
		}
	}
	original := p.Return.Original
	if h.resumeRoutes == nil {
		h.resumeRoutes = map[resumeRouteKey]resumeRoute{}
	}
	// Bound short handoff recovery metadata independently of room churn.
	if len(h.resumeRoutes) >= 1024 {
		for key := range h.resumeRoutes {
			delete(h.resumeRoutes, key)
			break
		}
	}
	h.resumeRoutes[resumeRouteKey{battle.Code, sha256.Sum256([]byte(p.Token))}] = resumeRoute{home, now.Add(reconnectGrace)}
	for _, tr := range group {
		old, n := tr.Original, tr.Pilot
		if battle.Match != nil && battle.Match.Rematch != nil {
			delete(battle.Match.Rematch, n.Member)
		}
		old.Name = n.Name
		old.Away = nil
		old.Return = nil
		old.Input = Input{}
		old.FirePending = false
		old.Ready = false
		old.InputAt = now
		old.DisconnectedAt = time.Time{}
		n.Return = nil
		n.Client = nil
	}
	h.expirePlayer(battle, p.ID)
	original.Client = c
	c.room = home
	c.player = original
	c.mapGeneration = -1
	home.LastAction = now
	h.electHost(home)
	// Home has always remained a setup, never a parallel live game.
	h.travelWelcome(c, home, original, "party_return")
	h.broadcastRoom(home)
	h.sendState(c, home)
	h.finishQueueForfeit(battle)
	h.broadcastRoom(battle)
	h.broadcastState(battle)
}
func (h *Hub) abandonTravel(tr *MatchTravel) {
	if tr == nil {
		return
	}
	tr.Pilot.Return = nil
	tr.Original.Away = nil
	// Make old credentials unusable at the origin after an explicit leave or a
	// reconnect timeout. A fresh manual join remains possible as usual.
	h.expirePlayer(tr.Home, tr.Original.ID)
	h.broadcastRoom(tr.Home)
}
func (h *Hub) finishQueueForfeit(r *Room) {
	if r.Match == nil || r.Game.Phase == "matchOver" || r.Game.Phase == "roundOver" && r.Game.roundClinched {
		return
	}
	sides := map[int]int{}
	for id, p := range r.Players {
		if p != nil {
			sides[sideKey(id, p.Team)] = id
		}
	}
	if len(sides) < 2 {
		winner := -1
		for _, id := range sides {
			winner = id
		}
		r.Game.finishMatchStats(winner)
		r.Game.Winner = winner
		r.Game.Phase = "matchOver"
		r.Game.PhaseTime = 0
		r.Game.emit("matchEnd", nil, winner, "Opponent left the match.")
	} else if r.Game.Phase == "lobby" {
		// A short disconnect is still a reserved participant. Wait through reconnect
		// grace instead of turning a fixed public match into an editable lobby.
		r.Game.Phase = "roundOver"
		r.Game.PhaseTime = .5
	}
}
func (q *QueueTicket) String() string {
	return fmt.Sprintf("queue(%s,%d,%d pilots)", q.Definition.Key, q.ID, len(q.Pilots))
}
