package main

import (
	"database/sql"
	"encoding/json"
	"errors"
	"math"
	"net/http"
	"sync"
	"time"
)

const (
	infinitePrivateCapacity = 128
	infinitePublicIdle      = 5 * time.Minute
	infiniteResumeIdle      = 3 * time.Second
	infiniteSessionActive   = "This pilot is already playing Infinity."
	infiniteResumeExpired   = "Your Infinity reconnect window expired. Join again from the room."
)

type infiniteRoom struct {
	room       *Room
	generation uint64
}

type infiniteConnection struct {
	arena     *infiniteArena
	pilot     *infinitePilot
	local     *infinitePilot
	room      infiniteRoom
	seat      *Player
	localSeat *Player
}

type infiniteReservation struct {
	connection infiniteConnection
	until      time.Time
}

type infiniteRoomPilot struct {
	room infiniteRoom
	seat *Player
}

type infiniteServer struct {
	mu                     sync.Mutex
	closed                 bool
	hub                    *Hub
	public                 *infiniteArena
	private                map[infiniteRoom]*infiniteArena
	connections            map[*Client]infiniteConnection // A nil arena is still joining.
	reservations           map[infiniteRoomPilot]infiniteReservation
	privateCount           int
	publicPending          map[infiniteRoomPilot]infinitePendingSeat
	publicPendingCount     int
	nextSweep              time.Time
	publicDB               *sql.DB
	publicProfiles         map[string]infinitePublicProfile
	publicScoreOwners      map[int]string
	publicZeroProfiles     map[string]bool
	publicSavedNextID      int
	publicSavedBotLives    uint64
	publicSavedSeed        uint32
	publicStoreInitialized bool
	nextProfilePrune       time.Time
}

type infiniteMessage struct {
	Type                string `json:"type"`
	Version             string `json:"version"`
	Name                string `json:"name"`
	LocalName           string `json:"localName"`
	ColorIndex          *int   `json:"colorIndex"`
	LocalColorIndex     *int   `json:"localColorIndex"`
	Code                string `json:"code"`
	Token               string `json:"token"`
	PublicToken         string `json:"publicToken"`
	LocalPublicToken    string `json:"localPublicToken"`
	LocalNewAccount     bool   `json:"localNewAccount"`
	IndependentAccounts bool   `json:"independentAccounts"`
	UpdateNames         bool   `json:"updateNames"`
	Resume              bool   `json:"resume"`
	Generation          uint64 `json:"generation"`
	Local               bool   `json:"local"`
	Paused              bool   `json:"paused"`
	Seat                int    `json:"seat"`
	RequestID           uint64 `json:"requestId"`
	Input

	T *float64 `json:"t"`
}

func newInfiniteServer(h *Hub) *infiniteServer {
	s := &infiniteServer{
		hub: h, public: newInfiniteArena(),
		private:       make(map[infiniteRoom]*infiniteArena),
		connections:   make(map[*Client]infiniteConnection),
		reservations:  make(map[infiniteRoomPilot]infiniteReservation),
		publicPending: make(map[infiniteRoomPilot]infinitePendingSeat),
	}
	s.public.publicEntries = make(map[int]infinitePublicEntry)
	s.public.publicArchiveDirty = true
	s.public.commitBeforeBroadcast = true
	s.publicProfiles = make(map[string]infinitePublicProfile)
	s.publicScoreOwners = make(map[int]string)
	s.publicZeroProfiles = make(map[string]bool)
	return s
}

func (a *App) infiniteSocket(w http.ResponseWriter, r *http.Request) {
	a.serveSocket(w, r, a.infinite.admit, a.infinite.readLoop)
}

func (s *infiniteServer) admit(c *Client) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed || len(s.connections) >= infiniteCapacity+infinitePrivateCapacity {
		return false
	}
	s.connections[c] = infiniteConnection{}
	return true
}

