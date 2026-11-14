package main

import (
	"fmt"
	"math"
	"testing"
	"time"
)

func fillRoamingBots(a *infiniteArena) {
	for range infiniteBotsPerPlayer + 1 {
		a.tick = a.nextBot
		a.populate()
	}
}

func roamingBots(a *infiniteArena) []*infinitePilot {
	var bots []*infinitePilot
	for _, p := range a.pilots {
		if p.Bot && p.roomBot == nil {
			bots = append(bots, p)
		}
	}
	return bots
}

func TestPublicInfinityRoamingBotsUseDumbAndPrivateSettingsStillApply(t *testing.T) {
	now := time.Unix(0, 0)
	public := newSeededInfiniteArena(37)
	pilot := public.join(fakeClient(), "PILOT", now)
	fillRoamingBots(public)
	if len(roamingBots(public)) == 0 {
		t.Fatal("public population did not spawn")
	}
	for _, bot := range roamingBots(public) {
		if infiniteBotTunings[bot.botLevel].name != "dumb" {
			t.Fatal("public roaming bot was not Dumb")
		}
	}
	public.suspend(pilot)
	if reason := public.resume(fakeClient(), pilot, 0, now.Add(time.Second)); reason != "" {
		t.Fatal(reason)
	}
	fillRoamingBots(public)
	for _, bot := range roamingBots(public) {
		if infiniteBotTunings[bot.botLevel].name != "dumb" {
			t.Fatal("pooled public bot lost its Dumb difficulty")
		}
	}
	for _, difficulty := range []string{"dumb", "easy", "normal", "hard", "godlike"} {
		rules := defaultRules()
		rules.InfinityRandomBots, rules.InfinityBotDifficulty = true, difficulty
		private := newRoomInfiniteArena(rules, nil)
		private.join(fakeClient(), "PILOT", now)
		fillRoamingBots(private)
		if len(roamingBots(private)) == 0 {
			t.Fatal("private roaming population did not spawn")
		}
		for _, bot := range roamingBots(private) {
			if infiniteBotTunings[bot.botLevel].name != difficulty {
				t.Fatalf("private %s bot setting was overridden", difficulty)
			}
		}
	}
}

func TestInfiniteRoamingBudgetCountsConnectedSeatsAndKeepsStableNumbers(t *testing.T) {
	a := newSeededInfiniteArena(37)
	now := time.Unix(0, 0)
	primary, local := a.joinSeats(fakeClient(), infiniteSeat{name: "P1"}, &infiniteSeat{name: "P2"}, 0, now)
	fillRoamingBots(a)
	bots := roamingBots(a)
	if len(bots) != 32 {
		t.Fatalf("two connected seats have %d roaming bots, want 32", len(bots))
	}
	for i, bot := range bots {
		if bot.Name != fmt.Sprintf("Bot %d", i+1) || bot.ID <= local.ID {
			t.Fatal("bot labels share the monotonic human/owner ID counter")
		}
	}
	dead := bots[16]
	dead.HP, dead.Score, dead.respawn = 0, -7, a.tick+60
	a.removeLocal(primary)
	if len(roamingBots(a)) != 16 || len(a.inactiveBots) != 16 || a.players != 1 || a.connected != 1 {
		t.Fatal("removing P2 did not immediately trim to sixteen roaming bots")
	}
	a.join(fakeClient(), "Replacement", now)
	lastID := a.nextID
	a.nextBot = a.tick
	a.populate()
	if a.pilotByID(dead.ID) != dead || dead.HP != 0 || dead.Score != -7 || dead.respawn != a.tick+60 || a.nextID != lastID {
		t.Fatal("reusing the first pooled identity lost its death deadline, score, or owner ID")
	}
	fillRoamingBots(a)
	if len(roamingBots(a)) != 32 || len(a.inactiveBots) != 0 || a.nextID != lastID {
		t.Fatal("growing the budget allocated replacements instead of reusing the pool")
	}
	a.join(fakeClient(), "Third", now)
	fillRoamingBots(a)
	if len(roamingBots(a)) != 48 {
		t.Fatal("three connected seats did not receive sixteen roaming bots each")
	}
	a.join(fakeClient(), "Fourth", now)
	fillRoamingBots(a)
	if len(roamingBots(a)) != 64 {
		t.Fatal("four connected seats were restricted by an old global ceiling")
	}
}

