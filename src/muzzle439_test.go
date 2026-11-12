package main

import (
	"math"
	"testing"
)

func TestPhasedWallLaunchAlwaysFiresAndRicochets(t *testing.T) {
	for _, power := range []string{"ghost", "starman"} {
		for _, kind := range []string{"", "laser", "grenade", "rapid", "scatter", "homing", "cannon"} {
			for _, origin := range []string{"face", "embedded", "corner"} {
				t.Run(power+"/"+kind+"/"+origin, func(t *testing.T) {
					g := battle(2)
					wall := Wall{X: 230, Y: 180, W: 8, H: 80}
					g.World.Walls = append(g.World.Walls, wall)
					shooter, target := g.Tanks[0], g.Tanks[1]
					shooter.X, target.X = wall.X-1, wall.X+40
					g.grantPower(shooter, power)
					if kind != "" {
						g.grantPower(shooter, kind)
					}
					radius := regularRadius
					switch kind {
					case "laser":
						radius = laserRadius
					case "grenade":
						radius = 6
					case "homing":
						radius = 5
					case "rapid":
						radius = machineRadius
					case "cannon":
						radius = cannonRadius
					}
					if origin == "embedded" {
						shooter.X = wall.X + wall.W/2
					}
					if origin == "corner" {
						shooter.X, shooter.Y, shooter.Angle = wall.X-.9*radius, wall.Y-.9*radius, math.Pi/4
					}
					charges, rounds := shooter.Charges, shooter.MachineRounds
					launch := g.projectileLaunch(shooter, shooter.Angle, radius, 28)
					if !g.fire(shooter) || shooter.ShotSerial != 1 || shooter.Recoil != 1 {
						t.Fatal("wall-facing shot did not fire")
					}
					if power == "starman" {
						if shooter.Charges != charges || shooter.MachineRounds != rounds {
							t.Fatal("Starman spent saved ammunition")
						}
					} else if kind == "rapid" && shooter.MachineRounds != rounds-1 || kind != "rapid" && charges > 0 && shooter.Charges != charges-1 {
						t.Fatal("reflected shot did not spend exactly one charge")
					}
					if kind == "cannon" {
						if launch.bounced {
							t.Fatal("Cannon must penetrate instead of projecting")
						}
						return
					}
					if !launch.valid || !launch.bounced || launch.ux >= 0 && launch.uy >= 0 {
						t.Fatal("overlapping launch did not reflect toward a clear face", launch)
					}
					if origin != "corner" && !target.Alive {
						t.Fatal("reflected shot tunneled forward through the wall")
					}
					if kind == "laser" {
						points, _ := g.traceLaser(shooter)
						if len(points) < 2 || points[0].X != launch.x || points[0].Y != launch.y || points[1].X >= points[0].X && points[1].Y >= points[0].Y {
							t.Fatal("laser did not begin at its reflected anchor", points)
						}
						return
					}
					want := 1
					if kind == "scatter" {
						want = 3
					}
					if len(g.Bullets) != want {
						t.Fatalf("got %d bullets, want %d", len(g.Bullets), want)
					}
					for _, b := range g.Bullets {
						if b.Bounces < 1 || b.VX >= 0 && b.VY >= 0 {
							t.Fatal("wall launch did not ricochet", b)
						}
						if kind == "homing" || kind == "grenade" {
							if b.SeekDelay != missileWallDelay {
								t.Fatal("reflected guidance skipped its wall delay")
							}
						}
					}
				})
			}
		}
	}
}

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
