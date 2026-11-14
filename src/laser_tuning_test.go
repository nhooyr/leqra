package main

import (
	"fmt"
	"math"
	"testing"
	"time"
)

func narrowLaserGame(pilots int) (*Game, [maxTanks]*Player, [maxTanks]Input) {
	players := testPlayers(maxTanks)
	g := battle(maxTanks)
	g.World = World{Cols: 24, Rows: 14, Width: 24 * cellSize, Height: 14 * cellSize, Walls: []Wall{
		{X: -4, Y: -4, W: 24*cellSize + 8, H: 8, Axis: "h", Line: 0},
		{X: -4, Y: cellSize - 4, W: 24*cellSize + 8, H: 8, Axis: "h", Line: cellSize},
	}}
	g.Phase, g.Clock, g.SpawnClock = "playing", 1e9, 1e9
	g.Pickups = nil
	var input [maxTanks]Input
	for id, tank := range g.Tanks {
		if tank == nil {
			continue
		}
		tank.X, tank.Y, tank.Angle = float64(id*2+1)*cellSize+cellSize/2, cellSize/2, math.Pi/2
		tank.SpawnProtected = false
		tank.Invulnerable, tank.GhostTime, tank.StarmanTime = 1e9, 1e9, 1e9
		if id < pilots {
			g.grantPower(tank, "laser")
			input[id].Fire = true
		}
	}
	return g, players, input
}

func TestDoubledUltrawideLaserBudgetSurvivesMoreThan128NarrowCorridorReflections(t *testing.T) {
	g, _, _ := narrowLaserGame(1)
	points, target := g.traceLaser(g.Tanks[0])
	want := 4*(g.World.Width+g.World.Height) - 28
	if target != nil || len(points) <= 129 || len(points) > 257 || math.Abs(beamLength(points)-want) > 1e-5 {
		t.Fatal("the old defensive segment limit truncated doubled range", len(points), beamLength(points), want)
	}
}

func TestLaserAndCannonReloadAreReducedByOneThird(t *testing.T) {
	want := .85 * 2 / 3
	if math.Abs(laserCooldown-want) > 1e-12 || math.Abs(cannonCooldown-want) > 1e-12 {
		t.Fatal("weapon reloads were not reduced by one third")
	}
	for _, kind := range []string{"laser", "cannon"} {
		g := battle(1)
		pilot := g.Tanks[0]
		g.grantPower(pilot, kind)
		if !g.fire(pilot) || pilot.Cooldown != want || pilot.CooldownTotal != want || pilot.Charges != 2 {
			t.Fatal("fixed weapon did not use the shared reload", kind, pilot.Cooldown, pilot.Charges)
		}
		a := newSeededInfiniteArena(37)
		p := a.join(fakeClient(), "Pilot", time.Unix(0, 0))
		p.Protected, p.kit.Invulnerable, p.kit.SpawnProtected = false, 0, false
		applyPower(&p.kit, kind, infinitePowerDuration, infiniteStarDuration)
		a.fire(p)
		if p.kit.Cooldown != want || p.kit.CooldownTotal != want || p.kit.Charges != 2 {
			t.Fatal("Infinity weapon did not use the shared reload", kind, p.kit.Cooldown, p.kit.Charges)
		}
	}
}

func TestInfinityLaserRangeDoublesWithoutChangingBallisticRanges(t *testing.T) {
	a := newSeededInfiniteArena(37)
	p := a.join(fakeClient(), "Pilot", time.Unix(0, 0))
	p.X, p.Y = cellSize/2, cellSize/2
	for _, angle := range []float64{0, .17, math.Pi / 4, math.Pi / 2, 2.91} {
		p.Angle = angle
		points, target := a.traceLaser(p)
		if target != nil || math.Abs(beamLength(points)-(36*cellSize-28)) > 1e-5 {
			t.Fatal("Infinity laser did not receive exactly twice its old budget", angle, beamLength(points))
		}
	}
	if infiniteShotRange != 18*cellSize || infiniteSpec("cannon").life != 5.3 || infiniteSpec("rapid").life != 18*cellSize/machineSpeed || infiniteSpec("homing").life != 18*cellSize/missileSpeed {
		t.Fatal("laser tuning changed another projectile's range or lifetime")
	}
}

func BenchmarkDoubledLaserNarrowCorridorTick(b *testing.B) {
	for _, count := range []int{1, maxTanks} {
		b.Run(fmt.Sprintf("pilots_%d", count), func(b *testing.B) {
			g, players, input := narrowLaserGame(count)
			for range 240 {
				g.step(tickDT, input, players)
			}
			b.ReportAllocs()
			b.ResetTimer()
			for range b.N {
				g.step(tickDT, input, players)
			}
		})
	}
}

func BenchmarkDoubledLaserNarrowCorridorSnapshot(b *testing.B) {
	g, players, input := narrowLaserGame(maxTanks)
	for range 240 {
		g.step(tickDT, input, players)
	}
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
}

func BenchmarkDoubledLaserNarrowCorridorCompressedSnapshot(b *testing.B) {
	g, players, input := narrowLaserGame(maxTanks)
	for range 240 {
		g.step(tickDT, input, players)
	}
	h, room, _ := performanceRoom437(0)
	room.Game = g
	data, ok := encodePacket(h.stateWire(room))
	if !ok {
		b.Fatal("snapshot encoding failed")
	}
	var frame snapshotFrame
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		frame = compressSnapshot(data)
	}
	b.ReportMetric(float64(len(frame.data)), "wire-bytes")
}
