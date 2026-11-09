package main

import "time"

func infinityCanPlay(p *Player) bool {
	return p != nil && !p.Spectating && p.Away == nil && playerKind(p) == "human"
}

func (r *Room) lineupError() string {
	if !r.Game.settings().Infinity {
		return r.Game.lineupError(r.Players)
	}
	for _, p := range r.Players {
		if infinityCanPlay(p) && p.Client != nil {
			return ""
		}
	}
	return "Infinity needs at least one connected player in a combat seat."
}

// The room socket stays connected for membership and host authority. A fresh
// generation makes sockets from a previous launch ineligible after a restart.
// Called while Hub.mu is held.
func (h *Hub) startRoomInfinity(r *Room) {
	r.infinityActive = true
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
func (h *Hub) infiniteMember(code, token string) (*Room, *Player, uint64, string) {
	if token == "" {
		return nil, nil, 0, ""
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
		return nil, nil, 0, ""
	}
	for _, p := range r.Players {
		if p != nil && p.Token == token && h.infiniteMemberValid(r, p, r.infinityGeneration, now) {
			return r, p, r.infinityGeneration, p.Name
		}
	}
	return nil, nil, 0, ""
}

func (h *Hub) validInfiniteMember(r *Room, p *Player, generation uint64) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.infiniteMemberValid(r, p, generation, time.Now())
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
	return !h.closed && r != nil && r.infinityActive && generation != 0 && r.infinityGeneration == generation &&
		h.rooms[r.Code] == r && infinityCanPlay(p) && r.contains(p) &&
		(p.Client != nil || now.Sub(p.DisconnectedAt) <= reconnectGrace)
}
