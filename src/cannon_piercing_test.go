package main

import (
	"math"
	"testing"
	"time"
)

func TestCannonPiercesEverySweptTargetAndKeepsOneContactPerLife(t *testing.T) {
	for _, infinity := range []bool{false, true} {
		t.Run(map[bool]string{false: "fixed", true: "infinity"}[infinity], func(t *testing.T) {
			if infinity {
				a := newSeededInfiniteArena(37)
				owner := a.join(fakeClient(), "Owner", time.Unix(0, 0))
				owner.X, owner.Y = 42, 42
				a.rules = &infiniteRules{Target: 1}
				var victims []*infinitePilot
				for _, x := range []float64{210, 150, 180} {
					p := a.addPilot("Target", true, 0, 0, 0, 0)
					p.X, p.Y, p.Protected, p.kit.Invulnerable = x, 42, false, 0
					victims = append(victims, p)
				}
				b := infiniteBullet{ID: 1, Owner: owner.ID, X: 100, Y: 42, Kind: "cannon", radius: cannonRadius, Life: cannonLifetime}
				if !a.advanceBullet(&b, 150, 0) || b.X != 250 || b.Life != cannonLifetime || b.dead {
					t.Fatal("piercing changed full segment travel or projectile lifetime")
				}
				for _, p := range victims {
					if p.HP != 0 {
						t.Fatal("cannon missed a later target")
					}
				}
				if owner.Score != 3 || a.result == nil || a.result.Score != 3 {
					t.Fatal("winning cannon froze before all same-segment hits", owner.Score, a.result)
				}
				return
			}
			g := battle(5)
			for i, x := range []float64{60, 210, 150, 180, 300} {
				g.Tanks[i].X, g.Tanks[i].Y = x, 210
			}
			g.Tanks[2].Shield, g.Tanks[2].ShieldCharges = 10, 3
			g.Tanks[4].Invulnerable = 10
			b := &Bullet{ID: 1, Owner: 0, X: 100, Y: 210, VX: 300, Kind: "cannon", R: cannonRadius, Life: cannonLifetime}
			g.Bullets = []*Bullet{b}
			g.updateBullets(.5)
			if g.Tanks[1].Alive || g.Tanks[3].Alive || !g.Tanks[2].Alive || g.Tanks[2].ShieldCharges != 2 || !g.Tanks[4].Alive || b.Dead || b.X != 250 || math.Abs(b.Life-(cannonLifetime-.5)) > 1e-9 {
				t.Fatal("cannon failed mixed swept damage eligibility")
			}
			g.Tanks[2].Invulnerable = 0
			b.VX = -300
			g.updateBullets(.5)
			if g.Tanks[2].ShieldCharges != 2 || g.Tanks[0].stats.Eliminations != 2 {
				t.Fatal("return crossing hit a shield or corpse twice")
			}
			g.Tanks[2].SpawnSerial++
			b.VX = 300
			g.updateBullets(.5)
			if g.Tanks[2].ShieldCharges != 1 {
				t.Fatal("a genuinely new life remained immune to the old shell")
			}
		})
	}
}

func TestCannonMuzzlePiercesOverlappingTargetsWithoutTerminalFlight(t *testing.T) {
	g := battle(4)
	g.Tick = 2
	owner := g.Tanks[0]
	owner.X, owner.Y, owner.Angle = 100, 100, 0
	for id := 1; id < 4; id++ {
		g.Tanks[id].X, g.Tanks[id].Y = 128, 100
	}
	g.grantPower(owner, "cannon")
	if !g.fire(owner) || len(g.Bullets) != 1 || owner.stats.Eliminations != 3 {
		t.Fatal("hidden muzzle path stopped on its first overlapping victim")
	}
	contacts := 0
	for _, event := range g.events {
		if event.Flight != nil {
			t.Fatal("a live piercing shell was published as terminal")
		}
		if event.Contact != nil {
			contacts++
			if event.Contact.ProjectileID != 0 || event.Contact.Kind != "cannon" {
				t.Fatal("piercing hit would wait for the shell's final flight")
			}
		}
	}
	if contacts != 3 || g.Bullets[0].X != 132 || g.Bullets[0].Life != cannonLifetime {
		t.Fatal("muzzle victims or full launch travel missing")
	}
}

func TestGrenadeDetonationHoldWaitsForReleaseAcrossPickup(t *testing.T) {
	for _, infinity := range []bool{false, true} {
		h := newMachineSynergyArena(infinity)
		h.grant("grenade")
		h.stepHeld(true, true)
		h.stepHeld(false, false)
		h.stepHeld(true, true)
		h.grant("cannon")
		for range 60 {
			h.stepHeld(true, false)
		}
		if h.tank.ShotSerial != 1 || len(h.shots()) != 0 {
			t.Fatal("detonation hold crossed into another shot or newly collected weapon", infinity)
		}
		h.stepHeld(false, false)
		h.stepHeld(true, true)
		if h.tank.ShotSerial != 2 || len(h.shots()) != 1 {
			t.Fatal("release did not enable the next intended shot", infinity)
		}
	}
}

func TestCannonBoundsKeepGrazingContacts(t *testing.T) {
	// Rounding in the shared quadratic solver can accept the adjacent floating
	// point at a tangent. The broad phase must not discard that valid contact.
	y := math.Nextafter(tankRadius+cannonRadius, math.Inf(1))
	if _, hit := circleHit(0, 0, 200, 0, 100, y, tankRadius+cannonRadius); !hit {
		t.Fatal("grazing fixture no longer reaches the shared narrow phase")
	}
	g := battle(2)
	target := g.Tanks[1]
	target.X, target.Y, target.Invulnerable = 100, y, 0
	g.cannonSegment(&Bullet{Kind: "cannon", Owner: 0, R: cannonRadius}, 200, 0, 0, 0)
	if target.Alive {
		t.Fatal("fixed Cannon discarded a grazing contact")
	}
	a := newSeededInfiniteArena(37)
	owner := a.join(fakeClient(), "Owner", time.Unix(0, 0))
	victim := a.addPilot("Target", true, 0, 0, 0, 0)
	victim.X, victim.Y, victim.Protected, victim.kit.Invulnerable = 100, y, false, 0
	a.cannonSegment(&infiniteBullet{Kind: "cannon", Owner: owner.ID, radius: cannonRadius}, 200, 0, 0, 0)
	if victim.HP != 0 {
		t.Fatal("Infinity Cannon discarded a grazing contact")
	}
}
