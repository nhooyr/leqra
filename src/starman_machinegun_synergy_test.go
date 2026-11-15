package main

import (
	"fmt"
	"math"
	"testing"
	"time"
)

type machineSynergyShot struct {
	id, bounces int
	epoch       uint64
	speed, life float64
	radius      float64
	boosted     bool
}

type machineSynergyArena struct {
	game  *Game
	arena *infiniteArena
	pilot *infinitePilot
	tank  *Tank
}

func newMachineSynergyArena(infinity bool) machineSynergyArena {
	if infinity {
		a := newSeededInfiniteArena(44937)
		p := a.join(fakeClient(), "Probe", time.Unix(1_800_000_000, 0))
		p.X, p.Y, p.Angle = 42, 42, 0
		p.kit.Invulnerable, p.kit.SpawnProtected, p.Protected = 0, false, false
		a.nextBot, a.nextPickup = math.MaxUint64, math.MaxUint64
		return machineSynergyArena{arena: a, pilot: p, tank: &p.kit}
	}
	g := battle(2)
	g.World = World{Cols: 24, Rows: 14, Width: 2016, Height: 1176, Walls: []Wall{
		{X: -4, Y: -4, W: 2024, H: 8, Axis: "h", Line: 0},
		{X: -4, Y: 1172, W: 2024, H: 8, Axis: "h", Line: 1176},
		{X: -4, Y: -4, W: 8, H: 1184, Axis: "v", Line: 0},
		{X: 2012, Y: -4, W: 8, H: 1184, Axis: "v", Line: 2016},
	}}
	g.spatial = nil
	g.Tanks[0].X, g.Tanks[0].Y, g.Tanks[0].Angle = 42, 42, 0
	g.Tanks[1].X, g.Tanks[1].Y, g.Tanks[1].Invulnerable = 1008, 1008, 1000
	return machineSynergyArena{game: g, tank: g.Tanks[0]}
}

func (h machineSynergyArena) grant(kind string) {
	if h.game != nil {
		h.game.grantPower(h.tank, kind)
	} else {
		applyPower(h.tank, kind, infinitePowerDuration, infiniteStarDuration)
	}
}

func (h machineSynergyArena) fire() bool {
	if h.game != nil {
		h.game.Tick++
		return h.game.fire(h.tank)
	}
	h.arena.tick++
	before := h.tank.ShotSerial
	h.arena.fire(h.pilot)
	return h.tank.ShotSerial == before+1
}

func (h machineSynergyArena) shots() []machineSynergyShot {
	var shots []machineSynergyShot
	if h.game != nil {
		for _, b := range h.game.Bullets {
			if !b.Dead {
				shots = append(shots, machineSynergyShot{b.ID, b.Bounces, b.AmmoEpoch, math.Hypot(b.VX, b.VY), b.Life, b.R, b.boosted})
			}
		}
	} else {
		for _, b := range h.arena.bullets {
			if !b.dead {
				shots = append(shots, machineSynergyShot{b.ID, b.Bounces, b.AmmoEpoch, math.Hypot(b.VX, b.VY), b.Life, b.radius, b.boosted})
			}
		}
	}
	return shots
}

func (h machineSynergyArena) advance() {
	if h.game != nil {
		h.game.updateBullets(tickDT)
	} else {
		h.arena.advanceBullets()
	}
}

func (h machineSynergyArena) audible() int {
	n := 0
	if h.game != nil {
		for _, effect := range h.game.events {
			if effect.Type == "shot" && effect.Tick == h.game.Tick {
				n++
			}
		}
	} else {
		for _, effect := range h.arena.effects {
			if effect.Kind == "shot:rapid" && effect.Tick == h.arena.tick {
				n++
			}
		}
	}
	return n
}

