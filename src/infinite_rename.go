package main

import "time"

// Only the authenticated connection's two seats can be renamed. The server
// mutex also excludes reconnect replacement and room-seat retirement.
func (s *infiniteServer) renamePilot(c *Client, msg infiniteMessage, now time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	fail := func(message string) {
		c.enqueue(map[string]any{"type": "rename_error", "requestId": msg.RequestID, "seat": msg.Seat, "message": message})
	}
	connection, ok := s.connections[c]
	if s.closed || !ok || connection.arena == nil || connection.pilot == nil {
		fail("Reconnect before changing the callsign.")
		return
	}
	if msg.RequestID == 0 || msg.RequestID > 1<<53-1 || msg.Seat < 0 || msg.Seat > 1 {
		fail("Choose a current local tank.")
		return
	}
	name := cleanCallsign(msg.Name)
	if name == "" {
		fail("Use letters, numbers, spaces, hyphens or underscores (up to 16 characters).")
		return
	}
	pilot, member := connection.pilot, connection.seat
	if msg.Seat == 1 {
		pilot, member = connection.local, connection.localSeat
	}
	if pilot == nil {
		fail("That local tank is no longer available.")
		return
	}
	a := connection.arena
	a.mu.Lock()
	valid := connection.pilot.client == c &&
		(pilot == connection.pilot || pilot == connection.pilot.local)
	a.mu.Unlock()
	if !valid {
		fail("Reconnect before changing the callsign.")
		return
	}
	if connection.seat != nil && !s.hub.renameInfiniteMember(connection.room, connection.seat, member, name, now) {
		fail("That room seat is no longer available.")
		return
	}
	a.mu.Lock()
	pilot.Name = name
	a.mu.Unlock()
	c.enqueue(map[string]any{"type": "renamed", "requestId": msg.RequestID, "seat": msg.Seat, "name": name})
}

// Hub metadata and the streamed arena keep one raw callsign. Do not acquire an
// arena mutex here: room broadcasts can run independently of Infinity input.
func (h *Hub) renameInfiniteMember(key infiniteRoom, owner, member *Player, name string, now time.Time) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	r := key.room
	if !h.infiniteMemberValid(r, owner, key.generation, now) || member == nil || !r.contains(member) ||
		(member != owner && !infinityOwnsLocal(owner, member)) {
		return false
	}
	member.Name = name
	if tank := r.tankFor(member); tank != nil {
		tank.Name = name
	}
	r.LastAction = now
	h.broadcastRoom(r)
	return true
}
