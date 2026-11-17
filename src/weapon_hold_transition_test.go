package main

import (
	"fmt"
	"testing"
	"time"
)

var finiteHoldWeapons = []string{"rapid", "scatter", "homing", "grenade", "laser", "cannon"}

func (h machineSynergyArena) stepHeld(held, pressed bool) {
	if h.game != nil {
		h.game.step(tickDT, [maxTanks]Input{{Fire: held, FirePressed: pressed}}, testPlayers(2))
		return
	}
	now := time.Unix(1_800_000_000, 0).Add(time.Duration(h.arena.tick) * time.Second / 60)
	h.pilot.input, h.pilot.inputAt, h.pilot.firePending = Input{Fire: held}, now, pressed
	h.arena.step(now)
}

func TestEveryFiniteWeaponAcceptsFireEdgesBetweenTicks(t *testing.T) {
	for _, kind := range finiteHoldWeapons {
		for _, infinity := range []bool{false, true} {
			for _, released := range []bool{false, true} {
				t.Run(fmt.Sprintf("%s/infinity=%v/released=%v", kind, infinity, released), func(t *testing.T) {
					now := time.Now()
					var tank *Tank
					var send func(uint64, bool)
					var step func()
					var pending func() bool
					if infinity {
						a := newSeededInfiniteArena(513)
						client := fakeClient()
						p := a.join(client, "Pilot", now)
						a.nextBot, a.nextPickup = 1<<60, 1<<60
						p.X, p.Y, p.Angle, p.Protected = 42, 42, 0, false
						p.kit = Tank{}
						tank = &p.kit
						applyPower(tank, kind, 15, 8)
						send = func(seq uint64, held bool) {
							a.setConnectionInput(client, p, p, Input{Seq: seq, Fire: held}, false, now)
						}
						step = func() { a.step(now) }
						pending = func() bool { return p.firePending }
					} else {
						h, room, clients := preparedRoom(t, 2)
						tank = room.Game.Tanks[0]
						tank.Y, room.Game.Tanks[1].Y = 70, 350
						room.Game.grantPower(tank, kind)
						send = func(seq uint64, held bool) {
							action(t, h, clients[0], map[string]any{"type": "input", "seq": seq, "fire": held})
						}
						step = func() { h.tick(now) }
						pending = func() bool { return clients[0].player.FirePending }
					}
					tank.Charges, tank.MachineRounds = 1, 1
					send(1, true)
					step()
					if tank.Power != "" || tank.ShotSerial != 1 || pending() {
						t.Fatal("final finite shot did not consume exactly one input edge")
					}
					if kind == "grenade" && tank.GrenadeEpoch == nil {
						t.Fatal("last grenade lost its pending detonation bank")
					}
					send(2, false)
					send(3, true)
					if released {
						send(4, false)
					}
					if !pending() {
						t.Fatal("coalesced fresh Fire edge was dropped")
					}
					now = now.Add(time.Second / 60)
					step()
					wantSerial := uint64(2)
					if kind == "grenade" {
						wantSerial = 1
					}
					if tank.ShotSerial != wantSerial || pending() {
						t.Fatal("coalesced press did not perform exactly one shot or grenade pop")
					}
					now = now.Add(time.Second / 60)
					step()

					if tank.ShotSerial != wantSerial || pending() {
						t.Fatal("held fire failed to continue, or a released edge replayed")
					}
				})
			}
		}
	}
}

func TestEveryFiniteWeaponEndKeepsTryingWhileHeld(t *testing.T) {
	for _, kind := range finiteHoldWeapons {
		for _, timer := range []bool{false, true} {
			for _, infinity := range []bool{false, true} {
				t.Run(fmt.Sprintf("%s/timer=%v/infinity=%v", kind, timer, infinity), func(t *testing.T) {
					h := newMachineSynergyArena(infinity)
					h.grant(kind)
					epoch := h.tank.AmmoEpoch
					h.tank.fireHeld = true
					if timer {
						h.tank.PowerTime = tickDT / 2
					} else {
						h.tank.Charges, h.tank.MachineRounds = 1, 1
					}
					h.stepHeld(true, !timer)
					if h.tank.Power != "" || h.tank.AmmoEpoch != epoch+1 || h.tank.ShotSerial != 1 {
						t.Fatal("weapon end did not produce one action with fresh standard ammo")
					}
					if !timer {
						for _, shot := range h.shots() {
							if shot.epoch != epoch {
								t.Fatal("depletion fired a second standard projectile in the same tick")
							}
						}
						h.stepHeld(true, false)
						if h.tank.ShotSerial != 2 {
							t.Fatal("held fire did not use standard ammo on the following tick")
						}
					}
					serial := h.tank.ShotSerial
					for range 21 {
						h.stepHeld(true, false)
					}
					if h.tank.ShotSerial != serial+1 {
						t.Fatal("held fire did not keep retrying through ordinary reload")
					}
				})
			}
		}
	}
}

