package main

import (
	"math"
	"testing"
)

func godlikeArena426() (*Game, *Tank) {
	g := battle(2)
	g.buildNavigation()
	g.Pickups = nil
	bot := g.Tanks[0]
	bot.Difficulty = "godlike"
	bot.Bot = true
	bot.X = 300
	bot.Y = 210
	bot.Angle = 0
	bot.Cooldown = 100
	bot.AI = &BotState{Goal: -1, Target: -1, LastX: bot.X, LastY: bot.Y}
	g.Tanks[1].X = 450
	g.Tanks[1].Y = 60
	return g, bot
}

func TestGodlikeDifficulty426(t *testing.T) {
	if !validDifficulty("godlike") || validDifficulty("Godlike") || validDifficulty("impossible") {
		t.Fatal("difficulty validation")
	}
	if err := validPresetRoster([]SeatSpec{{Kind: "human", Name: "Pilot"}, {Kind: "bot", Name: "Godlike", Difficulty: "godlike"}}); err != nil {
		t.Fatal(err)
	}
	hard, god := tuneBot("hard"), tuneBot("godlike")
	if god.speed != hard.speed || god.turn != hard.turn || god.think >= hard.think || god.reaction >= hard.reaction {
		t.Fatal("Godlike should improve decisions without extra movement speed")
	}
}

func TestGodlikeEscapesRemoteGrenadeBlast426(t *testing.T) {
	g, bot := godlikeArena426()
	bot.X = 260
	b := &Bullet{Owner: 1, Kind: "grenade", X: 110, Y: 210, R: 6, Life: 9, Age: 1}
	g.Bullets = []*Bullet{b}
	initial := dist(bot.X, bot.Y, b.X, b.Y)
	for i := 0; i < 60; i++ {
		a, v := g.godlikeDodge(bot, tuneBot("godlike"), 0, 0)
		diff := delta(bot.Angle, a)
		bot.Angle += clamp(diff, -4.3*tickDT, 4.3*tickDT)
		speed := 123 * v * math.Max(0, math.Cos(diff))
		g.moveTank(bot, math.Cos(bot.Angle)*speed*tickDT, math.Sin(bot.Angle)*speed*tickDT)
	}
	if r := dist(bot.X, bot.Y, b.X, b.Y); r < blastRadius+bot.R || r < initial+85 {
		t.Fatalf("did not escape blast: initial=%v final=%v", initial, r)
	}
}

func TestGodlikeRespectsGrenadeCover426(t *testing.T) {
	g, bot := godlikeArena426()
	bot.X = 260
	g.World.Walls = append(g.World.Walls, Wall{X: 210, Y: 0, W: 8, H: 420, Axis: "v", Line: 214})
	g.Bullets = []*Bullet{{Owner: 1, Kind: "grenade", X: 110, Y: 210, R: 6, Life: 9, Age: 1}}
	a, v := g.godlikeDodge(bot, tuneBot("godlike"), 0, 0)
	if a != 0 || v != 0 {
		t.Fatalf("fled safely covered grenade: %v %v", a, v)
	}
}

func TestGodlikeEscapesOwnFuse426(t *testing.T) {
	g, bot := godlikeArena426()
	bot.X = 260
	g.Bullets = []*Bullet{{Owner: bot.ID, Kind: "grenade", X: 65, Y: 210, R: 6, Life: .8, Age: 9.2}}
	for i := 0; i < 50 && bot.Alive; i++ {
		if i%4 == 0 {
			bot.AI.MoveAngle, bot.AI.Drive = g.godlikeDodge(bot, tuneBot("godlike"), 0, 0)
		}
		diff := delta(bot.Angle, bot.AI.MoveAngle)
		bot.Angle += clamp(diff, -4.3*tickDT, 4.3*tickDT)
		speed := 123 * bot.AI.Drive * math.Max(0, math.Cos(diff))
		g.moveTank(bot, math.Cos(bot.Angle)*speed*tickDT, math.Sin(bot.Angle)*speed*tickDT)
		g.updateBullets(tickDT)
	}
	if !bot.Alive || len(g.Bullets) != 0 {
		t.Fatal("bot failed to survive its expiring grenade")
	}
}

