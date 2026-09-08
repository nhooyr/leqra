package main

import (
	"math"
	"testing"
)

func Test49MachineGunUsesQuarterPerimeterRange(t *testing.T) {
	for _, size := range [][2]int{{7, 7}, {12, 10}, {16, 14}} {
		g := &Game{World: World{Cols: size[0], Rows: size[1], Width: float64(size[0]) * cellSize, Height: float64(size[1]) * cellSize}}
		want := (g.World.Width + g.World.Height) / 2
		if got := g.machineTravelRange(); math.Abs(got-want) > 1e-9 {
			t.Fatalf("%dx%d machine range %.6f want %.6f", size[0], size[1], got, want)
		}
	}
}

func Test49BotAvoidsGrenadeBodyWithoutFleeingBlastRadius(t *testing.T) {
	g := battle(2)
	bot := g.Tanks[0]
	bot.Bot = true
	bot.Difficulty = "easy" // Basic grenade avoidance applies even when projectile dodging is disabled.
	bot.X, bot.Y, bot.Angle = 100, 210, 0
	d := tuneBot(bot.Difficulty)

	// A grenade directly in the bot's planned driving line should change the command.
	g.Bullets = []*Bullet{{ID: 1, Owner: 1, Kind: "grenade", X: 158, Y: 210, R: 6, Life: 9}}
	a, drive := g.botAvoidGrenades(bot, d, 0, 1)
	if math.Abs(delta(0, a)) < .15 && drive > .25 {
		t.Fatalf("bot still headbutts stationary grenade: angle=%.3f drive=%.3f", a, drive)
	}

	// This grenade is well inside the 220-unit blast radius, but far off the
	// driving line. Avoiding the whole blast area would alter this command.
	g.Bullets = []*Bullet{{ID: 2, Owner: 1, Kind: "grenade", X: 180, Y: 330, R: 6, Life: 9}}
	a, drive = g.botAvoidGrenades(bot, d, 0, 1)
	if math.Abs(delta(0, a)) > 1e-9 || math.Abs(drive-1) > 1e-9 {
		t.Fatalf("bot fled grenade blast radius instead of just its body: angle=%.3f drive=%.3f", a, drive)
	}
}

func Test49BotAvoidsCrossingGrenade(t *testing.T) {
	g := battle(2)
	bot := g.Tanks[0]
	bot.Bot = true
	bot.Difficulty = "normal"
	bot.X, bot.Y, bot.Angle = 100, 210, 0
	d := tuneBot(bot.Difficulty)
	// The grenade crosses the bot's projected route during the avoidance horizon.
	g.Bullets = []*Bullet{{ID: 1, Owner: 1, Kind: "grenade", X: 155, Y: 160, VX: 0, VY: 115, R: 6, Life: 8}}
	a, drive := g.botAvoidGrenades(bot, d, 0, 1)
	if math.Abs(delta(0, a)) < .12 && drive > .3 {
		t.Fatalf("bot ignored crossing grenade: angle=%.3f drive=%.3f", a, drive)
	}
}

func Test49Version(t *testing.T) {
	if version != "4.24.0" {
		t.Fatalf("version=%q", version)
	}
}
