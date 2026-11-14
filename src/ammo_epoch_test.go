package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"testing"
	"time"
)

func assertFullReadyAmmo(t *testing.T, tank *Tank, epoch uint64) {
	t.Helper()
	if tank.AmmoEpoch != epoch || tank.Cooldown != 0 || tank.CooldownTotal != 0 || tank.fireBlocked {
		t.Fatalf("magazine is not fresh/ready: epoch%d want%d power%s cooldown%v/%v blocked%v", tank.AmmoEpoch, epoch, tank.Power, tank.Cooldown, tank.CooldownTotal, tank.fireBlocked)
	}
	want := 0
	switch tank.Power {
	case "scatter":
		want = 5
	case "homing", "grenade", "laser", "cannon":
		want = 3
	}
	if tank.Charges != want || tank.Power == "rapid" && tank.MachineRounds != machineFiringRounds || tank.Power != "rapid" && tank.MachineRounds != 0 {
		t.Fatal("selected weapon did not refill", tank.Power, tank.Charges, tank.MachineRounds)
	}
}

func TestEveryPickupRefillsSelectedAmmoWithoutRemovingLiveShots(t *testing.T) {
	for _, current := range []string{"", "rapid", "scatter", "homing", "grenade", "laser", "cannon"} {
		for _, pickup := range pickupTypes {
			t.Run(current+"/"+pickup, func(t *testing.T) {
				g := battle(2)
				p := g.Tanks[0]
				g.Tanks[1].Alive = false
				if current != "" {
					g.grantPower(p, current)
				}
				p.MachineRounds, p.Charges, p.Cooldown, p.CooldownTotal, p.fireBlocked = 1, 1, .4, .7, true
				p.fireHeld = true
				epoch := p.AmmoEpoch
				old := &Bullet{ID: 100, Owner: p.ID, AmmoEpoch: epoch, Kind: "cannon", Life: 5, X: 300, Y: 300, R: cannonRadius}
				g.Bullets = []*Bullet{old}
				g.grantPower(p, pickup)
				assertFullReadyAmmo(t, p, epoch+1)
				if !p.fireHeld || old.Dead || len(g.Bullets) != 1 || g.Bullets[0] != old {
					t.Fatal("refill changed held input or removed an old shot")
				}
				if !g.fire(p) {
					t.Fatal("fresh magazine could not fire immediately", pickup)
				}
				if old.Dead {
					t.Fatal("firing fresh magazine recycled an old shot")
				}
			})
		}
	}
	for _, pickup := range pickupTypes {
		t.Run("infinity/"+pickup, func(t *testing.T) {
			a := newSeededInfiniteArena(503)
			p := a.addPilot("Pilot", false, 0, 0, 0, 0)
			p.X, p.Y, p.Angle = 42, 42, 0
			p.kit.Invulnerable, p.kit.SpawnProtected = 0, false
			applyPower(&p.kit, "rapid", 15, 8)
			p.kit.Cooldown, p.kit.CooldownTotal, p.kit.MachineRounds, p.kit.fireBlocked = .5, .7, 1, true
			epoch := p.kit.AmmoEpoch
			a.bullets = []infiniteBullet{{ID: 100, Owner: p.ID, AmmoEpoch: epoch, Kind: "cannon", Life: 5, X: 300, Y: 300, radius: cannonRadius}}
			a.pickups = []Pickup{{Type: pickup, X: p.X, Y: p.Y, Life: 30}}
			a.collectPickup(p)
			assertFullReadyAmmo(t, &p.kit, epoch+1)
			serial := p.kit.ShotSerial
			a.fire(p)
			if p.kit.ShotSerial != serial+1 || a.bullets[0].dead || a.bullets[0].AmmoEpoch != epoch {
				t.Fatal("Infinity fresh fire lost its prior live shell", pickup)
			}
		})
	}
}

func expireAmmoFixture(tank *Tank, kind string) {
	tank.Power, tank.PowerTime, tank.Charges, tank.MachineRounds = "rapid", 5, 1, 1
	tank.Cooldown, tank.CooldownTotal = .5, .8
	switch kind {
	case "shield":
		tank.Shield, tank.ShieldCharges = tickDT/2, 1
	case "speed":
		tank.SpeedTime, tank.SpeedStacks = tickDT/2, 2
	case "ghost":
		tank.GhostTime = tickDT / 2
	case "starman":
		tank.StarmanTime = tickDT / 2
	default:
		tank.Power, tank.PowerTime = kind, tickDT/2
	}
}

