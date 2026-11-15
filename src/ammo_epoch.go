package main

// Epochs are presentation-safe JSON integers. Old shots keep their physics but
// stop occupying the fresh magazine after a pickup or an equipment transition.
const maxAmmoEpoch = uint64(1<<53 - 1)

func refillAmmo(t *Tank) {
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

func refillExpiredAmmo(t *Tank) {
	if !t.expiryRefilled {
		refillAmmo(t)
		t.expiryRefilled = true
	}
}

func clearWeapon(t *Tank) {
	// Ending a finite weapon never turns its held trigger into a standard shot.
	// Timer expiry sees the prior held state; a fresh input edge can release it.
	if t.Power != "" && t.fireHeld {
		t.fireBlocked = true
	}
	t.Power, t.PowerTime, t.Charges, t.MachineRounds = "", 0, 0, 0
}
