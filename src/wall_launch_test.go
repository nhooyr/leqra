package main

import (
	"encoding/json"
	"math"
	"os"
	"testing"
	"time"
)

func TestWallLaunchSharedGeometryFixtures(t *testing.T) {
	data, err := os.ReadFile("tests/fixtures/wall_launch.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixtures []struct {
		Name                         string
		X, Y, UX, UY, Radius, Muzzle float64
		Walls                        []Wall
		Bounds                       []float64
		Expected                     struct {
			X, Y, UX, UY, Distance, Muzzle float64
			Bounced, Valid                 bool
		}
	}
	if err := json.Unmarshal(data, &fixtures); err != nil {
		t.Fatal(err)
	}
	for _, f := range fixtures {
		t.Run(f.Name, func(t *testing.T) {
			var bounds func(float64, float64) bool
			if len(f.Bounds) > 0 {
				bounds = func(x, y float64) bool {
					return x >= f.Bounds[0] && y >= f.Bounds[1] && x <= f.Bounds[2] && y <= f.Bounds[3]
				}
			}
			check := func(walls []Wall) {
				t.Helper()
				got := wallLaunch(f.X, f.Y, f.UX, f.UY, f.Radius, f.Muzzle, walls, bounds)
				want := f.Expected
				if got.bounced != want.Bounced || got.valid != want.Valid {
					t.Fatalf("launch flags = %+v, want %+v", got, want)
				}
				for name, pair := range map[string][2]float64{"x": {got.x, want.X}, "y": {got.y, want.Y}, "ux": {got.ux, want.UX}, "uy": {got.uy, want.UY}, "distance": {got.distance, want.Distance}, "muzzle": {got.muzzle, want.Muzzle}} {
					if math.Abs(pair[0]-pair[1]) > 1e-7 {
						t.Errorf("%s = %.12f, want %.12f", name, pair[0], pair[1])
					}
				}
				if got.valid && got.bounced {
					if got.distance > 32 || (got.x-f.X)*f.UX+(got.y-f.Y)*f.UY > 1e-7 {
						t.Fatal("anchor escaped the bounded incoming side")
					}
					if got.distance+got.muzzle > math.Max(32, f.Muzzle)+1e-7 {
						t.Fatal("projection granted extra muzzle travel")
					}
				}
			}
			check(f.Walls)
			for i, j := 0, len(f.Walls)-1; i < j; i, j = i+1, j-1 {
				f.Walls[i], f.Walls[j] = f.Walls[j], f.Walls[i]
			}
			check(f.Walls) // Query order must not decide a corner's clear side.
		})
	}
}

func wallLaunchInfinityArena() (*infiniteArena, *infinitePilot, *infinitePilot, Wall) {
	a := newSeededInfiniteArena(37)
	shooter := a.join(fakeClient(), "Shooter", time.Unix(0, 0))
	target := a.join(fakeClient(), "Target", time.Unix(0, 0))
	a.maze = newInfiniteMaze(37)
	// A deterministic single wall in an otherwise empty region, including the
	// entire Laser budget. This exercises real Infinity maze collision queries.
	for cy := -4; cy <= 4; cy++ {
		for cx := -4; cx <= 4; cx++ {
			a.maze.chunks[infiniteChunkCoord{cx, cy}] = new(infiniteChunk)
		}
	}
	a.maze.chunks[infiniteChunkCoord{0, 0}][3*infiniteChunkCells+3] = infiniteWest
	wall := a.maze.wallsNear(200, 200, 300, 350)[0]
	shooter.X, shooter.Y, shooter.Angle, shooter.Protected = wall.X-1, wall.Y+wall.H/2, 0, false
	shooter.kit.Invulnerable, shooter.kit.SpawnProtected = 0, false
	target.X, target.Y, target.Protected = wall.X+40, shooter.Y, false
	target.kit.Invulnerable, target.kit.SpawnProtected = 0, false
	return a, shooter, target, wall
}

