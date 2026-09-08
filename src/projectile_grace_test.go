package main

import (
	"math"
	"testing"
)

func TestProjectileOwnerGracePreservesEarlyGrazes(t *testing.T) {
	for _, weapon := range []struct {
		kind          string
		radius, speed float64
	}{
		{"", regularRadius, regularSpeed},
		{"homing", 5, missileSpeed},
		{"grenade", 6, grenadeSpeed},
		{"cannon", cannonRadius, cannonSpeed},
	} {
		for _, dt := range []float64{tickDT, .001} {
			g := battle(1)
			owner := g.Tanks[0]
			owner.X, owner.Y = 200, 200
			b := &Bullet{Owner: owner.ID, Kind: weapon.kind, X: 199.7, Y: owner.Y + owner.R + weapon.radius - .001, VX: weapon.speed, R: weapon.radius, Life: grenadeFuse - .195, Age: .195, Target: -1}
			g.Bullets = []*Bullet{b}
			for elapsed := 0.0; elapsed < tickDT-1e-10; {
				span := math.Min(dt, tickDT-elapsed)
				g.updateBullets(span)
				elapsed += span
			}
			if !owner.Alive || b.Dead {
				t.Fatalf("%q dt=%v: a graze before age .20 hit the owner", weapon.kind, dt)
			}
		}
	}
}

func TestProjectileOwnerGraceExpiryDuringSweep(t *testing.T) {
	for _, tc := range []struct {
		name              string
		x, age, dt, wantX float64
		alive             bool
	}{
		{"still protected", 180, .15, tickDT, 184.7, true},
		{"overlapping at expiry", 180, .195, tickDT, 181.41, false},
		{"expiry at endpoint", 180, .19, .01, 182.82, false},
		{"contact after expiry", 175, .195, tickDT, 179.5, false},
		{"already vulnerable", 175, .21, tickDT, 179.5, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			g := battle(1)
			owner := g.Tanks[0]
			owner.X, owner.Y = 200, 200
			b := &Bullet{Owner: owner.ID, X: tc.x, Y: owner.Y, VX: regularSpeed, R: regularRadius, Life: 1, Age: tc.age}
			g.Bullets = []*Bullet{b}
			g.updateBullets(tc.dt)
			if owner.Alive != tc.alive || b.Dead == tc.alive || math.Abs(b.X-tc.wantX) > 1e-8 {
				t.Fatalf("owner alive=%v, projectile dead=%v at %v; want alive=%v at %v", owner.Alive, b.Dead, b.X, tc.alive, tc.wantX)
			}
		})
	}
}

func TestProjectileOwnerGraceTracksTimeAcrossRicochets(t *testing.T) {
	for _, wallX := range []float64{204, 205} {
		g := battle(1)
		owner := g.Tanks[0]
		owner.X, owner.Y = 200, 200
		g.World.Walls = append(g.World.Walls, Wall{X: wallX, Y: 219, W: 8, H: 20})
		b := &Bullet{Owner: owner.ID, X: 200.3, Y: 220.499, VX: regularSpeed, R: regularRadius, Life: 1, Age: .195}
		g.Bullets = []*Bullet{b}
		g.updateBullets(tickDT)
		wantAlive := wallX == 204 // The shorter trip grazes and leaves before expiry.
		if owner.Alive != wantAlive || b.Bounces != 1 {
			t.Fatalf("wall x=%v: owner alive=%v, bounces=%v", wallX, owner.Alive, b.Bounces)
		}
		if !wantAlive {
			wantX := owner.X + math.Sqrt(math.Pow(owner.R+b.R, 2)-math.Pow(b.Y-owner.Y, 2))
			if math.Abs(b.X-wantX) > 1e-8 {
				t.Fatalf("ricochet contact moved from %v to %v", wantX, b.X)
			}
		}
	}
}

func TestProjectileOwnerGraceKeepsOtherCollisionEligibility(t *testing.T) {
	for _, kind := range []string{"rapid", "scatter"} {
		g := battle(1)
		owner := g.Tanks[0]
		b := &Bullet{Owner: owner.ID, Kind: kind, X: owner.X, Y: owner.Y, VX: machineSpeed, R: regularRadius, Life: 1, Age: 1}
		g.Bullets = []*Bullet{b}
		g.updateBullets(tickDT)
		if !owner.Alive || b.Dead {
			t.Fatalf("%s lost permanent owner immunity", kind)
		}
	}
	g := battle(2)
	other := g.Tanks[1]
	b := &Bullet{Owner: 0, X: other.X, Y: other.Y, VX: regularSpeed, R: regularRadius, Life: 1, Age: .195}
	g.Bullets = []*Bullet{b}
	g.updateBullets(tickDT)
	if other.Alive || !b.Dead || b.X != other.X {
		t.Fatal("owner grace delayed another tank's immediate contact")
	}
}

func TestProjectileOwnerGraceUsesAvailableFlightTime(t *testing.T) {
	for _, kind := range []string{"", "homing"} {
		g := battle(1)
		owner := g.Tanks[0]
		owner.X, owner.Y = 200, 200
		speed := regularSpeed
		b := &Bullet{Owner: owner.ID, Kind: kind, X: 180, Y: owner.Y, R: regularRadius, Age: .195, Life: .003, Target: -1}
		if kind == "homing" {
			speed = missileSpeed
			b.Life, b.RangeLeft, b.rangeSet = 1, speed*.003, true
		}
		b.VX = speed
		g.Bullets = []*Bullet{b}
		g.updateBullets(tickDT)
		if !owner.Alive || !b.Dead || math.Abs(b.X-(180+speed*.003)) > 1e-8 {
			t.Fatalf("%q expired during grace: owner alive=%v, projectile dead=%v at %v", kind, owner.Alive, b.Dead, b.X)
		}
	}
}
