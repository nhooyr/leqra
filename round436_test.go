package main

import (
	"encoding/json"
	"testing"
)

func TestRound436SurvivalNewMazeAndBossCountdownFreezeProgress(t *testing.T) {
	_, _, r := survivalRoom427(t, 2)
	g := r.Game
	g.Rules.ScoreTarget = 15
	g.startMatch(r.Players)
	reachSurvivalWave433(t, r, 4)
	g.Phase = "playing"
	g.stats.duration = 12
	generation, walls := g.Generation, &g.World.Walls[0]
	clearSurvivalWave427(t, r)
	for tick := 1; tick < 120; tick++ {
		g.step(tickDT, [maxTanks]Input{{Forward: true, Fire: true}}, r.Players)
		if g.Generation != generation || &g.World.Walls[0] != walls || g.survivalState().Wave != 4 {
			t.Fatalf("maze advanced before hold at tick%d", tick)
		}
	}
	g.step(tickDT, [maxTanks]Input{}, r.Players)
	if g.Phase != "countdown" || g.PhaseTime != 3 || g.Generation != generation+1 || &g.World.Walls[0] == walls || g.survivalState().Wave != 5 || g.survivalState().WavesCleared != 4 {
		t.Fatal("missing next maze/countdown with preserved progress")
	}
	cp := g.survivalCheckpoint
	if cp.wave != 5 || cp.duration != 12 {
		t.Fatal("new wave checkpoint did not preserve earlier statistics")
	}
	var boss *Tank
	for _, tank := range g.Tanks {
		if tank != nil && tank.SurvivalBoss {
			boss = tank
		}
	}
	if boss == nil || boss.Power != "homing" || boss.ShieldCharges != 1 || g.Tanks[0].ShieldCharges < 1 || g.Tanks[1].ShieldCharges < 1 {
		t.Fatal("boss countdown missed starting equipment")
	}
	frozen, _ := json.Marshal(g.Tanks)
	world := &g.World.Walls[0]
	for tick := 1; tick < 180; tick++ {
		g.step(tickDT, [maxTanks]Input{{Forward: true, Fire: true}}, r.Players)
		now, _ := json.Marshal(g.Tanks)
		if g.Phase != "countdown" || string(now) != string(frozen) || g.Clock != 75 || g.stats.duration != 12 || &g.World.Walls[0] != world {
			t.Fatalf("countdown changed combat/progress at tick%d", tick)
		}
	}
	g.step(tickDT, [maxTanks]Input{}, r.Players)
	if g.Phase != "playing" || g.Clock != 75 || g.stats.duration != 12 || g.survivalCheckpoint != cp {
		t.Fatal("countdown did not release at exactly three seconds")
	}
}

func TestRound436AllModesStartWithThreeSecondCountdown(t *testing.T) {
	for _, mode := range []string{"elimination", "ctf", "koth", "survival"} {
		t.Run(mode, func(t *testing.T) {
			players := testPlayers(2)
			g := newGame(436)
			g.Rules.Mode = mode
			if mode == "survival" {
				players[0].Team = 1
				players[1].Team = 1
			} else if mode == "ctf" {
				players[0].Team = 1
				players[1].Team = 2
			}
			g.startMatch(players)
			if g.PhaseTime != 3 {
				t.Fatal("wrong countdown", g.PhaseTime)
			}
			for tick := 1; tick < 180; tick++ {
				g.step(tickDT, [maxTanks]Input{}, players)
				if g.Phase != "countdown" {
					t.Fatalf("started at tick%d", tick)
				}
			}
			g.step(tickDT, [maxTanks]Input{}, players)
			if g.Phase != "playing" {
				t.Fatal("countdown did not finish at tick180")
			}
		})
	}
}
