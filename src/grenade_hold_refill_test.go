package main

import (
	"fmt"
	"testing"
)

func TestLastGrenadeConsumesWholeHoldAcrossRefills(t *testing.T) {
	for _, infinity := range []bool{false, true} {
		for _, coalesced := range []bool{false, true} {
			t.Run(fmt.Sprintf("infinity=%v/coalesced=%v", infinity, coalesced), func(t *testing.T) {
				if infinity {
					a := newSeededInfiniteArena(511)
					p := a.addPilot("Pilot", false, 0, 0, 0, 0)
					p.X, p.Y, p.Angle = 42, 42, 0
					p.kit = Tank{}
					applyPower(&p.kit, "grenade", 15, 8)
					p.kit.Charges = 1
					a.weaponControl(p, true, true)
					if p.kit.Power != "" || p.kit.Charges != 0 || p.kit.Cooldown != 0 || !p.kit.fireBlocked || len(a.bullets) != 1 || a.bullets[0].Kind != "grenade" {
						t.Fatal("final grenade failed to replenish standard ammo and consume its hold")
					}
					serial := p.kit.ShotSerial
					for range 8 {
						a.weaponControl(p, true, false)
					}
					applyPower(&p.kit, "shield", 15, 8)
					a.weaponControl(p, true, false)
					p.kit.Shield = tickDT / 2
					a.advanceEquipment(p)
					a.weaponControl(p, true, false)
					if p.kit.ShotSerial != serial || len(a.bullets) != 1 || a.bullets[0].dead || !p.kit.fireBlocked {
						t.Fatal("holding final grenade fired standard ammo after depletion, pickup or expiry")
					}
					if !coalesced {
						a.weaponControl(p, false, false)
					}
					a.weaponControl(p, true, true)
					if p.kit.ShotSerial != serial+1 || len(a.bullets) != 2 || a.bullets[0].dead || a.bullets[1].Kind != "" || a.bullets[1].AmmoEpoch != p.kit.AmmoEpoch {
						t.Fatal("fresh standard press was blocked or detonated an old-epoch grenade")
					}
				} else {
					g, p := grenadeGame()
					g.Tanks[1].Alive = false
					p.Charges = 1
					g.weaponControl(p, true, true)
					if p.Power != "" || p.Charges != 0 || p.Cooldown != 0 || !p.fireBlocked || len(g.Bullets) != 1 || g.Bullets[0].Kind != "grenade" {
						t.Fatal("final grenade failed to replenish standard ammo and consume its hold")
					}
					old := g.Bullets[0]
					serial := p.ShotSerial
					for range 8 {
						g.weaponControl(p, true, false)
					}
					g.grantPower(p, "shield")
					g.weaponControl(p, true, false)
					p.Shield = tickDT / 2
					g.step(tickDT, [maxTanks]Input{{Fire: true}}, testPlayers(2))
					if p.ShotSerial != serial || len(g.Bullets) != 1 || old.Dead || !p.fireBlocked {
						t.Fatal("holding final grenade fired standard ammo after depletion, pickup or expiry")
					}
					if !coalesced {
						g.weaponControl(p, false, false)
					}
					g.weaponControl(p, true, true)
					if p.ShotSerial != serial+1 || len(g.Bullets) != 2 || old.Dead || g.Bullets[1].Kind != "" || g.Bullets[1].AmmoEpoch != p.AmmoEpoch {
						t.Fatal("fresh standard press was blocked or detonated an old-epoch grenade")
					}
				}
			})
		}
	}
}
