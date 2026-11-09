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
	arena *infiniteArena
	pilot *infinitePilot
	room  infiniteRoom
	seat  *Player
}

type infiniteServer struct {
	mu           sync.Mutex
	closed       bool
	hub          *Hub
	public       *infiniteArena
	private      map[infiniteRoom]*infiniteArena
	connections  map[*Client]infiniteConnection // A nil arena is still joining.
	privateCount int
}

type infiniteMessage struct {
	Type    string `json:"type"`
	Version string `json:"version"`
	Name    string `json:"name"`
	Code    string `json:"code"`
	Token   string `json:"token"`
	Paused  bool   `json:"paused"`
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
	count := 0
	for {
		data, err = c.ws.readMessage()
		if err != nil {
			closeInfiniteError(c, err)
			return
		}
		now := time.Now()
		if now.Sub(window) >= time.Second {
			window, count = now, 0
		}
		count++
		if count > clientMessageLimit {
			c.ws.writeClose(1008, "Input rate exceeded")
			return
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
		if connection.seat != nil && !msg.Paused && now.Sub(lastTouch) >= time.Second && infiniteActiveInput(msg.Input) {
			s.hub.touchInfiniteMember(connection.room.room, connection.seat, connection.room.generation, now)
			lastTouch = now
		}
		connection.arena.setInput(connection.pilot, msg.Input, msg.Paused, now)
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
	if msg.Code != "" || msg.Token != "" {
		room, seat, generation, name := s.hub.infiniteMember(msg.Code, msg.Token)
		if generation == 0 {
			return infiniteConnection{}, "Join the room as a pilot to play private Infinity."
		}
		if s.privateCount >= infinitePrivateCapacity {
			return infiniteConnection{}, "Private Infinity is full. Try again when a pilot leaves."
		}
		key := infiniteRoom{room: room, generation: generation}
		for _, other := range s.connections {
			if other.room == key && other.seat == seat {
				return infiniteConnection{}, "This pilot is already playing Infinity."
			}
		}
		connection.room, connection.seat = key, seat
		connection.arena = s.private[key]
		if connection.arena == nil {
			connection.arena = newInfiniteArena()
		}
		msg.Name = name
	} else if s.public.players >= infiniteCapacity {
		return infiniteConnection{}, "Infinity Online is full. Try again when a pilot leaves."
	}

	connection.pilot = connection.arena.join(c, msg.Name, now)
	if connection.pilot == nil {
		return infiniteConnection{}, "Could not join Infinity."
	}
	s.connections[c] = connection
	if connection.seat != nil {
		s.private[connection.room] = connection.arena
		s.privateCount++
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
		if connection.arena.players == 0 {
			delete(s.private, connection.room)
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
		privateRevoked := connection.seat != nil && !s.hub.validInfiniteMember(connection.room.room, connection.seat, connection.room.generation)
		if publicIdle || privateRevoked {
			c.stop()
			s.removeLocked(c)
		}
	}
	s.public.step(now)
	for _, arena := range s.private {
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