func TestEveryPowerEndRefillsOnceAndKeepsImmediateFire(t *testing.T) {
	for _, kind := range pickupTypes {
		for _, infinity := range []bool{false, true} {
			t.Run(fmt.Sprintf("%s/infinity=%v", kind, infinity), func(t *testing.T) {
				if infinity {
					a := newSeededInfiniteArena(503)
					p := a.addPilot("Pilot", false, 0, 0, 0, 0)
					p.kit = Tank{AmmoEpoch: 17}
					expireAmmoFixture(&p.kit, kind)
					a.advanceEquipment(p)
					assertFullReadyAmmo(t, &p.kit, 18)
					if kind == "rapid" || kind == "scatter" || kind == "homing" || kind == "grenade" || kind == "laser" || kind == "cannon" {
						if p.kit.Power != "" {
							t.Fatal("expired weapon survived")
						}
					}
					serial := p.kit.ShotSerial
					a.fire(p)
					if p.kit.ShotSerial != serial+1 {
						t.Fatal("expired power blocked immediate fire")
					}
				} else {
					g := battle(2)
					p := g.Tanks[0]
					p.AmmoEpoch = 17
					expireAmmoFixture(p, kind)
					g.step(tickDT, [maxTanks]Input{}, testPlayers(2))
					assertFullReadyAmmo(t, p, 18)
					if !g.fire(p) {
						t.Fatal("expired power blocked immediate fixed fire")
					}
				}
			})
		}
	}
	for _, bot := range []bool{false, true} {
		g := battle(2)
		p := g.Tanks[0]
		p.Bot = bot
		p.Difficulty = "dumb"
		p.AmmoEpoch = 31
		p.Power = "cannon"
		p.PowerTime, p.Shield, p.StarmanTime, p.SpeedTime, p.GhostTime = tickDT/2, tickDT/2, tickDT/2, tickDT/2, tickDT/2
		p.ShieldCharges, p.SpeedStacks = 1, 1
		g.step(tickDT, [maxTanks]Input{}, testPlayers(2))
		if p.AmmoEpoch != 32 || p.Power != "" {
			t.Fatal("simultaneous timer ends reset more than once", bot, p.AmmoEpoch)
		}
	}
	a := newSeededInfiniteArena(503)
	p := a.addPilot("Pilot", false, 0, 0, 0, 0)
	p.kit = Tank{AmmoEpoch: 31, Power: "cannon", PowerTime: tickDT / 2, Shield: tickDT / 2, ShieldCharges: 1, StarmanTime: tickDT / 2, SpeedTime: tickDT / 2, SpeedStacks: 1, GhostTime: tickDT / 2}
	a.advanceEquipment(p)
	assertFullReadyAmmo(t, &p.kit, 32)
}

