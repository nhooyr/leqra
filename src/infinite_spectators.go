package main

import "time"

// Observer state is deliberately separate from pilots: it cannot own a tank,
// receive input, occupy a player place, or contribute to the bot population.
type infiniteObserver struct {
	client    *Client
	following int
}

func stopInfiniteRoomAccess(c *Client) {
	stopAccountTransport(c, map[string]any{"type": "error", "code": "room_access_changed", "action": "spectate", "message": "Your room role changed or this Infinity run ended. Return to the room."})
}

// User-triggered broadcasts can happen between simulation ticks. Recheck every
// observer before those broadcasts so a removed member cannot keep receiving a
// room view through another spectator's follow or another player's admission.
func (s *infiniteServer) pruneObservers(now time.Time) {
	for c, connection := range s.connections {
		if connection.observer != nil && !s.hub.validInfiniteObserver(connection.room.room, connection.seat, connection.room.generation, now) {
			s.removeLocked(c)
			stopInfiniteRoomAccess(c)
		}
	}
}

// Caller holds server.mu. Room credentials, membership, role and run generation
// are authenticated by Hub; the requested role alone grants no access.
func (s *infiniteServer) joinObserver(c *Client, msg infiniteMessage, now time.Time) (infiniteConnection, string) {
	room, seat, generation, setup := s.hub.infiniteMember(msg.Code, msg.Token, true)
	if generation == 0 || setup.public || msg.Code == "" {
		if msg.Resume {
			return infiniteConnection{}, infiniteResumeExpired
		}
		return infiniteConnection{}, "Join a private Infinity room as a spectator before watching."
	}
	if msg.Generation != 0 && msg.Generation != generation {
		return infiniteConnection{}, infiniteResumeExpired
	}
	key := infiniteRoom{room, generation}
	connection := infiniteConnection{room: key, seat: seat, arena: s.private[key]}
	var observer *infiniteObserver
	for old, existing := range s.connections {
		if existing.room == key && existing.seat == seat && existing.pilot != nil {
			// Demotion can be followed by an observer join before the next
			// simulation tick. Revoke the former body's input immediately.
			s.removeLocked(old)
			stopInfiniteRoomAccess(old)
			continue
		}
		if existing.room == key && existing.seat == seat && existing.observer != nil {
			if !msg.Resume {
				return infiniteConnection{}, infiniteSessionActive
			}
			observer = existing.observer
			connection.arena = existing.arena
			connection.arena.removeObserver(observer)
			delete(s.connections, old)
			stopInfiniteRoomAccess(old)
			break
		}
	}
	reservationKey := infiniteRoomPilot{key, seat}
	if reservation, exists := s.reservations[reservationKey]; exists {
		if reservation.connection.observer != nil && !now.After(reservation.until) {
			observer = reservation.connection.observer
			connection.arena = reservation.connection.arena
			delete(s.reservations, reservationKey)
		} else {
			s.expireReservation(reservationKey, reservation)
		}
	}
	if connection.arena == nil {
		connection.arena = newRoomInfiniteArena(setup.rules, setup.bots)
	}
	if observer == nil {
		observer = &infiniteObserver{}
	}
	connection.observer = observer
	if !connection.arena.addObserver(c, observer, generation, msg.Resume, msg.Target) {
		return infiniteConnection{}, "Could not watch Infinity."
	}
	s.private[key] = connection.arena
	s.connections[c] = connection
	return connection, ""
}

func (a *infiniteArena) addObserver(c *Client, observer *infiniteObserver, generation uint64, resumed bool, target int) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.publicEntries != nil || len(a.observers) >= maxSpectators {
		return false
	}
	if target > 0 {
		for _, p := range a.pilots {
			if p.ID == target {
				observer.following = target
				break
			}
		}
	}
	a.observerTarget(observer, a.rankedLeaders(nil))
	if !c.enqueue(map[string]any{"type": "welcome", "id": 0, "seed": a.seed, "generation": generation, "resumed": resumed, "spectating": true, "following": observer.following}) {
		return false
	}
	if a.observers == nil {
		a.observers = make(map[*Client]*infiniteObserver)
	}
	observer.client = c
	a.observers[c] = observer
	a.broadcast()
	return true
}

func (a *infiniteArena) removeObserver(observer *infiniteObserver) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.observers[observer.client] == observer {
		delete(a.observers, observer.client)
	}
}

// Call with arena.mu held. Death retains the selected identity for respawn;
// removal falls back to the highest ranked remaining actor, then its stable ID.
func (a *infiniteArena) observerTarget(observer *infiniteObserver, leaders []infiniteLeader) *infinitePilot {
	if p := a.observerPilot(observer); p != nil {
		return p
	}
	observer.following = 0
	if len(leaders) > 0 {
		observer.following = leaders[0].ID
		for _, p := range a.pilots {
			if p.ID == observer.following {
				return p
			}
		}
	}
	return nil
}

func (a *infiniteArena) observerPilot(observer *infiniteObserver) *infinitePilot {
	for _, p := range a.pilots {
		if p.ID == observer.following {
			return p
		}
	}
	return nil
}

func (s *infiniteServer) follow(c *Client, target int, now time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.pruneObservers(now)
	fail := func(message string) {
		c.enqueue(map[string]any{"type": "error", "code": "follow_invalid", "action": "follow", "message": message})
	}
	connection, ok := s.connections[c]
	if s.closed || !ok || connection.observer == nil || !s.hub.validInfiniteObserver(connection.room.room, connection.seat, connection.room.generation, now) {
		fail("Only a current room spectator can choose a tank to follow.")
		return
	}
	a := connection.arena
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.observers[c] != connection.observer || target <= 0 {
		fail("Choose a tank from this room's leaderboard.")
		return
	}
	for _, p := range a.pilots {
		if p.ID == target {
			connection.observer.following = target
			c.enqueue(map[string]any{"type": "followed", "following": target})
			a.broadcast()
			return
		}
	}
	fail("That tank is no longer in this arena.")
}
