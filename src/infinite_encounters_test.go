package main

import (
	"encoding/json"
	"math"
	"reflect"
	"testing"
	"time"
)

func TestInfinityBotSpawnRateDefaultsNormalizesAndRejectsInvalidRulesAtomically(t *testing.T) {
	rules := defaultRules()
	if rules.InfinityBotSpawnRate != 2 {
		t.Fatal("default bot cadence was not doubled")
	}
	rules.InfinityBotSpawnRate = 0
	if validateRules(rules) != nil || normalizedRules(rules).InfinityBotSpawnRate != 2 {
		t.Fatal("omitted legacy cadence did not normalize to the current default")
	}
	for _, rate := range []float64{.5, 1, 2, 4} {
		rules.InfinityBotSpawnRate = rate
		if validateRules(rules) != nil || normalizedRules(rules).InfinityBotSpawnRate != rate {
			t.Fatal("valid host cadence was not retained", rate)
		}
	}
	h, members, room := makeRoom(t, 1)
	before := normalizedRules(room.Game.settings())
	for _, rate := range []float64{-1, .25, 3, 8} {
		rules.InfinityBotSpawnRate = rate
		action(t, h, members[0], map[string]any{"type": "rules", "rules": rules})
		if !reflect.DeepEqual(normalizedRules(room.Game.settings()), before) {
			t.Fatal("invalid cadence partially changed room rules", rate)
		}
	}
	for _, rate := range []float64{math.NaN(), math.Inf(1)} {
		rules.InfinityBotSpawnRate = rate
		if validateRules(rules) == nil {
			t.Fatal("non-finite cadence was accepted")
		}
	}
	data, _ := json.Marshal(defaultRules())
	var wire map[string]any
	_ = json.Unmarshal(data, &wire)
	if wire["infinityBotSpawnRate"] != float64(2) || wire["infinityBotsPerPlayer"] != nil {
		t.Fatal("room wire lost its cadence or exposed a removed population knob")
	}
}

func TestInfinityRoamingPopulationHasSixteenPerHumanAndFairCadenceWaves(t *testing.T) {
	for _, private := range []bool{false, true} {
		a := newSeededInfiniteArena(37)
		humans := infiniteCapacity
		if private {
			rules := defaultRules()
			rules.InfinityRandomBots, rules.InfinityBotSpawnRate = true, 4
			a = newRoomInfiniteArena(rules, nil)
			humans = maxTanks
		}
		for id := range humans {
			p := a.join(fakeClient(), "Pilot", time.Unix(0, 0))
			p.X, p.Y = float64(id*50)*cellSize+cellSize/2, cellSize/2
		}
		for wave := 1; wave <= infiniteBotsPerPlayer; wave++ {
			a.tick = a.nextBot
			a.populate()
			if len(roamingBots(a)) != humans*wave {
				t.Fatal("spawn wave did not serve one encounter per living human", private, wave, len(roamingBots(a)))
			}
			delay := a.nextBot - a.tick
			if !private && (delay < 30 || delay > 60) || private && (delay < 15 || delay > 30) {
				t.Fatal("spawn-rate control did not scale the original one-to-two second interval", private, delay)
			}
		}
		if a.roamingBotBudget() != humans*16 || len(roamingBots(a)) != humans*16 {
			t.Fatal("population retained a legacy global cap", private)
		}
		for _, human := range a.pilots[:humans] {
			nearby := 0
			for _, bot := range roamingBots(a) {
				if math.Hypot(bot.X-human.X, bot.Y-human.Y) < 8*cellSize {
					nearby++
				}
			}
			if nearby != 16 {
				t.Fatal("a distant human was starved by another player's population", private, nearby)
			}
		}
	}
}