func TestEveryPickupKeepsHeldFireAndRetiresOldCapacity(t *testing.T) {
	for _, current := range append([]string{""}, finiteHoldWeapons...) {
		for _, pickup := range pickupTypes {
			for _, infinity := range []bool{false, true} {
				t.Run(fmt.Sprintf("%s/%s/infinity=%v", current, pickup, infinity), func(t *testing.T) {
					h := newMachineSynergyArena(infinity)
					if current != "" {
						h.grant(current)
					}
					h.tank.Cooldown = .5
					h.tank.fireHeld, h.tank.fireBlocked = true, true
					epoch := h.tank.AmmoEpoch
					if infinity {
						for id := range capacity(h.tank) {
							h.arena.bullets = append(h.arena.bullets, infiniteBullet{ID: 1000 + id, Owner: h.pilot.ID, AmmoEpoch: epoch, X: 1008, Y: 1008, Life: 10, radius: regularRadius})
						}
					} else {
						for id := range capacity(h.tank) {
							h.game.Bullets = append(h.game.Bullets, &Bullet{ID: 1000 + id, Owner: h.tank.ID, AmmoEpoch: epoch, X: 1008, Y: 1008, Life: 10, R: regularRadius})
						}
					}
					h.stepHeld(true, false)
					if h.tank.ShotSerial != 0 {
						t.Fatal("fixture did not begin with a denied held attempt")
					}
					h.grant(pickup)
					h.stepHeld(true, false)
					if h.tank.ShotSerial != 1 || h.tank.AmmoEpoch != epoch+1 || !h.tank.fireHeld {
						t.Fatal("pickup required release, lost the hold or failed to retire old capacity")
					}
					for _, shot := range h.shots() {
						if shot.id >= 1000 && shot.id < 1000+capacity(&Tank{Power: current}) && shot.epoch != epoch {
							t.Fatal("fresh held fire retagged a pre-pickup projectile")
						}
					}
				})
			}
		}
	}
}

func TestPassiveExpiryPreservesSameWeaponHeldFire(t *testing.T) {
	for _, kind := range finiteHoldWeapons {
		for _, buff := range []string{"shield", "speed", "ghost", "starman"} {
			for _, infinity := range []bool{false, true} {
				t.Run(fmt.Sprintf("%s/%s/infinity=%v", kind, buff, infinity), func(t *testing.T) {
					h := newMachineSynergyArena(infinity)
					h.grant(kind)
					h.stepHeld(true, true)
					h.grant(buff)
					switch buff {
					case "shield":
						h.tank.Shield = tickDT / 2
					case "speed":
						h.tank.SpeedTime = tickDT / 2
					case "ghost":
						h.tank.GhostTime = tickDT / 2
					case "starman":
						h.tank.StarmanTime = tickDT / 2
					}
					serial := h.tank.ShotSerial
					h.stepHeld(true, false)
					if h.tank.Power != kind || h.tank.ShotSerial != serial+1 {
						t.Fatal("passive expiry interrupted held fire or changed the selected weapon")
					}
				})
			}
		}
	}
}

