package main

import (
	"math"
	"testing"
)

func ctfEscortArena429(level string, escorts int, corridor bool) (*Game, [maxTanks]*Player, *Flag) {
	g := battle(escorts + 2)
	ps := testPlayers(escorts + 2)
	g.Rules.Mode, g.Rules.TeamMode, g.Rules.ScoreTarget = "ctf", "teams", 20
	g.Pickups, g.SpawnClock = nil, 100
	for i := 0; i <= escorts; i++ {
		q := g.Tanks[i]
		q.Team, q.X, q.Y, q.Angle, q.Cooldown = 1, 126, 210, 0, 100
		ps[i].Team = 1
		if i > 0 {
			q.Bot, q.Difficulty = true, level
			ps[i].Kind, ps[i].Difficulty = "bot", level
			q.Y += float64(i-1) * 36
			q.AI = &BotState{Goal: -1, Target: -1, LastX: q.X, LastY: q.Y}
		}
	}
	carrier := g.Tanks[0]
	carrier.X, carrier.Angle = 378, math.Pi
	enemy := g.Tanks[escorts+1]
	enemy.Team, enemy.X, enemy.Y, enemy.Invulnerable = 2, 462, 42, 100
	ps[escorts+1].Team = 2
	own := &Flag{Team: 1, X: 126, Y: 210, HomeX: 126, HomeY: 210, Home: true, Carrier: -1}
	other := &Flag{Team: 2, X: carrier.X, Y: carrier.Y, HomeX: 462, HomeY: 42, Home: false, Carrier: 0}
	g.Objectives = &ObjectiveState{Mode: "ctf", Flags: []*Flag{own, other}}
	if corridor {
		g.World.Walls = append(g.World.Walls, Wall{X: 80, Y: 164, W: 8, H: 92, Axis: "v", Line: 84}, Wall{X: 80, Y: 164, W: 344, H: 8, Axis: "h", Line: 168}, Wall{X: 80, Y: 248, W: 344, H: 8, Axis: "h", Line: 252})
		for i := 1; i <= escorts; i++ {
			g.Tanks[i].X = 126 + float64(i-1)*40
			g.Tanks[i].Y = 210
		}
	}
	g.buildNavigation()
	return g, ps, own
}

func TestAllBotsClearCTFBaseForCarrier429(t *testing.T) {
	for _, level := range []string{"easy", "normal", "hard", "godlike"} {
		for _, human := range []bool{true, false} {
			for _, corridor := range []bool{false, true} {
				for _, escorts := range []int{1, 3} {
					t.Run(level+map[bool]string{true: "/human", false: "/bot"}[human]+map[bool]string{true: "/corridor", false: "/open"}[corridor]+string(rune('0'+escorts)), func(t *testing.T) {
						g, ps, _ := ctfEscortArena429(level, escorts, corridor)
						carrier := g.Tanks[0]
						if !human {
							carrier.Bot, carrier.Difficulty = true, level
							ps[0].Kind, ps[0].Difficulty = "bot", level
							carrier.AI = &BotState{Goal: -1, Target: -1, LastX: carrier.X, LastY: carrier.Y}
						}
						for i := 0; i < 600 && g.Scores[0] == 0; i++ {
							var in [maxTanks]Input
							if human {
								in[0] = Input{Forward: true}
							}
							g.step(tickDT, in, ps)
						}
						if g.Scores[0] == 0 {
							for i := 0; i <= escorts; i++ {
								q := g.Tanks[i]
								t.Logf("tank%d %.1f %.1f ai=%+v", i, q.X, q.Y, q.AI)
							}
							t.Fatal("carrier blocked from capture")
						}
					})
				}
			}
		}
	}
}

func TestCTFCoverPreservesFlagRecovery429(t *testing.T) {
	for _, level := range []string{"easy", "normal", "hard", "godlike"} {
		t.Run(level, func(t *testing.T) {
			g, ps, own := ctfEscortArena429(level, 1, false)
			own.Home, own.X, own.Y, own.ReturnIn = false, 210, 210, 20
			for i := 0; i < 600 && g.Scores[0] == 0; i++ {
				g.step(tickDT, [maxTanks]Input{{Forward: true}}, ps)
			}
			if !own.Home || g.Scores[0] == 0 {
				t.Fatal("support failed to return the dropped flag and clear the base")
			}
		})
	}
}

