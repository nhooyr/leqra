package main

import "testing"

func TestSurvival436PickupsFreezeUntilNextWave(t *testing.T) {
	h, _, r := survivalRoom427(t, 1)
	g := r.Game
	g.startMatch(r.Players)
	g.Phase = "playing"
	// Almost-expired pickup under a living ally exercises both expiry and collection.
	pickup := &Pickup{ID: 900, X: g.Tanks[0].X, Y: g.Tanks[0].Y, Type: "laser", Age: 29.95, Life: .05}
	g.Pickups = []*Pickup{pickup}
	before := *pickup
	clearSurvivalWave427(t, r)
	for tick := 0; tick < 119; tick++ {
		g.step(1.0/60, [maxTanks]Input{}, r.Players)
		if len(g.Pickups) != 1 || g.Pickups[0] != pickup || *pickup != before {
			t.Fatalf("pickup changed during completed-wave hold at tick %d: %+v", tick, g.Pickups)
		}
	}
	for _, wire := range [][]Pickup{h.stateMessage(r)["pickups"].([]Pickup), h.stateWire(r).Pickups} {
		if len(wire) != 1 || wire[0].ID != pickup.ID || wire[0].Life != .05 || wire[0].Age != 29.95 {
			t.Fatalf("held pickup missing from online snapshot: %+v", wire)
		}
	}
	g.step(1.0/60, [maxTanks]Input{}, r.Players)
	if g.survivalState().Wave != 2 {
		t.Fatal("wave hold did not end at two seconds")
	}
	for _, current := range g.Pickups {
		if current == pickup || current.ID == pickup.ID {
			t.Fatal("old-maze pickup leaked into the new wave")
		}
	}
}

func TestSurvival436FinalScenesKeepPickupsFrozen(t *testing.T) {
	for _, won := range []bool{false, true} {
		t.Run(map[bool]string{false: "loss", true: "win"}[won], func(t *testing.T) {
			h, _, r := survivalRoom427(t, 1)
			g := r.Game
			g.Rules.ScoreTarget = 1
			g.startMatch(r.Players)
			g.Phase = "playing"
			pickup := &Pickup{ID: 900, X: g.Tanks[0].X, Y: g.Tanks[0].Y, Type: "laser", Age: 29.95, Life: .05}
			g.Pickups = []*Pickup{pickup}
			before := *pickup
			if won {
				clearSurvivalWave427(t, r)
			} else {
				g.Tanks[0].Alive = false
				g.stepSurvival(r.Players)
			}
			for tick := 0; tick < 180; tick++ {
				g.step(1.0/60, [maxTanks]Input{}, r.Players)
			}
			if len(g.Pickups) != 1 || g.Pickups[0] != pickup || *pickup != before {
				t.Fatal("final scene pickup disappeared or aged")
			}
			if len(h.stateWire(r).Pickups) != 1 {
				t.Fatal("final scene pickup missing from online snapshot")
			}
		})
	}
}
