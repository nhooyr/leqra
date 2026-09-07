package main

import (
	"math"
	"testing"
)

func TestMachineGunQuarterPerimeterRangeAndShooterImmunity(t *testing.T) {
	g := battle(2)
	tank := g.Tanks[0]
	tank.Invulnerable = 0
	g.grantPower(tank, "rapid")
	if !g.fire(tank) || len(g.Bullets) != 1 {
		t.Fatal("machine gun did not fire")
	}
	b := g.Bullets[0]
	wantRange := (g.World.Width + g.World.Height) / 2
	gotRange := 28 + b.Life*math.Hypot(b.VX, b.VY)
	if math.Abs(gotRange-wantRange) > 1e-7 {
		t.Fatalf("machine gun range %.6f want %.6f", gotRange, wantRange)
	}
	g.hurt(tank, &Bullet{Owner: tank.ID, Kind: "rapid"})
	if !tank.Alive || tank.stats.SelfDestructs != 0 {
		t.Fatal("machine gun damaged its sender")
	}
}

func Test46MachineCapacityCoversLargestContinuousRange(t *testing.T) {
	width, height := 16*cellSize, 14*cellSize
	flight := (width + height) / (2 * machineSpeed)
	required := int(math.Ceil(flight/tickDT)) + 1
	if machineCapacity < required {
		t.Fatalf("capacity %d cannot sustain %d live rounds", machineCapacity, required)
	}
}

func Test46GrenadeDoubleFuseAndBlast(t *testing.T) {
	if grenadeFuse != 10 || blastRadius != 220 {
		t.Fatalf("grenade tuning fuse=%v blast=%v", grenadeFuse, blastRadius)
	}
	g := battle(2)
	g.Tanks[0].X, g.Tanks[0].Y = 100, 210
	g.Tanks[1].X, g.Tanks[1].Y = 300, 210
	g.Tanks[0].Invulnerable, g.Tanks[1].Invulnerable = 0, 0
	b := &Bullet{Owner: 0, Kind: "grenade", X: 100, Y: 210, Life: grenadeFuse}
	g.detonate(b)
	if g.Tanks[1].Alive {
		t.Fatal("expanded grenade blast did not reach a tank 200 units away")
	}
	found := false
	for _, e := range g.events {
		if e.Type == "blast" && e.Radius == blastRadius {
			found = true
		}
	}
	if !found {
		t.Fatal("expanded blast radius was not serialized")
	}
}

func TestMachineGunQuarterPerimeterRangeSurvivesRicochets(t *testing.T) {
	g := &Game{World: World{Cols: 16, Rows: 14, Width: 16 * cellSize, Height: 14 * cellSize}}
	g.World.Walls = []Wall{
		{X: -wallSize / 2, Y: -wallSize / 2, W: wallSize, H: g.World.Height + wallSize, Axis: "v", Line: 0},
		{X: cellSize - wallSize/2, Y: -wallSize / 2, W: wallSize, H: g.World.Height + wallSize, Axis: "v", Line: cellSize},
	}
	life := g.machineTravelRange() / machineSpeed
	b := &Bullet{ID: 1, Owner: 0, Kind: "rapid", X: cellSize / 2, Y: cellSize / 2, VX: machineSpeed, VY: 0, R: machineRadius, Life: life, Color: tankColors[0]}
	g.Bullets = []*Bullet{b}
	stepsBeforeExpiry := int(math.Floor(life/tickDT)) - 2
	for i := 0; i < stepsBeforeExpiry; i++ {
		g.updateBullets(tickDT)
	}
	if b.Dead || b.Bounces < 10 {
		t.Fatalf("Machine gun should remain live through repeated ricochets: dead=%v bounces=%d life=%.3f", b.Dead, b.Bounces, b.Life)
	}
	for i := 0; i < 6 && !b.Dead; i++ {
		g.updateBullets(tickDT)
	}
	if !b.Dead {
		t.Fatalf("Machine gun should expire at quarter-perimeter range; life=%.6f bounces=%d", b.Life, b.Bounces)
	}
}
