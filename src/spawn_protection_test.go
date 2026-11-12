package main

import "testing"

func TestSpawnProtectionBlocksWeaponsWithoutSpendingAmmo(t *testing.T) {
	for _, kind := range []string{"regular", "rapid", "scatter", "homing", "grenade", "laser", "cannon"} {
		t.Run(kind, func(t *testing.T) {
			g := battle(2)
			pilot := g.Tanks[0]
			if kind != "regular" {
				g.grantPower(pilot, kind)
			}
			pilot.SpawnProtected, pilot.Invulnerable = true, .75
			charges, rounds, serial, events := pilot.Charges, pilot.MachineRounds, pilot.ShotSerial, len(g.events)
			if g.fire(pilot) || kind == "laser" && g.fireLaser(pilot) {
				t.Fatal("spawn-protected tank fired")
			}
			g.weaponControl(pilot, true, true)
			if len(g.Bullets) != 0 || len(g.events) != events || pilot.Charges != charges || pilot.MachineRounds != rounds || pilot.ShotSerial != serial || pilot.Cooldown != 0 || pilot.Recoil != 0 {
				t.Fatalf("blocked fire changed weapon state: %+v", pilot)
			}
			pilot.Invulnerable = 0
			if !g.fire(pilot) {
				t.Fatal("weapon remained blocked after spawn protection expired")
			}
		})
	}
}

func TestSpawnProtectionBlocksOwnedGrenadeDetonation(t *testing.T) {
	g := battle(2)
	pilot := g.Tanks[0]
	g.grantPower(pilot, "grenade")
	if !g.fire(pilot) {
		t.Fatal("initial grenade failed")
	}
	grenade := g.Bullets[0]
	pilot.SpawnProtected, pilot.Invulnerable = true, 1
	if g.detonateOwned(pilot) || grenade.Dead {
		t.Fatal("spawn-protected tank detonated an existing grenade")
	}
	g.weaponControl(pilot, true, true)
	if grenade.Dead || pilot.fireBlocked {
		t.Fatal("protected action detonated a grenade or consumed the hold")
	}
	pilot.Invulnerable = 0
	if !g.detonateOwned(pilot) || !grenade.Dead {
		t.Fatal("grenade remained blocked after protection expired")
	}
}

func TestSpawnProtectionIsDistinctFromStarmanAndShieldProtection(t *testing.T) {
	g := battle(2)
	pilot := g.Tanks[0]
	pilot.SpawnProtected, pilot.Invulnerable = true, 1
	g.grantPower(pilot, "starman")
	if pilot.SpawnProtected || !g.fire(pilot) {
		t.Fatal("Starman pickup retained spawn firing restrictions")
	}
	pilot.StarmanTime, pilot.Invulnerable = 0, 0
	g.grantPower(pilot, "shield")
	g.hurt(pilot, &Bullet{Owner: 1})
	pilot.Cooldown = 0
	if pilot.SpawnProtected || pilot.Invulnerable <= 0 || !g.fire(pilot) {
		t.Fatal("shield-hit protection was mistaken for spawn protection")
	}
	g = newGame(42)
	g.startMatch(testPlayers(2))
	pilot = g.Tanks[0]
	g.respawnTank(pilot)
	if !pilot.SpawnProtected || pilot.Invulnerable <= 0 || g.fire(pilot) {
		t.Fatal("respawn did not restore the spawn firing restriction")
	}
}
