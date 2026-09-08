package main

import "testing"

func TestAddBot445UsesNewestMemberInsteadOfHighestSeat(t *testing.T) {
	for _, tc := range []struct {
		name       string
		older      uint64
		newer      uint64
		difficulty string
	}{
		{name: "member order survives reused seats", older: 2, newer: 4, difficulty: "godlike"},
		{name: "legacy zero members use seat order", difficulty: "easy"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			h, clients, r := makeRoom(t, 1)
			r.Players[5] = &Player{ID: 5, Member: tc.older, Kind: "bot", Name: "OLDER", Difficulty: "easy"}
			r.Players[2] = &Player{ID: 2, Member: tc.newer, Kind: "bot", Name: "NEWER", Difficulty: "godlike"}
			// A newer human-controlled tank must not mask the last bot.
			r.Players[7] = &Player{ID: 7, Member: 5, Kind: "local", Name: "P2", Owner: 0, Controller: clients[0].player}
			r.NextMember = 5
			action(t, h, clients[0], map[string]any{"type": "add", "kind": "bot"})
			added := r.Players[1]
			if added == nil || added.Difficulty != tc.difficulty || added.Member != 6 {
				t.Fatalf("new bot = %+v, want member 6 with %s difficulty", added, tc.difficulty)
			}
		})
	}
}
