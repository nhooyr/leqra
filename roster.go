package main

import "time"

// Seats are gameplay identities; sockets are controllers. A second keyboard
// pilot shares a controller but never a credential or input sequence.
type SeatSpec struct {
	Spectating bool   `json:"spectating,omitempty"`
	Name       string `json:"name"`
	Kind       string `json:"kind"`
	Difficulty string `json:"difficulty"`
	Team       int    `json:"team"`
	ColorIndex *int   `json:"colorIndex,omitempty"`
}

func playerKind(p *Player) string {
	if p.Kind == "" {
		return "human"
	}
	return p.Kind
}
func validDifficulty(s string) bool {
	return s == "easy" || s == "normal" || s == "hard" || s == "godlike"
}
func sideKey(id, team int) int {
	if team > 0 {
		return team
	}
	return -id - 1
}
func participantColor(id, team int) string {
	if team > 0 && team <= 4 {
		return tankColors[team-1]
	}
	return tankColors[id%maxTanks]
}
func participantAvailable(ps [maxTanks]*Player, id int) bool {
	if id < 0 || id >= len(ps) || ps[id] == nil {
		return false
	}
	p := ps[id]
	if p.Away != nil {
		return false
	}
	if p.Kind == "bot" {
		return true
	}
	if p.Kind == "local" {
		if p.Controller != nil {
			return p.Controller.Client != nil
		}
		return p.Owner >= 0 && p.Owner < len(ps) && ps[p.Owner] != nil && ps[p.Owner].Kind != "local" && ps[p.Owner].Kind != "bot" && ps[p.Owner].Client != nil
	}
	return p.Client != nil
}
func availableSides(ps [maxTanks]*Player) int {
	sides := map[int]bool{}
	for id, p := range ps {
		if p != nil && participantAvailable(ps, id) {
			sides[sideKey(id, p.Team)] = true
		}
	}
	return len(sides)
}
func (g *Game) canDamage(owner int, target *Tank) bool {
	if target == nil || owner < 0 || owner >= len(g.Tanks) {
		return false
	}
	shooter := g.Tanks[owner]
	// Allow isolated test/projectile fixtures with an absent shooter, but never
	// accept such projectiles from clients. Network ownership is socket-derived.
	if shooter == nil {
		return true
	}
	if shooter.ID == target.ID {
		return true // Self damage is not friendly fire, for ANY seat or bot.
	}
	return g.settings().FriendlyFire || shooter.Team == 0 || shooter.Team != target.Team
}

