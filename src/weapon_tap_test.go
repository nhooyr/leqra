package main

import (
	"fmt"
	"testing"
)

func depletedReload(kind string) float64 {
	switch kind {
	case "homing":
		return .36
	case "grenade":
		return .8
	default:
		return .34
	}
}

func assertDepletedAmmo(t *testing.T, tank *Tank, epoch uint64, kind string) {
	t.Helper()
	want := depletedReload(kind)
	if tank.Cooldown != want || tank.CooldownTotal != want {
		t.Fatalf("depleted %s reload = %v/%v, want %v", kind, tank.Cooldown, tank.CooldownTotal, want)
	}
	copy := *tank
	copy.Cooldown, copy.CooldownTotal = 0, 0
	assertFullReadyAmmo(t, &copy, epoch)
}

func TestEveryDepletedWeaponWaitsForReloadThenContinuesHeldFire(t *testing.T) {
	for _, kind := range finiteHoldWeapons {
		for _, infinity := range []bool{false, true} {
			t.Run(fmt.Sprintf("%s/infinity=%v", kind, infinity), func(t *testing.T) {
				h := newMachineSynergyArena(infinity)
				h.grant(kind)
				h.tank.Charges, h.tank.MachineRounds = 1, 1
				h.stepHeld(true, true)
				assertDepletedAmmo(t, h.tank, 2, kind)
				elapsed := 0.0
				for tick := 0; tick < 60 && h.tank.ShotSerial == 1; tick++ {
					h.stepHeld(true, false)
					elapsed += tickDT
					if elapsed+1e-9 < depletedReload(kind) && h.tank.ShotSerial != 1 {
						t.Fatal("standard ammo fired before reload")
					}
				}
				if h.tank.ShotSerial != 2 {
					t.Fatal("held trigger did not resume after reload")
				}
			})
		}
	}
}

func TestLastPowerUpChargeDoesNotFireStandardAmmoDuringATap(t *testing.T) {
	for _, kind := range finiteHoldWeapons {
		for _, infinity := range []bool{false, true} {
			for _, ticks := range []int{1, 3, 6, 10} {
				t.Run(fmt.Sprintf("%s/infinity=%v/ticks=%d", kind, infinity, ticks), func(t *testing.T) {
					h := newMachineSynergyArena(infinity)
					h.grant(kind)
					h.tank.Charges, h.tank.MachineRounds = 1, 1
					for tick := range ticks {
						h.stepHeld(true, tick == 0)
						if h.tank.ShotSerial != 1 {
							t.Fatalf("one %dms tap fired %d volleys, including standard ammo", ticks*1000/60, h.tank.ShotSerial)
						}
					}
					for range 30 {
						h.stepHeld(false, false)
					}
					if h.tank.ShotSerial != 1 {
						t.Fatal("the released tap fired a delayed standard volley")
					}
				})
			}
		}
	}
}
