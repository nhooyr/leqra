package main

import (
	"math"
	"testing"
)

// Seeded head-to-head smoke runs validate the full decision/physics/objective
// integration. Outcomes are evidence, not a brittle claim that any bot must win.
func TestGodlikeModesSimulation426(t *testing.T) {
	for _, mode := range []string{"elimination", "ctf", "koth"} {
		scores := [2]int{}
		kills := [2]int{}
		deaths := [2]int{}
		captures := [2]int{}
		holds := [2]float64{}
		for seed := int64(426); seed < 429; seed++ {
			g := newGame(seed)
			g.Rules.Mode = mode
			g.Rules.TeamMode = "teams"
			g.Rules.MapSize = "compact"
			g.Rules.ScoreTarget = 20
			g.Rules.TimeLimit = 90
			if mode == "koth" {
				g.Rules.ScoreTarget = 120
			}
			ps := testPlayers(4)
			for i, p := range ps {
				if p == nil {
					continue
				}
				p.Kind = "bot"
				p.Team = 1 + i%2
				p.Difficulty = "hard"
				if i%2 == 0 {
					p.Difficulty = "godlike"
				}
			}
			g.startMatch(ps)
			for tick := 0; tick < 60*120 && g.Phase != "matchOver"; tick++ {
				g.step(tickDT, [maxTanks]Input{}, ps)
				for _, bot := range g.Tanks {
					if bot == nil {
						continue
					}
					if math.IsNaN(bot.X) || math.IsNaN(bot.Y) || math.IsInf(bot.Angle, 0) {
						t.Fatalf("%s seed%d invalid bot state", mode, seed)
					}
				}
			}
			scores[0] += g.Scores[0]
			scores[1] += g.Scores[1]
			for _, row := range g.stats.rows {
				i := row.Team - 1
				if i < 0 || i > 1 {
					continue
				}
				kills[i] += row.Eliminations
				deaths[i] += row.Deaths
				captures[i] += row.Captures
				holds[i] += row.HillSeconds
			}
		}
		t.Logf("%s: Godlike/Fierce scores %v, kills %v, deaths %v, captures %v, hill seconds %.1f/%.1f (3 seeds, up to120s each)", mode, scores, kills, deaths, captures, holds[0], holds[1])
	}
}