// Target selection is intentionally independent of damage permission. Enabling
// friendly fire never makes bots or missile seekers deliberately hunt allies.
func (g *Game) isOpponent(owner int, target *Tank) bool {
	if target == nil || target.ID == owner || owner < 0 || owner >= len(g.Tanks) {
		return false
	}
	shooter := g.Tanks[owner]
	return shooter == nil || shooter.Team == 0 || shooter.Team != target.Team
}
func (h *Hub) editableHost(c *Client, action string) (*Room, bool) {
	fail := func(code, msg string) { e := roomError(code, msg); e["action"] = action; c.enqueue(e) }
	if c.room == nil || c.player == nil || c.player.Client != c || !c.room.contains(c.player) {
		fail("not_joined", "Join a room first.")
		return nil, false
	}
	if c.room.Host != c.player.ID {
		fail("not_host", "Only the host can change the room setup.")
		return nil, false
	}
	return c.room, true
}
func resetReady(r *Room) {
	for _, p := range r.Players {
		if p != nil {
			p.Ready = false
			p.Input = Input{}
			p.FirePending = false
		}
	}
}
func (h *Hub) configureRoom(c *Client, m clientMessage, now time.Time) {
	r, ok := h.editableHost(c, m.Type)
	if !ok {
		return
	}
	fail := func(code, msg string) { e := roomError(code, msg); e["action"] = m.Type; c.enqueue(e) }
	if m.Type == "lobby" {
		r.Game.Phase = "lobby"
		r.Game.PhaseTime = 0
		r.Game.Winner = -1
		r.Game.Bullets = []*Bullet{}
		r.Game.Pickups = []*Pickup{}
		r.Game.Tanks = [maxTanks]*Tank{}
		r.Game.Objectives = nil
		r.Game.survivalCheckpoint = nil
		r.Game.Scores = [maxTanks]int{}
		resetReady(r)
		r.LastAction = now
		h.broadcastRoom(r)
		for _, p := range r.members() {
			if p.Client != nil {
				h.sendState(p.Client, r)
			}
		}
		return
	}
	if r.Game.Phase != "lobby" && r.Game.Phase != "matchOver" {
		fail("match_active", "Return to the room before changing the roster or teams.")
		return
	}
	if r.Game.settings().TeamMode == "ffa" && m.Team != nil && *m.Team != 0 {
		fail("teams_locked", "Free-for-all is enabled by the host. Team selection is locked.")
		return
	}
	if r.Game.settings().TeamMode == "teams" && m.Team != nil && (*m.Team < 1 || *m.Team > 4) {
		fail("bad_team", "Choose one of the four teams. Free-for-all is a room-wide rule.")
		return
	}
	if r.Game.settings().Mode == "ctf" && m.Team != nil && (*m.Team < 1 || *m.Team > 2) {
		fail("bad_team", "Capture the Flag uses Team 1 and Team 2.")
		return
	}
	if r.Game.survivalMode() && m.Team != nil && *m.Team != 1 {
		fail("bad_team", "Survival players share Team 1.")
		return
	}
	if m.ColorIndex != nil {
		fail("paint_action", "Tank paint uses the owner-aware paint action.")
		return
	}
	if m.Type == "add" {
		if r.Game.survivalMode() && participantCount(r.Players) >= survivalMaxPlayers {
			fail("survival_full", "The four-player survival squad is full.")
			return
		}
		if m.Kind != "bot" && m.Kind != "local" {
			fail("bad_kind", "Add a bot or a second local player.")
			return
		}
		difficulty := m.Difficulty
		if m.Kind == "bot" && difficulty == "" {
			difficulty = "normal"
			// Roster order is seat order. Resolve against the current roster so
			// a queued difficulty edit is reflected by the next Add Bot action.
			for id := len(r.Players) - 1; id >= 0; id-- {
				if p := r.Players[id]; p != nil && p.Kind == "bot" {
					if validDifficulty(p.Difficulty) {
						difficulty = p.Difficulty
					}
					break
				}
			}
		}
		if m.Kind == "bot" && !validDifficulty(difficulty) {
			fail("bad_difficulty", "Choose Chill, Normal, Fierce, or Godlike.")
			return
		}
		if m.Team != nil && (*m.Team < 0 || *m.Team > 4) {
			fail("bad_team", "Choose one of the four teams.")
			return
		}
		slot := r.freeCombatSeat()
		for _, p := range r.members() {
			if p != nil && p.Kind == "local" && m.Kind == "local" {
				fail("local_exists", "There is already a second local player in this room.")
				return
			}
		}
		if slot < 0 {
			fail("room_full", "All eight seats are occupied. Remove a pilot or bot first.")
			return
		}
		r.NextMember++
		name := m.Name
		if name == "" {
			if m.Kind == "bot" {
				name = "BOT"
			} else {
				name = "PLAYER 2"
			}
		}
		p := &Player{ID: slot, Member: r.NextMember, Name: cleanName(name), Kind: m.Kind, Owner: c.player.ID, Controller: c.player, Difficulty: difficulty, Ready: true, InputAt: now}
		// Decide against the current authoritative roster, not a stale client
		// count. The host can change this assignment after the tank is added.
		p.Team = joinTeam(r)
		r.Players[slot] = p
		r.Game.Scores[slot] = 0
	} else {
		if m.Target == nil || *m.Target < 0 || *m.Target >= maxTanks || m.Member == 0 {
			fail("bad_target", "Select a current room participant.")
			return
		}
		p := r.member(*m.Target)
		if p == nil || p.Member != m.Member {
			fail("player_missing", "That seat has changed. Check the roster.")
			return
		}
		if m.Team != nil && (*m.Team < 0 || *m.Team > 4) {
			fail("bad_team", "Choose one of the four teams.")
			return
		}
		if m.Difficulty != "" && (p.Kind != "bot" || !validDifficulty(m.Difficulty)) {
			fail("bad_difficulty", "Only bots have a difficulty setting.")
			return
		}
		if m.Name != "" && (p.Kind != "bot" && p.Kind != "local" || cleanCallsign(m.Name) == "") {
			fail("bad_name", "Pilots change their own callsigns.")
			return
		}
		if m.Team != nil {
			p.Team = *m.Team
		}
		if m.Difficulty != "" {
			p.Difficulty = m.Difficulty
		}
		if m.Name != "" {
			p.Name = cleanCallsign(m.Name)
		}
	}
	applyFormat(r)
	// Ready is consent to this roster/teams, not to an earlier configuration.
	resetReady(r)
	r.LastAction = now
	h.broadcastRoom(r)
}

