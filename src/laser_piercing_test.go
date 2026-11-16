package main

import (
	"testing"
	"time"
)

func TestLaserPiercesTargetsOnceAndKeepsDefenses(t *testing.T) {
	g := battle(6)
	shooter, shield, first, protected, ally, last := g.Tanks[0], g.Tanks[1], g.Tanks[2], g.Tanks[3], g.Tanks[4], g.Tanks[5]
	shooter.Team, ally.Team = 1, 1
	shield.Shield, shield.ShieldCharges = 10, 3
	protected.Invulnerable, protected.SpawnProtected = 1, true
	g.grantPower(shooter, "laser")
	points, targets := g.traceLaser(shooter)
	if len(targets) != 3 || targets[0] != shield || targets[1] != first || targets[2] != last {
		t.Fatal("targets not ordered/deduplicated along full path", targets)
	}
	if beamLength(points) < g.laserRange()-29 {
		t.Fatal("targets truncated beam")
	}
	g.fireLaser(shooter)
	if first.Alive || last.Alive || !shooter.Alive || !protected.Alive || !ally.Alive || !shield.Alive || shield.ShieldCharges != 2 {
		t.Fatal("piercing laser changed damage permissions or hit a shield repeatedly")
	}
}

func TestInfinityLaserPiercesEveryTargetBeforeScoreWin(t *testing.T) {
	a := newSeededInfiniteArena(37)
	shooter := a.join(fakeClient(), "LASER", time.Unix(0, 0))
	shooter.X, shooter.Y, shooter.Angle = 42, 42, 0
	shooter.Protected, shooter.kit.Invulnerable, shooter.kit.SpawnProtected = false, 0, false
	// Three overlapping opponents before the nearest possible cell wall, placed
	// in reverse path order to check geometric ordering rather than roster order.
	var victims []*infinitePilot
	for _, x := range []float64{74, 64, 69} {
		p := a.addPilot("TARGET", true, x, 42, 1, 0)
		p.X, p.Y = x, 42
		p.Protected, p.kit.Invulnerable, p.kit.SpawnProtected = false, 0, false
		victims = append(victims, p)
	}
	applyPower(&shooter.kit, "laser", 10, 8)
	a.rules = &infiniteRules{Target: 1}
	_, targets := a.traceLaser(shooter)
	if len(targets) != 3 || targets[0] != victims[1] || targets[1] != victims[2] || targets[2] != victims[0] {
		t.Fatal("Infinity did not trace all opponents in order")
	}
	a.fireLaser(shooter)
	for _, target := range victims {
		if target.HP != 0 || target.Score != -1 {
			t.Fatal("score win stopped the beam before its final target")
		}
	}
	if shooter.Score != 3 || a.result == nil || a.result.Score != 3 {
		t.Fatal("score result omitted part of the volley", shooter.Score, a.result)
	}
}
