package main

import (
	"math"
	"testing"
)

func botGoalArena428(level string) (*Game, *Tank, [maxTanks]*Player) {
	g := battle(2)
	ps := testPlayers(2)
	ps[0].Kind, ps[0].Difficulty, ps[0].Team, ps[1].Team = "bot", level, 1, 2
	g.Rules.TeamMode, g.Rules.ScoreTarget = "teams", 20
	g.Pickups, g.SpawnClock = nil, 100
	bot, enemy := g.Tanks[0], g.Tanks[1]
	bot.Bot, bot.Difficulty, bot.Team = true, level, 1
	bot.X, bot.Y, bot.Angle, bot.Cooldown = 170, 180, math.Atan2(30, 40), 100
	bot.AI = &BotState{Goal: -1, Target: -1, LastX: bot.X, LastY: bot.Y}
	enemy.Team, enemy.X, enemy.Y, enemy.Invulnerable = 2, 462, 378, 100
	g.buildNavigation()
	return g, bot, ps
}

func TestBotsFinishObjectiveApproach428(t *testing.T) {
	for _, level := range []string{"easy", "normal", "hard", "godlike"} {
		for _, kind := range []string{"flag", "dropped flag", "base", "hill"} {
			t.Run(level+"/"+kind, func(t *testing.T) {
				g, bot, ps := botGoalArena428(level)
				own := &Flag{Team: 1, X: 42, Y: 42, HomeX: 42, HomeY: 42, Home: true, Carrier: -1}
				other := &Flag{Team: 2, X: 210, Y: 210, HomeX: 210, HomeY: 210, Home: true, Carrier: -1}
				g.Rules.Mode = "ctf"
				g.Objectives = &ObjectiveState{Mode: "ctf", Flags: []*Flag{own, other}}
				switch kind {
				case "dropped flag":
					own.Home = false
					own.X = 239
					own.Y = 215
					own.ReturnIn = 20
				case "base":
					own.X = 210
					own.Y = 210
					own.HomeX = 210
					own.HomeY = 210
					other.Home = false
					other.Carrier = bot.ID
				case "hill":
					g.Rules.Mode = "koth"
					g.Objectives = &ObjectiveState{Mode: "koth", Flags: []*Flag{}, HillX: 210, HillY: 210, Radius: 32}
				}
				success := false
				for i := 0; i < 360; i++ {
					g.step(tickDT, [maxTanks]Input{}, ps)
					switch kind {
					case "flag":
						success = other.Carrier == bot.ID
					case "dropped flag":
						success = own.Home
					case "base", "hill":
						success = g.Scores[bot.ID] > 0
					}
					if success {
						break
					}
				}
				if !success {
					t.Fatalf("stalled before %s at %.2f, %.2f; path=%v drive=%v", kind, bot.X, bot.Y, bot.AI.Path, bot.AI.Drive)
				}
			})
		}
	}
}

func TestGodlikeCollectsPickupBeforeFighting428(t *testing.T) {
	g, bot, ps := botGoalArena428("godlike")
	// A nearby available shot must not pull the tank away from its final approach.
	g.Tanks[1].X, g.Tanks[1].Y, g.Tanks[1].Invulnerable = 360, 210, 0
	g.Pickups = []*Pickup{{ID: 1, X: 210, Y: 210, Type: "shield", Life: 30}}
	for i := 0; i < 120 && bot.Shield <= 0; i++ {
		g.step(tickDT, [maxTanks]Input{}, ps)
	}
	if bot.Shield <= 0 {
		t.Fatalf("never collected nearby shield: %.2f, %.2f", bot.X, bot.Y)
	}
}

