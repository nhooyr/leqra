package main

import (
	"bytes"
	"testing"
)

func TestClinchedResultSurvivesRoleChanges(t *testing.T) {
	for _, format := range []string{"ffa", "teams"} {
		for _, change := range []string{"spectate", "rejoin", "swap", "leave"} {
			t.Run(format+"/"+change, func(t *testing.T) {
				h, cs, r := makeRoom(t, 3)
				r.Game.Rules.TeamMode = format
				r.Game.Rules.ScoreTarget = 1
				for i, p := range r.Players {
					if p != nil {
						p.Team = 0
						if format == "teams" {
							p.Team = 1 + i/2
						}
					}
				}
				viewer := fakeClient()
				h.addClient(viewer)
				mmAction(t, h, viewer, map[string]any{"type": "join", "code": r.Code, "name": "REPLACEMENT", "spectating": true})
				winner, replacement := cs[0].player, viewer.player
				r.Game.startMatch(r.Players)
				r.Game.Phase = "playing"
				r.Game.finishRound(winner.ID)
				generation := r.Game.Generation
				frozen := append([]byte(nil), r.Game.matchReportWire...)
				if len(frozen) == 0 || r.Game.Phase != "roundOver" {
					t.Fatal("clinched result was not frozen during the round pause")
				}
				if h.stateMessage(r)["matchStats"] != nil || h.stateWire(r).MatchStats != nil {
					t.Fatal("match report was published before the result pause finished")
				}
				switch change {
				case "spectate", "rejoin":
					mmAction(t, h, cs[0], map[string]any{"type": "spectate", "spectating": true})
					if !winner.Spectating {
						t.Fatal("winner could not spectate during the result pause")
					}
					if change == "rejoin" {
						mmAction(t, h, cs[0], map[string]any{"type": "spectate", "spectating": false})
						if winner.Spectating {
							t.Fatal("winner could not reclaim an available seat")
						}
					}
				case "swap":
					mmAction(t, h, cs[0], map[string]any{"type": "swap", "target": winner.ID, "member": winner.Member, "spectator": replacement.ID, "spectatorMember": replacement.Member})
					if replacement.Spectating || !winner.Spectating {
						t.Fatal("winner and spectator were not exchanged")
					}
				case "leave":
					mmAction(t, h, cs[0], map[string]any{"type": "leave"})
					if r.contains(winner) {
						t.Fatal("winner did not leave the room")
					}
				}
				r.Game.step(2.8, [maxTanks]Input{}, r.Players)
				if r.Game.Phase != "matchOver" || r.Game.Round != 1 || r.Game.Generation != generation {
					t.Fatal("role change erased the clinched match or started another round")
				}
				if !bytes.Equal(frozen, r.Game.matchReportWire) {
					t.Fatal("role change mutated the announced match result")
				}
				winners := 0
				for _, row := range r.Game.matchReport.Players {
					if row.Member == replacement.Member {
						t.Fatal("replacement was credited with the finished match")
					}
					if row.Winner {
						winners++
						if row.Score != 1 || row.Member != winner.Member && (format != "teams" || row.Member != cs[1].player.Member) {
							t.Fatal("frozen winner identity or score is incorrect", row)
						}
					}
				}
				want := 1
				if format == "teams" {
					want = 2
				}
				if winners != want {
					t.Fatalf("got %d winners, want %d", winners, want)
				}
				wire, _ := encodePacket(h.stateWire(r))
				canonical, _ := encodePacket(h.stateMessage(r))
				if !bytes.Equal(wire, canonical) {
					t.Fatal("frozen report differs between snapshot encoders")
				}
				r.Game.startMatch(r.Players)
				if r.Game.roundClinched || r.Game.matchReport != nil {
					t.Fatal("previous result survived into the next match")
				}
			})
		}
	}
}

func TestNonfinalRoundWinnerCanLeaveBeforeNextRound(t *testing.T) {
	h, cs, r := makeRoom(t, 3)
	r.Game.Rules.TeamMode = "ffa"
	r.Game.Rules.ScoreTarget = 2
	for _, p := range r.Players {
		if p != nil {
			p.Team = 0
		}
	}
	r.Game.startMatch(r.Players)
	r.Game.Phase = "playing"
	r.Game.finishRound(cs[0].player.ID)
	mmAction(t, h, cs[0], map[string]any{"type": "spectate", "spectating": true})
	r.Game.step(2.8, [maxTanks]Input{}, r.Players)
	if r.Game.Phase != "countdown" || r.Game.Round != 2 || r.Game.Winner != -1 || r.Game.roundClinched || r.Game.matchReport != nil {
		t.Fatal("ordinary round winner departure prevented the next round")
	}
}

func TestClinchedQueueWinnerReturningDoesNotForfeitVictory(t *testing.T) {
	h := newHub(12)
	a, home := mmRoom(t, h, 1)
	b, _ := mmRoom(t, h, 1)
	mmQueue(t, h, a, "elimination-1")
	mmQueue(t, h, b, "elimination-1")
	mmScan(h)
	battle := a[0].room
	winnerID := a[0].player.ID
	battle.Game.Phase = "playing"
	battle.Game.Scores[winnerID] = battle.Game.settings().ScoreTarget - 1
	battle.Game.finishRound(winnerID)
	frozen := append([]byte(nil), battle.Game.matchReportWire...)
	mmAction(t, h, a[0], map[string]any{"type": "return_party"})
	if a[0].room != home || battle.Game.Phase != "roundOver" || battle.Game.Winner != winnerID {
		t.Fatal("returning winner forfeited the already-clinched game")
	}
	battle.Game.step(2.8, [maxTanks]Input{}, battle.Players)
	if battle.Game.Phase != "matchOver" || battle.Game.Winner != winnerID || !bytes.Equal(frozen, battle.Game.matchReportWire) {
		t.Fatal("delayed queued match result lost its original winner")
	}
}
