package main

import (
	"testing"
	"time"
)

func TestInfiniteSpawnProtectionBlocksEveryWeaponWithoutSpendingAmmo(t *testing.T) {
	for _, kind := range []string{"", "rapid", "scatter", "homing", "grenade", "laser", "cannon"} {
		t.Run(kind, func(t *testing.T) {
			a := newSeededInfiniteArena(37)
			p := a.join(fakeClient(), "Pilot", time.Unix(0, 0))
			if kind != "" {
				applyPower(&p.kit, kind, infinitePowerDuration, infiniteStarDuration)
			}
			before := p.kit
			a.weaponControl(p, true, true)
			a.fire(p)
			if kind == "laser" {
				a.fireLaser(p)
			}
			if p.kit.ShotSerial != 0 || a.nextBullet != 0 || len(a.effects) != 0 || p.kit.Cooldown != before.Cooldown || p.kit.Recoil != 0 || p.kit.Charges != before.Charges || p.kit.MachineRounds != before.MachineRounds {
				t.Fatalf("protected spawn fired or spent weapon state: before=%+v after=%+v", before, p.kit)
			}
			if !p.wireTank(a.tick).SpawnProtected {
				t.Fatal("spawn protection missing from snapshot")
			}
			p.kit.Invulnerable = tickDT
			a.advanceEquipment(p)
			if p.kit.SpawnProtected || p.wireTank(a.tick).SpawnProtected {
				t.Fatal("expired protection remained active")
			}
			a.fire(p)
			if p.kit.ShotSerial != 1 {
				t.Fatal("weapon remained blocked after spawn protection expired")
			}
		})
	}
}

func TestInfiniteSpawnProtectionBlocksOldGrenadeDetonation(t *testing.T) {
	a := newSeededInfiniteArena(37)
	p := a.join(fakeClient(), "Pilot", time.Unix(0, 0))
	a.bullets = []infiniteBullet{{Owner: p.ID, Kind: "grenade", X: p.X, Y: p.Y, Life: 10}}
	a.weaponControl(p, true, true)
	if a.bullets[0].dead || len(a.effects) != 0 {
		t.Fatal("protected spawn detonated its old grenade")
	}
	p.kit.Invulnerable = 0
	a.weaponControl(p, false, false)
	a.weaponControl(p, true, true)
	if !a.bullets[0].dead {
		t.Fatal("unprotected fresh press could not detonate its old grenade")
	}
}

func TestInfiniteShieldHitInvulnerabilityDoesNotBlockWeapons(t *testing.T) {
	a := newSeededInfiniteArena(37)
	p := a.join(fakeClient(), "Pilot", time.Unix(0, 0))
	p.kit.Invulnerable, p.Protected = 0, false
	applyPower(&p.kit, "shield", infinitePowerDuration, infiniteStarDuration)
	a.hurt(p, p.ID+1, 0, "Opponent")
	if p.kit.SpawnProtected || !p.Protected || p.kit.Invulnerable != .35 {
		t.Fatal("shield hit was marked as spawn protection")
	}
	a.fire(p)
	if p.kit.ShotSerial != 1 {
		t.Fatal("shield-hit invulnerability blocked return fire")
	}
}
