package main

import (
	"testing"
	"time"
)

func TestRespawn438ReleasedDeadLifePressDoesNotFireOnRevival(t *testing.T) {
	for _, mode := range []string{"ctf", "koth"} {
		for _, kind := range []string{"primary", "local2"} {
			t.Run(mode+"/"+kind, func(t *testing.T) {
				h, clients, r := makeRoom(t, 2)
				g := r.Game
				g.Rules.Mode, g.Rules.PickupRate = mode, "off"
				player := r.Players[0]
				if kind == "local2" {
					h.configureRoom(clients[0], clientMessage{Type: "add", Kind: "local"}, time.Now())
					player = r.Players[2]
				}
				g.startMatch(r.Players)
				g.Phase = "playing"
				tank := g.Tanks[player.ID]
				tank.Alive, tank.RespawnTime = false, tickDT/2
				serial := tank.SpawnSerial
				// The press and release both reach the hub while this life is dead.
				// A live pilot's short tap must still survive the same tick batching.
				for _, packet := range []map[string]any{
					{"type": "input", "player": player.ID, "seq": 10, "fire": true},
					{"type": "input", "player": player.ID, "seq": 11, "fire": false},
				} {
					action(t, h, clients[0], packet)
				}
				action(t, h, clients[1], map[string]any{"type": "input", "seq": 20, "fire": true})
				action(t, h, clients[1], map[string]any{"type": "input", "seq": 21, "fire": false})
				if !player.FirePending || player.Input.Fire {
					t.Fatal("fixture did not latch a released press")
				}
				h.tick(time.Now())
				if !tank.Alive || tank.SpawnSerial != serial+1 {
					t.Fatal("tank did not revive")
				}
				for _, bullet := range g.Bullets {
					if bullet.Owner == player.ID {
						t.Fatal("press released before revival fired in the new life")
					}
				}
				if g.Tanks[1].ShotSerial != 1 {
					t.Fatal("revival discarded another living player's valid quick tap")
				}
				// A fresh new-life tap still works immediately afterward.
				action(t, h, clients[0], map[string]any{"type": "input", "player": player.ID, "seq": 12, "fire": true})
				action(t, h, clients[0], map[string]any{"type": "input", "player": player.ID, "seq": 13, "fire": false})
				h.tick(time.Now())
				if tank.ShotSerial != 1 {
					t.Fatal("fresh new-life press did not fire")
				}
			})
		}
	}
}

func TestRespawn438HeldControlsRemainUsableOnRevival(t *testing.T) {
	h, clients, r := makeRoom(t, 2)
	g := r.Game
	g.Rules.Mode, g.Rules.PickupRate = "koth", "off"
	g.startMatch(r.Players)
	g.Phase = "playing"
	tank := g.Tanks[0]
	spawnAngle := tank.Angle
	tank.Alive, tank.RespawnTime = false, tickDT/2
	action(t, h, clients[0], map[string]any{"type": "input", "seq": 10, "fire": true, "right": true})
	h.tick(time.Now())
	if !tank.Alive || tank.ShotSerial != 1 || tank.Ack != 10 {
		t.Fatal("revival discarded currently held fire or its acknowledgement")
	}
	if tank.Angle <= spawnAngle {
		t.Fatal("revival discarded currently held turning controls")
	}
}