func TestGodlikeAvoidsSuicidalRemoteDetonation426(t *testing.T) {
	g, bot := godlikeArena426()
	bot.X = 90
	g.Tanks[1].X = 190
	g.Tanks[1].Y = 210
	g.Bullets = []*Bullet{{Owner: bot.ID, Kind: "grenade", X: 140, Y: 210, R: 6, Life: 9, Age: 1}}
	g.botControl(bot, tickDT)
	if !bot.Alive || g.Bullets[0].Dead {
		t.Fatal("Godlike remotely detonated its own lethal blast")
	}
	bot.X = 450
	bot.Y = 350
	if !g.godlikeCanDetonate(bot) {
		t.Fatal("did not identify safe exposed opponent")
	}
}

func TestGodlikeDetonationChecksAllOwnedGrenades426(t *testing.T) {
	g, bot := godlikeArena426()
	bot.X = 90
	g.Tanks[1].X = 450
	g.Tanks[1].Y = 210
	g.Bullets = []*Bullet{{Owner: bot.ID, Kind: "grenade", X: 425, Y: 210, R: 6, Life: 9, Age: 1}, {Owner: bot.ID, Kind: "grenade", X: 120, Y: 210, R: 6, Life: 9, Age: 1}}
	if g.godlikeCanDetonate(bot) {
		t.Fatal("a safe target grenade hid another grenade beside the bot")
	}
}

func TestGodlikeSeeksUsefulSafePowerups426(t *testing.T) {
	g, bot := godlikeArena426()
	bot.X = 210
	bot.Y = 210
	goal := g.Tanks[1]
	safe := &Pickup{X: 294, Y: 294, Type: "shield", Life: 20}
	unsafe := &Pickup{X: 42, Y: 210, Type: "cannon", Life: 20}
	g.Pickups = []*Pickup{unsafe, safe}
	g.Bullets = []*Bullet{{Owner: 1, Kind: "grenade", X: 42, Y: 210, R: 6, Life: 4, Age: 6}}
	if got := g.godlikePickup(bot, tuneBot("godlike"), goal, false); got != safe {
		t.Fatalf("selected dangerous or no pickup: %+v", got)
	}
	bot.Shield = 10
	bot.ShieldCharges = maxShieldCharges
	if got := g.godlikePickup(bot, tuneBot("godlike"), goal, false); got != nil {
		t.Fatal("chased an unneeded shield or dangerous weapon")
	}
}

func TestGodlikePickupChecksReachability426(t *testing.T) {
	g, bot := godlikeArena426()
	bot.X = 42
	bot.Y = 42
	for i := range g.Neighbors {
		g.Neighbors[i] = nil
	}
	g.Pickups = []*Pickup{{X: 126, Y: 42, Type: "shield", Life: 20}}
	if g.godlikePickup(bot, tuneBot("godlike"), g.Tanks[1], false) != nil {
		t.Fatal("selected unreachable pickup")
	}
}

func TestGodlikeCTFAndHillPriorities426(t *testing.T) {
	g, bot := godlikeArena426()
	bot.Team = 1
	g.Tanks[1].Team = 2
	g.Rules.TeamMode = "teams"
	g.Rules.Mode = "ctf"
	own := &Flag{Team: 1, HomeX: 42, HomeY: 378, X: 126, Y: 294, Carrier: -1}
	enemy := &Flag{Team: 2, HomeX: 462, HomeY: 42, X: bot.X, Y: bot.Y, Carrier: bot.ID}
	g.Objectives = &ObjectiveState{Mode: "ctf", Flags: []*Flag{own, enemy}}
	x, y, ok := g.godlikeObjective(bot)
	if !ok || x != own.X || y != own.Y {
		t.Fatal("carrier failed to return dropped friendly flag")
	}
	own.Home = true
	x, y, ok = g.godlikeObjective(bot)
	if !ok || x != own.HomeX || y != own.HomeY {
		t.Fatal("carrier failed to head home")
	}
	g.Pickups = []*Pickup{{X: bot.X + 10, Y: bot.Y, Type: "shield", Life: 20}}
	if g.godlikePickup(bot, tuneBot("godlike"), &Tank{X: x, Y: y}, true) != nil {
		t.Fatal("carrier abandoned flag goal for pickup")
	}
	g.Objectives = &ObjectiveState{Mode: "koth", HillX: bot.X, HillY: bot.Y, Radius: 32}
	x, y, ok = g.godlikeObjective(bot)
	if !ok || x != bot.X || y != bot.Y {
		t.Fatal("did not hold hill")
	}
	if g.godlikePickup(bot, tuneBot("godlike"), &Tank{X: x, Y: y}, true) != nil {
		t.Fatal("left scoring hill for pickup")
	}
	g.Objectives.SuddenDeath = true
	if _, _, ok = g.godlikeObjective(bot); ok {
		t.Fatal("continued objective during sudden death")
	}
}