func TestWeaponDepletionAndLastShieldRefillStandardWithoutRetiringShots(t *testing.T) {
	for _, kind := range []string{"rapid", "scatter", "homing", "grenade", "laser", "cannon"} {
		t.Run(kind, func(t *testing.T) {
			g := battle(2)
			p := g.Tanks[0]
			g.Tanks[1].Alive = false
			g.grantPower(p, kind)
			p.Charges, p.MachineRounds = 1, 1
			epoch := p.AmmoEpoch
			if !g.fire(p) {
				t.Fatal("last charge did not fire")
			}
			assertFullReadyAmmo(t, p, epoch+1)
			if p.Power != "" {
				t.Fatal("depleted weapon survived")
			}
			for _, b := range g.Bullets {
				if b.Dead || b.AmmoEpoch != epoch {
					t.Fatal("last-charge projectile was removed or retagged")
				}
			}
			if !g.fire(p) {
				t.Fatal("depletion did not ready full standard ammo")
			}
			a := newSeededInfiniteArena(503)
			q := a.addPilot("Pilot", false, 0, 0, 0, 0)
			q.X, q.Y, q.Angle = 42, 42, 0
			q.kit = Tank{}
			applyPower(&q.kit, kind, 15, 8)
			q.kit.Charges, q.kit.MachineRounds = 1, 1
			e := q.kit.AmmoEpoch
			a.fire(q)
			assertFullReadyAmmo(t, &q.kit, e+1)
			if q.kit.Power != "" {
				t.Fatal("Infinity depleted weapon survived")
			}
			for _, b := range a.bullets {
				if b.dead || b.AmmoEpoch != e {
					t.Fatal("Infinity discarded last-charge projectile")
				}
			}
		})
	}
	g := battle(2)
	p := g.Tanks[0]
	g.grantPower(p, "rapid")
	g.grantPower(p, "shield")
	p.ShieldCharges, p.MachineRounds = 1, 1
	p.Cooldown = .4
	e := p.AmmoEpoch
	g.hurt(p, &Bullet{Owner: 1})
	assertFullReadyAmmo(t, p, e+1)
	if !p.Alive || p.Shield != 0 || p.Invulnerable != .35 {
		t.Fatal("last Shield reset changed damage protection")
	}
	a := newSeededInfiniteArena(503)
	q := a.addPilot("Pilot", false, 0, 0, 0, 0)
	q.kit = Tank{AmmoEpoch: 9, Power: "rapid", PowerTime: 5, MachineRounds: 1, Shield: 5, ShieldCharges: 1, Cooldown: .4}
	q.Protected = false
	a.hurt(q, 99, 0, "Other")
	assertFullReadyAmmo(t, &q.kit, 10)
	if q.HP == 0 || q.kit.Invulnerable != .35 {
		t.Fatal("Infinity shield refill changed damage protection")
	}
}

func TestOldEpochProjectileStillHitsAndOldGrenadeFinishesNaturally(t *testing.T) {
	g := battle(2)
	p, target := g.Tanks[0], g.Tanks[1]
	target.X = 400
	g.fire(p)
	old := g.Bullets[0]
	epoch := old.AmmoEpoch
	g.grantPower(p, "shield")
	target.X, target.Y = old.X+30, old.Y
	g.updateBullets(.1)
	if !old.Dead || target.Alive || old.AmmoEpoch != epoch || p.stats.Eliminations != 1 {
		t.Fatal("refill changed old projectile damage")
	}
	a := newSeededInfiniteArena(503)
	q := a.addPilot("Pilot", false, 0, 0, 0, 0)
	r := a.addPilot("Target", false, 0, 0, 0, 0)
	q.X, q.Y, q.Angle, r.X, r.Y = 20, 42, 0, 70, 42
	q.kit, r.kit = Tank{}, Tank{}
	q.Protected, r.Protected = false, false
	a.fire(q)
	if len(a.bullets) != 1 {
		t.Fatal("old Infinity projectile fixture hit too early")
	}
	oldEpoch := a.bullets[0].AmmoEpoch
	applyPower(&q.kit, "shield", 15, 8)
	a.advanceBullet(&a.bullets[0], 30, 0)
	if r.HP != 0 || q.Score != 1 || a.bullets[0].AmmoEpoch != oldEpoch {
		t.Fatal("Infinity refill changed old shot's collision/credit")
	}
	for _, infinity := range []bool{false, true} {
		t.Run(fmt.Sprint("grenade/", infinity), func(t *testing.T) {
			if infinity {
				a := newSeededInfiniteArena(503)
				p := a.addPilot("Pilot", false, 0, 0, 0, 0)
				p.kit = Tank{}
				applyPower(&p.kit, "grenade", 15, 8)
				p.kit.Charges = 1
				a.weaponControl(p, true, true)
				if len(a.bullets) != 1 {
					t.Fatal("grenade did not launch")
				}
				b := &a.bullets[0]
				a.weaponControl(p, false, false)
				a.weaponControl(p, true, true)
				if b.dead || len(a.bullets) < 2 || a.bullets[1].Kind != "" {
					t.Fatal("old grenade consumed fresh standard trigger")
				}
				a.bullets[0].Life = tickDT / 2
				a.advanceBullets()
				found := false
				for _, fx := range a.effects {
					found = found || fx.Kind == "blast"
				}
				if !found {
					t.Fatal("old grenade lost natural fuse")
				}
			} else {
				g := battle(2)
				p := g.Tanks[0]
				g.Tanks[1].Alive = false
				g.grantPower(p, "grenade")
				p.Charges = 1
				g.weaponControl(p, true, true)
				b := g.Bullets[0]
				g.weaponControl(p, false, false)
				g.weaponControl(p, true, true)
				if b.Dead || len(g.Bullets) < 2 || g.Bullets[1].Kind != "" {
					t.Fatal("old grenade consumed fresh standard trigger")
				}
				b.Life = tickDT / 2
				g.updateBullets(tickDT)
				if !b.Dead {
					t.Fatal("old grenade lost natural fuse")
				}
			}
		})
	}
}

