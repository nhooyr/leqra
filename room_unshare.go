package main

import "time"

// unshareRoom takes a host's ordinary private room back offline. The browser
// preserves the host/local-player/bot lobby locally; every remote controller is
// detached from the server room and told explicitly that the host took it offline.
func (h *Hub) unshareRoom(c *Client, now time.Time) {
	fail := func(code, text string) { e := roomError(code, text); e["action"] = "unshare"; c.enqueue(e) }
	r, host := c.room, c.player
	if r == nil || host == nil || host.Client != c || !r.contains(host) {
		fail("not_joined", "Join a room before taking it offline.")
		return
	}
	if r.Host != host.ID {
		fail("host_only", "Only the host can unshare this room.")
		return
	}
	if r.Queue != nil || r.Match != nil || r.hasAway() {
		fail("room_busy", "Return from matchmaking before taking this room offline.")
		return
	}
	if r.Game.Phase != "lobby" && r.Game.Phase != "matchOver" {
		fail("match_active", "End the match before taking this room offline.")
		return
	}
	code := r.Code
	// Notify each socket once. A primary pilot and their local P2 can share one
	// Client, so iterating seats directly would otherwise enqueue duplicate
	// unshared/room_offline packets and make the browser run teardown twice.
	var seen [maxTanks + maxSpectators]*Client
	seenN := 0
	for _, p := range r.members() {
		if p == nil || p.Client == nil {
			continue
		}
		cl := p.Client
		duplicate := false
		for i := 0; i < seenN; i++ {
			if seen[i] == cl {
				duplicate = true
				break
			}
		}
		if duplicate {
			continue
		}
		seen[seenN] = cl
		seenN++
		if cl == c {
			cl.enqueue(map[string]any{"type": "unshared", "room": code})
		} else {
			cl.enqueue(map[string]any{"type": "room_offline", "room": code, "message": "The host took this room offline."})
		}
		cl.room = nil
		cl.player = nil
		cl.mapGeneration = -1
	}
	for _, p := range r.members() {
		if p == nil {
			continue
		}
		p.Client = nil
		p.Input = Input{}
		p.FirePending = false
		p.Ready = false
	}
	r.LastAction = now
	delete(h.rooms, code)
}
