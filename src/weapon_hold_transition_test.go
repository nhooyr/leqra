package main

import (
	"fmt"
	"testing"
	"time"
)

var finiteHoldWeapons = []string{"rapid", "scatter", "homing", "grenade", "laser", "cannon"}

func assertNoStandardShot(t *testing.T, events []Event) {
	t.Helper()
	for _, event := range events {
		if event.Type == "shot" && event.Text == "" {
			t.Fatal("consumed finite-weapon hold emitted a standard shot/sound")
		}
	}
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
					if tank.Power != "" || tank.ShotSerial != 1 || !tank.fireBlocked || pending() {
						t.Fatal("final finite shot did not consume the first input edge")
					}
					if kind == "grenade" && tank.GrenadeEpoch == nil {
						t.Fatal("last grenade lost its pending detonation bank")
					}
					// Both edges arrive before the next simulation sample. The optional
					// final release also covers a complete tap between samples.
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
						wantSerial = 1 // The next press pops the last grenade before standard fire.
					}
					if tank.ShotSerial != wantSerial || kind != "grenade" && tank.Cooldown <= 0 || kind == "grenade" && (tank.Cooldown != 0 || tank.GrenadeEpoch != nil) || pending() {
						t.Fatal("coalesced press did not fire exactly one ready standard shot")
					}
					now = now.Add(time.Second / 60)
					step()
					if tank.ShotSerial != wantSerial || pending() {
						t.Fatal("consumed edge replayed on the next simulation sample")
					}
					if kind == "grenade" {
						send(5, false)
						send(6, true)
						now = now.Add(time.Second / 60)
						step()
						if tank.ShotSerial != 2 || tank.Cooldown <= 0 || pending() {
							t.Fatal("fresh press after the final pop did not fire standard ammo")
						}
					}
				})
			}
		}
	}
}

func TestEveryFiniteWeaponEndConsumesHeldFire(t *testing.T) {
	for _, kind := range finiteHoldWeapons {
		for _, timer := range []bool{false, true} {
			for _, infinity := range []bool{false, true} {
				for _, coalesced := range []bool{false, true} {
					t.Run(fmt.Sprintf("%s/timer=%v/infinity=%v/coalesced=%v", kind, timer, infinity, coalesced), func(t *testing.T) {
						if infinity {
							a := newSeededInfiniteArena(512)
							p := a.addPilot("Pilot", false, 0, 0, 0, 0)
							p.X, p.Y, p.Angle = 42, 42, 0
							p.kit = Tank{}
							applyPower(&p.kit, kind, 15, 8)
							epoch := p.kit.AmmoEpoch
							if timer {
								p.kit.fireHeld = true
								p.kit.PowerTime = tickDT / 2
								a.advanceEquipment(p)
							} else {
								p.kit.Charges, p.kit.MachineRounds = 1, 1
								a.weaponControl(p, true, true)
							}
							if p.kit.Power != "" || p.kit.MachineRounds != 0 || p.kit.Charges != 0 || p.kit.Cooldown != 0 || p.kit.CooldownTotal != 0 || p.kit.AmmoEpoch != epoch+1 || !p.kit.fireBlocked {
								t.Fatal("weapon end did not provide fresh standard ammo with consumed hold", p.kit.Power, p.kit.fireBlocked)
							}
							serial, shots := p.kit.ShotSerial, len(a.bullets)
							for range 10 {
								a.weaponControl(p, true, false)
							}
							applyPower(&p.kit, "shield", 15, 8)
							p.kit.Shield = tickDT / 2
							a.advanceEquipment(p)
							a.weaponControl(p, true, false)
							if p.kit.ShotSerial != serial || len(a.bullets) != shots || p.kit.Cooldown != 0 || !p.kit.fireBlocked {
								t.Fatal("held Fire leaked a standard shot after end/refill")
							}
							for _, effect := range a.effects {
								if effect.Kind == "shot:" {
									t.Fatal("held finite weapon emitted standard shot sound")
								}
							}
							if !coalesced {
								a.weaponControl(p, false, false)
							}
							a.weaponControl(p, true, true)
							if p.kit.ShotSerial != serial+1 || len(a.bullets) != shots+1 || a.bullets[len(a.bullets)-1].Kind != "" {
								t.Fatal("new standard press did not fire exactly once")
							}
							if !timer && kind != "laser" {
								for _, b := range a.bullets[:shots] {
									if b.dead || b.AmmoEpoch == p.kit.AmmoEpoch {
										t.Fatal("transition retired or retagged final finite shot")
									}
								}
							}
						} else {
							g := battle(2)
							p := g.Tanks[0]
							g.Tanks[1].Alive = false
							g.grantPower(p, kind)
							epoch := p.AmmoEpoch
							if timer {
								p.fireHeld = true
								p.PowerTime = tickDT / 2
								g.step(tickDT, [maxTanks]Input{{Fire: true}}, testPlayers(2))
							} else {
								p.Charges, p.MachineRounds = 1, 1
								g.weaponControl(p, true, true)
							}
							if p.Power != "" || p.MachineRounds != 0 || p.Charges != 0 || p.Cooldown != 0 || p.CooldownTotal != 0 || p.AmmoEpoch != epoch+1 || !p.fireBlocked {
								t.Fatal("weapon end did not provide fresh standard ammo with consumed hold", p.Power, p.fireBlocked)
							}
							serial, shots := p.ShotSerial, len(g.Bullets)
							for range 10 {
								g.weaponControl(p, true, false)
							}
							g.grantPower(p, "shield")
							p.Shield = tickDT / 2
							g.step(tickDT, [maxTanks]Input{{Fire: true}}, testPlayers(2))
							if p.ShotSerial != serial || len(g.Bullets) != shots || p.Cooldown != 0 || !p.fireBlocked {
								t.Fatal("held Fire leaked a standard shot after end/refill")
							}
							assertNoStandardShot(t, g.events)
							if !coalesced {
								g.weaponControl(p, false, false)
							}
							g.weaponControl(p, true, true)
							if p.ShotSerial != serial+1 || len(g.Bullets) != shots+1 || g.Bullets[len(g.Bullets)-1].Kind != "" {
								t.Fatal("new standard press did not fire exactly once")
							}
							if !timer && kind != "laser" {
								for _, b := range g.Bullets[:shots] {
									if b.Dead || b.AmmoEpoch == p.AmmoEpoch {
										t.Fatal("transition retired or retagged final finite shot")
									}
								}
							}
						}
					})
				}
			}
		}
	}
}