func (s *infiniteServer) readLoop(c *Client) {
	defer c.stop()
	defer func() { s.disconnect(c, time.Now()) }()
	joinTimeout := time.AfterFunc(5*time.Second, c.stop)
	defer joinTimeout.Stop()
	data, err := c.ws.readMessage()
	if err != nil {
		closeInfiniteError(c, err)
		return
	}
	if !joinTimeout.Stop() {
		return
	}
	var join infiniteMessage
	if json.Unmarshal(data, &join) != nil || join.Type != "join" || join.Version != version {
		rejectInfinite(c, "Reload leqra to play Infinity.")
		return
	}
	connection, rejection := s.join(c, join, time.Now())
	if rejection != "" {
		rejectInfinite(c, rejection)
		return
	}
	// The reliable welcome was queued before this pilot could receive snapshots.
	go c.writeLoop()
	window := time.Now()
	var lastTouch time.Time
	var count [2]int
	var renames, pings int
	for {
		data, err = c.ws.readMessage()
		if err != nil {
			closeInfiniteError(c, err)
			return
		}
		now := time.Now()
		if now.Sub(window) >= time.Second {
			window, count = now, [2]int{}
			renames, pings = 0, 0
		}
		var msg infiniteMessage
		if json.Unmarshal(data, &msg) != nil {
			c.ws.writeClose(1007, "Invalid JSON")
			return
		}
		if msg.Type == "leave" {
			s.remove(c)
			return
		}
		if msg.Type == "ping" {
			pings++
			if pings > 8 {
				c.ws.writeClose(1008, "Ping rate exceeded")
				return
			}
			if msg.T == nil || math.IsNaN(*msg.T) || math.IsInf(*msg.T, 0) {
				c.ws.writeClose(1008, "Invalid ping timestamp")
				return
			}
			if !c.enqueue(map[string]any{"type": "pong", "t": *msg.T}) {
				return
			}
			continue
		}
		if msg.Type == "rename" {
			renames++
			if renames > 8 {
				c.ws.writeClose(1008, "Callsign change rate exceeded")
				return
			}
			s.renamePilot(c, msg, now)
			continue
		}
		if msg.Type != "input" {
			c.ws.writeClose(1008, "Unsupported Infinity message")
			return
		}
		pilot, seat := connection.pilot, 0
		if msg.Local {
			if connection.local == nil {
				c.ws.writeClose(1008, "This connection has no local co-pilot")
				return
			}
			pilot, seat = connection.local, 1
		}
		count[seat]++
		if count[seat] > clientMessageLimit {
			c.ws.writeClose(1008, "Input rate exceeded")
			return
		}
		if connection.seat != nil && !msg.Paused && now.Sub(lastTouch) >= time.Second && infiniteActiveInput(msg.Input) {
			s.hub.touchInfiniteMember(connection.room.room, connection.seat, connection.room.generation, now)
			lastTouch = now
		}
		connection.arena.setConnectionInput(c, connection.pilot, pilot, msg.Input, msg.Paused, now)
	}
}

func infiniteActiveInput(in Input) bool {
	return infiniteButtonsDown(in) || math.Hypot(in.StickX, in.StickY) > .1
}

func infiniteButtonsDown(in Input) bool {
	return in.Forward || in.Reverse || in.Left || in.Right || in.Fire
}

func closeInfiniteError(c *Client, err error) {
	var wsErr *wsError
	if errors.As(err, &wsErr) {
		c.ws.writeClose(wsErr.code, wsErr.reason)
	}
}

func rejectInfinite(c *Client, message string) {
	packet := map[string]any{"type": "error", "message": message}
	if c.accountFailureSeat != nil {
		packet["seat"] = *c.accountFailureSeat
	}
	if len(c.callsignConflicts) > 0 {
		packet["code"] = "callsign_taken"
		packet["conflicts"] = c.callsignConflicts
		if c.callsignReserved {
			packet["code"], packet["reason"] = "callsign_reserved", "reserved"
		}
	}
	switch message {
	case errSameSeatAccount.Error(), errNewAccountKeyInvalid.Error():
		packet["code"] = "account_seat_conflict"
	case infiniteSessionActive:
		packet["code"] = "session_active"
	case infiniteResumeExpired:
		packet["code"] = "resume_expired"
	case infinitePublicResumeInvalid:
		packet["code"] = "public_resume_invalid"
	case infiniteAccountKeyRevoked:
		packet["code"] = "account_key_revoked"
	case infinitePublicStoreBusy:
		packet["code"] = "server_busy"
	case "The leqra server is shutting down.":
		packet["code"] = "server_shutdown"
	case "Public Infinity is full. Try again when enough pilots leave.":
		packet["code"] = "arena_full"
	}
	data, _ := encodePacket(packet)
	_ = c.ws.writeFrame(1, data)
	c.ws.writeClose(1008, "Infinity join rejected")
}