func TestGodlikeGrenadeFireHasUsefulRange426(t *testing.T) {
	g, bot := godlikeArena426()
	bot.X = 60
	bot.Y = 210
	bot.Power = "grenade"
	bot.Charges = 3
	e := g.Tanks[1]
	e.X = 380
	e.Y = 210
	if _, ok := g.botAim(bot, e, tuneBot("godlike")); !ok {
		t.Fatal("Godlike never throws grenade at a safe target")
	}
	e.X = 190
	if _, ok := g.botAim(bot, e, tuneBot("godlike")); ok {
		t.Fatal("Godlike throws suicidal contact grenade")
	}
}

func TestGodlikeDodgesGuidedMissile426(t *testing.T) {
	simulate := func(dodge bool) bool {
		g, bot := godlikeArena426()
		g.World.Walls = append(g.World.Walls, Wall{X: 260, Y: 230, W: 8, H: 170, Axis: "v", Line: 264})
		bot.X = 300
		bot.Y = 210
		bot.Angle = math.Pi / 2
		g.Tanks[1].X = 450
		g.Tanks[1].Y = 370
		g.Bullets = []*Bullet{{Owner: 1, Kind: "homing", X: 100, Y: 210, VX: missileSpeed, R: 5, Life: 3, Age: .3, Target: bot.ID, RangeLeft: 500, rangeSet: true}}
		for i := 0; i < 130 && bot.Alive && len(g.Bullets) > 0; i++ {
			if i%4 == 0 && dodge {
				bot.AI.MoveAngle, bot.AI.Drive = g.godlikeDodge(bot, tuneBot("godlike"), bot.Angle, 0)
			}
			if dodge {
				diff := delta(bot.Angle, bot.AI.MoveAngle)
				bot.Angle += clamp(diff, -4.3*tickDT, 4.3*tickDT)
				speed := 123 * bot.AI.Drive * math.Max(0, math.Cos(diff))
				g.moveTank(bot, math.Cos(bot.Angle)*speed*tickDT, math.Sin(bot.Angle)*speed*tickDT)
			}
			g.updateBullets(tickDT)
		}
		return bot.Alive
	}
	if simulate(false) {
		t.Fatal("fixture missile does not threaten stationary tank")
	}
	if !simulate(true) {
		t.Fatal("Godlike failed to evade guided missile")
	}
}

func BenchmarkGodlikeEightBotsUltrawide426(b *testing.B) {
	g := newGame(426)
	g.Rules.MapSize = "ultrawide"
	players := testPlayers(maxTanks)
	for _, p := range players {
		p.Kind = "bot"
		p.Difficulty = "godlike"
	}
	g.startMatch(players)
	for _, t := range g.Tanks {
		t.Invulnerable = 0
		t.Cooldown = 100
		t.AI = &BotState{Goal: -1, Target: -1, LastX: t.X, LastY: t.Y}
	}
	for i := 0; i < 80; i++ {
		x, y := g.cellCenter((i * 13) % (g.World.Cols * g.World.Rows))
		kind := "rapid"
		speed := machineSpeed
		if i%10 == 0 {
			kind = "homing"
			speed = missileSpeed
		}
		if i%11 == 0 {
			kind = "grenade"
			speed = 0
		}
		g.Bullets = append(g.Bullets, &Bullet{Owner: i % maxTanks, Kind: kind, X: x, Y: y, VX: speed, R: 5, Life: 4, Age: 1, Target: -1})
	}
	for warm := 0; warm < 30; warm++ {
		for _, t := range g.Tanks {
			t.AI.Think = 0
			g.botControl(t, tickDT)
		}
	}
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		for _, t := range g.Tanks {
			t.AI.Think = 0
			g.botControl(t, tickDT)
		}
	}
}

