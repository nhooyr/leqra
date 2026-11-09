package main

import (
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

type infiniteServer struct {
	mu           sync.Mutex
	closed       bool
	hub          *Hub
	public       *infiniteArena
	private      map[infiniteRoom]*infiniteArena
	connections  map[*Client]infiniteConnection // A nil arena is still joining.
	privateCount int
	nextSweep    time.Time
}

type infiniteMessage struct {
	Type      string `json:"type"`
	Version   string `json:"version"`
	Name      string `json:"name"`
	LocalName string `json:"localName"`
	Code      string `json:"code"`
	Token     string `json:"token"`
	Local     bool   `json:"local"`
	Paused    bool   `json:"paused"`
	Input
}

func newInfiniteServer(h *Hub) *infiniteServer {
	return &infiniteServer{
		hub: h, public: newInfiniteArena(),
		private:     make(map[infiniteRoom]*infiniteArena),
		connections: make(map[*Client]infiniteConnection),
	}
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
	defer s.remove(c)
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
		rejectInfinite(c, "Reload leqra to join Infinity Online.")
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
	for {
		data, err = c.ws.readMessage()
		if err != nil {
			closeInfiniteError(c, err)
			return
		}
		now := time.Now()
		if now.Sub(window) >= time.Second {
			window, count = now, [2]int{}
		}
		var msg infiniteMessage
		if json.Unmarshal(data, &msg) != nil {
			c.ws.writeClose(1007, "Invalid JSON")
			return
		}
		if msg.Type != "input" {
			c.ws.writeClose(1008, "Unsupported Infinity message")
			return
		}
		pilot, seat := connection.pilot, 0
		if msg.Local {
			if connection.local == nil {
				c.ws.writeClose(1008, "This connection has no local Player 2")
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
		connection.arena.setInput(pilot, msg.Input, msg.Paused, now)
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
	data, _ := encodePacket(map[string]string{"type": "error", "message": message})
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
	connection := infiniteConnection{arena: s.public}
	first := infiniteSeat{name: msg.Name, colorIndex: -1}
	var local *infiniteSeat
	seats := 1
	if msg.Code != "" || msg.Token != "" {
		room, seat, generation, setup := s.hub.infiniteMember(msg.Code, msg.Token)
		if generation == 0 {
			return infiniteConnection{}, "Join the room as a pilot to play private Infinity."
		}
		if setup.local != nil {
			seats++
		}
		if s.privateCount+seats > infinitePrivateCapacity {
			return infiniteConnection{}, "Private Infinity is full. Try again when a pilot leaves."
		}
		key := infiniteRoom{room: room, generation: generation}
		for _, other := range s.connections {
			if other.room == key && other.seat == seat {
				return infiniteConnection{}, "This pilot is already playing Infinity."
			}
		}
		connection.room, connection.seat, connection.localSeat = key, seat, setup.seat
		connection.arena = s.private[key]
		if connection.arena == nil {
			connection.arena = newRoomInfiniteArena(setup.rules)
		}
		first, local = setup.pilot, setup.local
	} else {
		if cleanCallsign(msg.LocalName) != "" {
			local = &infiniteSeat{name: msg.LocalName, colorIndex: -1}
			seats++
		}
		if s.public.players+seats > infiniteCapacity {
			return infiniteConnection{}, "Infinity Online is full. Try again when enough pilots leave."
		}
	}

	connection.pilot, connection.local = connection.arena.joinSeats(c, first, local, now)
	if connection.pilot == nil {
		return infiniteConnection{}, "Could not join Infinity."
	}
	s.connections[c] = connection
	if connection.seat != nil {
		s.private[connection.room] = connection.arena
		s.privateCount += seats
	}
	return connection, ""
}

func (s *infiniteServer) remove(c *Client) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.removeLocked(c)
}

func (s *infiniteServer) removeLocked(c *Client) {
	connection := s.connections[c]
	delete(s.connections, c)
	if connection.arena == nil {
		return
	}
	connection.arena.remove(connection.pilot)
	if connection.seat != nil {
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
	for c, connection := range s.connections {
		publicIdle := connection.arena == s.public && s.public.idle(connection.pilot, now)
		privateRevoked := connection.seat != nil && !s.hub.infiniteConnectionValid(connection.room.room, connection.seat, connection.localSeat, connection.room.generation, now)
		if publicIdle || privateRevoked {
			c.stop()
			s.removeLocked(c)
		}
	}
	s.public.step(now)
	sweep := !now.Before(s.nextSweep)
	if sweep {
		s.nextSweep = now.Add(time.Second)
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
	data, _ := encodePacket(map[string]string{"type": "error", "message": "The leqra server is shutting down."})
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
	s.closed = true
	for c := range s.connections {
		c.stop()
	}
}