func TestCTFCoverCacheAndTeamScope429(t *testing.T) {
	g, _, home := ctfEscortArena429("godlike", 1, false)
	bot, carrier := g.Tanks[1], g.Tanks[0]
	x, y := g.ctfCoverGoal(bot, home, carrier)
	if dist(x, y, home.HomeX, home.HomeY) < 44 {
		t.Fatal("open base has no clearance")
	}
	g.Neighbors = nil // A cache hit must not rebuild or inspect the maze.
	for i := 0; i < 100; i++ {
		xx, yy := g.ctfCoverGoal(bot, home, carrier)
		if xx != x || yy != y || g.Neighbors != nil {
			t.Fatal("cover position was recalculated")
		}
	}
	g.Objectives.Flags[1].Carrier = -1
	_, _, ok := g.objectiveGoal(bot)
	if !ok {
		t.Fatal("dropped enemy flag lost as objective")
	}
	g.Objectives.SuddenDeath = true
	if _, _, ok = g.objectiveGoal(bot); ok {
		t.Fatal("CTF cover survives sudden death")
	}
}

func TestAllBotsVacateCTFCapturePoint429(t *testing.T) {
	for _, level := range []string{"easy", "normal", "hard", "godlike"} {
		t.Run(level, func(t *testing.T) {
			g, ps, home := ctfEscortArena429(level, 1, false)
			for i := 0; i < 150; i++ {
				g.step(tickDT, [maxTanks]Input{}, ps)
			}
			guard := g.Tanks[1]
			if dist(guard.X, guard.Y, home.HomeX, home.HomeY) < 44 {
				t.Fatalf("support occupies carrier's scoring area: %.1f, %.1f", guard.X, guard.Y)
			}
			for i := 0; i < 180 && g.Scores[0] == 0; i++ {
				g.step(tickDT, [maxTanks]Input{{Forward: true}}, ps)
			}
			if g.Scores[0] == 0 {
				t.Fatal("support moved back into the returning carrier")
			}
		})
	}
}

func TestBoostedAndGhostCTFSupport429(t *testing.T) {
	for _, level := range []string{"easy", "normal", "hard", "godlike"} {
		for _, power := range []string{"speed", "ghost"} {
			t.Run(level+"/"+power, func(t *testing.T) {
				g, ps, _ := ctfEscortArena429(level, 3, true)
				for i := 1; i <= 3; i++ {
					if power == "speed" {
						g.Tanks[i].SpeedTime, g.Tanks[i].SpeedStacks = 15, 5
					} else {
						g.Tanks[i].GhostTime = 15
					}
				}
				for i := 0; i < 600 && g.Scores[0] == 0; i++ {
					g.step(tickDT, [maxTanks]Input{{Forward: true}}, ps)
				}
				if g.Scores[0] == 0 {
					t.Fatal("powered support blocked carrier")
				}
			})
		}
	}
}

func BenchmarkCTFCoverSearch429(b *testing.B) {
	g, _, home := ctfEscortArena429("godlike", 3, false)
	bot, carrier := g.Tanks[1], g.Tanks[0]
	g.ctfCoverGoal(bot, home, carrier)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		bot.AI.ctfCoverClock = 0
		g.ctfCoverGoal(bot, home, carrier)
	}
}

func TestGodlikeCTFCoverKeepsDangerAvoidance429(t *testing.T) {
	g, _, home := ctfEscortArena429("godlike", 1, false)
	g.Tanks[0].X = 336
	bot := g.Tanks[1]
	bot.X, bot.Y = g.ctfCoverGoal(bot, home, g.Tanks[0])
	x, y := bot.X, bot.Y
	g.Pickups = []*Pickup{{ID: 1, Type: "shield", X: home.HomeX, Y: home.HomeY, Life: 30}}
	g.botControl(bot, tickDT)
	if g.cellAt(bot.AI.ctfCoverX, bot.AI.ctfCoverY) == g.cellAt(home.HomeX, home.HomeY) || bot.AI.Drive != 0 {
		t.Fatal("abandoned cover for a pickup")
	}
	g.Bullets = []*Bullet{{Owner: 2, X: bot.X + 65, Y: bot.Y, VX: -300, R: 3.5, Life: 3}}
	for i := 0; i < 30; i++ {
		g.botControl(bot, tickDT)
	}
	if dist(x, y, bot.X, bot.Y) < 2 {
		t.Fatal("cover hold prevented projectile avoidance")
	}
}
