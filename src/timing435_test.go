package main

import "testing"

func TestTiming435EliminationRoundHoldIsExactlyTwoSeconds(t *testing.T) {
	for _, final := range []bool{false, true} {
		name := "next_round"
		if final {
			name = "final_result"
		}
		t.Run(name, func(t *testing.T) {
			players := testPlayers(2)
			g := newGame(435)
			g.Rules.TeamMode = "ffa"
			g.Rules.ScoreTarget = 2
			if final {
				g.Rules.ScoreTarget = 1
			}
			g.startMatch(players)
			g.Phase = "playing"
			generation := g.Generation
			g.finishRound(0)
			if g.PhaseTime != 2 {
				t.Fatalf("round-end hold = %v, want 2", g.PhaseTime)
			}
			for tick := 1; tick < 120; tick++ {
				g.step(tickDT, [maxTanks]Input{{Forward: true, Fire: true}}, players)
				if g.Phase != "roundOver" || g.Generation != generation {
					t.Fatalf("advanced at tick %d", tick)
				}
			}
			g.step(tickDT, [maxTanks]Input{}, players)
			if final {
				if g.Phase != "matchOver" || g.Generation != generation || g.Scores[0] != 1 {
					t.Fatalf("final hold did not finish at tick120: %s %v", g.Phase, g.PhaseTime)
				}
			} else if g.Phase != "countdown" || g.Generation != generation+1 || g.Round != 2 {
				t.Fatalf("next round did not start at tick120: %s %v", g.Phase, g.PhaseTime)
			}
		})
	}
}

func TestTiming435SurvivalBossBreakEndsAtTwoSeconds(t *testing.T) {
	_, _, r := survivalRoom427(t, 2)
	g := r.Game
	g.startMatch(r.Players)
	g.Phase = "playing"
	g.survivalState().Wave = 3
	g.survivalState().WavesCleared = 3
	g.nextSurvivalWave(r.Players)
	generation, walls := g.Generation, &g.World.Walls[0]
	clearSurvivalWave427(t, r)
	if s := g.survivalState(); s.BreakTime != 2 || s.Wave != 4 {
		t.Fatalf("unexpected boss preview break: %+v", s)
	}
	for tick := 1; tick < 120; tick++ {
		g.step(tickDT, [maxTanks]Input{{Fire: true}}, r.Players)
		if s := g.survivalState(); s.Status != "break" || s.Wave != 4 {
			t.Fatalf("boss spawned early at tick%d: %+v", tick, s)
		}
	}
	g.step(tickDT, [maxTanks]Input{}, r.Players)
	if s := g.survivalState(); s.Status != "wave" || s.Wave != 5 || !s.Boss {
		t.Fatalf("boss did not spawn at tick120: %+v", s)
	}
	if g.Generation != generation+1 || &g.World.Walls[0] == walls || g.Phase != "countdown" || g.PhaseTime != 3 {
		t.Fatal("Survival hold did not prepare the next maze countdown")
	}
}