func (s *infiniteServer) join(c *Client, msg infiniteMessage, now time.Time) (infiniteConnection, string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return infiniteConnection{}, "The leqra server is shutting down."
	}
	if existing, admitted := s.connections[c]; !admitted || existing.pilot != nil {
		return infiniteConnection{}, "Could not join Infinity."
	}
	if err := s.applySeatMigrations(); err != nil {
		return infiniteConnection{}, infinitePublicStoreBusy
	}
	connection := infiniteConnection{arena: s.public}
	if msg.Code == "" && (msg.IndependentAccounts || msg.LocalPublicToken != "") {
		return s.joinIndependentPublic(c, msg, now, connection)
	}
	if msg.PublicToken != "" && msg.Code == "" {
		hash, _ := publicTokenHash(msg.PublicToken)
		independentPair := func(other infiniteConnection) bool {
			return other.arena == s.public && other.pilot != nil && other.local != nil && other.pilot.publicKey != other.local.publicKey && (other.pilot.publicKey == hash || other.local.publicKey == hash)
		}
		attached := false
		for _, other := range s.connections {
			attached = attached || independentPair(other)
		}
		for _, reservation := range s.reservations {
			attached = attached || independentPair(reservation.connection)
		}
		if attached {
			return s.joinIndependentPublic(c, msg, now, connection)
		}
		return s.resumePublic(c, msg, now)
	}
	first := infiniteSeat{name: msg.Name, colorIndex: -1}
	var local *infiniteSeat
	seats := 1
	if msg.Code != "" || msg.Token != "" {
		room, seat, generation, setup := s.hub.infiniteMember(msg.Code, msg.Token)
		if msg.Resume && (generation == 0 || msg.Generation != 0 && msg.Generation != generation) {
			return infiniteConnection{}, infiniteResumeExpired
		}
		if generation == 0 {
			return infiniteConnection{}, "Join the room as a pilot before entering Infinity."
		}
		if setup.local != nil {
			seats++
		}
		key := infiniteRoom{room: room, generation: generation}
		for old, other := range s.connections {
			if other.room == key && other.seat == seat {
				if !msg.Resume || other.localSeat != nil && other.localSeat != setup.seat {
					return infiniteConnection{}, infiniteSessionActive
				}
				if reason := other.arena.resume(c, other.pilot, generation, now); reason != "" {
					return infiniteConnection{}, reason
				}
				delete(s.connections, old)
				s.connections[c] = other
				old.stop()
				return other, ""
			}
		}
		reservationKey := infiniteRoomPilot{key, seat}
		if reservation, exists := s.reservations[reservationKey]; exists {
			if !now.After(reservation.until) {
				if local := reservation.connection.localSeat; local != nil && local != setup.seat {
					s.retireLocal(&reservation.connection)
					s.reservations[reservationKey] = reservation
				}
				previous := reservation.connection
				if reason := previous.arena.resume(c, previous.pilot, generation, now); reason != "" {
					return infiniteConnection{}, reason
				}
				delete(s.reservations, reservationKey)
				s.connections[c] = previous
				return previous, ""
			}
			s.expireReservation(reservationKey, reservation)
		}
		if msg.Resume {
			return infiniteConnection{}, infiniteResumeExpired
		}
		if !setup.public && s.privateCount+seats > infinitePrivateCapacity {
			return infiniteConnection{}, "Private Infinity is full. Try again when a pilot leaves."
		}
		connection.room, connection.seat, connection.localSeat = key, seat, setup.seat
		connection.arena = s.private[key]
		if setup.public {
			reserved := s.publicPending[reservationKey].seats
			if s.public.players+s.publicPendingCount-reserved+seats > infiniteCapacity {
				return infiniteConnection{}, "Public Infinity is full. Try again when enough pilots leave."
			}
			connection.arena = s.public
			setup.pilot.team = 0
			if setup.local != nil {
				setup.local.team = 0
			}
		} else if connection.arena == nil {
			connection.arena = newRoomInfiniteArena(setup.rules, setup.bots)
		} else if connection.arena.players == 0 {
			connection.arena.roomBots = setup.bots
		}
		first, local = setup.pilot, setup.local
	} else {
		if msg.Resume {
			return infiniteConnection{}, infiniteResumeExpired
		}
		if msg.ColorIndex != nil && validColorIndex(msg.ColorIndex) {
			first.colorIndex = *msg.ColorIndex
		}
		if cleanCallsign(msg.LocalName) != "" {
			local = &infiniteSeat{name: msg.LocalName, colorIndex: -1}
			if msg.LocalColorIndex != nil && validColorIndex(msg.LocalColorIndex) {
				local.colorIndex = *msg.LocalColorIndex
			}
			seats++
		}
		if s.public.players+s.publicPendingCount+seats > infiniteCapacity {
			return infiniteConnection{}, "Public Infinity is full. Try again when enough pilots leave."
		}
	}

	if connection.arena == s.public {
		if msg.IndependentAccounts || local != nil && local.publicToken != "" && local.publicToken != first.publicToken {
			msg.Name, msg.PublicToken = first.name, first.publicToken
			msg.UpdateNames = true
			if local != nil {
				msg.LocalName, msg.LocalPublicToken = local.name, local.publicToken
			}
			return s.joinIndependentPublic(c, msg, now, connection)
		}
		var err error
		first, local, err = s.createPublicIdentity(first, local, now)
		if err != nil {
			return infiniteConnection{}, publicJoinClaimError(c, err)
		}
	}
	connection.pilot, connection.local = connection.arena.joinSeats(c, first, local, connection.room.generation, now)
	if connection.pilot == nil {
		return infiniteConnection{}, "Could not join Infinity."
	}
	s.connections[c] = connection
	if connection.seat != nil {
		if connection.arena == s.public {
			s.dropPublicPending(infiniteRoomPilot{connection.room, connection.seat})
			localMember := uint64(0)
			if connection.localSeat != nil {
				localMember = connection.localSeat.Member
			}
			connection.arena.bindParty(connection.pilot, connection.local, connection.room, connection.seat.Member, localMember)
		} else {
			s.private[connection.room] = connection.arena
			s.privateCount += seats
		}
	}
	return connection, ""
}