func TestGrenadesAutoThrowWhileHeldAndDetonationRequiresRelease(t *testing.T) {
	for _, infinity := range []bool{false, true} {
		for _, pop := range []bool{false, true} {
			t.Run(fmt.Sprintf("infinity%v/pop%v", infinity, pop), func(t *testing.T) {
				h := newMachineSynergyArena(infinity)
				h.grant("grenade")
				for tick := 1; tick <= 97; tick++ {
					h.stepHeld(true, tick == 1)
					want := uint64(1 + (tick-1)/48)
					if h.tank.ShotSerial != want {
						t.Fatal("grenade hold did not obey its 48-tick reload", tick, h.tank.ShotSerial, want)
					}
				}
				if h.tank.Power != "" || len(h.shots()) != 3 || h.tank.GrenadeEpoch == nil {
					t.Fatal("last automatic throw fired an ordinary projectile in the same tick")
				}
				h.stepHeld(true, pop)
				if pop {
					if h.tank.ShotSerial != 3 || len(h.shots()) != 0 || h.tank.GrenadeEpoch != nil {
						t.Fatal("fresh press did not exclusively pop the final grenade bank")
					}
					h.stepHeld(true, false)
				}
				if pop {
					if h.tank.ShotSerial != 3 {
						t.Fatal("detonation hold fired again")
					}
					h.stepHeld(false, false)
					h.stepHeld(true, true)
				}
				if h.tank.ShotSerial != 4 {
					t.Fatal("ordinary ammo did not resume after release")
				}
			})
		}
	}
}

func TestStarmanGrenadeHoldRetainsItsOneThrowPerTickBoost(t *testing.T) {
	for _, infinity := range []bool{false, true} {
		for _, count := range []int{4, 49, machineCapacity} {
			t.Run(fmt.Sprintf("infinity%v/count%d", infinity, count), func(t *testing.T) {
				h := newMachineSynergyArena(infinity)
				h.grant("grenade")
				h.grant("starman")
				for tick := 1; tick <= count; tick++ {
					h.stepHeld(true, tick == 1)
					if h.tank.ShotSerial != uint64(tick) || h.tank.Charges != 3 {
						t.Fatal("boosted grenade hold skipped or doubled a simulation tick")
					}
				}
				h.stepHeld(true, true)
				if h.tank.ShotSerial != uint64(count) || len(h.shots()) != 0 {
					t.Fatal("boosted pop also threw another grenade")
				}
				h.stepHeld(true, false)
				if h.tank.ShotSerial != uint64(count) {
					t.Fatal("boosted pop hold fired again")
				}
				h.stepHeld(false, false)
				h.stepHeld(true, true)
				if h.tank.ShotSerial != uint64(count+1) || len(h.shots()) != 1 {
					t.Fatal("boosted hold did not resume after the pop tick")
				}
			})
		}
	}
}

func TestHeldFireRetriesWhenReloadOrActiveCapacityBecomesReady(t *testing.T) {
	for _, infinity := range []bool{false, true} {
		for _, capacityBound := range []bool{false, true} {
			t.Run(fmt.Sprintf("infinity%v/capacity%v", infinity, capacityBound), func(t *testing.T) {
				h := newMachineSynergyArena(infinity)
				if capacityBound {
					if infinity {
						for id := range 5 {
							h.arena.bullets = append(h.arena.bullets, infiniteBullet{ID: 1000 + id, Owner: h.pilot.ID, X: 1008, Y: 1008, Life: tickDT / 2, radius: regularRadius})
						}
					} else {
						for id := range 5 {
							h.game.Bullets = append(h.game.Bullets, &Bullet{ID: 1000 + id, Owner: h.tank.ID, X: 1008, Y: 1008, Life: tickDT / 2, R: regularRadius})
						}
					}
				} else {
					h.tank.Cooldown = 2 * tickDT
				}
				h.stepHeld(true, true)
				if h.tank.ShotSerial != 0 {
					t.Fatal("initial denied fire attempt unexpectedly succeeded")
				}
				h.stepHeld(true, false)
				if h.tank.ShotSerial != 1 {
					t.Fatal("held trigger needed a new press after readiness returned")
				}
			})
		}
	}
}

func TestFreshPressAtWeaponExpiryIsNotMistakenForOldHold(t *testing.T) {
	for _, kind := range finiteHoldWeapons {
		for _, infinity := range []bool{false, true} {
			h := newMachineSynergyArena(infinity)
			h.grant(kind)
			h.tank.PowerTime, h.tank.fireHeld = tickDT/2, true
			h.stepHeld(true, true)
			if h.tank.Power != "" || h.tank.ShotSerial != 1 || len(h.shots()) != 1 {
				t.Fatal("fresh press at expiry was suppressed or doubled", kind, infinity)
			}
		}
	}
}
