package main

import (
	"fmt"
	"testing"
)

func TestLastGrenadeHeldFireContinuesAcrossRefillsWithoutRemovingItsFuse(t *testing.T) {
	for _, infinity := range []bool{false, true} {
		t.Run(fmt.Sprint(infinity), func(t *testing.T) {
			h := newMachineSynergyArena(infinity)
			h.grant("grenade")
			h.tank.Charges = 1
			h.stepHeld(true, true)
			if h.tank.ShotSerial != 1 || h.tank.Power != "" || len(h.shots()) != 1 {
				t.Fatal("last grenade did not produce exactly one final throw")
			}
			old := h.shots()[0]
			h.stepHeld(true, false)
			if h.tank.ShotSerial != 2 {
				t.Fatal("held trigger did not continue with the standard magazine")
			}
			h.grant("shield")
			h.stepHeld(true, false)
			if h.tank.ShotSerial != 3 || h.tank.GrenadeEpoch != nil {
				t.Fatal("pickup needed release or retained the old remote bank")
			}
			h.tank.Shield = tickDT / 2
			h.stepHeld(true, false)
			if h.tank.ShotSerial != 4 {
				t.Fatal("passive expiry interrupted the held trigger")
			}
			found := false
			for _, shot := range h.shots() {
				if shot.id == old.id {
					found = shot.epoch == old.epoch && shot.life > 0 && shot.life < old.life
				}
			}
			if !found {
				t.Fatal("continued held fire removed or retagged the old natural-fuse grenade")
			}
		})
	}
}
