package main

import (
	"encoding/json"
	"testing"
)

func TestPortraitMazeSwapsDimensionsWithoutChangingPickupDensity(t *testing.T) {
	for _, size := range sizeCases38 {
		t.Run(size.name, func(t *testing.T) {
			g := newGame(47)
			g.Rules.MapSize, g.Rules.PortraitMaze = size.name, true
			g.startMatch(testPlayers(maxTanks))

			w := g.World
			if w.Cols != size.rows || w.Rows != size.cols || w.Width != float64(size.rows)*cellSize || w.Height != float64(size.cols)*cellSize {
				t.Fatalf("world is %d × %d, want %d × %d", w.Cols, w.Rows, size.rows, size.cols)
			}
			if len(g.Pickups) != size.start || pickupCap(w.Cols, w.Rows) != size.cap {
				t.Fatalf("portrait map changed pickup density")
			}
			if len(g.Neighbors) != size.rows*size.cols {
				t.Fatal("maze navigation does not cover the portrait grid")
			}
		})
	}
}

func TestPortraitMazeSurvivalWaves(t *testing.T) {
	g := newGame(47)
	g.Rules.Mode, g.Rules.TeamMode, g.Rules.MapSize = "survival", "teams", "ultrawide"
	g.Rules.PortraitMaze = true
	players := testPlayers(2)
	g.startMatch(players)
	firstGeneration := g.Generation
	g.nextSurvivalWave(players)
	if g.Generation != firstGeneration+1 || g.World.Cols != 14 || g.World.Rows != 24 {
		t.Fatalf("expected a fresh portrait wave, got generation %d and %d × %d maze", g.Generation, g.World.Cols, g.World.Rows)
	}
}

func TestPortraitMazeIsHostOwnedAndBroadcast(t *testing.T) {
	h, clients, room := makeRoom(t, 2)
	host, guest := clients[0], clients[1]
	if room.Game.Rules.PortraitMaze {
		t.Fatal("new rooms must default to landscape")
	}
	rules := room.Game.Rules
	rules.MapSize, rules.PortraitMaze = "standard", true
	action(t, h, guest, map[string]any{"type": "rules", "rules": rules})
	if !hasError(guest, "not_host") || room.Game.Rules.PortraitMaze {
		t.Fatal("guest changed maze orientation")
	}
	action(t, h, host, map[string]any{"type": "rules", "rules": rules})
	if !room.Game.Rules.PortraitMaze {
		t.Fatal("host's maze orientation was not accepted")
	}
	packets := drain(guest)
	if len(packets) == 0 || packets[len(packets)-1]["type"] != "room" {
		t.Fatalf("guest did not receive room rules: %v", packets)
	}
	wireRules := packets[len(packets)-1]["rules"].(map[string]any)
	if wireRules["portraitMaze"] != true {
		t.Fatalf("guest received the wrong maze orientation: %v", wireRules)
	}
	readyAll(t, h, clients)
	action(t, h, host, map[string]any{"type": "start"})
	if room.Game.World.Cols != 8 || room.Game.World.Rows != 9 {
		t.Fatalf("online match used %d × %d", room.Game.World.Cols, room.Game.World.Rows)
	}

	var legacy MatchRules
	if err := json.Unmarshal([]byte(`{"mapSize":"standard"}`), &legacy); err != nil || legacy.PortraitMaze {
		t.Fatalf("legacy rules must default to landscape: %+v, %v", legacy, err)
	}
	if err := json.Unmarshal([]byte(`{"portraitMaze":"yes"}`), &legacy); err == nil {
		t.Fatal("non-boolean maze orientation was accepted")
	}
}
