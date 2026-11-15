package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"testing"
	"time"
)

func TestEveryGrenadeIncludingLastChargeKeepsItsNextDetonationPress(t *testing.T) {
	for _, epoch := range []uint64{0, 7, maxAmmoEpoch} {
		for _, coalesced := range []bool{false, true} {
			for _, infinity := range []bool{false, true} {
				t.Run(fmt.Sprintf("epoch%d/coalesced%v/infinity%v", epoch, coalesced, infinity), func(t *testing.T) {
					g, tank := grenadeGame()
					g.Tanks[1].Alive = false
					a := newSeededInfiniteArena(631)
					c := partySnapshotClient()
					pilot := a.join(c, "Pilot", time.Unix(0, 0))
					pilot.X, pilot.Y, pilot.Angle, pilot.Protected = 42, 42, 0, false
					applyPower(&pilot.kit, "grenade", 15, 8)
					pilot.kit.Invulnerable, pilot.kit.SpawnProtected = 0, false
					if infinity {
						tank = &pilot.kit
					}
					tank.AmmoEpoch = epoch
					control := func(held, pressed bool) {
						if infinity {
							a.weaponControl(pilot, held, pressed)
						} else {
							g.weaponControl(tank, held, pressed)
						}
					}
					for throw := 1; throw <= 3; throw++ {
						tank.Cooldown = 0
						control(true, true)
						if tank.ShotSerial != uint64(throw) || tank.Charges != 3-throw {
							t.Fatal("fresh throw did not spend exactly one grenade")
						}
						if throw == 3 {
							wantEpoch := epoch + 1
							if epoch == maxAmmoEpoch {
								wantEpoch = 1
							}
							if tank.Power != "" || tank.Cooldown != 0 || tank.AmmoEpoch != wantEpoch || tank.GrenadeEpoch == nil || *tank.GrenadeEpoch != epoch {
								t.Fatal("last throw lost its control bank or full ready standard ammo")
							}
							wire, err := json.Marshal(tank)
							if err != nil || !bytes.Contains(wire, []byte(fmt.Sprintf(`"grenadeEpoch":%d`, epoch))) {
								t.Fatal("fixed snapshot omitted the retained bank, including epoch zero")
							}
							if infinity {
								a.bullets[len(a.bullets)-1].X = pilot.X + 2*infiniteSight
								a.broadcast()
								packet := readPartySnapshot(t, c)
								if len(packet.Tanks) != 1 || packet.Tanks[0].GrenadeEpoch == nil || *packet.Tanks[0].GrenadeEpoch != epoch || packet.Tanks[0].AmmoUsed != 0 || packet.Tanks[0].Grenades != 1 || packet.Tanks[0].GrenadeLife != grenadeFuse {
									t.Fatal("offscreen final grenade lost remote HUD control or occupied fresh standard ammo", packet.Tanks, packet.Bullets)
								}
							}
						}
						for range 8 {
							control(true, false)
						}
						if !coalesced {
							control(false, false)
						}
						control(true, true)
						if tank.ShotSerial != uint64(throw) || !tank.fireBlocked || tank.GrenadeEpoch != nil {
							t.Fatal("detonation also fired, left the control bank armed, or did not consume its hold")
						}
						if infinity {
							if len(a.bullets) != throw || !a.bullets[throw-1].dead || a.bullets[throw-1].AmmoEpoch != epoch {
								t.Fatal("detonation spawned another projectile or retagged the grenade")
							}
						} else if len(g.Bullets) != throw || !g.Bullets[throw-1].Dead || g.Bullets[throw-1].AmmoEpoch != epoch {
							t.Fatal("detonation spawned another projectile or retagged the grenade")
						}
						for range 8 {
							control(true, false)
						}
						if tank.ShotSerial != uint64(throw) {
							t.Fatal("held detonation fell through to standard fire")
						}
						control(false, false)
					}
					control(true, true)
					if tank.ShotSerial != 4 || tank.Power != "" {
						t.Fatal("the press after the final detonation did not fire standard ammo")
					}
				})
			}
		}
	}
}

func TestGenuineRefillsAndDeathReleaseFinalGrenadeControlWithoutRemovingItsFuse(t *testing.T) {
	for _, kind := range pickupTypes {
		for _, infinity := range []bool{false, true} {
			t.Run(fmt.Sprintf("pickup%s/infinity%v", kind, infinity), func(t *testing.T) {
				if infinity {
					a := newSeededInfiniteArena(631)
					p := a.addPilot("Pilot", false, 0, 0, 0, 0)
					p.X, p.Y, p.Angle = 42, 42, 0
					p.kit.Invulnerable, p.kit.SpawnProtected, p.Protected = 0, false, false
					applyPower(&p.kit, "grenade", 15, 8)
					p.kit.Charges = 1
					a.weaponControl(p, true, true)
					old := a.bullets[0]
					applyPower(&p.kit, kind, 15, 8)
					a.weaponControl(p, true, true)
					if p.kit.GrenadeEpoch != nil || a.bullets[0].dead || a.bullets[0].AmmoEpoch != old.AmmoEpoch || a.bullets[0].Life != old.Life || p.kit.ShotSerial != 2 {
						t.Fatal("new pickup reused the retired bank, erased its natural fuse, or blocked fresh firing")
					}
				} else {
					g, p := grenadeGame()
					g.Tanks[1].Alive = false
					p.Charges = 1
					g.weaponControl(p, true, true)
					old := g.Bullets[0]
					epoch, life := old.AmmoEpoch, old.Life
					g.grantPower(p, kind)
					g.weaponControl(p, true, true)
					if p.GrenadeEpoch != nil || old.Dead || old.AmmoEpoch != epoch || old.Life != life || p.ShotSerial != 2 {
						t.Fatal("new pickup reused the retired bank, erased its natural fuse, or blocked fresh firing")
					}
				}
			})
		}
	}
	for _, infinity := range []bool{false, true} {
		t.Run(fmt.Sprintf("death/infinity%v", infinity), func(t *testing.T) {
			if infinity {
				a := newSeededInfiniteArena(631)
				p := a.addPilot("Pilot", false, 0, 0, 0, 0)
				p.X, p.Y, p.Angle = 42, 42, 0
				p.kit.Invulnerable, p.kit.SpawnProtected, p.Protected = 0, false, false
				applyPower(&p.kit, "grenade", 15, 8)
				p.kit.Charges = 1
				a.weaponControl(p, true, true)
				a.eliminatePilot(p, 100, 0, "Enemy")
				if p.kit.GrenadeEpoch != nil || a.bullets[0].dead || a.bullets[0].Life != grenadeFuse {
					t.Fatal("death retained remote control or removed the grenade's natural fuse")
				}
			} else {
				g, p := grenadeGame()
				p.Charges = 1
				g.weaponControl(p, true, true)
				g.eliminateTank(p, 1)
				if p.GrenadeEpoch != nil || g.Bullets[0].Dead || g.Bullets[0].Life != grenadeFuse {
					t.Fatal("death retained remote control or removed the grenade's natural fuse")
				}
			}
		})
	}
}