func TestGodlikeGrenadeRejectsFriendlyContact426(t *testing.T) {
	g, bot := godlikeArena426()
	bot.X = 60
	bot.Y = 210
	bot.Team = 1
	bot.Power = "grenade"
	bot.Charges = 3
	enemy := g.Tanks[1]
	enemy.X = 380
	enemy.Y = 210
	enemy.Team = 2
	g.Tanks[2] = &Tank{ID: 2, Team: 1, X: 110, Y: 210, R: tankRadius, Alive: true, Invulnerable: 1}
	if g.godlikeSafeShot(bot, enemy, 0) {
		t.Fatal("grenade would hit a friendly tank beside its owner")
	}
}

func TestGodlikeLoneCarrierRecoversStolenFlag426(t *testing.T) {
	g, bot := godlikeArena426()
	bot.Team = 1
	g.Tanks[1].Team = 2
	own := &Flag{Team: 1, HomeX: 42, HomeY: 378, X: 450, Y: 60, Carrier: 1}
	enemy := &Flag{Team: 2, HomeX: 462, HomeY: 42, X: bot.X, Y: bot.Y, Carrier: bot.ID}
	g.Objectives = &ObjectiveState{Mode: "ctf", Flags: []*Flag{own, enemy}}
	x, y, ok := g.godlikeObjective(bot)
	if !ok || x != own.X || y != own.Y {
		t.Fatal("lone carrier camped home while its flag was stolen")
	}
}

func TestGodlikeForecastIncludesBoostedMovement426(t *testing.T) {
	g, bot := godlikeArena426()
	bot.X = 42
	bot.Y = 210
	g.Bullets = []*Bullet{{Owner: 1, Kind: "grenade", X: 460, Y: 210, R: 6, Life: 9, Age: 1}}
	d := tuneBot("godlike")
	d.speed *= 1 + boostSpeedPerStack*5
	threats, _ := g.godlikeForecast(bot, d)
	if len(threats) == 0 {
		t.Fatal("speed-boosted approach ignored reachable blast danger")
	}
}

func TestGodlikePredictionDoesNotMutateMatch426(t *testing.T) {
	g, bot := godlikeArena426()
	missile := &Bullet{Owner: 1, Kind: "homing", X: 100, Y: 210, VX: missileSpeed, R: 5, Life: 3, Age: .3, Target: bot.ID, RangeLeft: 500, rangeSet: true}
	g.Bullets = []*Bullet{missile}
	before := *missile
	x, y, angle := bot.X, bot.Y, bot.Angle
	ex, ey := g.Tanks[1].X, g.Tanks[1].Y
	g.godlikeDodge(bot, tuneBot("godlike"), 0, 0)
	if before != *missile || bot.X != x || bot.Y != y || bot.Angle != angle || g.Tanks[1].X != ex || g.Tanks[1].Y != ey {
		t.Fatal("speculative dodge mutated live physics")
	}
}

func TestGodlikeHoldsHillWhileAimingWithSpeedStacks426(t *testing.T) {
	g, bot := godlikeArena426()
	bot.SpeedStacks = maxSpeedStacks
	bot.SpeedTime = 10
	g.Objectives = &ObjectiveState{Mode: "koth", HillX: bot.X, HillY: bot.Y, Radius: 32}
	g.Tanks[1].X = bot.X + 60
	g.Tanks[1].Y = bot.Y
	x, y := bot.X, bot.Y
	for i := 0; i < 60; i++ {
		g.botControl(bot, tickDT)
	}
	if dist(x, y, bot.X, bot.Y) > .01 || bot.AI.Drive != 0 {
		t.Fatal("boosted Godlike abandoned uncontested hill to aim at close enemy")
	}
}

func TestGodlikeAnticipatesReadyLaser426(t *testing.T) {
	g, bot := godlikeArena426()
	bot.Angle = math.Pi / 2
	e := g.Tanks[1]
	e.X = 100
	e.Y = bot.Y
	e.Angle = 0
	e.Power = "laser"
	e.Cooldown = 0
	_, drive := g.godlikeDodge(bot, tuneBot("godlike"), bot.Angle, 0)
	if drive == 0 {
		t.Fatal("Godlike stood in a ready enemy laser's firing lane")
	}
}
