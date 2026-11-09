package main

import (
	"math"
	"testing"
)

func TestSimultaneousShotsAndPickupsRotateLiveSeatPriority(t *testing.T) {
	for _, pickup := range []bool{false, true} {
		for tick := 0; tick < 4; tick++ {
			g := battle(2)
			players := testPlayers(2)
			const second = 6
			g.Tanks[1].ID, players[1].ID = second, second
			g.Tanks[second], g.Tanks[1] = g.Tanks[1], nil
			players[second], players[1] = players[1], nil
			first, other := g.Tanks[0], g.Tanks[second]
			first.X, first.Y, first.Angle = 100, 100, 0
			other.X, other.Y, other.Angle = 140, 100, math.Pi
			g.Tick, g.Pickups = tick, nil
			var inputs [maxTanks]Input
			if pickup {
				g.Pickups = []*Pickup{{X: 120, Y: 100, Type: "shield", Life: 10}}
			} else {
				inputs[0] = Input{Fire: true, FirePressed: true}
				inputs[second] = inputs[0]
			}
			g.step(tickDT, inputs, players)
			want := 0
			if tick%2 == 0 {
				want = second
			}
			if pickup {
				if shieldCount(g.Tanks[want]) != 1 || shieldCount(g.Tanks[second-want]) != 0 || len(g.Pickups) != 0 {
					t.Fatalf("tick %d: expected seat %d to claim the shared pickup", tick, want)
				}
			} else if g.Winner != want {
				t.Fatalf("tick %d: simultaneous muzzle hits picked seat %d, want %d", tick, g.Winner, want)
			}
		}
	}
}

func TestFlagDroppedByPhasedCarrierCanBeReturnedImmediately(t *testing.T) {
	g := battle(2)
	players := testPlayers(2)
	players[0].Team, players[1].Team = 1, 2
	g.Tanks[0].Team, g.Tanks[1].Team = 1, 2
	g.Rules.Mode, g.Rules.TeamMode = "ctf", "teams"
	g.World.Walls = append(g.World.Walls, Wall{X: 80, Y: 80, W: 8, H: 84})
	carrier, defender := g.Tanks[0], g.Tanks[1]
	carrier.X, carrier.Y, carrier.GhostTime = 85, 126, 5
	defender.X, defender.Y = 106, 126
	flag := &Flag{Team: 2, X: carrier.X, Y: carrier.Y, HomeX: 378, HomeY: 42, Carrier: 0}
	g.Objectives = &ObjectiveState{Mode: "ctf", Flags: []*Flag{{Team: 1, Home: true, Carrier: -1}, flag}}
	g.hurt(carrier, &Bullet{Owner: 1, Kind: "cannon"})
	if carrier.Alive || carrier.X != 85 || flag.Home || flag.Carrier != -1 || !g.clearTankAt(flag.X, flag.Y, tankRadius) {
		t.Fatalf("expected flag to leave the wall without moving the carrier: %+v", flag)
	}
	g.stepObjectives(tickDT, players)
	if !flag.Home || flag.X != flag.HomeX || flag.Y != flag.HomeY {
		t.Fatalf("defender could not return dropped flag: %+v", flag)
	}
}
