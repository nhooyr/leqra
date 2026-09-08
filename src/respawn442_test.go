package main

import (
	"testing"
	"time"
)

func TestRespawn442HeldControlsDoNotStopAfterFirstRevivalTick(t *testing.T) {
	for _, mode := range []string{"ctf", "koth"} {
		for _, kind := range []string{"primary", "local2"} {
			t.Run(mode+"/"+kind, func(t *testing.T) {
				h, clients, room := makeRoom(t, 2)
				g := room.Game
				g.Rules.Mode, g.Rules.PickupRate = mode, "off"
				player := room.Players[0]
				if kind == "local2" {
					h.configureRoom(clients[0], clientMessage{Type: "add", Kind: "local"}, time.Now())
					player = room.Players[2]
				}
				g.startMatch(room.Players)
				g.Phase = "playing"
				tank := g.Tanks[player.ID]
				tank.Alive, tank.RespawnTime = false, tickDT/2
				action(t, h, clients[0], map[string]any{"type": "input", "player": player.ID, "seq": 40, "right": true})
				now := time.Now()
				h.tick(now)
				if !tank.Alive || tank.Ack != 40 {
					t.Fatal("fixture did not revive under the held input")
				}
				angle := tank.Angle
				// No new network packet is needed to keep a key held. Its original
				// timeout remains valid, and acknowledgements must not go backwards.
				h.tick(time.Now())
				if tank.Angle <= angle || tank.Ack != 40 || tank.AckSteps != 2 {
					t.Fatalf("held turn stopped or acknowledgement reset after revival: angle %v -> %v, ack=%d steps=%d", angle, tank.Angle, tank.Ack, tank.AckSteps)
				}
				inputAt := player.InputAt
				action(t, h, clients[0], map[string]any{"type": "input", "player": player.ID, "seq": 39, "left": true})
				if player.Input.Seq != 40 || !player.Input.Right || player.Input.Left || player.InputAt != inputAt {
					t.Fatal("revival reopened the input sequence to a stale command")
				}
				angle = tank.Angle
				action(t, h, clients[0], map[string]any{"type": "input", "player": player.ID, "seq": 41, "right": true})
				h.tick(player.InputAt)
				if tank.Angle <= angle || tank.Ack != 41 {
					t.Fatal("fresh held input did not resume control")
				}
				angle = tank.Angle
				action(t, h, clients[0], map[string]any{"type": "input", "player": player.ID, "seq": 42})
				h.tick(player.InputAt)
				if tank.Angle != angle || tank.Ack != 42 {
					t.Fatal("fresh release did not stop the preserved held control")
				}
				action(t, h, clients[0], map[string]any{"type": "input", "player": player.ID, "seq": 43, "right": true})
				h.tick(player.InputAt)
				angle = tank.Angle
				h.tick(player.InputAt.Add(inputTimeout + time.Millisecond))
				if tank.Angle != angle || tank.Ack != 43 {
					t.Fatal("held input did not become neutral at its original timeout")
				}
			})
		}
	}
}
