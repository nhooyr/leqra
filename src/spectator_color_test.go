package main

import "testing"

func TestSpectatorDefaultPaintSurvivesViewerIDAndNewCombatSeats(t *testing.T) {
	h, clients, r := makeRoom(t, 1)
	r.Game.Rules.TeamMode = "ffa"
	primary := clients[0].player
	primary.Team = 0
	action(t, h, clients[0], map[string]any{"type": "add", "kind": "local", "name": "WING", "team": 0})
	second := r.Players[1]
	if second == nil || second.Kind != "local" {
		t.Fatal("secondary tank was not added")
	}
	action(t, h, clients[0], map[string]any{"type": "spectate", "target": second.ID, "member": second.Member, "spectating": true})
	if second.ID != maxTanks || h.roomWire(r).Spectators[0].Color != tankColors[1] {
		t.Fatal("secondary inherited its viewer ID's paint instead of its tank paint")
	}
	role33(t, h, clients[0], true)
	for _, viewer := range h.roomWire(r).Spectators {
		want := tankColors[0]
		if viewer.Member == second.Member {
			want = tankColors[1]
		}
		if viewer.Color != want {
			t.Fatalf("spectator %s changed color: got %s, want %s", viewer.Name, viewer.Color, want)
		}
	}
	assertRoomWire443(t, h, r)
	if primary.ColorIndex != nil || second.ColorIndex != nil {
		t.Fatal("spectating converted automatic paint into an explicit selection")
	}
	// A later combat seat keeps its usual automatic paint; watching again captures
	// that new paint rather than retaining the first seat forever.
	r.moveMember(second, 3, false)
	if second.roomColor(r.Game.settings()) != tankColors[3] || second.spectatorColor != "" {
		t.Fatal("returning to combat retained stale spectator paint")
	}
	r.moveMember(second, r.viewerID(), true)
	if second.roomColor(r.Game.settings()) != tankColors[3] {
		t.Fatal("second role change failed to capture the current tank paint")
	}
}

func TestSpectatorPaintTracksExplicitSelectionAndTeamColor(t *testing.T) {
	h, clients, r := makeRoom(t, 1)
	r.Game.Rules.TeamMode = "ffa"
	primary := clients[0].player
	primary.Team = 0
	primary.ColorIndex = color44(5)
	role33(t, h, clients[0], true)
	if h.roomWire(r).Spectators[0].Color != tankColors[5] {
		t.Fatal("spectating discarded explicit paint")
	}
	action(t, h, clients[0], map[string]any{"type": "paint", "colorIndex": 6})
	if h.roomWire(r).Spectators[0].Color != tankColors[6] {
		t.Fatal("cached spectator paint overrode an updated selection")
	}
	r.Game.Rules.TeamMode = "teams"
	r.Game.Rules.TeamColors = []int{0, 7, 2, 3}
	primary.Team = 2
	if h.roomWire(r).Spectators[0].Color != tankColors[7] {
		t.Fatal("cached spectator paint overrode the current team color")
	}
	assertRoomWire443(t, h, r)
}
