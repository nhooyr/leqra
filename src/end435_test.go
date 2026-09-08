package main

import "testing"

func TestEnd435CallsignAutosaveThenEndCompletesWithOneLobbyAction(t *testing.T) {
	for _, phase := range []string{"playing", "roundOver", "countdown", "matchOver"} {
		t.Run(phase, func(t *testing.T) {
			h, clients, r := makeRoom(t, 2)
			r.Game.startMatch(r.Players)
			r.Game.Phase = phase
			r.Game.Scores[0] = 3
			for _, c := range clients {
				drain(c)
			}
			action(t, h, clients[0], map[string]any{"type": "rename", "name": "NEW CALLSIGN"})
			action(t, h, clients[0], map[string]any{"type": "lobby"})
			if r.Game.Phase != "lobby" || r.Game.Scores[0] != 0 || len(r.Game.Bullets) != 0 || len(r.Game.Pickups) != 0 || r.Players[0].Name != "NEW CALLSIGN" {
				t.Fatal("autosave prevented the first End match action from returning the room")
			}
			for _, c := range clients {
				lobbyStates := 0
				for _, message := range drain(c) {
					if message["type"] == "error" {
						t.Fatal("valid autosave/end sequence generated an error", message)
					}
					if message["type"] == "state" && message["phase"] == "lobby" {
						lobbyStates++
					}
				}
				if lobbyStates != 1 {
					t.Fatal("End must acknowledge the lobby once to each client", lobbyStates)
				}
			}
		})
	}
}

func TestEnd435CallsignAutosaveThenLeaveRemovesBothOwnedPilots(t *testing.T) {
	h, clients, r := makeRoom(t, 2)
	action(t, h, clients[0], map[string]any{"type": "add", "kind": "local"})
	var local *Player
	for _, p := range r.Players {
		if p != nil && p.Kind == "local" {
			local = p
		}
	}
	if local == nil {
		t.Fatal("fixture has no secondary pilot")
	}
	r.Game.startMatch(r.Players)
	r.Game.Phase = "playing"
	action(t, h, clients[0], map[string]any{"type": "rename_local", "target": local.ID, "member": local.Member, "name": "SECOND PILOT"})
	drain(clients[0])
	action(t, h, clients[0], map[string]any{"type": "leave"})
	if clients[0].room != nil || clients[0].player != nil || r.Players[0] != nil || r.Players[local.ID] != nil || r.Host != clients[1].player.ID {
		t.Fatal("first Leave action left the primary or secondary pilot in the room")
	}
	for _, id := range []int{0, local.ID} {
		if tank := r.Game.Tanks[id]; tank != nil && tank.Alive {
			t.Fatal("Leave retained a live tank owned by the departing controller")
		}
	}
	left := 0
	for _, message := range drain(clients[0]) {
		if message["type"] == "error" {
			t.Fatal("valid autosave/leave sequence generated an error", message)
		}
		if message["type"] == "left" {
			left++
		}
	}
	if left != 1 {
		t.Fatal("Leave must acknowledge the departing client once", left)
	}
}
