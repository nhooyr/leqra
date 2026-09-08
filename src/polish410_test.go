package main

import (
	"math"
	"testing"
)

func Test410EveryEquippedTimedPowerupUsesTenSeconds(t *testing.T) {
	if powerEffectDuration != 10 || pickupLifetime(16, 14) != 61 || boostDuration != 10 || shieldDuration != 10 || scopeDuration != 10 || ghostDuration != 10 {
		t.Fatalf("duration values: effect=%v giantPickup=%v boost=%v shield=%v scope=%v ghost=%v", powerEffectDuration, pickupLifetime(16, 14), boostDuration, shieldDuration, scopeDuration, ghostDuration)
	}
	for _, kind := range pickupTypes {
		g := battle(2)
		p := g.Tanks[0]
		g.grantPower(p, kind)
		switch kind {
		case "shield":
			if p.Shield != powerEffectDuration {
				t.Fatalf("%s duration=%v", kind, p.Shield)
			}
		case "speed":
			if p.SpeedTime != powerEffectDuration {
				t.Fatalf("%s duration=%v", kind, p.SpeedTime)
			}
		case "scope":
			if p.ScopeTime != powerEffectDuration {
				t.Fatalf("%s duration=%v", kind, p.ScopeTime)
			}
		case "ghost":
			if p.GhostTime != powerEffectDuration {
				t.Fatalf("%s duration=%v", kind, p.GhostTime)
			}
		default:
			if p.Power != kind || p.PowerTime != powerEffectDuration {
				t.Fatalf("%s power=%q duration=%v", kind, p.Power, p.PowerTime)
			}
		}
	}
}

func Test410SpawnedPickupUsesMazeLifetime(t *testing.T) {
	g := battle(2)
	g.Pickups = nil
	g.spawnPower()
	if len(g.Pickups) != 1 || math.Abs(g.Pickups[0].Life-pickupLifetime(g.World.Cols, g.World.Rows)) > 1e-12 {
		t.Fatalf("spawned pickup=%+v lifetime=%v", g.Pickups, pickupLifetime(g.World.Cols, g.World.Rows))
	}
}

func Test410BotsIgnoreHarmlessFriendlyGrenadesButAvoidOwnAndDangerous(t *testing.T) {
	g := battle(3)
	bot, ally, enemy := g.Tanks[0], g.Tanks[1], g.Tanks[2]
	bot.Bot, bot.Difficulty = true, "easy"
	bot.Team, ally.Team, enemy.Team = 1, 1, 2
	bot.X, bot.Y = 100, 210
	ally.X, ally.Y = 60, 210
	enemy.X, enemy.Y = 420, 210
	grenade := &Bullet{ID: 1, Kind: "grenade", X: 150, Y: 210, VX: 0, VY: 0, R: 6, Life: 9}
	g.Bullets = []*Bullet{grenade}
	d := tuneBot("easy")

	g.Rules.FriendlyFire = false
	grenade.Owner = ally.ID
	if got := len(g.botGrenadeThreats(bot, d, .7)); got != 0 {
		t.Fatalf("harmless friendly grenade produced %d avoidance threats", got)
	}
	grenade.Owner = bot.ID
	if got := len(g.botGrenadeThreats(bot, d, .7)); got == 0 {
		t.Fatal("bot did not avoid its own grenade")
	}
	grenade.Owner = enemy.ID
	if got := len(g.botGrenadeThreats(bot, d, .7)); got == 0 {
		t.Fatal("bot did not avoid enemy grenade")
	}
	g.Rules.FriendlyFire = true
	grenade.Owner = ally.ID
	if got := len(g.botGrenadeThreats(bot, d, .7)); got == 0 {
		t.Fatal("bot did not avoid friendly grenade when friendly fire was enabled")
	}
}

func Test410Version(t *testing.T) {
	if version != "4.43.0" {
		t.Fatalf("version=%q", version)
	}
}