func TestAmmoEpochTransportAndWrapPreserveLegacyRapidTuple(t *testing.T) {
	g := battle(2)
	g.Tanks[0].AmmoEpoch = 7
	g.Bullets = []*Bullet{{ID: 1, Owner: 0, Kind: "rapid", Color: tankColors[0], AmmoEpoch: 6}, {ID: 2, Owner: 0, Kind: "rapid", Color: tankColors[0], AmmoEpoch: 7}, {ID: 3, Owner: 1, Kind: "rapid", Color: tankColors[1]}, {ID: 4, Owner: 0, Color: tankColors[0], AmmoEpoch: 8}}
	h, r, _ := performanceRoom437(0)
	r.Game = g
	wire := h.stateWire(r)
	if fmt.Sprint(wire.MachineAmmoEpochs) != "[6 7 0]" || len(wire.MachineBullets) != 3 || len(wire.MachineBullets[0]) != 12 || wire.Bullets[0].AmmoEpoch != 8 || wire.Tanks[0].AmmoEpoch != 7 {
		t.Fatal("epoch transport changed tuples/order", wire.MachineAmmoEpochs)
	}
	encoded, _ := json.Marshal(wire)
	reference, _ := json.Marshal(h.stateMessage(r))
	if !bytes.Equal(encoded, reference) {
		t.Fatal("optimized epoch packet differs from reference")
	}
	for _, b := range g.Bullets {
		b.AmmoEpoch = 0
	}
	wire = h.stateWire(r)
	encoded, _ = json.Marshal(wire)
	if len(wire.MachineAmmoEpochs) != 0 || bytes.Contains(encoded, []byte("machineAmmoEpochs")) {
		t.Fatal("zero legacy epoch vector was not omitted")
	}
	p := &Tank{AmmoEpoch: maxAmmoEpoch, fireHeld: true, rapidTick: 10, rapidFired: true}
	refillAmmo(p)
	if p.AmmoEpoch != 1 || !p.fireHeld || !p.rapidFired || p.rapidTick != 10 {
		t.Fatal("wrap/reset changed held input or rapid cadence")
	}
	a := newSeededInfiniteArena(503)
	c := partySnapshotClient()
	q := a.join(c, "Pilot", time.Now())
	q.kit.AmmoEpoch = 9
	q.X, q.Y = 42, 42
	a.bullets = []infiniteBullet{{ID: 1, Owner: q.ID, Kind: "grenade", AmmoEpoch: 8, Life: 7, X: 50, Y: 42}, {ID: 2, Owner: q.ID, Kind: "grenade", AmmoEpoch: 9, Life: 5, X: 50, Y: 42}, {ID: 3, Owner: q.ID, AmmoEpoch: 9, Life: 4, X: 50, Y: 42}, {ID: 4, Owner: q.ID, AmmoEpoch: 9, Life: 4, X: 50, Y: 42, boosted: true}}
	a.broadcast()
	snapshot := readPartySnapshot(t, c)
	if snapshot.Tanks[0].AmmoEpoch != 9 || snapshot.Tanks[0].AmmoUsed != 2 || snapshot.Tanks[0].Grenades != 1 || snapshot.Tanks[0].GrenadeLife != 5 || len(snapshot.Bullets) != 4 {
		t.Fatal("Infinity HUD lost current ammo or retired old visible shots", snapshot.Tanks[0])
	}
}

