package main

import (
	"encoding/json"
	"testing"
)

func TestFixedMazeKillerInDeathSnapshot(t *testing.T) {
	for _, tc := range []struct {
		name string
		kill func(g *Game, attacker, target *Tank)
	}{
		{"shell", func(g *Game, attacker, target *Tank) {
			g.fire(attacker)
			g.updateBullets(.5)
		}},
		{"grenade", func(g *Game, attacker, target *Tank) {
			g.detonate(&Bullet{Owner: attacker.ID, Kind: "grenade", X: target.X, Y: target.Y})
		}},
		{"laser", func(g *Game, attacker, target *Tank) {
			g.grantPower(attacker, "laser")
			g.fireLaser(attacker)
		}},
		{"Starman", func(g *Game, attacker, target *Tank) {
			target.X = attacker.X + attacker.R + target.R
			g.grantPower(attacker, "starman")
			g.step(tickDT, [maxTanks]Input{}, testPlayers(2))
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			g := battle(2)
			attacker, target := g.Tanks[0], g.Tanks[1]
			attacker.Name = "Rüst ★"
			tc.kill(g, attacker, target)
			if target.Alive {
				t.Fatal("attack did not destroy the target")
			}
			// A snapshot still has the callsign when the attacker has left.
			room, hub := &Room{Game: g}, &Hub{}
			room.clearCombatSeat(attacker.ID)
			wire := func() map[string]any {
				t.Helper()
				packet, ok := encodePacket(hub.stateWire(room))
				if !ok {
					t.Fatal("could not encode state")
				}
				var state struct {
					Tanks []map[string]any `json:"tanks"`
				}
				if err := json.Unmarshal(packet, &state); err != nil {
					t.Fatal(err)
				}
				if len(state.Tanks) != 1 || state.Tanks[0]["id"] != float64(target.ID) {
					t.Fatalf("expected only the victim in the snapshot: %+v", state.Tanks)
				}
				return state.Tanks[0]
			}
			if got := wire()["killedBy"]; got != attacker.Name {
				t.Fatalf("killedBy = %v, want %q", got, attacker.Name)
			}
			g.respawnTank(target)
			if !target.Alive {
				t.Fatal("target did not respawn")
			}
			if got, found := wire()["killedBy"]; found {
				t.Fatalf("respawn retained killedBy = %v", got)
			}
		})
	}
}