func (s *infiniteServer) disconnect(c *Client, now time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	connection := s.connections[c]
	delete(s.connections, c)
	if connection.seat == nil || s.closed {
		s.retire(connection)
		return
	}
	s.reserve(connection, now)
}

func (s *infiniteServer) reserve(connection infiniteConnection, now time.Time) {
	connection.arena.suspend(connection.pilot)
	s.reservations[infiniteRoomPilot{connection.room, connection.seat}] = infiniteReservation{connection, now.Add(reconnectGrace)}
}

func (s *infiniteServer) remove(c *Client) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.removeLocked(c)
}

func (s *infiniteServer) removeLocked(c *Client) {
	connection := s.connections[c]
	delete(s.connections, c)
	s.retire(connection)
}

func (s *infiniteServer) expireReservation(key infiniteRoomPilot, reservation infiniteReservation) {
	delete(s.reservations, key)
	s.retire(reservation.connection)
}

func (s *infiniteServer) retireLocal(connection *infiniteConnection) {
	connection.arena.removeLocal(connection.pilot)
	connection.local, connection.localSeat = nil, nil
	if connection.arena != s.public {
		s.privateCount--
	}
}

func (s *infiniteServer) retire(connection infiniteConnection) {
	if connection.arena == nil {
		return
	}
	connection.arena.remove(connection.pilot)
	if connection.seat != nil && connection.arena != s.public {
		s.privateCount--
		if connection.local != nil {
			s.privateCount--
		}
		if a := connection.arena; a.players == 0 {
			if !a.teams() && a.rules.Target == 0 || !s.hub.validInfiniteRoom(connection.room.room, connection.room.generation) {
				delete(s.private, connection.room)
			}
		}
	}
}

