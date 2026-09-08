package main

import "testing"

// Preserve the original map-based scoring as an independent parity oracle.
func originalGodlikePickupValue(t *Tank, kind string) float64 {
	switch kind {
	case "shield":
		if shieldCount(t) >= maxShieldCharges && t.Shield > 4 {
			return 0
		}
		return 5
	case "speed":
		if speedCount(t) >= maxSpeedStacks && t.SpeedTime > 4 {
			return 0
		}
		return 3.7
	case "ghost":
		if t.GhostTime > 4 {
			return 0
		}
		return 3.8
	case "scope":
		if t.ScopeTime > 3 {
			return 0
		}
		return .65
	}
	value := map[string]float64{"rapid": 3.7, "scatter": 3, "homing": 4.2, "grenade": 3, "laser": 5, "cannon": 5.2}[kind]
	if t.Power != "" && t.PowerTime > 3 && t.Charges > 0 && (t.Power != "rapid" || t.MachineRounds >= 120) {
		current := map[string]float64{"rapid": 3.7, "scatter": 3, "homing": 4.2, "grenade": 3, "laser": 5, "cannon": 5.2}[t.Power]
		if current >= value {
			return 0
		}
		value -= current * .6
	}
	return value
}

func TestGodlikePickupValuesPreserveScoring(t *testing.T) {
	kinds := append(append([]string(nil), pickupTypes...), "", "unknown")
	check := func(bot *Tank) {
		t.Helper()
		for _, kind := range kinds {
			if got, want := godlikePickupValue(bot, kind), originalGodlikePickupValue(bot, kind); got != want {
				t.Fatalf("pickup %q with power %q, time %v, charges %v, rounds %v: value %v, want %v", kind, bot.Power, bot.PowerTime, bot.Charges, bot.MachineRounds, got, want)
			}
		}
	}
	for _, power := range kinds {
		for _, duration := range []float64{0, 3, 3.0001, 10} {
			for _, charges := range []int{0, 1} {
				for _, rounds := range []int{0, 119, 120, 180} {
					check(&Tank{Power: power, PowerTime: duration, Charges: charges, MachineRounds: rounds})
				}
			}
		}
	}
	for _, duration := range []float64{0, 3, 3.0001, 4, 4.0001, 10} {
		for _, stacks := range []int{0, 1, 5, 6} {
			check(&Tank{Shield: duration, ShieldCharges: stacks, SpeedTime: duration, SpeedStacks: stacks, GhostTime: duration, ScopeTime: duration})
		}
	}
}

var godlikePickupValueSink float64
var godlikePickupSearchSink *Pickup

func BenchmarkGodlikePickupValue(b *testing.B) {
	kinds := []string{"rapid", "scatter", "homing", "grenade", "laser", "cannon"}
	for _, power := range []string{"", "homing"} {
		name := "unarmed"
		if power != "" {
			name = "armed"
		}
		b.Run(name, func(b *testing.B) {
			bot := &Tank{Power: power, PowerTime: 10, Charges: 3}
			b.ReportAllocs()
			for i := 0; i < b.N; i++ {
				godlikePickupValueSink = godlikePickupValue(bot, kinds[i%len(kinds)])
			}
		})
	}
}

func BenchmarkGodlikePickupSearch(b *testing.B) {
	g := newGame(426)
	g.Rules.MapSize = "ultrawide"
	g.startMatch(testPlayers(2))
	bot, goal := g.Tanks[0], g.Tanks[1]
	bot.AI = &BotState{}
	bot.Power, bot.PowerTime, bot.Charges = "homing", 10, 3
	g.Pickups = nil
	kinds := []string{"rapid", "scatter", "homing", "grenade", "laser", "cannon"}
	for i := 0; i < 34; i++ {
		x, y := g.cellCenter((i*13 + 5) % (g.World.Cols * g.World.Rows))
		g.Pickups = append(g.Pickups, &Pickup{X: x, Y: y, Type: kinds[i%len(kinds)], Life: 60})
	}
	tuning := tuneBot("godlike")
	g.godlikePickup(bot, tuning, goal, false)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		godlikePickupSearchSink = g.godlikePickup(bot, tuning, goal, false)
	}
}
