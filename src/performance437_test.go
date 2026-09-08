package main

import (
	"fmt"
	"testing"
	"time"
)

func performanceRoom437(spectators int) (*Hub, *Room, time.Time) {
	now := time.Unix(1_800_000_000, 0)
	h := newHub(4)
	r := &Room{Code: "PERF", Game: newGame(437), LastAction: now, Spectators: map[int]*Player{}}
	for id := 0; id < maxTanks; id++ {
		c := &Client{send: make(chan []byte, 32), updates: make(chan []byte, 1), done: make(chan struct{}), born: now}
		p := &Player{ID: id, Member: uint64(id + 1), Name: "PILOT", Client: c, InputAt: now}
		c.player, c.room = p, r
		r.Players[id] = p
	}
	for n := 0; n < spectators; n++ {
		id := maxTanks + n*3
		c := &Client{send: make(chan []byte, 32), updates: make(chan []byte, 1), done: make(chan struct{}), born: now}
		p := &Player{ID: id, Member: uint64(id + 1), Name: "SPECTATOR", Client: c, Spectating: true}
		c.player, c.room = p, r
		r.Spectators[id] = p
	}
	h.rooms[r.Code] = r
	h.nextQueueScan = now.Add(time.Hour)
	return h, r, now
}

var memberResult437 int

func BenchmarkMembers437(b *testing.B) {
	for _, viewers := range []int{0, 16} {
		b.Run(fmt.Sprintf("viewers_%d", viewers), func(b *testing.B) {
			_, r, _ := performanceRoom437(viewers)
			b.ReportAllocs()
			b.ResetTimer()
			for n := 0; n < b.N; n++ {
				memberResult437 = len(r.members())
			}
		})
	}
}

func BenchmarkRoomTick437(b *testing.B) {
	for _, parked := range []bool{false, true} {
		b.Run(fmt.Sprintf("parked_%v", parked), func(b *testing.B) {
			h, r, now := performanceRoom437(16)
			if parked {
				r.Players[0].Away = &MatchTravel{Battle: &Room{Code: "BATTLE"}}
			}
			b.ReportAllocs()
			b.ResetTimer()
			for n := 0; n < b.N; n++ {
				h.tick(now)
			}
		})
	}
}

func TestMemberSnapshots437KeepOrderAndIndependence(t *testing.T) {
	_, r, _ := performanceRoom437(16)
	r.Players[1], r.Players[5] = nil, nil
	first := r.members()
	for n, p := range first {
		if n > 0 && first[n-1].ID >= p.ID {
			t.Fatalf("roster is not ordered at %d: %d then %d", n, first[n-1].ID, p.ID)
		}
	}
	oldFirst := first[0]
	delete(r.Spectators, maxTanks)
	r.Players[0] = &Player{ID: 0, Name: "REPLACEMENT"}
	second := r.members()
	if first[0] != oldFirst || first[0] == second[0] {
		t.Fatal("new roster reused the previous independent snapshot")
	}
	if len(first) != len(second)+1 || first[6].ID != maxTanks {
		t.Fatal("removing a spectator changed the earlier snapshot")
	}
	var storage [maxTanks + maxSpectators]*Player
	scratch := r.appendMembers(storage[:0])
	for n, p := range second {
		if scratch[n] != p {
			t.Fatalf("scratch roster changed identity/order at %d", n)
		}
	}
}

func TestTick437RefreshesMembersAfterControllerExpiry(t *testing.T) {
	for _, observers := range []int{0, 2} {
		t.Run(fmt.Sprintf("spectators_%d", observers), func(t *testing.T) {
			h, r, now := performanceRoom437(observers)
			for id := 2; id < maxTanks; id++ {
				r.Players[id] = nil
			}
			parent, child := r.Players[0], r.Players[1]
			parent.Client = nil
			parent.DisconnectedAt = now.Add(-reconnectGrace - time.Second)
			child.Client = nil
			child.Kind = "local"
			child.Owner = parent.ID
			child.Controller = parent
			h.tick(now)
			if r.Players[0] != nil || r.Players[1] != nil {
				t.Fatal("expired controller retained a combat seat or P2")
			}
			if observers == 0 {
				if h.rooms[r.Code] != nil {
					t.Fatal("stale member snapshot kept an empty room alive")
				}
			} else {
				if h.rooms[r.Code] != r || r.Host != maxTanks {
					t.Fatal("remaining spectators lost the room or deterministic host election")
				}
				for _, p := range r.Spectators {
					if p.Client.room != r {
						t.Fatal("controller expiry detached a surviving spectator")
					}
				}
			}
		})
	}
}

func TestTick437StackRosterDoesNotLeakBetweenRooms(t *testing.T) {
	h, a, now := performanceRoom437(16)
	_, b, _ := performanceRoom437(0)
	b.Code = "SECOND"
	for id := 1; id < maxTanks; id++ {
		b.Players[id] = nil
	}
	h.rooms[b.Code] = b
	for n := 0; n < 20; n++ {
		h.tick(now)
	}
	if h.rooms[a.Code] != a || h.rooms[b.Code] != b {
		t.Fatal("scratch from another room corrupted membership")
	}
	if len(a.members()) != maxTanks+16 || len(b.members()) != 1 {
		t.Fatal("shared scratch changed a room's roster")
	}
	for _, r := range []*Room{a, b} {
		for _, p := range r.members() {
			if p.Client.room != r {
				t.Fatal("room traversal crossed client ownership")
			}
		}
	}
}
