package main

import (
	"crypto/sha256"
	"time"
)

// renameRoom changes only the public room key. The room object, roster, scores,
// chat, reconnect identities and current maze remain intact.
func (h *Hub) renameRoom(c *Client, m clientMessage, now time.Time) {
	fail := func(code, text string) {
		e := roomError(code, text)
		e["action"] = "rename_room"
		c.enqueue(e)
	}
	r, p := c.room, c.player
	if r == nil || p == nil || p.Client != c || !r.contains(p) {
		fail("not_joined", "Join an online room before renaming it.")
		return
	}
	if r.Host != p.ID {
		fail("not_host", "Only the room host can rename the room code.")
		return
	}
	if r.Match != nil || r.Queue != nil || r.hasAway() {
		fail("room_busy", "Return the party to the room and cancel matchmaking before renaming it.")
		return
	}
	code := cleanCode(m.Code)
	if !validCode(code) {
		fail("bad_code", "Use a room name of 1–128 characters on one line.")
		return
	}
	old := r.Code
	if code == old {
		c.enqueue(map[string]any{"type": "room_renamed", "old": old, "room": code, "unchanged": true})
		return
	}
	if h.rooms[code] != nil {
		fail("room_exists", "That room code is already in use. Choose another name.")
		return
	}

	// Preserve automatic reconnects that were already in flight when the host
	// renamed the room. Old public invite links are not aliases for fresh joins.
	if h.resumeRoutes == nil {
		h.resumeRoutes = map[resumeRouteKey]resumeRoute{}
	}
	for _, member := range r.members() {
		if member == nil || member.Token == "" {
			continue
		}
		h.resumeRoutes[resumeRouteKey{old, sha256.Sum256([]byte(member.Token))}] = resumeRoute{r, now.Add(reconnectGrace)}
	}

	delete(h.rooms, old)
	r.Code = code
	h.rooms[code] = r
	r.LastAction = now
	event := map[string]any{"type": "room_renamed", "old": old, "room": code}
	for _, member := range r.members() {
		if member != nil && member.Client != nil {
			member.Client.enqueue(event)
		}
	}
	h.broadcastRoom(r)
}
