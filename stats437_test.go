package main

import "testing"

func TestStats437DepartedParticipantsKeepEarnedScores(t *testing.T) {
	for _, mode := range []string{"elimination", "ctf", "koth", "survival"} {
		for _, departure := range []string{"spectate", "leave", "swap"} {
			t.Run(mode+"/"+departure, func(t *testing.T) {
				h, clients, r := makeRoom(t, 3)
				g := r.Game
				g.Rules.Mode = mode
				if mode == "survival" {
					for _, p := range r.Players {
						if p != nil {
							p.Team = 1
						}
					}
				}
				g.startMatch(r.Players)
				g.Phase = "playing"
				departed := r.Players[1]
				row := g.stats.members[departed]
				g.Scores[departed.ID] = 3
				row.Eliminations = 7
				switch departure {
				case "leave":
					h.expirePlayer(r, departed.ID)
				case "spectate":
					r.moveMember(departed, r.viewerID(), true)
				case "swap":
					r.moveMember(departed, r.viewerID(), true)
					replacement := &Player{ID: 1, Member: 900, Name: "REPLACEMENT", Team: 1, Kind: "bot"}
					r.Players[1] = replacement
					r.initializeSeat(replacement, 3)
					g.Scores[1] = 4
				}
				g.finishMatchStats(clients[0].player.ID)
				result := g.matchReport.Players[row.ID-1]
				if result.Score != 3 || result.Active || result.Winner || result.Eliminations != 7 {
					t.Fatalf("departed participant lost earned score or inherited a replacement result: %+v", result)
				}
			})
		}
	}
}

func TestStats437SurvivalCheckpointKeepsDepartedScoreThroughRetry(t *testing.T) {
	_, _, r := survivalRoom427(t, 2)
	g := r.Game
	g.startMatch(r.Players)
	g.Phase = "playing"
	clearSurvivalWave427(t, r)
	departed := r.Players[1]
	r.moveMember(departed, r.viewerID(), true)
	g.prepareSurvival(survivalBreakSeconds, r.Players)
	g.Phase = "playing"
	g.endSurvival(r.Players, false)
	g.restartSurvivalWave(r.Players)
	g.Phase = "playing"
	g.endSurvival(r.Players, false)
	for _, row := range g.matchReport.Players {
		if row.Member == departed.Member {
			if row.Score != 1 || row.Active || row.Winner {
				t.Fatalf("retry erased departed participant's completed-wave score: %+v", row)
			}
			return
		}
	}
	t.Fatal("departed participant missing from the retried match")
}

func TestStats437ReturningParticipantUsesCurrentSeatScore(t *testing.T) {
	g, players := statsBattle("elimination", 3)
	r := &Room{Game: g, Players: players, NextViewerID: maxTanks}
	p := players[0]
	g.Scores[0] = 3
	r.moveMember(p, r.viewerID(), true)
	row := g.stats.members[p]
	if row.Score != 3 {
		t.Fatal("departure failed to preserve score")
	}
	r.moveMember(p, 3, false)
	r.initializeSeat(p, 1)
	g.finishMatchStats(1)
	result := g.matchReport.Players[row.ID-1]
	if result.Score != 1 || !result.Active || result.Seat != 3 {
		t.Fatalf("returned participant kept departed seat score: %+v", result)
	}
}