// FFA paint is cosmetic and owner-scoped. A remote human paints only their own
// tank; a local P2 is painted by its controller; bots are painted by the host.
// Team games reject per-tank paint because the team color is authoritative.
func (h *Hub) paintTank(c *Client, m clientMessage, now time.Time) {
	fail := func(code, text string) { e := roomError(code, text); e["action"] = "paint"; c.enqueue(e) }
	if c.room == nil || c.player == nil || c.player.Client != c || !c.room.contains(c.player) {
		fail("not_joined", "Join a room before changing tank color.")
		return
	}
	r := c.room
	if r.Game.Phase != "lobby" && r.Game.Phase != "matchOver" {
		fail("match_active", "Change tank color between matches.")
		return
	}
	if r.Game.settings().TeamMode != "ffa" {
		fail("team_color_locked", "Team games use the host-selected team color.")
		return
	}
	if m.ColorIndex == nil || !validColorIndex(m.ColorIndex) {
		fail("bad_color", "Choose one of the eight palette colors.")
		return
	}
	target := c.player
	if m.Target != nil {
		p := r.member(*m.Target)
		if p == nil || m.Member == 0 || p.Member != m.Member {
			fail("player_missing", "That seat has changed. Check the roster.")
			return
		}
		target = p
	}
	allowed := target == c.player
	if target.Kind == "local" && target.Owner == c.player.ID {
		allowed = true
	}
	if target.Kind == "bot" && r.Host == c.player.ID {
		allowed = true
	}
	if !allowed {
		fail("not_owner", "Online players choose their own Free-for-all tank color.")
		return
	}
	target.ColorIndex = copyColorIndex(m.ColorIndex)
	if t := r.tankFor(target); t != nil {
		t.Color = selectedColor(t.ID, t.Team, target.ColorIndex, r.Game.settings())
	}
	r.LastAction = now
	h.broadcastRoom(r)
}

