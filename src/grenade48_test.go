package main

import (
	"math"
	"testing"
)

func Test48GrenadeKeepsSpeedUntilLateFuse(t *testing.T) {
	g := &Game{World: World{Width: 10000, Height: 10000}}
	b := &Bullet{ID: 1, Owner: 7, Kind: "grenade", X: 5000, Y: 5000, VX: grenadeSpeed, R: 6, Life: grenadeFuse}
	g.Bullets = []*Bullet{b}
	advance := func(seconds float64) {
		for i := 0; i < int(math.Round(seconds/tickDT)); i++ {
			g.updateBullets(tickDT)
		}
	}
	advance(5)
	if got := math.Hypot(b.VX, b.VY) / grenadeSpeed; got < .87 {
		t.Fatalf("grenade slowed too early at 5s: %.3f of launch speed", got)
	}
	advance(3)
	if got := math.Hypot(b.VX, b.VY) / grenadeSpeed; got < .74 {
		t.Fatalf("grenade should still cruise with 2s left: %.3f of launch speed", got)
	}
	advance(1)
	if got := math.Hypot(b.VX, b.VY) / grenadeSpeed; got > .50 || got < .39 {
		t.Fatalf("grenade late-fuse braking unexpected with 1s left: %.3f", got)
	}
}

func Test48GrenadeDragCurveIsStepInvariant(t *testing.T) {
	whole := grenadeDragFactor(grenadeFuse, 0)
	stepped := 1.0
	life := grenadeFuse
	for i := 0; i < 600; i++ {
		next := math.Max(0, life-grenadeFuse/600)
		stepped *= grenadeDragFactor(life, next)
		life = next
	}
	if math.Abs(whole-stepped) > 1e-12 {
		t.Fatalf("drag curve changes with step size: whole %.15f stepped %.15f", whole, stepped)
	}
	if whole > .12 || whole < .09 {
		t.Fatalf("unexpected end-of-fuse speed fraction %.3f", whole)
	}
}
