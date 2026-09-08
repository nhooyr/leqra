package main

import (
	"math"
	"testing"
)

func TestGodlikeKeepsSafeRoute427(t *testing.T) {
	g, bot := godlikeArena426()
	bot.X, bot.Y = 200, 200
	g.Bullets = []*Bullet{{Owner: 1, Kind: "bullet", X: 140, Y: 305, VX: 282, R: 3.5, Life: 1, Age: 1}}
	for _, drive := range []float64{0, .15, .65, 1} {
		angle, got := g.godlikeDodge(bot, tuneBot("godlike"), 0, drive)
		if angle != 0 || got != drive {
			t.Fatalf("unrelated passing round interrupted safe plan: %v, %v", angle, got)
		}
	}
}

func TestGodlikeCoopAdvancesWhileFiring427(t *testing.T) {
	g := battle(3)
	g.Pickups = nil
	g.Rules.TeamMode = "teams"
	bot, human, enemy := g.Tanks[0], g.Tanks[1], g.Tanks[2]
	bot.Difficulty, bot.Bot, bot.Team, human.Team, enemy.Team = "godlike", true, 1, 1, 2
	bot.X, bot.Y, human.X, human.Y, enemy.X, enemy.Y = 126, 210, 90, 150, 360, 210
	bot.AI = &BotState{Goal: -1, Target: -1, LastX: bot.X, LastY: bot.Y}
	reversals, previous, shots := 0, 1.0, 0
	for i := 0; i < 60; i++ {
		g.botControl(bot, tickDT)
		shots += len(g.Bullets)
		// Keep the target alive to measure engagement movement, not round resolution.
		g.Bullets = nil
		bot.Cooldown = math.Max(0, bot.Cooldown-tickDT)
		if bot.AI.Drive*previous < 0 {
			reversals++
		}
		previous = bot.AI.Drive
	}
	if bot.AI.Target != enemy.ID || bot.X < 180 || reversals != 0 {
		t.Fatalf("hesitant co-op attack: target=%d x=%v reversals=%d", bot.AI.Target, bot.X, reversals)
	}
	if shots == 0 {
		t.Fatal("never took an available shot")
	}
}

func TestGodlikeBankAimPersistsBetweenScans427(t *testing.T) {
	g, bot := godlikeArena426()
	bot.X, bot.Y = 100, 210
	enemy := g.Tanks[1]
	enemy.X, enemy.Y = 400, 210
	g.World.Walls = append(g.World.Walls, Wall{X: 248, Y: 170, W: 8, H: 80, Axis: "v", Line: 252})
	angle, ok := g.botAim(bot, enemy, tuneBot("godlike"))
	if !ok {
		t.Fatal("fixture has no usable bank shot")
	}
	for i := 0; i < 4; i++ {
		bot.AI.Bank -= .075
		again, valid := g.botAim(bot, enemy, tuneBot("godlike"))
		if !valid || angle != again {
			t.Fatalf("bank shot vanished between scans: angle=%v next=%v valid=%v", angle, again, valid)
		}
	}
	// Changing the target or weapon cannot reuse an unrelated cached solution.
	bot.Power = "scatter"
	if _, valid := g.botAim(bot, enemy, tuneBot("godlike")); valid {
		t.Fatal("cached shot survived weapon change")
	}
}

func TestGodlikeRetreatHysteresis427(t *testing.T) {
	g, bot := godlikeArena426()
	bot.X, bot.Y = 200, 210
	enemy := g.Tanks[1]
	enemy.X, enemy.Y = 250, 210
	g.botControl(bot, tickDT)
	if bot.AI.Drive >= 0 {
		t.Fatal("did not create close-range separation")
	}
	enemy.X = bot.X + 84
	bot.AI.Think = 0
	g.botControl(bot, tickDT)
	if bot.AI.Drive >= 0 {
		t.Fatal("retreat flipped at the initial trigger threshold")
	}
	enemy.X = bot.X + 110
	bot.AI.Think = 0
	g.botControl(bot, tickDT)
	if bot.AI.Drive <= 0 {
		t.Fatal("did not resume pressure once separated")
	}
}

func TestGodlikeCommitmentYieldsToImminentThreat427(t *testing.T) {
	g, bot := godlikeArena426()
	bot.X, bot.Y, bot.Angle = 300, 210, math.Pi/2
	bot.AI.DodgeTime, bot.AI.DodgeAngle, bot.AI.DodgeDrive = .25, math.Pi/2, 0
	g.Bullets = []*Bullet{{Owner: 1, Kind: "bullet", X: 200, Y: 210, VX: 282, R: 3.5, Life: 1, Age: 1}}
	angle, drive := g.godlikeDodge(bot, tuneBot("godlike"), math.Pi/2, 0)
	if angle == math.Pi/2 && drive == 0 {
		t.Fatal("old stationary commitment overruled imminent collision")
	}
}

func TestGodlikeRepositionsAfterUnproductiveAiming427(t *testing.T) {
	g, bot := godlikeArena426()
	bot.X, bot.Y = 100, 210
	enemy := g.Tanks[1]
	enemy.X, enemy.Y = 450, 210
	// A motionless attacker can still turn and aim, so wall-contact detection alone
	// cannot identify this stall. Progress is measured over time instead.
	for i := 0; i < 90; i++ {
		g.godlikeProgress(bot, enemy, tickDT)
	}
	if bot.AI.Advance <= 0 || bot.AI.RouteClock != 0 {
		t.Fatal("unproductive aiming never requested a fresh approach")
	}
	// Holding a scoring hill must not trigger the same recovery.
	bot.AI = &BotState{}
	g.Objectives = &ObjectiveState{Mode: "koth", HillX: bot.X, HillY: bot.Y, Radius: 32}
	for i := 0; i < 180; i++ {
		g.godlikeProgress(bot, enemy, tickDT)
	}
	if bot.AI.Advance > 0 {
		t.Fatal("intentional scoring hold mistaken for a stall")
	}
}

func TestGodlikeUsesSpawnProtectionAgainstReadyLaser427(t *testing.T) {
	g, bot := godlikeArena426()
	bot.Invulnerable = 2
	bot.X, bot.Y = 300, 210
	enemy := g.Tanks[1]
	enemy.X, enemy.Y, enemy.Power, enemy.Angle, enemy.Cooldown = 100, 210, "laser", 0, 0
	angle, drive := g.godlikeDodge(bot, tuneBot("godlike"), 0, .65)
	if angle != 0 || drive != .65 {
		t.Fatal("protected bot fled a harmless laser lane")
	}
	bot.Invulnerable = 0
	angle, drive = g.godlikeDodge(bot, tuneBot("godlike"), 0, .65)
	if angle == 0 && drive == .65 {
		t.Fatal("ignored the same laser after protection ended")
	}
}
