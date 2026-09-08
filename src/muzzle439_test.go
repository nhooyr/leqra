package main

import (
	"math"
	"testing"
)

func TestMuzzle439CloseGrazingTankCannotBeSkippedByLaunch(t *testing.T) {
	for _, tc := range []struct {
		kind string
		x, y float64
	}{
		{"", 27.2, 20.49},
		{"homing", 26, 21.99},
		{"grenade", 25.2, 22.99},
		{"cannon", 17, 30},
	} {
		t.Run(tc.kind, func(t *testing.T) {
			g := battle(2)
			shooter, target := g.Tanks[0], g.Tanks[1]
			shooter.X, shooter.Y, shooter.Angle = 100, 100, 0
			target.X, target.Y = shooter.X+tc.x, shooter.Y+tc.y
			if math.Hypot(tc.x, tc.y) <= shooter.R+target.R {
				t.Fatal("fixture overlaps tanks")
			}
			if tc.kind != "" {
				g.grantPower(shooter, tc.kind)
			}
			if !g.fire(shooter) {
				t.Fatal("fixture did not fire")
			}
			if target.Alive || len(g.Bullets) != 0 {
				t.Fatal("launch contact was not resolved before exposing the projectile")
			}
			g.updateBullets(tickDT)
			if target.Alive {
				t.Fatal("launch skipped a vulnerable tank inside the muzzle sweep")
			}
		})
	}
}

func TestMuzzle439ContactKeepsDamageEligibility(t *testing.T) {
	for _, kind := range []string{"", "homing", "cannon", "grenade"} {
		for _, status := range []string{"ally", "friendly_fire", "protected", "dead"} {
			t.Run(kind+"/"+status, func(t *testing.T) {
				g := battle(2)
				shooter, target := g.Tanks[0], g.Tanks[1]
				shooter.X, shooter.Y, shooter.Angle = 100, 100, 0
				target.X, target.Y = 135, 100
				shooter.Invulnerable = 1 // Keep grenade splash out of this eligibility check.
				switch status {
				case "ally", "friendly_fire":
					shooter.Team, target.Team = 1, 1
					g.Rules.FriendlyFire = status == "friendly_fire"
				case "protected":
					target.Invulnerable = 1
				case "dead":
					target.Alive = false
				}
				if kind != "" {
					g.grantPower(shooter, kind)
				}
				g.fire(shooter)
				contact := status == "friendly_fire" || kind == "grenade" && status != "dead"
				if (len(g.Bullets) == 0) != contact {
					t.Fatal("muzzle contact did not match flight eligibility", len(g.Bullets))
				}
				if target.Alive != (status != "friendly_fire" && status != "dead") {
					t.Fatal("contact bypassed friendly fire or protection")
				}
				wantBlasts := 0
				if kind == "grenade" && contact {
					wantBlasts = 1
				}
				if blastCount(g) != wantBlasts || !shooter.Alive {
					t.Fatal("grenade contact duplicated blast or bypassed owner protection")
				}
			})
		}
	}
}

func TestMuzzle439ShieldAndShotAccounting(t *testing.T) {
	for _, kind := range []string{"", "rapid", "scatter", "homing", "grenade", "cannon"} {
		t.Run(kind, func(t *testing.T) {
			g := battle(2)
			shooter, target := g.Tanks[0], g.Tanks[1]
			shooter.X, shooter.Y, shooter.Angle = 100, 100, 0
			target.X, target.Y = 135, 100
			shooter.Invulnerable = 1
			g.grantPower(target, "shield")
			if kind != "" {
				g.grantPower(shooter, kind)
			}
			charges, rounds, serial := shooter.Charges, shooter.MachineRounds, shooter.ShotSerial
			if !g.fire(shooter) || !target.Alive || shieldCount(target) != 0 || target.Invulnerable <= 0 {
				t.Fatal("shield did not absorb exactly one launch impact")
			}
			if shooter.ShotSerial != serial+1 || kind == "rapid" && shooter.MachineRounds != rounds-1 || charges > 0 && kind != "rapid" && shooter.Charges != charges-1 {
				t.Fatal("launch impact bypassed or duplicated shot accounting")
			}
			wantBullets := 0
			if kind == "scatter" {
				wantBullets = 2 // First pellet grants protection from the rest of this volley.
			}
			if len(g.Bullets) != wantBullets {
				t.Fatal("consumed launch projectile leaked into snapshots", len(g.Bullets))
			}
			g.updateBullets(tickDT)
			if !target.Alive || shieldCount(target) != 0 {
				t.Fatal("consumed projectile caused repeated contact damage")
			}
		})
	}
}

func TestMuzzle439WallPrecedenceAndCannonPassage(t *testing.T) {
	for _, kind := range []string{"", "homing", "grenade", "cannon"} {
		t.Run(kind, func(t *testing.T) {
			g := battle(2)
			shooter, target := g.Tanks[0], g.Tanks[1]
			shooter.X, shooter.Y, shooter.Angle = 100, 100, 0
			target.X, target.Y = 147, 100
			g.World.Walls = append(g.World.Walls, Wall{X: 122, Y: 0, W: 8, H: 420})
			if kind != "" {
				g.grantPower(shooter, kind)
			}
			g.fire(shooter)
			if kind == "cannon" {
				if target.Alive || len(g.Bullets) != 0 {
					t.Fatal("cannon muzzle no longer passes through interior cover")
				}
				return
			}
			if !target.Alive || len(g.Bullets) != 1 || g.Bullets[0].VX >= 0 || g.Bullets[0].Bounces != 1 || blastCount(g) != 0 {
				t.Fatal("muzzle tank sweep bypassed intervening wall")
			}
		})
	}
}

func TestMuzzle439HitsNearestTankRegardlessOfSeatOrder(t *testing.T) {
	g := battle(3)
	shooter, farther, nearer := g.Tanks[0], g.Tanks[1], g.Tanks[2]
	shooter.X, shooter.Y, shooter.Angle = 100, 100, 0
	farther.X, farther.Y = 137, 82
	nearer.X, nearer.Y = 132, 118
	g.fire(shooter)
	if !farther.Alive || nearer.Alive || len(g.Bullets) != 0 {
		t.Fatal("launch did not stop at first eligible tank contact")
	}
}
