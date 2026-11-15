package main

// Epochs are presentation-safe JSON integers. Old shots keep their physics but
// stop occupying the fresh magazine after a pickup or an equipment transition.
const maxAmmoEpoch = uint64(1<<53 - 1)

func refillAmmo(t *Tank) {
	t.GrenadeEpoch = nil
	if t.AmmoEpoch >= maxAmmoEpoch {
		t.AmmoEpoch = 1
	} else {
		t.AmmoEpoch++
	}
	t.Cooldown, t.CooldownTotal = 0, 0
	t.MachineRounds = 0
	switch t.Power {
	case "rapid":
		t.MachineRounds, t.Charges = machineFiringRounds, 0
	case "scatter":
		t.Charges = 5
	case "homing", "grenade", "laser", "cannon":
		t.Charges = 3
	default:
		t.Charges = 0
	}
}

func grenadeControlEpoch(t *Tank) uint64 {
	if t.GrenadeEpoch != nil {
		return *t.GrenadeEpoch
	}
	return t.AmmoEpoch
}

// A final grenade still owns its next remote-detonation press even though its
// automatic return to standard ammo starts a fresh capacity epoch.
func refillDepletedWeapon(t *Tank) {
	grenade, bank := t.Power == "grenade", grenadeControlEpoch(t)
	clearWeapon(t)
	refillAmmo(t)
	if grenade {
		t.GrenadeEpoch = &bank
	}
}

func refillExpiredAmmo(t *Tank) {
	if !t.expiryRefilled {
		refillAmmo(t)
		t.expiryRefilled = true
	}
}

func clearWeapon(t *Tank) {
	t.Power, t.PowerTime, t.Charges, t.MachineRounds = "", 0, 0, 0
}