func TestStarmanMachineGunDoublesSpeedAndRangeWithoutChangingCadenceOrRadius(t *testing.T) {
	for _, infinity := range []bool{false, true} {
		for _, order := range [][]string{{"rapid"}, {"rapid", "starman"}, {"starman", "rapid"}} {
			t.Run(fmt.Sprintf("infinity%v/%v", infinity, order), func(t *testing.T) {
				h := newMachineSynergyArena(infinity)
				for _, kind := range order {
					h.grant(kind)
				}
				star := len(order) == 2
				wantSpeed := machineSpeed
				if star {
					wantSpeed *= 2
				}
				audible, peak := 0, 0
				for frame := 0; frame < machineFiringRounds; frame++ {
					if !h.fire() {
						t.Fatalf("held stream skipped tick %d", frame)
					}
					audible += h.audible()
					shots := h.shots()
					latest := shots[len(shots)-1]
					if latest.speed != wantSpeed || latest.radius != machineRadius || latest.boosted != star {
						t.Fatal("combo changed its radius, failed to accelerate, or mislabeled its shot", latest)
					}
					if frame == 0 {
						wantPath := infiniteShotRange + 28 // Normal Infinity retains its post-muzzle allowance.
						if h.game != nil {
							wantPath = h.game.machineTravelRange()
						}
						if star {
							wantPath *= 2
						}
						if math.Abs(latest.speed*latest.life+28-wantPath) > 1e-9 {
							t.Fatal("boosted total range did not double including hidden muzzle travel")
						}
					}
					h.advance()
					peak = max(peak, len(h.shots()))
				}
				if h.tank.ShotSerial != machineFiringRounds || audible != machineFiringRounds/4 || peak > machineCapacity {
					t.Fatal("combo changed firing/cosmetic cadence or exceeded the existing live limit", h.tank.ShotSerial, audible, peak)
				}
				if star && (h.tank.MachineRounds != machineFiringRounds || h.tank.Power != "rapid") || !star && h.tank.Power != "" {
					t.Fatal("combo spent its frozen budget or changed ordinary weapon depletion")
				}
			})
		}
	}
}

func TestStarmanMachineGunTransitionsKeepFlyingRoundsAtTheirOriginalSpeed(t *testing.T) {
	for _, infinity := range []bool{false, true} {
		t.Run(fmt.Sprintf("infinity%v", infinity), func(t *testing.T) {
			h := newMachineSynergyArena(infinity)
			h.grant("rapid")
			if !h.fire() {
				t.Fatal("ordinary shot rejected")
			}
			ordinary := h.shots()[0]
			h.grant("starman")
			if !h.fire() {
				t.Fatal("boosted shot rejected")
			}
			boosted := h.shots()[1]
			if h.shots()[0] != ordinary || boosted.speed != machineSpeed*2 || ordinary.epoch == boosted.epoch {
				t.Fatal("pickup retuned an old shot or did not start the faster fresh magazine")
			}
			h.tank.StarmanTime = tickDT
			if h.game != nil {
				h.game.step(tickDT, [maxTanks]Input{}, testPlayers(2))
			} else {
				h.arena.step(time.Unix(1_800_000_000, 0))
			}
			if h.tank.StarmanTime != 0 || h.tank.Power != "rapid" || h.tank.MachineRounds != machineFiringRounds {
				t.Fatal("boost expiry did not restore a full ordinary machine gun")
			}
			if !h.fire() {
				t.Fatal("first unboosted shot after expiry was blocked")
			}
			shots := h.shots()
			if len(shots) != 3 || shots[0].id != ordinary.id || shots[0].speed != machineSpeed || shots[1].id != boosted.id || shots[1].speed != machineSpeed*2 || shots[2].speed != machineSpeed || shots[2].boosted {
				t.Fatal("expiry deleted/retuned old shots or kept new shots boosted", shots)
			}
			if math.Abs(shots[0].life-(ordinary.life-tickDT)) > 1e-9 || math.Abs(shots[1].life-(boosted.life-tickDT)) > 1e-9 || shots[2].epoch == boosted.epoch || h.tank.MachineRounds != machineFiringRounds-1 {
				t.Fatal("transition changed an existing lifetime or failed to consume fresh ordinary ammo")
			}
		})
	}
}

func TestStarmanMachineGunFasterRicochetsStillReachTheExactTankCircle(t *testing.T) {
	for _, infinity := range []bool{false, true} {
		for _, star := range []bool{false, true} {
			t.Run(fmt.Sprintf("infinity%v/star%v", infinity, star), func(t *testing.T) {
				h := newMachineSynergyArena(infinity)
				wall := Wall{X: 500, Y: -4, W: 8, H: 92, Axis: "v", Line: 504}
				if infinity {
					for _, candidate := range h.arena.maze.wallsNear(-500, -500, 500, 500) {
						if candidate.Axis == "v" {
							wall = candidate
							break
						}
					}
				} else {
					h.game.World.Walls = append(h.game.World.Walls, wall)
					h.game.spatial = nil
				}
				x, y := wall.X-38.5, wall.Y+wall.H/2-16
				tx, ty := wall.X-58.5, y+32
				angle := math.Atan2(ty-y, 2*(wall.X-machineRadius)-tx-x)
				var targetAlive func() bool
				if infinity {
					h.pilot.X, h.pilot.Y, h.pilot.Angle = x, y, angle
					q := h.arena.addPilot("Target", false, 0, 0, 0, 0)
					q.X, q.Y, q.Protected, q.kit.Invulnerable = tx, ty, false, 0
					targetAlive = func() bool { return q.HP > 0 }
				} else {
					h.tank.X, h.tank.Y, h.tank.Angle = x, y, angle
					q := h.game.Tanks[1]
					q.X, q.Y, q.Invulnerable = tx, ty, 0
					targetAlive = func() bool { return q.Alive }
				}
				h.grant("rapid")
				if star {
					h.grant("starman")
				}
				if !h.fire() {
					t.Fatal("ricochet shot rejected")
				}
				ticks := 0
				for targetAlive() && ticks < 8 {
					h.advance()
					ticks++
				}
				want := 4
				if star {
					want = 2
				}
				if targetAlive() || ticks != want {
					t.Fatal("faster swept ricochet missed, tunneled or changed its circle geometry", ticks, want)
				}
			})
		}
	}
}

