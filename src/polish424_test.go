package main

import (
	"reflect"
	"testing"
)

func Test424TeamAssignmentLifecycle(t *testing.T) {
	for _, mode := range []string{"elimination", "koth", "ctf"} {
		t.Run(mode, func(t *testing.T) {
			h, cs, r := makeRoom(t, 1)
			rules := defaultRules()
			rules.TeamMode, rules.Mode = "teams", mode
			action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
			count := 4
			if mode == "ctf" {
				count = 2
			}
			for i := 1; i < maxTanks; i++ {
				cs[0].actionCount = 0
				kind := "bot"
				if i == 1 {
					kind = "local"
				}
				// A stale default team sent by older callers must not skew assignment.
				action(t, h, cs[0], map[string]any{"type": "add", "kind": kind, "difficulty": "normal", "team": 1})
				if r.Players[i] == nil || r.Players[i].Team != 1+i%count {
					t.Fatalf("seat %d: %+v", i, r.Players[i])
				}
			}
		})
	}
}

func Test424SwitchingTeamCountBalancesAndOrdinaryEditsPreserve(t *testing.T) {
	h, cs, r := makeRoom(t, 8)
	rules := defaultRules()
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	check := func(count int) {
		t.Helper()
		for id, p := range r.Players {
			want := 0
			if count > 0 {
				want = 1 + id%count
			}
			if p.Team != want {
				t.Fatalf("seat %d team=%d want=%d", id, p.Team, want)
			}
		}
	}
	check(0)
	rules.TeamMode = "teams"
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	check(4)
	for _, c := range cs {
		c.player.Ready = true
	}
	rules.Mode = "ctf"
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	check(2)
	for _, c := range cs {
		if c.player.Ready {
			t.Fatal("roster change retained readiness")
		}
	}
	configureSeat(t, h, cs[0], r.Players[1], 1)
	rules.ScoreTarget = 7
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	if r.Players[1].Team != 1 {
		t.Fatal("unrelated rule edit reset manual teams")
	}
	rules.Mode = "koth"
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	check(4)
}

func Test424JoinUsesEmptyTeamsAndIgnoresSpectators(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	r.Players[0].Team, r.Players[1].Team = 1, 2
	watcher := fakeClient()
	action(t, h, watcher, map[string]any{"type": "join", "code": r.Code, "name": "WATCH", "spectating": true})
	if watcher.player == nil || !watcher.player.Spectating {
		t.Fatal("missing spectator")
	}
	watcher.player.Team = 3
	guest := fakeClient()
	action(t, h, guest, map[string]any{"type": "join", "code": r.Code, "name": "NEW"})
	if guest.player == nil || guest.player.Team != 3 {
		t.Fatal("new guest skipped empty Team 3")
	}
	action(t, h, watcher, map[string]any{"type": "spectate", "spectating": false})
	if watcher.player.Spectating || watcher.player.Team != 4 {
		t.Fatal("spectator did not fill Team 4")
	}
	configureSeat(t, h, cs[0], guest.player, 1)
	if next := joinTeam(r); next != 3 {
		t.Fatalf("empty side not reused: %d", next)
	}
}

func Test424CTFRejectsUnavailableTeamsAtomically(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	rules := r.Game.settings()
	rules.Mode = "ctf"
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	for _, team := range []int{0, 3, 4, 5, -1} {
		cs[0].actionCount = 0
		before := r.Players[1].Team
		action(t, h, cs[0], map[string]any{"type": "configure", "target": 1, "member": r.Players[1].Member, "team": team})
		if !hasError(cs[0], "bad_team") || r.Players[1].Team != before {
			t.Fatalf("accepted CTF team %d", team)
		}
		action(t, h, cs[0], map[string]any{"type": "add", "kind": "bot", "difficulty": "normal", "team": team})
		if !hasError(cs[0], "bad_team") || r.Players[2] != nil {
			t.Fatalf("added invalid CTF team %d", team)
		}
	}
	r.Players[1].Team = 3
	if r.Game.lineupError(r.Players) == "" {
		t.Fatal("invalid CTF lineup can start")
	}
}

func Test424LegacyCTFImportsMigrateWithoutMutatingInput(t *testing.T) {
	for _, operation := range []string{"publish", "preset"} {
		t.Run(operation, func(t *testing.T) {
			h := newHub(8)
			c := fakeClient()
			if operation == "preset" {
				action(t, h, c, map[string]any{"type": "create", "name": "HOST"})
			}
			rules := defaultRules()
			rules.TeamMode = "teams"
			rules.Mode = "ctf"
			roster := []SeatSpec{{Kind: "human", Name: "HOST", Team: 3}, {Kind: "local", Name: "P2", Team: 3}, {Kind: "bot", Name: "BOT", Team: 4, Difficulty: "normal"}, {Kind: "bot", Name: "BOT2", Team: 4, Difficulty: "normal"}}
			before := append([]SeatSpec{}, roster...)
			action(t, h, c, map[string]any{"type": operation, "rules": rules, "roster": roster})
			if c.room == nil {
				t.Fatalf("%s failed: %+v", operation, drain(c))
			}
			for i := 0; i < len(roster); i++ {
				if c.room.Players[i] == nil || c.room.Players[i].Team != 1+i%2 {
					t.Fatalf("unmigrated %s seat %d", operation, i)
				}
			}
			if !reflect.DeepEqual(before, roster) {
				t.Fatal("input roster changed")
			}
		})
	}
}

func Test424FFAAddsRemainIndependent(t *testing.T) {
	h, cs, r := makeRoom(t, 1)
	rules := defaultRules()
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	for i := 1; i < 4; i++ {
		action(t, h, cs[0], map[string]any{"type": "add", "kind": "bot", "difficulty": "normal"})
		if r.Players[i] == nil || r.Players[i].Team != 0 {
			t.Fatalf("FFA seat %d joined team", i)
		}
	}
}