// Sharing imports a local lobby atomically. Never overwrite an existing room,
// import client combat state, or silently merge the roster into someone else's room.
func (h *Hub) publishRoom(c *Client, m clientMessage, now time.Time) {
	fail := func(code, text string) { e := roomError(code, text); e["action"] = "publish"; c.enqueue(e) }
	if c.room != nil {
		fail("already_joined", "This room is already online.")
		return
	}
	if len(m.Roster) < 1 || len(m.Roster) > maxTanks+2 {
		fail("bad_roster", "Use up to eight tanks and two local spectators.")
		return
	}
	if m.Rules != nil {
		if err := validateRules(*m.Rules); err != nil {
			fail("bad_rules", err.Error())
			return
		}
	}
	active, locals := 0, 0
	for i, s := range m.Roster {
		if s.Team < 0 || s.Team > 4 || !validColorIndex(s.ColorIndex) {
			fail("bad_team", "Choose an existing team or Free-for-all.")
			return
		}
		if i == 0 {
			if s.Kind != "human" {
				fail("bad_roster", "The first member must be the host.")
				return
			}
		} else if s.Kind == "local" {
			locals++
		} else if s.Kind != "bot" {
			fail("bad_roster", "Only local players and bots can be imported.")
			return
		}
		if s.Kind == "bot" && (!validDifficulty(s.Difficulty) || s.Spectating) {
			fail("bad_difficulty", "Bots need a difficulty and an active tank seat.")
			return
		}
		if !s.Spectating {
			active++
		}
	}
	if m.Rules != nil && m.Rules.Mode == "survival" && active > survivalMaxPlayers {
		fail("survival_full", "Survival supports up to four allied tanks.")
		return
	}
	if active > maxTanks {
		fail("bad_roster", "There are only eight tank seats.")
		return
	}
	if locals > 1 {
		fail("local_exists", "Only one secondary local player is supported.")
		return
	}
	code := cleanCode(m.Code)
	if code != "" && !validCode(code) {
		fail("bad_code", "Enter a room name of 1–128 characters on one line.")
		return
	}
	if code != "" && h.rooms[code] != nil {
		fail("room_exists", "That name is already in use. Choose another name or join that room.")
		return
	}
	h.joinRoom(c, code == "", code, cleanName(m.Roster[0].Name), "", now, m.Roster[0].Spectating, true)
	if c.room == nil {
		return
	}
	r := c.room
	if m.Rules != nil {
		r.Game.Rules = normalizedRules(*m.Rules)
	}
	c.player.Team = m.Roster[0].Team
	c.player.ColorIndex = copyColorIndex(m.Roster[0].ColorIndex)
	for _, s := range m.Roster[1:] {
		id := r.freeCombatSeat()
		if s.Spectating {
			id = r.viewerID()
		}
		r.NextMember++
		p := &Player{ID: id, Member: r.NextMember, Name: cleanName(s.Name), Kind: s.Kind, Owner: c.player.ID, Controller: c.player, Team: s.Team, ColorIndex: copyColorIndex(s.ColorIndex), Difficulty: s.Difficulty, InputAt: now, Ready: true, Spectating: s.Spectating}
		if p.Spectating {
			r.putViewer(p)
		} else {
			r.Players[id] = p
		}
	}
	applyFormat(r)
	resetReady(r)
	h.broadcastRoom(r)
	h.sendState(c, r)
}

// A callsign change is metadata, even during a round. Only the authenticated
// controller can rename its dependent local pilot, including after host handoff.
// The member token prevents a stale save from renaming a replacement occupant.
func (h *Hub) renameLocal(c *Client, m clientMessage, now time.Time) {
	fail := func(code, text string) { e := roomError(code, text); e["action"] = "rename_local"; c.enqueue(e) }
	if c.room == nil || c.player == nil || c.player.Client != c || !c.room.contains(c.player) {
		fail("not_joined", "Join a room first.")
		return
	}
	if m.Target == nil || *m.Target < 0 || m.Member == 0 {
		fail("bad_target", "Select your current second local player.")
		return
	}
	r := c.room
	p := r.member(*m.Target)
	if p == nil || p.Member != m.Member {
		fail("player_missing", "That local seat has changed.")
		return
	}
	if p.Kind != "local" || p.Owner != c.player.ID {
		fail("not_owner", "Only this local player's controller can change their callsign.")
		return
	}
	name := cleanCallsign(m.Name)
	if name == "" {
		fail("bad_name", "Use letters, numbers, spaces, hyphens or underscores (up to 16 characters).")
		return
	}
	p.Name = name
	if t := r.tankFor(p); t != nil {
		t.Name = name
	}
	r.LastAction = now
	c.enqueue(map[string]any{"type": "renamed", "id": p.ID, "member": p.Member, "name": name})
	h.broadcastRoom(r)
}
