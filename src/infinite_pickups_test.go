package main

import (
	"math/rand/v2"
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

// Feed the production spawner the midpoint of every possible weighted choice,
// after two fixed position draws. This checks the exact lottery without a
// statistical tolerance, seed dependence, or a duplicate selection algorithm.
type pickupLotterySource struct {
	values []uint64
	draws  int
}

func (s *pickupLotterySource) Uint64() uint64 {
	value := s.values[s.draws]
	s.draws++
	return value
}
func lotteryBucket(bucket, total int) uint64 {
	span := ^uint64(0) / uint64(total)
	return uint64(bucket)*span + span/2
}

func TestPublicInfinityPickupLotteryGivesEveryWeaponEqualWeight(t *testing.T) {
	arena := newSeededInfiniteArena(37)
	pilot := arena.join(fakeClient(), "Explorer", time.Unix(0, 0))
	pilot.X, pilot.Y = 42, 42
	counts := map[string]int{}
	for choice := range 27 {
		source := &pickupLotterySource{values: []uint64{lotteryBucket(3, 7), lotteryBucket(4, 7), lotteryBucket(choice, 27)}}
		arena.random = rand.New(source)
		arena.pickups = arena.pickups[:0]
		if !arena.spawnPickup(pilot) || source.draws != 3 || len(arena.pickups) != 1 {
			t.Fatal("expected one positioned pickup and one type draw", choice, source.draws)
		}
		counts[arena.pickups[0].Type]++
	}
	expected := map[string]int{"rapid": 2, "scatter": 2, "shield": 6, "homing": 2, "grenade": 2, "speed": 6, "laser": 2, "cannon": 2, "ghost": 2, "starman": 1}
	if len(counts) != len(expected) {
		t.Fatal("unexpected pickup types", counts)
	}
	for kind, want := range expected {
		if counts[kind] != want {
			t.Errorf("%s receives %d of 27 lottery outcomes, want %d", kind, counts[kind], want)
		}
	}
}
