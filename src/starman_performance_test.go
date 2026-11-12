package main

import (
	"fmt"
	"testing"
	"time"
)

// Keep every tank protected so the benchmark sustains the maximum projectile
// load instead of becoming an empty arena after its first few kills. This
// measures authoritative simulation, excluding bots, snapshots and networking.
func starmanPerformanceGame(kind string, pilots int) (*Game, [maxTanks]*Player, [maxTanks]Input) {
	players := testPlayers(maxTanks)
	g := newGame(44937)
	g.Rules.MapSize = "ultrawide"
	g.startMatch(players)
	g.Phase, g.Clock, g.SpawnClock = "playing", 1e9, 1e9
	g.Pickups = nil
	var inputs [maxTanks]Input
	for id, tank := range g.Tanks {
		tank.SpawnProtected = false
		tank.Invulnerable, tank.GhostTime = 1e9, 1e9
		if id < pilots {
			if kind != "regular" {
				g.grantPower(tank, kind)
			}
			g.grantPower(tank, "starman")
			tank.StarmanTime = 1e9
			inputs[id].Fire = true
		}
	}
	for range 240 {
		g.step(tickDT, inputs, players)
	}
	return g, players, inputs
}

func BenchmarkStarmanFixedTick(b *testing.B) {
	for _, pilots := range []int{1, maxTanks} {
		for _, kind := range []string{"regular", "rapid", "scatter", "homing", "laser", "cannon"} {
			b.Run(fmt.Sprintf("%s/pilots_%d", kind, pilots), func(b *testing.B) {
				g, players, inputs := starmanPerformanceGame(kind, pilots)
				b.ReportAllocs()
				b.ResetTimer()
				for range b.N {
					g.step(tickDT, inputs, players)
				}
				b.ReportMetric(float64(len(g.Bullets)), "projectiles")
			})
		}
	}
}

func BenchmarkStarmanInfinityTick(b *testing.B) {
	for _, pilots := range []int{1, maxTanks} {
		for _, kind := range []string{"regular", "rapid", "scatter", "homing", "laser", "cannon"} {
			b.Run(fmt.Sprintf("%s/pilots_%d", kind, pilots), func(b *testing.B) {
				a := newSeededInfiniteArena(44937)
				a.rules = &infiniteRules{}
				a.nextPickup, a.nextBot = 1<<60, 1<<60
				now := time.Unix(1_800_000_000, 0)
				for id := range pilots {
					p := a.join(fakeClient(), "PERF", now)
					p.X, p.Y = float64(id*3)*cellSize+cellSize/2, cellSize/2
					p.Protected, p.kit.SpawnProtected = true, false
					p.kit.Invulnerable, p.kit.GhostTime, p.kit.StarmanTime = 1e9, 0, 1e9
					if kind != "regular" {
						applyPower(&p.kit, kind, infinitePowerDuration, infiniteStarDuration)
					}
					p.input, p.inputAt = Input{Fire: true}, now
				}
				a.connected = 0 // Exclude snapshot encoding and socket delivery.
				for range 240 {
					a.step(now)
				}
				b.ReportAllocs()
				b.ResetTimer()
				for range b.N {
					a.step(now)
				}
				b.ReportMetric(float64(len(a.bullets)), "projectiles")
			})
		}
	}
}

func BenchmarkStarmanFixedLaserSnapshot(b *testing.B) {
	for _, pilots := range []int{1, maxTanks} {
		b.Run(fmt.Sprintf("pilots_%d", pilots), func(b *testing.B) {
			g, _, _ := starmanPerformanceGame("laser", pilots)
			h, room, _ := performanceRoom437(0)
			room.Game = g
			data, ok := encodePacket(h.stateWire(room))
			if !ok {
				b.Fatal("snapshot encoding failed")
			}
			b.ReportAllocs()
			b.ResetTimer()
			for range b.N {
				data, ok = encodePacket(h.stateWire(room))
				if !ok {
					b.Fatal("snapshot encoding failed")
				}
			}
			b.ReportMetric(float64(len(data)), "wire-bytes")
		})
	}
}
