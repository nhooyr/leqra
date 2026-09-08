package main

import "testing"

func TestSurvival431DefeatedLineupStaysUntilNextWave(t *testing.T) {
	h, _, r := survivalRoom427(t, 2)
	g := r.Game
	g.startMatch(r.Players)
	g.Phase = "playing"
	defeated := map[int]*Tank{}
	for id, tank := range g.Tanks {
		if tank != nil && tank.SurvivalEnemy {
			defeated[id] = tank
		}
	}
	clearSurvivalWave427(t, r)
	g.prepareSurvival(3.9, r.Players)
	rows := 0
	for _, tank := range h.stateMessage(r)["tanks"].([]Tank) {
		if tank.SurvivalEnemy {
			rows++
			if tank.Alive || g.Tanks[tank.ID] != defeated[tank.ID] {
				t.Fatal("intermission replaced or revived defeated enemies")
			}
		}
	}
	if rows != len(defeated) || rows == 0 {
		t.Fatal("intermission snapshot lost lineup members")
	}
	g.prepareSurvival(.2, r.Players)
	if g.survivalState().Wave != 2 {
		t.Fatal("next wave did not start")
	}
	for id, prior := range defeated {
		if g.Tanks[id] == nil || g.Tanks[id] == prior || !g.Tanks[id].Alive || g.Tanks[id].SpawnSerial <= prior.SpawnSerial {
			t.Fatal("next wave did not atomically replace defeated enemy bodies")
		}
	}
}

func TestSurvival431BotSquadClearsRevivesAndWinsWithoutHuman(t *testing.T) {
	_, _, r := survivalRoom427(t, 2)
	for _, p := range r.Players {
		if p != nil {
			p.Kind = "bot"
			p.Client = nil
		}
	}
	g := r.Game
	g.Rules.ScoreTarget = 2
	g.startMatch(r.Players)
	g.Phase = "playing"
	g.Tanks[1].Alive = false
	clearSurvivalWave427(t, r)
	if g.survivalState().Status != "break" {
		t.Fatal("surviving bot could not clear the wave")
	}
	g.prepareSurvival(4, r.Players)
	if g.Phase != "playing" || g.survivalState().Wave != 2 || !g.Tanks[1].Alive {
		t.Fatal("bot squad did not revive for next wave")
	}
	clearSurvivalWave427(t, r)
	if g.Phase != "matchOver" || g.survivalState().Status != "won" || len(g.matchReport.Players) != 2 {
		t.Fatal("bot squad did not finish with squad-only results")
	}
	for _, row := range g.matchReport.Players {
		if !row.Winner || row.Score != 2 {
			t.Fatal("bot result lost earned progress")
		}
	}
}
