package main

import (
	"testing"
	"time"
)

func TestInfinitySpawnPoolIncludesEveryPowerUp(t *testing.T) {
	arena := newSeededInfiniteArena(37)
	pilot := arena.join(fakeClient(), "Explorer", time.Now())
	seen := make(map[string]bool)
	collectedGrenade := false
	for range 180 {
		arena.pickups = arena.pickups[:0]
		if !arena.spawnPickup(pilot) {
			t.Fatal("could not spawn a pickup around the pilot")
		}
		pickup := &arena.pickups[0]
		seen[pickup.Type] = true
		if pickup.Type == "grenade" && !collectedGrenade {
			x, y := pilot.X, pilot.Y
			pilot.X, pilot.Y = pickup.X, pickup.Y
			arena.collectPickup(pilot)
			pilot.X, pilot.Y = x, y
			collectedGrenade = pickup.Life == 0 && pilot.kit.Power == "grenade" && pilot.kit.Charges == 3
		}
	}
	for _, kind := range pickupTypes {
		if !seen[kind] {
			t.Errorf("production Infinity spawner never produced %s", kind)
		}
	}
	if !collectedGrenade {
		t.Error("a spawned grenade did not equip three charges")
	}
}