func (s *infiniteServer) run(done <-chan struct{}) {
	ticker := time.NewTicker(time.Second / 60)
	defer ticker.Stop()
	const step = time.Second / 60
	last := time.Now()
	var accumulated time.Duration
	for {
		select {
		case <-done:
			return
		case now := <-ticker.C:
			accumulated += min(now.Sub(last), 5*step)
			last = now
			for accumulated >= step {
				s.step(now)
				accumulated -= step
			}
		}
	}
}

func (s *infiniteServer) step(now time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return
	}
	if err := s.applySeatMigrations(); err != nil {
		s.publicStoreError(err)
		return
	}
	s.processPublicInfinity(now)
	for c, connection := range s.connections {
		if connection.arena == s.public && s.public.idle(connection.pilot, now) {
			c.stop()
			s.removeLocked(c)
			continue
		}
		if connection.seat == nil {
			continue
		}
		valid, localRevoked, removed := s.hub.infiniteConnectionStatus(connection.room.room, connection.seat, connection.localSeat, connection.room.generation, connection.arena.roomBots, now)
		if removed != 0 {
			connection.arena.removeRoomBots(removed)
		}
		if !valid {
			c.stop()
			s.removeLocked(c)
		} else if localRevoked {
			// Reuse the authenticated reconnect to deliver the solo seat binding.
			// Keep the primary tank and invalidate the old transport first.
			s.retireLocal(&connection)
			delete(s.connections, c)
			s.reserve(connection, now)
			c.stop()
		}
	}
	s.public.step(now)
	if err := s.persistPublicLocked(nil, nil); err != nil {
		s.publicStoreError(err)
	} else {
		s.public.mu.Lock()
		if s.public.broadcastPending {
			s.public.broadcastPending = false
			s.public.broadcast()
		}
		s.public.mu.Unlock()
	}
	sweep := !now.Before(s.nextSweep)
	if sweep {
		s.nextSweep = now.Add(time.Second)
		if !now.Before(s.nextProfilePrune) {
			s.nextProfilePrune = now.Add(time.Minute)
			s.publicStoreError(s.prunePublicProfiles(now))
		}
		for key, reservation := range s.reservations {
			connection := reservation.connection
			valid, localRevoked, removed := s.hub.infiniteConnectionStatus(key.room.room, key.seat, connection.localSeat, key.room.generation, connection.arena.roomBots, now)
			if !valid || now.After(reservation.until) {
				s.expireReservation(key, reservation)
				continue
			}
			if localRevoked {
				s.retireLocal(&reservation.connection)
				s.reservations[key] = reservation
			}
			if removed != 0 {
				connection.arena.removeRoomBots(removed)
			}
		}
	}
	for key, arena := range s.private {
		if arena.players == 0 {
			if sweep && !s.hub.validInfiniteRoom(key.room, key.generation) {
				delete(s.private, key)
			}
			continue
		}
		arena.step(now)
	}
}

func (s *infiniteServer) notifyShutdown() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	data, _ := encodePacket(map[string]string{"type": "error", "code": "server_shutdown", "message": "The leqra server is shutting down."})
	count := 0
	for c, connection := range s.connections {
		if connection.pilot != nil && c.enqueueBytes(data) {
			count++
		}
	}
	return count
}

func (s *infiniteServer) close() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return
	}
	s.closed = true
	for key, reservation := range s.reservations {
		s.expireReservation(key, reservation)
	}
	for c := range s.connections {
		c.stop()
	}
	s.publicStoreError(s.persistPublicLocked(nil, nil))
	if s.publicDB != nil {
		s.publicStoreError(s.publicDB.Close())
	}
}