func TestInfiniteRoamingRelocationPreservesVisibleAndDistantIdentities(t *testing.T) {
	a := newSeededInfiniteArena(37)
	p := a.join(fakeClient(), "P1", time.Unix(0, 0))
	fillRoamingBots(a)
	bot := roamingBots(a)[0]
	bot.Score = 12
	id, spawn, name, nextID := bot.ID, bot.Spawn, bot.Name, a.nextID
	for _, offset := range [][2]float64{{14 * cellSize, 0}, {15 * cellSize, 15 * cellSize}} {
		bot.X, bot.Y = p.X+offset[0], p.Y+offset[1]
		a.tick = a.nextBot
		a.populate()
		if bot.Spawn != spawn || bot.X != p.X+offset[0] || bot.Y != p.Y+offset[1] {
			t.Fatal("bot relocated within a connected view's safety margin")
		}
	}
	bot.X, bot.Y = p.X+17*cellSize, p.Y
	a.tick = a.nextBot
	a.populate()
	if bot.ID != id || bot.Name != name || bot.Score != 12 || bot.Spawn != spawn+1 || a.nextID != nextID || math.Hypot(bot.X-p.X, bot.Y-p.Y) > 7*cellSize {
		t.Fatal("off-screen relocation replaced the bot or lost its score")
	}
}

func TestInfiniteRoamingRetiresFarLivesAndWaitsForLiveConnectedAnchor(t *testing.T) {
	a := newSeededInfiniteArena(37)
	now := time.Unix(0, 0)
	p := a.join(fakeClient(), "P1", now)
	reserved := a.join(fakeClient(), "Reserved", now)
	a.populate()
	bot := roamingBots(a)[0]
	bot.HP, bot.Score, bot.respawn = 0, -3, a.tick+60
	bot.X, bot.Y = p.X+100*cellSize, p.Y
	spawn, id, name := bot.Spawn, bot.ID, bot.Name
	reserved.X, reserved.Y = bot.X, bot.Y
	a.suspend(reserved)
	p.HP, p.respawn = 0, a.tick+1000
	a.tick = bot.respawn - 2
	a.step(now)
	if bot.HP != 0 || bot.Spawn != spawn || !bot.ambientRetired {
		t.Fatal("abandoned bot was not retired without creating a life")
	}
	a.step(now)
	if bot.HP != 0 || bot.Spawn != spawn {
		t.Fatal("dead bot used an unavailable or disconnected human as its spawn anchor")
	}
	p.HP = 1
	a.nextBot = a.tick
	a.step(now)
	if bot.HP == 0 || bot.Spawn != spawn+1 || bot.Score != -3 || bot.ID != id || bot.Name != name || math.Hypot(bot.X-p.X, bot.Y-p.Y) > 6*cellSize {
		t.Fatal("retired bot did not start a fresh life near the live connected pilot with its identity and score")
	}
}

func TestInfinitePooledBotKeepsInFlightKillCreditAndClearsWithLastHuman(t *testing.T) {
	a := newSeededInfiniteArena(37)
	now := time.Unix(0, 0)
	target := a.join(fakeClient(), "P1", now)
	a.populate()
	bot := roamingBots(a)[0]
	target.X, target.Y, target.Protected = 142, 42, false
	bot.X, bot.Y, bot.Angle = 42, 42, 0
	bot.kit.Invulnerable = 0
	applyPower(&bot.kit, "cannon", infinitePowerDuration, infiniteStarDuration)
	a.fire(bot)
	if len(a.bullets) != 1 {
		t.Fatal("fixture did not fire its Cannon")
	}
	a.suspend(target)
	if len(roamingBots(a)) != 0 || len(a.inactiveBots) != 1 || len(a.leaderboard(nil)) != 1 {
		t.Fatal("a disconnected reservation retained active roaming bots")
	}
	if a.advanceBullet(&a.bullets[0], 100, 0) || target.HP != 0 || bot.Score != 1 || target.KilledBy != bot.Name {
		t.Fatal("pooled owner lost in-flight kill credit or callsign")
	}
	a.remove(target)
	if len(a.inactiveBots) != 0 || len(a.pilots) != 0 || len(a.bullets) != 0 {
		t.Fatal("last human departure retained the inactive population")
	}
}