func TestRepeatedRefillsKeepRapidSixtyHzAndLegacyTupleBound(t *testing.T) {
	g := battle(maxTanks)
	g.World.Cols, g.World.Rows = 24, 14
	g.World.Width, g.World.Height = 24*cellSize, 14*cellSize
	g.World.Walls = nil
	for i, p := range g.Tanks {
		p.X, p.Y, p.Angle = 42, 42+float64(i)*100, 0
		p.Invulnerable = 1000
		p.SpawnProtected = false
	}
	for range 240 {
		g.Tick++
		for _, p := range g.Tanks {
			g.grantPower(p, "rapid")
			if !g.fire(p) {
				t.Fatal("first rapid shot in tick blocked")
			}
			g.grantPower(p, "shield")
			if g.fire(p) {
				t.Fatal("refill allowed two rapid shots within one tick")
			}
		}
		g.updateBullets(tickDT)
		if len(g.Bullets) > maxTanks*machineCapacity {
			t.Fatal("natural rapid TTL exceeded legacy transport bound", len(g.Bullets))
		}
	}
}

func TestStarmanRecyclesOnlyCurrentEpochBonusShots(t *testing.T) {
	g := battle(2)
	p := g.Tanks[0]
	g.Tanks[1].Y = 350
	g.grantPower(p, "starman")
	for range machineCapacity {
		if !g.fire(p) {
			t.Fatal("initial Star shot blocked")
		}
	}
	old := append([]*Bullet(nil), g.Bullets...)
	g.grantPower(p, "shield")
	for range machineCapacity + 1 {
		if !g.fire(p) {
			t.Fatal("fresh Star epoch choked on old shots")
		}
	}
	liveCurrent := 0
	for _, b := range g.Bullets {
		if !b.Dead && b.AmmoEpoch == p.AmmoEpoch {
			liveCurrent++
		}
	}
	if liveCurrent != machineCapacity {
		t.Fatal("current Star epoch exceeded cap", liveCurrent)
	}
	for _, b := range old {
		if b.Dead {
			t.Fatal("refill/current Star recycling deleted a prior epoch shot")
		}
	}
	a := newSeededInfiniteArena(503)
	q := a.addPilot("Pilot", false, 0, 0, 0, 0)
	applyPower(&q.kit, "starman", 15, 8)
	for range machineCapacity {
		a.fire(q)
	}
	oldEpoch := q.kit.AmmoEpoch
	applyPower(&q.kit, "shield", 15, 8)
	for range machineCapacity + 1 {
		a.fire(q)
	}
	oldLive, currentLive := 0, 0
	for _, b := range a.bullets {
		if b.dead {
			continue
		}
		if b.AmmoEpoch == oldEpoch {
			oldLive++
		}
		if b.AmmoEpoch == q.kit.AmmoEpoch {
			currentLive++
		}
	}
	if oldLive != machineCapacity || currentLive != machineCapacity {
		t.Fatal("Infinity recycler crossed ammo epochs", oldLive, currentLive)
	}
}

func TestRespawnAdvancesAmmoEpochWithoutRetiringPreviousLifeShots(t *testing.T) {
	g, _ := objectiveFixture("ctf")
	p := g.Tanks[0]
	p.AmmoEpoch = 99
	p.Power = "rapid"
	p.MachineRounds = 1
	p.Cooldown = .7
	old := &Bullet{ID: 100, Owner: p.ID, AmmoEpoch: 99, Life: 5}
	g.Bullets = []*Bullet{old}
	g.respawnTank(p)
	assertFullReadyAmmo(t, p, 100)
	if old.Dead || len(g.Bullets) != 1 || !p.SpawnProtected {
		t.Fatal("respawn changed old shot physics or spawn protection")
	}
	a := newSeededInfiniteArena(503)
	q := a.addPilot("Pilot", false, 0, 0, 0, 0)
	if q.kit.AmmoEpoch != 0 {
		t.Fatal("fresh actor must use legacy-compatible initial epoch0")
	}
	applyPower(&q.kit, "shield", 15, 8)
	epoch := q.kit.AmmoEpoch
	a.bullets = []infiniteBullet{{ID: 100, Owner: q.ID, AmmoEpoch: epoch, Life: 5}}
	id := q.ID
	q.Score = 17
	a.spawn(q, q.X, q.Y, 2, 5)
	assertFullReadyAmmo(t, &q.kit, epoch+1)
	if a.bullets[0].dead || q.ID != id || q.Score != 17 || !q.kit.SpawnProtected {
		t.Fatal("Infinity respawn changed old physics, score, identity or spawn protection")
	}
}
