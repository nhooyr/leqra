package main

import (
	"sort"
	"time"
)

// Spectators are room members, not hidden tanks. They consume neither one of
// the eight combat seats nor a ready vote. Bounds also cover disconnected members.
const maxSpectators = 16

func (r *Room) member(id int) *Player {
	if id >= 0 && id < len(r.Players) {
		return r.Players[id]
	}
	return r.Spectators[id]
}
func (r *Room) contains(p *Player) bool { return p != nil && r.member(p.ID) == p }
func (r *Room) members() []*Player {
	return r.appendMembers(make([]*Player, 0, maxTanks+len(r.Spectators)))
}

// The tick loop supplies stack storage; other callers retain an independent
// snapshot. Keep spectator ordering identical without allocating an ID slice
// for the normal, bounded roster.
func (r *Room) appendMembers(all []*Player) []*Player {
	for _, p := range r.Players {
		if p != nil {
			all = append(all, p)
		}
	}
	var storage [maxSpectators]int
	ids := storage[:0]
	for id := range r.Spectators {
		ids = append(ids, id)
	}
	sort.Ints(ids)
	for _, id := range ids {
		all = append(all, r.Spectators[id])
	}
	return all
}

func (r *Room) tankFor(p *Player) *Tank {
	if p == nil || p.Spectating || p.ID < 0 || p.ID >= maxTanks {
		return nil
	}
	return r.Game.Tanks[p.ID]
}
func (r *Room) viewerID() int {
	if r.NextViewerID < maxTanks {
		r.NextViewerID = maxTanks
	}
	id := r.NextViewerID
	r.NextViewerID++
	return id
}
func (r *Room) putViewer(p *Player) {
	if r.Spectators == nil {
		r.Spectators = map[int]*Player{}
	}
	r.Spectators[p.ID] = p
}
func (r *Room) freeJoinSeat() int {
	if r.Game.survivalMode() && (r.survivalRunning() || participantCount(r.Players) >= survivalMaxPlayers) {
		return -1
	}
	for id, p := range r.Players {
		if p == nil && (r.Game.Phase == "lobby" || r.Game.Phase == "matchOver" || r.Game.Tanks[id] == nil) {
			return id
		}
	}
	return -1
}
func (r *Room) freeCombatSeat() int {
	for id, p := range r.Players {
		if p == nil {
			return id
		}
	}
	return -1
}

// Clear every gameplay effect owned by a vacated seat before it is reused.
// Drop carried objectives before deleting the tank. Spectators cannot carry,
// score, respawn, collect or fire through a former combat identity.
func (r *Room) clearCombatSeat(id int) {
	if id < 0 || id >= maxTanks {
		return
	}
	g := r.Game
	if t := g.Tanks[id]; t != nil && t.stats != nil {
		// A seat's score may be reset or inherited by its next occupant. Keep
		// the departed participant's earned result before that identity is lost.
		if t.stats.Active {
			t.stats.Score = g.Scores[id]
		}
		t.stats.Active = false
	}
	g.dropFlags(id)
	if t := g.Tanks[id]; t != nil && t.Alive {
		t.Alive = false
		t.VX = 0
		t.VY = 0
		g.emit("hit", t, -1, t.Name+" left the arena.")
	}
	g.Tanks[id] = nil
	live := g.Bullets[:0]
	for _, b := range g.Bullets {
		if b.Owner != id {
			live = append(live, b)
		}
	}
	g.Bullets = live
	// A missile locked onto the removed occupant must reacquire, not inherit a
	// target because a different person happens to be assigned this slot.
	for _, b := range g.Bullets {
		if b.Target == id {
			b.Target = -1
		}
	}
}
func (r *Room) initializeSeat(p *Player, inheritScore int) {
	id := p.ID
	g := r.Game
	g.Scores[id] = 0
	if inheritScore >= 0 {
		g.Scores[id] = inheritScore
	} else if p.Team > 0 {
		for otherID, other := range r.Players {
			if other != nil && otherID != id && other.Team == p.Team && g.Scores[otherID] > g.Scores[id] {
				g.Scores[id] = g.Scores[otherID]
			}
		}
	}
	// Joining a running elimination round never grants an extra life. Objectives
	// use their normal delayed respawn and spawn-protection rules.
	if g.Phase != "lobby" && g.Phase != "matchOver" {
		r.RoleVersion++
		t := &Tank{ID: id, Name: p.Name, Team: p.Team, Color: selectedColor(id, p.Team, p.ColorIndex, r.Game.settings()), R: tankRadius, Alive: false, X: cellSize / 2, Y: cellSize / 2, SpawnSerial: 1000000 + r.RoleVersion*10000}
		if g.objectiveMode() {
			t.RespawnTime = float64(g.settings().RespawnSeconds)
		}
		g.Tanks[id] = t
		g.bindTankStats(t, p)
	}
}

