package main

import (
	"math"
	"testing"
)

func TestMuzzlePlaybackOmitsHiddenBarrelSweep(t *testing.T) {
	for _, kind := range []string{"", "rapid", "scatter", "homing", "grenade", "cannon"} {
		for _, contact := range []string{"open", "wall", "tank"} {
			t.Run(kind+"/"+contact, func(t *testing.T) {
				g := battle(2)
				g.Tick = 2
				shooter, target := g.Tanks[0], g.Tanks[1]
				shooter.X, shooter.Y, shooter.Angle = 100, 100, 0
				target.X, target.Y = 400, 300
				if kind != "" {
					g.grantPower(shooter, kind)
				}
				if contact == "wall" {
					g.World.Walls = append(g.World.Walls, Wall{X: 122, Y: 50, W: 8, H: 100})
				} else if contact == "tank" {
					target.X, target.Y = 135, 100
				}
				if !g.fire(shooter) {
					t.Fatal("shot did not fire")
				}
				for _, bullet := range g.Bullets {
					if math.Hypot(bullet.flightBirth.X-shooter.X, bullet.flightBirth.Y-shooter.Y) < 1 {
						t.Fatal("playback starts at the tank centre", bullet.flightBirth)
					}
					if contact == "wall" && kind != "cannon" && (bullet.VX >= 0 || bullet.flightBirth.X > 122) {
						t.Fatal("muzzle visual bypassed the wall", bullet)
					}
				}
				for _, event := range g.events {
					if event.Flight != nil && math.Hypot(event.Flight.Points[0].X-shooter.X, event.Flight.Points[0].Y-shooter.Y) < 1 {
						t.Fatal("terminal playback includes the hidden barrel sweep", event.Flight)
					}
				}
			})
		}
	}
}

func TestInfiniteMuzzlePlaybackStartsAtFirstVisibleContact(t *testing.T) {
	for _, kind := range []string{"", "rapid", "scatter", "homing", "grenade", "cannon"} {
		t.Run(kind, func(t *testing.T) {
			a, shooter, target, wall := wallLaunchInfinityArena()
			shooter.X = wall.X - 22
			target.X, target.Y = shooter.X-150, shooter.Y+100
			if kind != "" {
				applyPower(&shooter.kit, kind, infinitePowerDuration, infiniteStarDuration)
			}
			a.fire(shooter)
			if len(a.bullets) == 0 {
				t.Fatal("shot did not fire")
			}
			for _, bullet := range a.bullets {
				if math.Hypot(bullet.flightBirth.X-shooter.X, bullet.flightBirth.Y-shooter.Y) < 1 {
					t.Fatal("Infinity playback includes the hidden barrel sweep", bullet.flightBirth)
				}
				if kind != "cannon" && bullet.VX >= 0 {
					t.Fatal("shot stopped respecting cover")
				}
				if kind != "cannon" && math.Abs(bullet.X-(wall.X-bullet.radius-.12)) > 1e-7 {
					t.Fatal("instant launch travel carried the ricochet back inside the tank", bullet.X)
				}
			}
		})
	}
}

func TestGhostWallOverlapStartsReflectionAtIncomingFace(t *testing.T) {
	for _, kind := range []string{"", "rapid", "scatter", "homing", "grenade"} {
		for _, gap := range []float64{22, 8, 1} {
			g := battle(2)
			pilot, target := g.Tanks[0], g.Tanks[1]
			pilot.X, pilot.Y, pilot.Angle = 248-gap, 200, 0
			target.X, target.Y = 500, 300
			g.World.Walls = []Wall{{X: 248, Y: 84, W: 8, H: 672}}
			g.grantPower(pilot, "ghost")
			if kind != "" {
				g.grantPower(pilot, kind)
			}
			if !g.fire(pilot) {
				t.Fatal("Ghost shot did not fire")
			}
			for _, b := range g.Bullets {
				if b.VX >= 0 || math.Abs(b.X-(248-b.R-.12)) > 1e-7 {
					t.Fatalf("Ghost %q gap %v skipped its incoming muzzle: %+v", kind, gap, b)
				}
			}
			a, p, other, wall := wallLaunchInfinityArena()
			p.X = wall.X - gap
			other.X, other.Y = p.X-150, p.Y+100
			applyPower(&p.kit, "ghost", 600, 600)
			if kind != "" {
				applyPower(&p.kit, kind, 600, 600)
			}
			a.fire(p)
			for _, b := range a.bullets {
				if b.VX >= 0 || math.Abs(b.X-(wall.X-b.radius-.12)) > 1e-7 {
					t.Fatalf("Infinity Ghost %q gap %v skipped its incoming muzzle: %+v", kind, gap, b)
				}
			}
		}
	}
}