func TestInfinitePhasedWallLaunchAllWeapons(t *testing.T) {
	for _, phase := range []string{"ghost", "starman"} {
		for _, kind := range []string{"", "laser", "grenade", "rapid", "scatter", "homing", "cannon"} {
			for _, embedded := range []bool{false, true} {
				name := "face"
				if embedded {
					name = "embedded"
				}
				t.Run(phase+"/"+kind+"/"+name, func(t *testing.T) {
					a, p, target, wall := wallLaunchInfinityArena()
					if embedded {
						p.X = wall.X + wall.W/2
					}
					applyPower(&p.kit, phase, infinitePowerDuration, infiniteStarDuration)
					if kind != "" {
						applyPower(&p.kit, kind, infinitePowerDuration, infiniteStarDuration)
					}
					charges, rounds := p.kit.Charges, p.kit.MachineRounds
					a.fire(p)
					if p.kit.ShotSerial != 1 || p.kit.Recoil != 1 {
						t.Fatal("wall-facing shot failed to fire")
					}
					if phase == "starman" {
						if p.kit.Charges != charges || p.kit.MachineRounds != rounds {
							t.Fatal("Starman spent saved ammunition")
						}
					} else if kind == "rapid" && p.kit.MachineRounds != rounds-1 || kind != "rapid" && charges > 0 && p.kit.Charges != charges-1 {
						t.Fatal("legal shot did not spend exactly one charge")
					}
					if kind == "cannon" {
						if target.HP != 0 {
							t.Fatal("Cannon stopped at the wall")
						}
						return
					}
					if target.HP != infiniteMaxHP {
						t.Fatal("reflected shot tunneled forward through a wall")
					}
					if kind == "laser" {
						points, _ := a.traceLaser(p)
						if len(points) < 2 || points[1].X >= points[0].X {
							t.Fatal("Laser did not start along its reflected path", points)
						}
						return
					}
					want := 1
					if kind == "scatter" {
						want = 3
					}
					if len(a.bullets) != want {
						t.Fatalf("got %d bullets, want %d", len(a.bullets), want)
					}
					for _, b := range a.bullets {
						if b.Bounces != 1 || b.VX >= 0 {
							t.Fatal("projectile did not reflect at launch", b)
						}
						if kind == "homing" || kind == "grenade" {
							if b.seekDelay != missileWallDelay {
								t.Fatal("guidance skipped its wall delay")
							}
						}
					}
				})
			}
		}
	}
}

func TestPhasedAbsorbedWallLaunchKeepsReadinessRules(t *testing.T) {
	for _, kind := range []string{"", "laser", "grenade", "rapid", "scatter", "homing"} {
		t.Run(kind, func(t *testing.T) {
			g := battle(2)
			p, target := g.Tanks[0], g.Tanks[1]
			g.World.Walls = append(g.World.Walls, Wall{X: 0, Y: 0, W: g.World.Width, H: g.World.Height})
			g.grantPower(p, "ghost")
			if kind != "" {
				g.grantPower(p, kind)
			}
			charges, rounds := p.Charges, p.MachineRounds
			p.SpawnProtected, p.Invulnerable = true, 1
			if g.fire(p) || p.ShotSerial != 0 || p.Charges != charges || p.MachineRounds != rounds {
				t.Fatal("spawn-protected attempt spent a shot")
			}
			p.SpawnProtected, p.Invulnerable = false, 0
			if !g.fire(p) || p.ShotSerial != 1 || len(g.Bullets) != 0 || !target.Alive {
				t.Fatal("solid geometry did not absorb a legal shot")
			}
			if kind == "rapid" && p.MachineRounds != rounds-1 || kind != "rapid" && charges > 0 && p.Charges != charges-1 {
				t.Fatal("absorbed shot spent incorrect ammunition")
			}
			if g.fire(p) || p.ShotSerial != 1 {
				t.Fatal("absorption bypassed reload or rapid cadence")
			}
		})
	}
}
