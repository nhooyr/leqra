package main

import "testing"

func TestQueuedRematchRequiresEveryControllerAndPreservesReservations(t *testing.T) {
	h := newHub(12)
	a, homeA := mmRoom(t, h, 1)
	b, homeB := mmRoom(t, h, 1)
	mmQueue(t, h, a, "elimination-1")
	mmQueue(t, h, b, "elimination-1")
	mmScan(h)
	battle := a[0].room
	if battle == nil || battle != b[0].room || battle.Match == nil {
		t.Fatal("1v1 matchmaking battle was not created")
	}
	battle.Game.Phase = "matchOver"
	battle.Game.Scores[0] = 4
	battle.Game.Scores[1] = 2
	generation := battle.Game.Generation
	drain(a[0])
	drain(b[0])

	mmAction(t, h, a[0], map[string]any{"type": "rematch"})
	if battle.Game.Phase != "matchOver" || battle.Game.Generation != generation {
		t.Fatal("one rematch vote restarted a hostless queue match")
	}
	if battle.Match.Rematch == nil || !battle.Match.Rematch[a[0].player.Member] {
		t.Fatal("first rematch vote was not retained")
	}
	room := h.roomMessage(battle)
	players := room["players"].([]map[string]any)
	seenVote := false
	for _, p := range players {
		if p["member"] == a[0].player.Member {
			seenVote = p["rematch"] == true
		}
	}
	if !seenVote {
		t.Fatal("rematch readiness is not exposed to the requesting client")
	}

	mmAction(t, h, b[0], map[string]any{"type": "rematch"})
	if battle.Game.Phase != "countdown" || battle.Game.Generation <= generation {
		t.Fatal("unanimous rematch did not start a fresh countdown")
	}
	if battle.Match.Rematch != nil {
		t.Fatal("rematch votes survived into the restarted match")
	}
	if battle.Game.Scores[0] != 0 || battle.Game.Scores[1] != 0 {
		t.Fatal("rematch did not reset matchmaking scores")
	}
	if a[0].player.Return == nil || b[0].player.Return == nil || !homeA.hasAway() || !homeB.hasAway() {
		t.Fatal("rematch lost private-party return reservations")
	}

	// Once one controller chooses BACK TO ROOM, the old battle cannot be restarted
	// around them by a remaining player.
	battle.Game.Phase = "matchOver"
	mmAction(t, h, a[0], map[string]any{"type": "return_party"})
	if a[0].room != homeA || homeA.hasAway() {
		t.Fatal("result BACK TO ROOM semantics did not restore the original party")
	}
	drain(b[0])
	mmAction(t, h, b[0], map[string]any{"type": "rematch"})
	if !hasError(b[0], "lineup_changed") {
		t.Fatal("remaining player could rematch after an opponent returned to their room")
	}
	if b[0].room != battle || battle.Game.Phase != "matchOver" {
		t.Fatal("failed rematch request mutated the remaining battle")
	}
}

func TestPickupLifetimeUsesEightThirdsGroundExpiry(t *testing.T) {
	cases := []struct {
		cols, rows int
		want       float64
	}{
		{7, 7, 30},
		{9, 8, 30},
		{12, 10, 32},
		{14, 12, 45},
		{16, 14, 61},
		{24, 14, 90},
	}
	for _, tc := range cases {
		if got := pickupLifetime(tc.cols, tc.rows); got != tc.want {
			t.Fatalf("pickup lifetime %dx%d = %v, want %v", tc.cols, tc.rows, got, tc.want)
		}
	}
}
