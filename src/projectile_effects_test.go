package main

import (
	"bytes"
	"encoding/json"
	"testing"
	"time"
)

func TestTerminalAndLaserPathsSurviveUnrelatedFixedCosmeticFlood(t *testing.T) {
	g := battle(2)
	g.Tick = 1
	pilot, target := g.Tanks[0], g.Tanks[1]
	target.X, target.Y = pilot.X+35, pilot.Y
	g.grantPower(pilot, "cannon")
	g.fire(pilot)
	var terminal int
	for _, event := range g.events {
		if event.Flight != nil {
			terminal = event.ID
		}
	}
	g.nextEvent++
	beam := Event{ID: g.nextEvent, Generation: g.Generation, Tick: g.Tick, Type: "laser", Points: []BeamPoint{{100, 100}, {200, 100}}}
	g.retainProjectileEvent(beam)
	for range 200 {
		g.emit("shot", pilot, pilot.ID, "rapid")
	}
	g.Tick += 24 // 400ms pending snapshot/jitter recovery.
	events := g.projectileSnapshotEvents(nil)
	seen, previous := map[int]bool{}, 0
	for _, event := range events {
		if seen[event.ID] || event.ID <= previous {
			t.Fatal("merged history duplicated or reordered an event")
		}
		seen[event.ID], previous = true, event.ID
	}
	if !seen[terminal] || !seen[beam.ID] || len(g.events) != 24 {
		t.Fatal("unrelated cosmetics evicted a terminal projectile or beam before recovery")
	}
	h, room := &Hub{}, &Room{Game: g}
	wire, _ := json.Marshal(h.stateWire(room))
	reference, _ := json.Marshal(h.stateMessage(room))
	if !bytes.Equal(wire, reference) {
		t.Fatal("retained path snapshot differs from the independent wire reference")
	}
	g.Tick += 12
	events = g.projectileSnapshotEvents(nil)
	for _, event := range events {
		if event.ID == terminal || event.ID == beam.ID {
			t.Fatal("separate history did not expire after its bounded jitter window")
		}
	}
	g.retainProjectileEvent(Event{ID: g.nextEvent + 1, Generation: g.Generation, Tick: g.Tick, Type: "laser"})
	g.startRound(testPlayers(2))
	if len(g.projectileEvents) != 0 {
		t.Fatal("old paths crossed a maze generation")
	}
}

func TestNearInfinityTerminalAndLaserPathsSurviveDistantShooters(t *testing.T) {
	a := newSeededInfiniteArena(37)
	a.tick = 1
	c := partySnapshotClient()
	pilot := a.join(c, "Pilot", time.Unix(0, 0))
	target := a.join(fakeClient(), "Target", time.Unix(0, 0))
	pilot.X, pilot.Y, pilot.Angle, pilot.kit.Invulnerable, pilot.kit.SpawnProtected = 42, 42, 0, 0, false
	target.X, target.Y, target.Protected, target.kit.Invulnerable = 77, 42, false, 0
	applyPower(&pilot.kit, "cannon", infinitePowerDuration, infiniteStarDuration)
	a.fire(pilot)
	var terminal int
	for _, effect := range a.effects {
		if effect.Flight != nil {
			terminal = effect.ID
		}
	}
	a.effect("laser", 42, 42, pilot.ID, []BeamPoint{{42, 42}, {77, 42}})
	beam := a.effectID
	for range 32 {
		for range 6 {
			a.effect("shot:rapid", 100*cellSize, 100*cellSize, 999, nil)
		}
	}
	a.tick += 24
	a.broadcast()
	state := readPartySnapshot(t, c)
	seen, previous := map[int]bool{}, 0
	for _, effect := range state.Effects {
		if seen[effect.ID] || effect.ID <= previous {
			t.Fatal("per-view path history was duplicated or reordered")
		}
		if effect.Owner == 999 {
			t.Fatal("distant cosmetics escaped view filtering")
		}
		seen[effect.ID], previous = true, effect.ID
	}
	if !seen[terminal] || !seen[beam] || len(a.effects) != 48 {
		t.Fatal("distant simultaneous shooters hid the nearby terminal flight or beam", seen)
	}
	a.tick += 12
	a.broadcast()
	for _, effect := range readPartySnapshot(t, c).Effects {
		if effect.ID == terminal || effect.ID == beam {
			t.Fatal("Infinity path history did not expire at the jitter limit")
		}
	}
}

func TestProjectilePathHistoriesStayBoundedByActors(t *testing.T) {
	g := battle(1)
	for id := 1; id <= 1000; id++ {
		g.retainProjectileEvent(Event{ID: id, Tick: g.Tick, Generation: g.Generation, Type: "laser"})
	}
	if len(g.projectileEvents) != maxTanks*projectileEffectsPerActor {
		t.Fatal("fixed path history is unbounded")
	}
	a := newSeededInfiniteArena(37)
	a.join(fakeClient(), "Pilot", time.Unix(0, 0))
	for id := 1; id <= 1000; id++ {
		a.retainProjectileEffect(infiniteEffect{ID: id, Kind: "laser", tick: a.tick})
	}
	if len(a.projectileEffects) != projectileEffectsPerActor {
		t.Fatal("Infinity path history is unbounded by its actual population")
	}
}
