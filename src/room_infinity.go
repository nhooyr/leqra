package main

import "time"

func infinityCanPlay(p *Player) bool {
	return p != nil && !p.Spectating && p.Away == nil && playerKind(p) == "human"
}

func infinityOwnsLocal(owner, local *Player) bool {
	return local != nil && local.Kind == "local" && !local.Spectating && local.Away == nil &&
		(local.Controller == owner || local.Controller == nil && local.Owner == owner.ID)
}

type infiniteRoomSetup struct {
	public bool
	rules  MatchRules
	pilot  infiniteSeat
	local  *infiniteSeat
	seat   *Player
	bots   []infiniteRoomBot
}

type infiniteRoomBot struct {
	seat       infiniteSeat
	member     *Player
	difficulty string
}

func infiniteRoomSeat(p *Player, rules MatchRules) infiniteSeat {
	team := p.Team
	if rules.TeamMode != "teams" {
		team = 0
	}
	ownerToken := ""
	if playerKind(p) == "human" {
		ownerToken = p.PublicToken
	}
	return infiniteSeat{name: p.Name, team: team, publicToken: ownerToken, colorIndex: tankColorIndex[selectedColor(p.ID, team, p.ColorIndex, rules)]}
}

func (r *Room) lineupError() string {
	rules := r.Game.settings()
	if !rules.Infinity {
		return r.Game.lineupError(r.Players)
	}
	sides := make(map[int]bool)
	primary := false
	for _, p := range r.Players {
		if p == nil || p.Spectating || p.Away != nil {
			continue
		}
		switch playerKind(p) {
		case "local":
			owner := p.Controller
			if owner == nil {
				owner = r.member(p.Owner)
			}
			if !infinityCanPlay(owner) || !socketLive(owner) || !r.contains(owner) {
				continue
			}
		case "human":
			if !socketLive(p) {
				continue
			}
			primary = true
		}
		team := 0
		if rules.TeamMode == "teams" {
			team = p.Team
		}
		sides[sideKey(p.ID, team)] = true
	}
	if !primary {
		return "Infinity needs at least one connected player in a combat seat."
	}
	if rules.InfinityTarget > 0 && !rules.InfinityRandomBots && len(sides) < 2 {
		return "Add an opposing tank or enable random bots to play to a score target."
	}
	return ""
}

// The room socket stays connected for membership and host authority. A fresh
// generation makes sockets from a previous launch ineligible after a restart.
// Called while Hub.mu is held.
func (h *Hub) startRoomInfinity(r *Room) {
	r.Game.resetLobby()
	r.infinityActive = true
	r.infinityPublic = false
	delete(h.publicInfinityRequests, r)
	r.infinityGeneration++
	resetReady(r)
	h.broadcastRoom(r)
	data, _ := encodePacket(map[string]string{"type": "infinity_start"})
	for _, p := range r.Players {
		if infinityCanPlay(p) && p.Client != nil {
			p.Client.enqueueBytes(data)
		}
	}
}

// Authenticate the separate Infinity socket with the current room identity.
// The pilot's callsign is copied while Hub.mu protects the roster.
func (h *Hub) infiniteMember(code, token string) (*Room, *Player, uint64, infiniteRoomSetup) {
	if token == "" {
		return nil, nil, 0, infiniteRoomSetup{}
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	now := time.Now()
	code = cleanCode(code)
	r := h.rooms[code]
	if resumed := h.resumedRoom(code, token, now); resumed != nil {
		r = resumed
	}
	if r == nil || !r.infinityActive {
		return nil, nil, 0, infiniteRoomSetup{}
	}
	for _, p := range r.Players {
		if p != nil && p.Token == token && h.infiniteMemberValid(r, p, r.infinityGeneration, now) {
			rules := r.Game.settings()
			setup := infiniteRoomSetup{public: r.infinityPublic, rules: rules, pilot: infiniteRoomSeat(p, rules)}
			for _, member := range r.Players {
				if member == nil || member.Spectating || member.Away != nil {
					continue
				}
				if playerKind(member) == "bot" {
					setup.bots = append(setup.bots, infiniteRoomBot{infiniteRoomSeat(member, rules), member, member.Difficulty})
				} else if setup.local == nil && infinityOwnsLocal(p, member) {
					spec := infiniteRoomSeat(member, rules)
					setup.local, setup.seat = &spec, member
				}
			}
			return r, p, r.infinityGeneration, setup
		}
	}
	return nil, nil, 0, infiniteRoomSetup{}
}

func (h *Hub) validInfiniteMember(r *Room, p *Player, generation uint64) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.infiniteMemberValid(r, p, generation, time.Now())
}

func (h *Hub) infiniteConnectionStatus(r *Room, p, local *Player, generation uint64, bots []infiniteRoomBot, now time.Time) (primaryValid, localRevoked bool, removedBots uint64) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if !h.infiniteMemberValid(r, p, generation, now) {
		return false, false, 0
	}
	localRevoked = local != nil && (!r.contains(local) || !infinityOwnsLocal(p, local))
	for i, bot := range bots {
		if !r.contains(bot.member) {
			removedBots |= 1 << i
		}
	}
	return true, localRevoked, removedBots
}

func (h *Hub) validInfiniteRoom(r *Room, generation uint64) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.infiniteRoomValid(r, generation)
}

func (h *Hub) touchInfiniteMember(r *Room, p *Player, generation uint64, now time.Time) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	if !h.infiniteMemberValid(r, p, generation, now) {
		return false
	}
	if now.After(r.LastAction) {
		r.LastAction = now
	}
	return true
}

// Room leaves, kicks and role changes revoke access even if the arena socket
// remains connected. The usual room reconnect window still applies.
// Called while Hub.mu is held.
func (h *Hub) infiniteMemberValid(r *Room, p *Player, generation uint64, now time.Time) bool {
	return h.infiniteRoomValid(r, generation) && infinityCanPlay(p) && r.contains(p) &&
		(p.Client != nil || now.Sub(p.DisconnectedAt) <= reconnectGrace)
}

func (h *Hub) infiniteRoomValid(r *Room, generation uint64) bool {
	return !h.closed && r != nil && r.infinityActive && generation != 0 &&
		r.infinityGeneration == generation && h.rooms[r.Code] == r
}