func TestStarmanMachineGunHeldTriggerUsesOrdinarySpeedImmediatelyAfterExpiry(t *testing.T) {
	for _, infinity := range []bool{false, true} {
		t.Run(fmt.Sprintf("infinity%v", infinity), func(t *testing.T) {
			h := newMachineSynergyArena(infinity)
			h.grant("rapid")
			h.grant("starman")
			if !h.fire() {
				t.Fatal("boosted shot rejected")
			}
			h.tank.StarmanTime = tickDT
			if h.game != nil {
				h.game.step(tickDT, [maxTanks]Input{{Fire: true}}, testPlayers(2))
			} else {
				now := time.Unix(1_800_000_000, 0)
				h.arena.setInput(h.pilot, Input{Seq: 1, Fire: true}, false, now)
				h.arena.step(now)
			}
			shots := h.shots()
			if len(shots) != 2 || shots[0].speed != machineSpeed*2 || shots[1].speed != machineSpeed || shots[1].boosted || h.tank.ShotSerial != 2 || h.tank.MachineRounds != machineFiringRounds-1 {
				t.Fatal("expiry blocked the held trigger, retuned its old shot, or kept new shots boosted", shots)
			}
		})
	}
}

func TestStarmanMachineGunSynergyDoesNotRetuneBareStarOrShotgun(t *testing.T) {
	for _, infinity := range []bool{false, true} {
		for _, power := range []string{"", "scatter"} {
			t.Run(fmt.Sprintf("infinity%v/%s", infinity, power), func(t *testing.T) {
				h := newMachineSynergyArena(infinity)
				if power != "" {
					h.grant(power)
				}
				h.grant("starman")
				if !h.fire() {
					t.Fatal("unchanged Starman weapon rejected")
				}
				want := regularSpeed
				if power == "scatter" {
					want = shotgunSpeed
				}
				for _, shot := range h.shots() {
					if math.Abs(shot.speed-want) > 1e-9 || shot.radius != regularRadius {
						t.Fatal("the machine-gun synergy changed a different weapon", shot)
					}
				}
			})
		}
	}
}

func TestStarmanMachineGunBotLeadUsesTheBoostedSpeedOnlyForRapid(t *testing.T) {
	g := battle(2)
	p, q := g.Tanks[0], g.Tanks[1]
	p.X, p.Y, q.X, q.Y, q.VX, q.VY = 42, 42, 400, 42, 0, 40
	p.Power = "rapid"
	_, ordinary := g.botLead(p, q, tuneBot("godlike"))
	p.StarmanTime = 8
	_, boosted := g.botLead(p, q, tuneBot("godlike"))
	if math.Abs((ordinary-q.Y)/2-(boosted-q.Y)) > 1e-9 {
		t.Fatal("bot still led a doubled-speed shot using the ordinary flight time")
	}
	p.Power = "scatter"
	_, scatter := g.botLead(p, q, tuneBot("godlike"))
	if math.Abs(scatter-ordinary) > 1e-9 {
		t.Fatal("the machine-gun combo retuned another weapon's forecast")
	}
}

