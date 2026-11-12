package main

import "time"

// Pending public places prevent unrelated joins taking a room's seats while
// its browsers open their arena sockets. No pilot body exists until it joins.
type infinitePendingSeat struct {
	seats int
	until time.Time
}

// Called with Hub.mu held. Arena admission is performed by infiniteServer.step
// later, preserving its established infiniteServer.mu -> Hub.mu lock order.
func (h *Hub) requestPublicInfinity(c *Client, now time.Time) {
	if _, message := publicInfinitySeats(c); message != "" {
		publicInfinityError(c, message)
		return
	}
	if h.publicInfinityRequests == nil {
		h.publicInfinityRequests = make(map[*Room]*Client)
	}
	h.publicInfinityRequests[c.room] = c
	c.room.LastAction = now
}

func (h *Hub) selectPublicInfinity(c *Client, enabled *bool, now time.Time) {
	r, ok := h.editableHost(c, "select_public_infinity")
	if !ok {
		return
	}
	fail := func(message string) {
		e := roomError("public_infinity_unavailable", message)
		e["action"] = "select_public_infinity"
		c.enqueue(e)
	}
	if !r.setupOpen() || r.Queue != nil || r.Match != nil || r.hasAway() {
		fail("Return to the room before changing its Infinity destination.")
		return
	}
	if enabled == nil {
		fail("Choose public Infinity or room play.")
		return
	}
	if r.infinityPublic != *enabled {
		r.infinityPublic = *enabled
		if !*enabled {
			addDefaultRoomBots(r, c.player, now)
		}
		resetReady(r)
		delete(h.publicInfinityRequests, r)
	}
	r.LastAction = now
	h.broadcastRoom(r)
}

func publicInfinityError(c *Client, message string) {
	e := roomError("public_infinity_unavailable", message)
	e["action"] = "start_public_infinity"
	c.enqueue(e)
}

// Called with Hub.mu held. Public play is FFA, so a lone room pilot is valid.
func publicInfinitySeats(c *Client) (map[*Player]int, string) {
	r, p := c.room, c.player
	if r == nil || p == nil || p.Client != c || !r.contains(p) || !socketLive(p) {
		return nil, "Join a room before entering Infinity Online together."
	}
	if r.Host != p.ID {
		return nil, "Only the host can enter Infinity Online with the room."
	}
	if !r.setupOpen() || r.Queue != nil || r.Match != nil || r.hasAway() {
		return nil, "Return to the room before entering Infinity Online together."
	}
	for _, member := range r.Players {
		if member == nil || playerKind(member) == "bot" {
			continue
		}
		if playerKind(member) == "local" {
			owner := member.Controller
			if owner == nil {
				owner = r.member(member.Owner)
			}
			if !infinityCanPlay(owner) {
				return nil, "Return Player 1 to combat or make Player 2 spectate before entering Infinity Online together."
			}
		} else if !socketLive(member) {
			return nil, "Wait for every room pilot to reconnect before entering Infinity Online together."
		}
	}
	if !r.infinityPublic {
		return nil, "Select Infinity Online for the room before launching."
	}
	seats := make(map[*Player]int)
	for _, p := range r.Players {
		if !infinityCanPlay(p) || !socketLive(p) {
			continue
		}
		if p.ID != r.Host && !p.Ready {
			return nil, "Ask connected guests to ready up before entering Infinity Online."
		}
		seats[p] = 1
		for _, local := range r.Players {
			if infinityOwnsLocal(p, local) {
				seats[p]++
				break
			}
		}
	}
	if len(seats) == 0 {
		return nil, "Infinity needs at least one connected player in a combat seat."
	}
	return seats, ""
}

func (s *infiniteServer) dropPublicPending(key infiniteRoomPilot) {
	if pending, ok := s.publicPending[key]; ok {
		s.publicPendingCount -= pending.seats
		delete(s.publicPending, key)
	}
}

// Called with infiniteServer.mu held; no Hub operation obtains that mutex.
func (s *infiniteServer) processPublicInfinity(now time.Time) {
	s.hub.mu.Lock()
	defer s.hub.mu.Unlock()
	for key, pending := range s.publicPending {
		if now.After(pending.until) || !s.hub.infiniteMemberValid(key.room.room, key.seat, key.room.generation, now) {
			s.dropPublicPending(key)
		}
	}
	for r, c := range s.hub.publicInfinityRequests {
		delete(s.hub.publicInfinityRequests, r)
		if c.room != r || s.hub.rooms[r.Code] != r {
			publicInfinityError(c, "The room changed before Infinity Online could start.")
			continue
		}
		seats, message := publicInfinitySeats(c)
		if message != "" {
			publicInfinityError(c, message)
			continue
		}
		count := 0
		for _, n := range seats {
			count += n
		}
		if s.public.players+s.publicPendingCount+count > infiniteCapacity {
			publicInfinityError(c, "Infinity Online does not have enough free places for this room. Try again when pilots leave.")
			continue
		}
		// Entry removes configured bots only after the complete party is admitted.
		for id, p := range r.Players {
			if p != nil && playerKind(p) == "bot" {
				s.hub.expirePlayer(r, id)
			}
		}
		r.Game.resetLobby()
		r.infinityActive, r.infinityPublic = true, true
		r.infinityGeneration++
		resetReady(r)
		key := infiniteRoom{r, r.infinityGeneration}
		for p, n := range seats {
			s.publicPending[infiniteRoomPilot{key, p}] = infinitePendingSeat{n, now.Add(reconnectGrace)}
			s.publicPendingCount += n
		}
		s.hub.broadcastRoom(r)
		data, _ := encodePacket(map[string]any{"type": "infinity_start", "public": true})
		for p := range seats {
			p.Client.enqueueBytes(data)
		}
	}
}