// Membership and host authority survive role changes. Controller pointers keep
// the secondary keyboard tank attached even when its owner watches the game.
func (r *Room) moveMember(p *Player, id int, spectating bool) {
	old := p.ID
	if p.Spectating {
		delete(r.Spectators, old)
	} else {
		r.clearCombatSeat(old)
		r.Players[old] = nil
	}
	p.ID = id
	p.Spectating = spectating
	p.Input = Input{}
	p.FirePending = false
	p.Ready = false
	if spectating {
		r.putViewer(p)
	} else {
		r.Players[id] = p
	}
	if r.Host == old {
		r.Host = id
	}
	if p.Kind != "local" && p.Kind != "bot" {
		for _, other := range r.members() {
			if other.Kind == "local" && other.Owner == old {
				other.Owner = id
				other.Controller = p
				other.Input = Input{}
				other.FirePending = false
			}
		}
	}
}
func (h *Hub) roleChanged(r *Room, now time.Time) {
	r.LastAction = now
	// A different member changing roles must not release unrelated players'
	// held controls or rewind their acknowledgement history.
	for _, p := range r.Players {
		if p != nil {
			p.Ready = false
		}
	}
	h.electHost(r)
	// This reliable identity message precedes the roster and forced world state.
	// It invalidates local input history without issuing a new reconnect token.
	for _, p := range r.members() {
		if p.Client != nil {
			localID, localMember := -1, uint64(0)
			for _, child := range r.members() {
				if child.Kind == "local" && child.Owner == p.ID {
					localID, localMember = child.ID, child.Member
					break
				}
			}
			p.Client.enqueue(map[string]any{"type": "identity", "id": p.ID, "member": p.Member, "spectating": p.Spectating, "localId": localID, "localMember": localMember})
			p.Client.mapGeneration = -1
		}
	}
	h.broadcastRoom(r)
	for _, p := range r.members() {
		if p.Client != nil {
			h.sendState(p.Client, r)
		}
	}
}
func (h *Hub) setSpectating(c *Client, m clientMessage, now time.Time) {
	fail := func(code, text string) { e := roomError(code, text); e["action"] = "spectate"; c.enqueue(e) }
	r, p := c.room, c.player
	if r == nil || p == nil || p.Client != c || !r.contains(p) {
		fail("not_joined", "Join a room first.")
		return
	}
	if m.Spectating == nil {
		fail("bad_role", "Choose Play or Spectate.")
		return
	}
	// A controller may change either of its own local roles, never a guest's.
	if m.Target != nil {
		target := r.member(*m.Target)
		if target == nil || target.Member != m.Member {
			fail("player_missing", "That member has changed. Check the room.")
			return
		}
		if target != p && (target.Kind != "local" || target.Owner != p.ID) {
			fail("not_owned", "You can only toggle your own pilots.")
			return
		}
		p = target
	}
	if p.Spectating == *m.Spectating {
		h.broadcastRoom(r)
		return
	}
	if !*m.Spectating && r.Game.survivalMode() {
		if r.survivalRunning() {
			fail("survival_active", "Join the squad between survival runs. This run is already underway.")
			return
		}
		if participantCount(r.Players) >= survivalMaxPlayers {
			fail("survival_full", "The four-player survival squad is full.")
			return
		}
	}
	h.cancelQueue(r, "A player changed roles. Join the queue again when the party is ready.")
	if *m.Spectating {
		if len(r.Spectators) >= maxSpectators {
			fail("spectators_full", "The spectator gallery is full. Try again after a spectator leaves.")
			return
		}
		r.moveMember(p, r.viewerID(), true)
	} else {
		id := r.freeCombatSeat()
		if id < 0 {
			fail("no_seat", "All eight tank seats are occupied. Keep spectating or ask the host for a swap.")
			return
		}
		if p.Kind == "local" {
			owner := r.member(p.Owner)
			if owner == nil || owner.Client == nil {
				fail("not_connected", "The local controller is reconnecting.")
				return
			}
		}
		p.Team = joinTeam(r)
		r.moveMember(p, id, false)
		r.initializeSeat(p, -1)
	}
	h.roleChanged(r, now)
}
func (h *Hub) swapSpectator(c *Client, m clientMessage, now time.Time) {
	r, ok := h.editableHost(c, "swap")
	if !ok {
		return
	}
	fail := func(code, text string) { e := roomError(code, text); e["action"] = "swap"; c.enqueue(e) }
	if r.survivalRunning() {
		fail("survival_active", "Swap players between survival runs. This run is already underway.")
		return
	}
	if m.Target == nil || m.Spectator == nil || m.Member == 0 || m.SpectatorMember == 0 {
		fail("bad_target", "Select an active player and a spectator.")
		return
	}
	active, viewer := r.member(*m.Target), r.member(*m.Spectator)
	if active == nil || viewer == nil || active.Member != m.Member || viewer.Member != m.SpectatorMember || active.Spectating || !viewer.Spectating {
		fail("player_missing", "The lineup changed. Choose the players again.")
		return
	}
	if active.Kind == "bot" || viewer.Kind == "bot" {
		fail("bad_target", "Swap human players. Remove a bot to make an open seat instead.")
		return
	}
	connected := viewer.Client != nil
	if viewer.Kind == "local" {
		owner := r.member(viewer.Owner)
		connected = owner != nil && owner.Client != nil
	}
	if !connected {
		fail("not_connected", "Wait for that spectator to reconnect before swapping.")
		return
	}
	// Atomic exchange under Hub.mu, even when the gallery or arena is full. The
	// replacement takes the seat's side and score, but never its tank or weapon.
	slot, viewerID, team, score := active.ID, viewer.ID, active.Team, r.Game.Scores[active.ID]
	delete(r.Spectators, viewerID)
	r.moveMember(active, viewerID, true)
	// viewer is temporarily outside the collections; do not delete active at its
	// new ID while moving the incoming member into the vacated combat seat.
	viewer.Spectating = false
	viewer.ID = slot
	viewer.Team = team
	viewer.Input = Input{}
	viewer.FirePending = false
	viewer.Ready = false
	r.Players[slot] = viewer
	// The incoming local spectator was temporarily removed from the member
	// collections during the atomic exchange. Update its owner explicitly when
	// it swaps with its own primary controller, which has just become a viewer.
	if viewer.Kind == "local" && viewer.Controller != nil {
		viewer.Owner = viewer.Controller.ID
	}
	if r.Host == viewerID && active.Client != c {
		r.Host = slot
	}
	if viewer.Kind != "local" {
		for _, other := range r.members() {
			if other.Kind == "local" && other.Controller == viewer {
				other.Owner = slot
				other.Input = Input{}
				other.FirePending = false
			}
		}
	}
	r.initializeSeat(viewer, score)
	h.roleChanged(r, now)
	c.enqueue(map[string]any{"type": "swapped", "message": viewer.Name + " is now playing; " + active.Name + " is spectating."})
}
