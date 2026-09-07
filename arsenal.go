package main

// Weapon IDs remain rapid/scatter for saved-preset and protocol compatibility.
// Labels are Machine gun / Shotgun. Visuals and simulation share these values.
const (
	regularSpeed     = 282.0
	regularRadius    = 3.5
	shotgunSpeed     = regularSpeed * 3
	machineSpeed     = regularSpeed * 3
	machineRadius    = regularRadius / 3
	machineCapacity  = 96 // Covers a continuous 60 Hz stream across the largest quarter-perimeter range.
	shieldDuration   = powerEffectDuration
	maxShieldCharges = 5
)

// Old deterministic fixtures may specify only Shield. Treat that as one charge;
// real pickups always initialize the explicit charge count.
func shieldCount(t *Tank) int {
	if t == nil || t.Shield <= 0 {
		return 0
	}
	if t.ShieldCharges < 1 {
		return 1
	}
	if t.ShieldCharges > maxShieldCharges {
		return maxShieldCharges
	}
	return t.ShieldCharges
}

func speedCount(t *Tank) int {
	if t == nil || t.SpeedTime <= 0 {
		return 0
	}
	if t.SpeedStacks < 1 {
		return 1 // Compatibility with older fixtures/snapshots that only set SpeedTime.
	}
	if t.SpeedStacks > maxSpeedStacks {
		return maxSpeedStacks
	}
	return t.SpeedStacks
}
func pickupWeight(kind string) int {
	if kind == "shield" || kind == "speed" {
		return 3
	}
	return 1
}
func (g *Game) choosePickup(types []string) string {
	total := 0
	for _, kind := range types {
		total += pickupWeight(kind)
	}
	if total == 0 {
		return ""
	}
	choice := g.rng.Intn(total)
	for _, kind := range types {
		choice -= pickupWeight(kind)
		if choice < 0 {
			return kind
		}
	}
	return types[len(types)-1]
}