func TestPassiveExpiryPreservesSameWeaponHeldFire(t *testing.T) {
	for _, kind := range finiteHoldWeapons {
		for _, buff := range []string{"shield", "speed", "ghost", "starman"} {
			for _, infinity := range []bool{false, true} {
				t.Run(fmt.Sprintf("%s/%s/infinity=%v", kind, buff, infinity), func(t *testing.T) {
					expire := func(tank *Tank) {
						switch buff {
						case "shield":
							tank.Shield = tickDT / 2
						case "speed":
							tank.SpeedTime = tickDT / 2
						case "ghost":
							tank.GhostTime = tickDT / 2
						case "starman":
							tank.StarmanTime = tickDT / 2
						}
					}
					if infinity {
						a := newSeededInfiniteArena(512)
						p := a.addPilot("Pilot", false, 0, 0, 0, 0)
						p.X, p.Y, p.Angle = 42, 42, 0
						p.kit = Tank{}
						applyPower(&p.kit, kind, 15, 8)
						a.weaponControl(p, true, true)
						applyPower(&p.kit, buff, 15, 8)
						expire(&p.kit)
						serial := p.kit.ShotSerial
						a.advanceEquipment(p)
						a.weaponControl(p, true, false)
						if p.kit.Power != kind {
							t.Fatal("passive expiry changed selected weapon")
						}
						if kind == "grenade" {
							if p.kit.ShotSerial != serial || !p.kit.fireBlocked {
								t.Fatal("passive expiry restarted held grenade action")
							}
						} else if p.kit.ShotSerial != serial+1 || p.kit.fireBlocked {
							t.Fatal("passive expiry interrupted normal same-weapon held fire")
						}
					} else {
						g := battle(2)
						p := g.Tanks[0]
						g.Tanks[1].Alive = false
						g.grantPower(p, kind)
						g.weaponControl(p, true, true)
						g.grantPower(p, buff)
						expire(p)
						serial := p.ShotSerial
						g.step(tickDT, [maxTanks]Input{{Fire: true}}, testPlayers(2))
						if p.Power != kind {
							t.Fatal("passive expiry changed selected weapon")
						}
						if kind == "grenade" {
							if p.ShotSerial != serial || !p.fireBlocked {
								t.Fatal("passive expiry restarted held grenade action")
							}
						} else if p.ShotSerial != serial+1 || p.fireBlocked {
							t.Fatal("passive expiry interrupted normal same-weapon held fire")
						}
					}
				})
			}
		}
	}
}

func TestFreshPressAtWeaponExpiryIsNotMistakenForOldHold(t *testing.T) {
	for _, kind := range finiteHoldWeapons {
		for _, previousHeld := range []bool{false, true} {
			g := battle(2)
			p := g.Tanks[0]
			g.Tanks[1].Alive = false
			g.grantPower(p, kind)
			p.PowerTime = tickDT / 2
			p.fireHeld = previousHeld
			g.step(tickDT, [maxTanks]Input{{Fire: true, FirePressed: true}}, testPlayers(2))
			if p.Power != "" || p.ShotSerial != 1 || len(g.Bullets) != 1 || g.Bullets[0].Kind != "" {
				t.Fatal("fresh press at expiry was suppressed", kind, previousHeld)
			}
			a := newSeededInfiniteArena(512)
			q := a.addPilot("Pilot", false, 0, 0, 0, 0)
			q.X, q.Y, q.Angle = 42, 42, 0
			q.kit = Tank{}
			applyPower(&q.kit, kind, 15, 8)
			q.kit.PowerTime = tickDT / 2
			q.kit.fireHeld = previousHeld
			a.advanceEquipment(q)
			a.weaponControl(q, true, true)
			if q.kit.Power != "" || q.kit.ShotSerial != 1 || len(a.bullets) != 1 || a.bullets[0].Kind != "" {
				t.Fatal("Infinity fresh press at expiry was suppressed", kind, previousHeld)
			}
		}
	}
}
