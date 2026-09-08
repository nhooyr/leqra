package main

import (
	"encoding/json"
	"math"
	"testing"
)

// Pickup-rate Off should put the spawn scheduler to sleep rather than wake it
// forever just to discover that spawning is disabled.
func Test417PickupOffSleepsSpawnScheduler(t *testing.T) {
	g := newGame(417)
	g.Rules.PickupRate = "off"
	players := testPlayers(2)
	g.startMatch(players)
	if !math.IsInf(g.SpawnClock, 1) {
		t.Fatalf("spawn clock=%v, want +Inf while pickups are off", g.SpawnClock)
	}
	if len(g.Pickups) != 0 {
		t.Fatalf("seeded %d pickups while pickups are off", len(g.Pickups))
	}
	var inputs [maxTanks]Input
	for i := 0; i < 1200; i++ {
		g.step(tickDT, inputs, players)
	}
	if !math.IsInf(g.SpawnClock, 1) || len(g.Pickups) != 0 {
		t.Fatalf("disabled pickup scheduler woke: clock=%v pickups=%d", g.SpawnClock, len(g.Pickups))
	}
}

// The optimized 60 Hz serializer must remain byte-for-byte equivalent to the
// canonical state serializer so clients cannot distinguish the fast path.
func Test417StateWireMatchesCanonicalAcrossLiveSteps(t *testing.T) {
	h := newHub(417)
	for _, size := range []string{"compact", "large", "giant", "ultrawide"} {
		g := newGame(int64(417 + len(size)))
		g.Rules.MapSize = size
		players := testPlayers(8)
		g.startMatch(players)
		r := &Room{Game: g, Players: players, Spectators: map[int]*Player{}}
		for step := 0; step < 90; step++ {
			var inputs [maxTanks]Input
			for id := range inputs {
				inputs[id] = Input{Forward: (step+id)%3 == 0, Left: (step+id)%11 == 0, Fire: (step+id)%7 == 0}
			}
			g.step(tickDT, inputs, players)
			canonical, err := json.Marshal(h.stateMessage(r))
			if err != nil {
				t.Fatal(err)
			}
			fast, err := json.Marshal(h.stateWire(r))
			if err != nil {
				t.Fatal(err)
			}
			if string(canonical) != string(fast) {
				t.Fatalf("state wire mismatch on %s at step %d", size, step)
			}
		}
	}
}
