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
	var terminal, contact int
	for _, event := range g.events {
		if event.Flight != nil {
			terminal = event.ID
		}
		if event.Contact != nil {
			contact = event.ID
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
	if !seen[terminal] || !seen[contact] || !seen[beam.ID] || len(g.events) != 24 {
		t.Fatal("unrelated cosmetics evicted a terminal projectile, victim contact or beam before recovery")
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
		if event.ID == terminal || event.ID == contact || event.ID == beam.ID {
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
	var terminal, contact int
	for _, effect := range a.effects {
		if effect.Flight != nil {
			terminal = effect.ID
		}
		if effect.Contact != nil {
			contact = effect.ID
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
	if !seen[terminal] || !seen[contact] || !seen[beam] || len(a.effects) != 48 {
		t.Fatal("distant simultaneous shooters hid the nearby terminal flight, victim contact or beam", seen)
	}
	a.tick += 12
	a.broadcast()
	for _, effect := range readPartySnapshot(t, c).Effects {
		if effect.ID == terminal || effect.ID == contact || effect.ID == beam {
			t.Fatal("Infinity path history did not expire at the jitter limit")
		}
	}
}

func TestProjectilePathHistoriesStayBoundedByActors(t *testing.T) {
	g := battle(1)
	for id := 1; id <= maxTanks*projectileEffectsPerActor*2; id++ {
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

func TestEightStarmanScatterShootersRetainAll864TerminalFlightsFor600ms(t *testing.T) {
	g := battle(maxTanks)
	a := newSeededInfiniteArena(37)
	for id := range maxTanks {
		a.join(fakeClient(), string(rune('A'+id)), time.Unix(0, 0))
	}
	id := 0
	for tick := uint64(1); tick <= projectileEffectHistoryTicks; tick++ {
		g.Tick, a.tick = int(tick), tick
		for actor := range maxTanks {
			for pellet := range 3 {
				id++
				b := &Bullet{ID: id, Owner: actor, Pellet: pellet, Kind: "scatter", R: regularRadius, Color: tankColors[actor], X: 120, Y: 100}
				b.beginFlight(100, 100, float64(tick)-.5)
				b.flightAge = tickDT / 2
				g.projectileEvent("projectileFlight", b, 0)
				f := &infiniteBullet{ID: id, Owner: actor + 1, Kind: "scatter", Color: actor, radius: regularRadius, X: 120, Y: 100}
				f.beginFlight(100, 100, float64(tick)-.5)
				f.flightAge = tickDT / 2
				a.effect("projectileFlight", f.X, f.Y, f.Owner, nil)
				a.attachFlightEffect(f)
			}
		}
	}
	if id != 864 || len(g.projectileEvents) != id || len(a.projectileEffects) != id {
		t.Fatal("actor cap truncated 600ms of simultaneous Starman Shotgun terminal paths", id, len(g.projectileEvents), len(a.projectileEffects))
	}
	for i, event := range g.projectileSnapshotEvents(nil) {
		if event.Flight == nil || event.Flight.ID != i+1 {
			t.Fatal("fixed terminal sequence lost a projectile", i, event)
		}
	}
	for i, effect := range a.projectileSnapshotEffects(nil) {
		if effect.Flight == nil || effect.Flight.ID != i+1 {
			t.Fatal("Infinity terminal sequence lost a projectile", i, effect)
		}
	}
	g.Tick++
	a.tick++
	if len(g.projectileSnapshotEvents(nil)) != id-24 || len(a.projectileSnapshotEffects(nil)) != id-24 {
		t.Fatal("retained rapid terminal paths did not expire at exactly 600ms")
	}
}