func TestBotsHoldScoringHillUnderFireOpportunity428(t *testing.T) {
	for _, level := range []string{"easy", "normal", "hard", "godlike"} {
		t.Run(level, func(t *testing.T) {
			g, bot, ps := botGoalArena428(level)
			bot.X, bot.Y, bot.Angle = 210, 210, 0
			g.Tanks[1].X, g.Tanks[1].Y, g.Tanks[1].Invulnerable = 270, 210, 0
			g.Rules.Mode = "koth"
			g.Objectives = &ObjectiveState{Mode: "koth", Flags: []*Flag{}, HillX: 210, HillY: 210, Radius: 32}
			for i := 0; i < 180; i++ {
				g.step(tickDT, [maxTanks]Input{}, ps)
			}
			if g.Scores[bot.ID] < 2 || dist(bot.X, bot.Y, 210, 210) > 29 {
				t.Fatalf("abandoned scoring hill to adjust shooting range: score=%d x=%v y=%v", g.Scores[bot.ID], bot.X, bot.Y)
			}
		})
	}
}

func TestBotShortcutCannotReturnToSkippedWaypoint428(t *testing.T) {
	g, bot, _ := botGoalArena428("godlike")
	bot.X, bot.Y, bot.Angle = 42, 294, math.Pi/2
	bot.AI = &BotState{Goal: 24, Target: -1, Path: []int{0, 6, 12, 18, 24}, RouteClock: 1, LastX: bot.X, LastY: bot.Y}
	g.Objectives = &ObjectiveState{Mode: "koth", Flags: []*Flag{}, HillX: 42, HillY: 378, Radius: 32}
	g.botControl(bot, tickDT)
	if math.Abs(delta(bot.AI.MoveAngle, math.Pi/2)) > .01 || bot.AI.Drive <= 0 {
		t.Fatalf("turned away from the final approach: angle=%v drive=%v path=%v", bot.AI.MoveAngle, bot.AI.Drive, bot.AI.Path)
	}
}

func TestBotsNavigateAroundWallToFlag428(t *testing.T) {
	for _, level := range []string{"easy", "normal", "hard", "godlike"} {
		t.Run(level, func(t *testing.T) {
			g, bot, ps := botGoalArena428(level)
			bot.X, bot.Y, bot.Angle = 126, 210, 0
			g.World.Walls = append(g.World.Walls, Wall{X: 164, Y: -4, W: 8, H: 260, Axis: "v", Line: 168})
			g.buildNavigation()
			own := &Flag{Team: 1, X: 42, Y: 42, HomeX: 42, HomeY: 42, Home: true, Carrier: -1}
			other := &Flag{Team: 2, X: 210, Y: 210, HomeX: 210, HomeY: 210, Home: true, Carrier: -1}
			g.Rules.Mode = "ctf"
			g.Objectives = &ObjectiveState{Mode: "ctf", Flags: []*Flag{own, other}}
			for i := 0; i < 900 && other.Carrier != bot.ID; i++ {
				g.step(tickDT, [maxTanks]Input{}, ps)
			}
			if other.Carrier != bot.ID {
				t.Fatalf("never rounded wall to flag: %.2f, %.2f path=%v", bot.X, bot.Y, bot.AI.Path)
			}
		})
	}
}

func TestBoostedBotsFinishObjectiveApproach428(t *testing.T) {
	for _, level := range []string{"easy", "normal", "hard", "godlike"} {
		t.Run(level, func(t *testing.T) {
			g, bot, ps := botGoalArena428(level)
			bot.SpeedStacks, bot.SpeedTime = 5, 15
			g.Rules.Mode = "koth"
			g.Objectives = &ObjectiveState{Mode: "koth", Flags: []*Flag{}, HillX: 210, HillY: 210, Radius: 32}
			for i := 0; i < 360 && g.Scores[bot.ID] == 0; i++ {
				g.step(tickDT, [maxTanks]Input{}, ps)
			}
			if g.Scores[bot.ID] == 0 {
				t.Fatalf("fully boosted bot overshot hill without scoring: %.2f, %.2f", bot.X, bot.Y)
			}
		})
	}
}
