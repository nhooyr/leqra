package main

import "testing"

func TestOwnedProjectilesPassThroughShooter(t *testing.T) {
	for _, weapon := range []struct {
		kind          string
		radius, speed float64
	}{
		{"", regularRadius, regularSpeed},
		{"homing", 5, missileSpeed},
		{"grenade", 6, grenadeSpeed},
		{"cannon", cannonRadius, cannonSpeed},
		{"rapid", machineRadius, machineSpeed},
		{"scatter", regularRadius, shotgunSpeed},
	} {
		for _, age := range []float64{0, 1} {
			g := battle(2)
			owner, enemy := g.Tanks[0], g.Tanks[1]
			owner.X, enemy.X = 200, 247
			owner.Shield, owner.ShieldCharges = 10, 2
			b := &Bullet{Owner: owner.ID, Kind: weapon.kind, X: 173, Y: owner.Y, VX: weapon.speed, R: weapon.radius, Life: grenadeFuse - age, Age: age, Target: -1}
			g.Bullets = []*Bullet{b}
			for i := 0; i < 30 && !b.Dead; i++ {
				g.updateBullets(tickDT)
			}
			if !owner.Alive || owner.ShieldCharges != 2 || owner.Invulnerable != 0 || enemy.Alive || !b.Dead {
				t.Fatalf("%q at age %v: owner must be untouched and enemy must be hit", weapon.kind, age)
			}
		}
	}
}

func TestRicochetPassesThroughShooterAndHitsEnemy(t *testing.T) {
	g := battle(2)
	owner, enemy := g.Tanks[0], g.Tanks[1]
	owner.X, enemy.X = 200, 140
	g.World.Walls = append(g.World.Walls, Wall{X: 230, Y: 180, W: 8, H: 80})
	b := &Bullet{Owner: owner.ID, X: 220, Y: owner.Y, VX: regularSpeed, R: regularRadius, Life: 1, Age: 1}
	g.Bullets = []*Bullet{b}
	for i := 0; i < 30 && !b.Dead; i++ {
		g.updateBullets(tickDT)
	}
	if !owner.Alive || enemy.Alive || b.Bounces != 1 || !b.Dead {
		t.Fatalf("expected the bounced shell to pass through its shooter and hit the enemy: %+v", b)
	}
}