func TestStarmanMachineGunDoublesFullRangeForReflectedAndEmbeddedLaunches(t *testing.T) {
	for _, infinity := range []bool{false, true} {
		for _, geometry := range []string{"muzzle wall", "embedded", "deep embedded"} {
			if infinity && geometry == "deep embedded" {
				continue // Procedural Infinity walls are always eight units thick.
			}
			t.Run(fmt.Sprintf("infinity%v/%s", infinity, geometry), func(t *testing.T) {
				h := newMachineSynergyArena(infinity)
				wall := Wall{X: 500, Y: -4, W: 8, H: 92, Axis: "v", Line: 504}
				if infinity {
					a, p, q, w := wallLaunchInfinityArena()
					q.HP = 0
					h = machineSynergyArena{arena: a, pilot: p, tank: &p.kit}
					wall = w
				} else {
					if geometry == "deep embedded" {
						wall.W = 56
					}
					h.game.World.Walls = append(h.game.World.Walls, wall)
					h.game.spatial = nil
				}
				x, y := wall.X-12, wall.Y+wall.H/2
				if geometry != "muzzle wall" {
					x = wall.X + wall.W/2
				}
				if infinity {
					h.pilot.X, h.pilot.Y, h.pilot.Angle = x, y, 0
				} else {
					h.tank.X, h.tank.Y, h.tank.Angle = x, y, 0
				}
				// Match the launch geometry before and after Star, including Ghost's
				// projection out of an occupied wall rather than a fresh clear muzzle.
				h.grant("ghost")
				h.grant("rapid")
				var launch projectileLaunch
				if infinity {
					launch = h.arena.projectileLaunch(h.pilot, 0, machineRadius, 28)
				} else {
					launch = h.game.projectileLaunch(h.tank, 0, machineRadius, 28)
				}
				if !launch.valid || geometry != "muzzle wall" && launch.distance <= 0 || geometry == "deep embedded" && launch.distance <= 28 {
					t.Fatal("fixture did not exercise its hidden launch path", launch)
				}
				if !h.fire() || len(h.shots()) != 1 {
					t.Fatal("ordinary phased machine gun did not launch")
				}
				ordinary := h.shots()[0]
				h.grant("starman")
				if !h.fire() || len(h.shots()) != 2 {
					t.Fatal("boosted phased machine gun did not launch")
				}
				boosted := h.shots()[1]
				if h.shots()[0] != ordinary || ordinary.bounces == 0 || boosted.bounces == 0 {
					t.Fatal("pickup changed an old round or the fixture did not ricochet")
				}
				if infinity {
					hidden := launch.distance + launch.muzzle
					ordinaryFull := ordinary.speed*ordinary.life + hidden
					boostedFull := boosted.speed*boosted.life + hidden
					if math.Abs(boostedFull-2*ordinaryFull) > 1e-8 {
						t.Fatal("Infinity did not double its existing complete launch allowance", ordinaryFull, boostedFull)
					}
				} else {
					base := h.game.machineTravelRange()
					// Infer the exact charged wall/muzzle distance from the ordinary
					// shot; Star must spend the same path once, including wall nudges.
					hidden := base - ordinary.speed*ordinary.life
					if hidden <= 0 || math.Abs(boosted.speed*boosted.life+hidden-2*base) > 1e-8 {
						t.Fatal("fixed Star range doubled after cropping its hidden path", hidden, boosted)
					}
				}
			})
		}
	}
}

func TestStarmanMachineGunRicochetsConsumeTheOriginalTotalRange(t *testing.T) {
	for _, infinity := range []bool{false, true} {
		for _, star := range []bool{false, true} {
			t.Run(fmt.Sprintf("infinity%v/star%v", infinity, star), func(t *testing.T) {
				h := newMachineSynergyArena(infinity)
				if infinity {
					h.pilot.Angle = math.Pi / 2
				} else {
					h.tank.Angle = math.Pi / 2
				}
				h.grant("rapid")
				if star {
					h.grant("starman")
				}
				if !h.fire() || len(h.shots()) != 1 {
					t.Fatal("range shot did not launch")
				}
				birth := h.shots()[0]
				var fixed *Bullet
				if !infinity {
					fixed = h.game.Bullets[0]
				}
				bounces := birth.bounces
				frames := 0
				for len(h.shots()) > 0 && frames < 240 {
					h.advance()
					frames++
					if shots := h.shots(); len(shots) > 0 {
						bounces = max(bounces, shots[0].bounces)
					}
				}
				if len(h.shots()) != 0 || bounces == 0 || frames != int(math.Ceil(birth.life/tickDT-1e-9)) {
					t.Fatal("ricochet reset or prematurely exhausted the travel budget", frames, birth.life, bounces)
				}
				elapsed := 0.0
				if fixed != nil {
					elapsed = fixed.Age
				} else {
					for _, effect := range h.arena.effects {
						if f := effect.Flight; f != nil && f.ID == birth.id {
							elapsed = (f.EndTick - f.StartTick) * tickDT
						}
					}
				}
				if math.Abs(elapsed-birth.life) > 1e-8 {
					t.Fatal("terminal flight did not retain the complete bounded ricochet path", elapsed, birth.life)
				}
			})
		}
	}
}

func TestStarmanMachineGunBotsUseTheDoubledRange(t *testing.T) {
	h := newMachineSynergyArena(false)
	g, p, q := h.game, h.tank, h.game.Tanks[1]
	q.X, q.Y, q.Invulnerable = 1900, 42, 0
	h.grant("rapid")
	if g.botShot(p, q, 0, q.X, q.Y, 0) || g.godlikeSafeShot(p, q, 0) {
		t.Fatal("ordinary machine gun unexpectedly reached beyond its range")
	}
	h.grant("starman")
	if !g.botShot(p, q, 0, q.X, q.Y, 0) || !g.godlikeSafeShot(p, q, 0) {
		t.Fatal("bot forecasts discarded the newly reachable boosted target")
	}
}
