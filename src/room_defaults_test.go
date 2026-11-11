package main

import "testing"

func TestNewOnlineRoomStartsWithOnlyItsPrimaryPilot(t *testing.T) {
	h := newHub(4)
	host := fakeClient()
	action(t, h, host, map[string]any{"type": "create", "name": "HOST"})
	if participantCount(host.room.Players) != 1 || playerKind(host.room.Players[host.room.Host]) != "human" {
		t.Fatal("new room contains more than its primary pilot")
	}
}

func TestSelectingFixedRulesAddsNormalOpponentsForALonePrimary(t *testing.T) {
	for _, mode := range []string{"elimination", "ctf", "koth", "survival"} {
		t.Run(mode, func(t *testing.T) {
			h, clients, r := makeRoom(t, 1)
			r.Game.Rules.Infinity = true
			rules := defaultRules()
			rules.Mode = mode
			if mode == "ctf" || mode == "survival" {
				rules.TeamMode = "teams"
			}
			action(t, h, clients[0], map[string]any{"type": "rules", "rules": rules})
			if participantCount(r.Players) != 4 || r.lineupError() != "" {
				t.Fatalf("fixed room is not playable: count=%d error=%q", participantCount(r.Players), r.lineupError())
			}
			for id, name := range []string{"RUST", "VAPOR", "EMBER"} {
				p := r.Players[id+1]
				if p == nil || p.Name != name || p.Kind != "bot" || p.Difficulty != "normal" || p.Owner != r.Host || p.Controller != clients[0].player || p.Member == 0 {
					t.Fatalf("invalid fallback bot: %+v", p)
				}
			}
			action(t, h, clients[0], map[string]any{"type": "rules", "rules": rules})
			if participantCount(r.Players) != 4 {
				t.Fatal("reapplying rules duplicated default bots")
			}
		})
	}
}

func TestFixedRuleFallbackPreservesCompanionsAndHumanCombatSeats(t *testing.T) {
	for _, scenario := range []string{"bot", "local", "spectating local", "human", "disconnected human"} {
		t.Run(scenario, func(t *testing.T) {
			h, clients, r := makeRoom(t, 1)
			if scenario == "human" || scenario == "disconnected human" {
				guest := fakeClient()
				action(t, h, guest, map[string]any{"type": "join", "code": r.Code, "name": "GUEST"})
				if scenario == "disconnected human" {
					guest.player.Client = nil
				}
			} else {
				kind := "local"
				if scenario == "bot" {
					kind = "bot"
				}
				action(t, h, clients[0], map[string]any{"type": "add", "kind": kind, "name": "EXISTING", "difficulty": "hard"})
				if scenario == "spectating local" {
					action(t, h, clients[0], map[string]any{"type": "spectate", "target": 1, "member": r.Players[1].Member, "spectating": true})
				}
			}
			r.Game.Rules.Infinity = true
			before := len(r.members())
			action(t, h, clients[0], map[string]any{"type": "rules", "rules": defaultRules()})
			if len(r.members()) != before {
				t.Fatal("fallback changed an existing party")
			}
		})
	}
}

func TestFixedRuleFallbackIgnoresSpectatorHumansAndHonorsHostAndPhase(t *testing.T) {
	h, clients, r := makeRoom(t, 1)
	watcher := fakeClient()
	action(t, h, watcher, map[string]any{"type": "join", "code": r.Code, "name": "WATCHER", "spectating": true})
	r.Game.Rules.Infinity = true
	action(t, h, watcher, map[string]any{"type": "rules", "rules": defaultRules()})
	if !hasError(watcher, "not_host") || participantCount(r.Players) != 1 {
		t.Fatal("spectator changed the room")
	}
	r.Game.Phase = "playing"
	action(t, h, clients[0], map[string]any{"type": "rules", "rules": defaultRules()})
	if !hasError(clients[0], "match_active") || participantCount(r.Players) != 1 {
		t.Fatal("active match gained fallback bots")
	}
	r.Game.Phase = "lobby"
	infinite := defaultRules()
	infinite.Infinity = true
	action(t, h, clients[0], map[string]any{"type": "rules", "rules": infinite})
	if participantCount(r.Players) != 1 {
		t.Fatal("Infinity gained fallback bots")
	}
	action(t, h, clients[0], map[string]any{"type": "rules", "rules": defaultRules()})
	if participantCount(r.Players) != 4 || len(r.Spectators) != 1 || watcher.player != r.Spectators[watcher.player.ID] {
		t.Fatal("spectators blocked fallback or changed identity")
	}
}

func TestFixedSoloPresetAddsFallbackOnlyWhenExitingInfinity(t *testing.T) {
	for _, infinity := range []bool{false, true} {
		h, clients, r := makeRoom(t, 1)
		r.Game.Rules.Infinity = infinity
		action(t, h, clients[0], map[string]any{"type": "preset", "rules": defaultRules(), "roster": []SeatSpec{{Name: "P1", Kind: "human"}}})
		want := 1
		if infinity {
			want = 4
		}
		if participantCount(r.Players) != want {
			t.Fatalf("Infinity=%v: preset has %d tanks, want %d", infinity, participantCount(r.Players), want)
		}
	}
}

func TestFixedRuleFallbackUsesCurrentHostAfterHandoff(t *testing.T) {
	h, clients, r := makeRoom(t, 2)
	action(t, h, clients[0], map[string]any{"type": "leave"})
	if r.Host != clients[1].player.ID || r.Host == 0 {
		t.Fatal("fixture did not transfer the host")
	}
	r.Game.Rules.Infinity = true
	rules := defaultRules()
	rules.TeamMode = "teams"
	action(t, h, clients[1], map[string]any{"type": "rules", "rules": rules})
	if participantCount(r.Players) != 4 || r.lineupError() != "" {
		t.Fatal("handed-off host did not get a valid fixed lineup")
	}
	for _, p := range r.Players {
		if p != nil && p.Kind == "bot" && (p.Owner != r.Host || p.Controller != clients[1].player) {
			t.Fatal("fallback bot retained the departed host")
		}
	}
}
