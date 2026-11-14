package main

import (
	"fmt"
	"math"
	"testing"
	"time"
)

func TestStarmanMovementMatchesTwoSpeedPickupsWithoutConsumingGear(t *testing.T) {
	for stacks := 0; stacks <= maxSpeedStacks; stacks++ {
		t.Run(fmt.Sprint(stacks), func(t *testing.T) {
			g := battle(1)
			pilot := g.Tanks[0]
			pilot.StarmanTime, pilot.SpeedStacks = 5, stacks
			if stacks > 0 {
				pilot.SpeedTime = 7
			}
			storedTime := pilot.SpeedTime
			input := Input{Forward: true, Right: true}
			x, y := pilot.X, pilot.Y
			g.control(pilot, input, tickDT)
			effective := max(stacks, 2)
			angle, throttle := steerTank(0, input, 1+boostTurnPerStack*float64(effective), tickDT)
			step := 128 * (1 + boostSpeedPerStack*float64(effective)) * throttle * tickDT
			if math.Abs(pilot.Angle-angle) > 1e-9 || math.Abs(pilot.X-x-math.Cos(angle)*step) > 1e-9 || math.Abs(pilot.Y-y-math.Sin(angle)*step) > 1e-9 {
				t.Fatal("Starman did not use the two-stack speed and turning floor", pilot)
			}
			if speedCount(pilot) != stacks || pilot.SpeedStacks != stacks || math.Abs(pilot.SpeedTime-max(0, storedTime-tickDT)) > 1e-9 || pilot.StarmanTime != 5 {
				t.Fatal("effective movement changed stored pickups or Starman duration", pilot)
			}
			pilot.StarmanTime = 0
			if movementSpeedCount(pilot) != stacks {
				t.Fatal("Starman expiry did not restore existing pickup speed")
			}
		})
	}
}

func TestStarmanMovementFloorSurvivesIndependentSpeedPickupExpiry(t *testing.T) {
	g := battle(1)
	pilot := g.Tanks[0]
	pilot.StarmanTime, pilot.SpeedTime, pilot.SpeedStacks = 3, tickDT, 5
	x := pilot.X
	g.control(pilot, Input{Forward: true}, tickDT)
	if pilot.SpeedTime != 0 || pilot.SpeedStacks != 0 || math.Abs(pilot.X-x-128*(1+2*boostSpeedPerStack)*tickDT) > 1e-9 {
		t.Fatal("expired pickup stacks replaced or removed the independent Starman floor")
	}
	g.grantPower(pilot, "speed")
	if speedCount(pilot) != 1 || movementSpeedCount(pilot) != 2 {
		t.Fatal("a speed pickup collected during Starman stacked onto virtual pickups")
	}
	pilot.StarmanTime = 0
	if movementSpeedCount(pilot) != 1 {
		t.Fatal("the real pickup was lost when Starman expired")
	}
}

func TestInfiniteStarmanMovementMatchesTwoSpeedPickupsAndKeepsStrongerGear(t *testing.T) {
	for _, private := range []bool{false, true} {
		for stacks := 0; stacks <= maxSpeedStacks; stacks++ {
			a := newSeededInfiniteArena(37)
			if private {
				a = newRoomInfiniteArena(defaultRules(), nil)
			}
			pilot := a.join(fakeClient(), "Pilot", time.Unix(0, 0))
			pilot.X, pilot.Y, pilot.Angle = 42, 42, 0
			pilot.kit.StarmanTime, pilot.kit.GhostTime, pilot.kit.SpeedStacks = 5, 5, stacks
			if stacks > 0 {
				pilot.kit.SpeedTime = 7
			}
			before := pilot.kit
			a.drive(pilot, Input{Forward: true, Right: true})
			effective := float64(max(stacks, 2))
			angle, throttle := steerTank(0, Input{Forward: true, Right: true}, 1+boostTurnPerStack*effective, tickDT)
			speed := infiniteTankSpeed * (1 + boostSpeedPerStack*effective) * throttle
			if math.Abs(pilot.Angle-angle) > 1e-9 || math.Abs(pilot.VX-math.Cos(angle)*speed) > 1e-8 || math.Abs(pilot.VY-math.Sin(angle)*speed) > 1e-8 || pilot.kit != before {
				t.Fatal("Infinity movement changed gear or differed from the Starman floor", private, stacks)
			}
		}
	}
}
