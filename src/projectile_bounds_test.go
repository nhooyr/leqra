package main

import (
	"math"
	"math/rand"
	"testing"
)

// The exhaustive reference intentionally has no broad phase. It retains the
// original candidate order, damage rules, grenade contact and circle solver.
func exhaustiveProjectileTankHit(g *Game, b *Bullet, x, y, dx, dy float64) (*Tank, float64) {
	var target *Tank
	first := 2.0
	for _, tank := range g.Tanks {
		if tank == nil || !tank.Alive || tank.ID == b.Owner || b.Kind != "grenade" && (!g.canDamage(b.Owner, tank) || tank.Invulnerable > 0) {
			continue
		}
		if at, ok := circleHit(x, y, dx, dy, tank.X, tank.Y, tank.R+b.R); ok && at < first {
			first, target = at, tank
		}
	}
	return target, first
}

func TestProjectileBoundsPreserveExhaustiveContacts(t *testing.T) {
	g := battle(maxTanks)
	g.Rules.TeamMode = "teams"
	random := rand.New(rand.NewSource(44937))
	for sample := range 6000 {
		for id, tank := range g.Tanks {
			tank.X, tank.Y = random.Float64()*2000-1000, random.Float64()*1200-600
			tank.Team = id%3 + 1
			tank.Alive = random.Intn(5) != 0
			tank.Invulnerable = float64(random.Intn(3))
		}
		g.Rules.FriendlyFire = sample%2 == 0
		bullet := &Bullet{Owner: sample % maxTanks, R: []float64{regularRadius, machineRadius, cannonRadius, 6}[sample%4]}
		if sample%3 == 0 {
			bullet.Kind = "grenade"
		}
		x, y, dx, dy := random.Float64()*2000-1000, random.Float64()*1200-600, random.Float64()*2000-1000, random.Float64()*1200-600
		if sample%11 == 0 {
			dx, dy = 0, 0
		}
		got, at := g.projectileTankHit(bullet, x, y, dx, dy)
		want, wantAt := exhaustiveProjectileTankHit(g, bullet, x, y, dx, dy)
		if got != want || math.Abs(at-wantAt) > 1e-12 {
			t.Fatalf("sample %d changed contact: got %v at %v, want %v at %v", sample, got, at, want, wantAt)
		}
	}
}

func TestProjectileBoundsKeepGrazingAndProtectedGrenadeContact(t *testing.T) {
	g := battle(3)
	for _, tank := range g.Tanks {
		if tank != nil {
			tank.Invulnerable = 0
		}
	}
	g.Tanks[1].X, g.Tanks[1].Y = 100, 20.5
	g.Tanks[2].X, g.Tanks[2].Y = 100, 20.5
	bullet := &Bullet{Owner: 0, R: regularRadius}
	got, _ := g.projectileTankHit(bullet, 0, 0, 200, 0)
	if got != g.Tanks[1] {
		t.Fatal("a tangent or equal-distance candidate changed order")
	}
	g.Tanks[1].Invulnerable, g.Tanks[2].Invulnerable = 10, 10
	if got, _ = g.projectileTankHit(bullet, 0, 0, 200, 0); got != nil {
		t.Fatal("ordinary shots must pass protected tanks")
	}
	bullet.Kind = "grenade"
	if got, _ = g.projectileTankHit(bullet, 0, 0, 200, 0); got != g.Tanks[1] {
		t.Fatal("grenades must retain protected-tank physical contact")
	}
}