func TestInfinityStrayedAmbientEndsWithoutScoreAndConfiguredBotStays(t *testing.T) {
	rules := defaultRules()
	rules.InfinityRandomBots = true
	a := newRoomInfiniteArena(rules, []infiniteRoomBot{{seat: infiniteSeat{name: "Roster"}, member: &Player{ID: 1, Kind: "bot"}, difficulty: "normal"}})
	human := a.join(fakeClient(), "Human", time.Unix(0, 0))
	a.populate()
	ambient := roamingBots(a)[0]
	var configured *infinitePilot
	for _, p := range a.pilots {
		if p.roomBot != nil {
			configured = p
		}
	}
	if configured == nil {
		t.Fatal("configured fixture missing")
	}
	ambient.X, ambient.Y, ambient.Score = human.X+20*cellSize, human.Y, 5
	configured.X, configured.Y = ambient.X, ambient.Y
	spawn, configuredSpawn, nextID := ambient.Spawn, configured.Spawn, a.nextID
	a.nextBot = a.tick + 60
	a.populate()
	if ambient.HP != 0 || ambient.Spawn != spawn || !ambient.ambientRetired || ambient.Score != 5 || human.Score != 0 || len(a.effects) != 0 || configured.HP == 0 || configured.Spawn != configuredSpawn || a.nextID != nextID {
		t.Fatal("stray retirement awarded damage/score, moved an existing life, or affected the roster bot")
	}
	a.tick = a.nextBot
	a.populate()
	if ambient.HP == 0 || ambient.Spawn != spawn+1 || ambient.ambientRetired || ambient.Score != 5 || math.Hypot(ambient.X-human.X, ambient.Y-human.Y) > 7*cellSize || a.nextID != nextID {
		t.Fatal("retired identity did not start a fresh nearby life")
	}
	human.paused = true
	a.tick = a.nextBot
	a.populate()
	if len(roamingBots(a)) != 1 || configured.HP == 0 || ambient.Spawn != spawn+1 {
		t.Fatal("a paused human spawned more bots, removed an existing nearby life, or removed its configured bot")
	}
	human.HP, human.paused = 0, false
	a.tick = a.nextBot
	a.populate()
	if len(roamingBots(a)) != 1 || ambient.Spawn != spawn+1 {
		t.Fatal("a temporary death spawned more bots or removed a nearby current life")
	}
	human.X += 50 * cellSize
	a.populate()
	if len(roamingBots(a)) != 0 || configured.HP == 0 {
		t.Fatal("a distant dead human kept an abandoned ambient life active")
	}
}

func infinityPopulationBenchmarkArena() (*infiniteArena, time.Time) {
	a := newSeededInfiniteArena(44944)
	now := time.Unix(1_800_000_000, 0)
	for id := range infiniteCapacity {
		p := a.join(fakeClient(), "Performance", now)
		p.X, p.Y = float64(id*50)*cellSize+cellSize/2, cellSize/2
		p.inputAt = now
	}
	fillRoamingBots(a)
	for _, p := range a.pilots {
		p.kit.Invulnerable, p.kit.SpawnProtected, p.Protected = 1e9, true, true
	}
	a.nextBot, a.nextPickup = math.MaxUint64, math.MaxUint64
	return a, now
}

func BenchmarkInfinityMaximumRoamingSimulation(b *testing.B) {
	a, now := infinityPopulationBenchmarkArena()
	a.commitBeforeBroadcast = true
	origins := make([]BeamPoint, len(a.pilots))
	for i, p := range a.pilots {
		origins[i] = BeamPoint{p.X, p.Y}
	}
	b.ReportAllocs()
	b.ResetTimer()
	for i := range b.N {
		// Keep the worst-case population for long benchmark runs, rather
		// than measuring fewer bots after they eventually wander away.
		if i%60 == 0 {
			for i, p := range a.pilots {
				p.X, p.Y = origins[i].X, origins[i].Y
			}
		}
		a.step(now)
	}
	b.ReportMetric(float64(len(roamingBots(a))), "bots")
}

func BenchmarkInfinityMaximumRoamingSnapshot(b *testing.B) {
	a, _ := infinityPopulationBenchmarkArena()
	a.broadcast()
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		a.broadcast()
	}
	b.ReportMetric(float64(len(roamingBots(a))), "bots")
}

func BenchmarkInfinityMaximumRoamingTerminalSnapshot(b *testing.B) {
	a, _ := infinityPopulationBenchmarkArena()
	for _, p := range a.pilots[:infiniteCapacity] {
		for volley := range 2 {
			a.effect("laser", p.X, p.Y, p.ID, []BeamPoint{{p.X, p.Y}, {p.X + 50, p.Y}})
			shell := infiniteBullet{ID: 100000 + p.ID*2 + volley, Owner: p.ID, Kind: "cannon", Color: p.ColorIndex, radius: cannonRadius}
			shell.beginFlight(p.X+32, p.Y, float64(a.tick)-1)
			shell.X, shell.Y, shell.flightAge = p.X+50, p.Y, tickDT
			a.effect("impact", shell.X, shell.Y, shell.Owner, nil)
			a.attachFlightEffect(&shell)
		}
	}
	a.broadcast()
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		a.broadcast()
	}
	b.ReportMetric(float64(len(roamingBots(a))), "bots")
	b.ReportMetric(float64(len(a.projectileEffects)), "paths")
}
