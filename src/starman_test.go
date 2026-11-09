package main

import (
	"encoding/json"
	"slices"
	"testing"
)

func TestStarmanBlocksHitsAndSafelyEndsWallPhasing(t *testing.T) {
	const duration = 5
	g := ghostArena41()
	pilot, opponent := g.Tanks[0], g.Tanks[1]
	opponent.X, opponent.Y = 100, pilot.Y
	g.grantPower(pilot, "shield")
	g.Pickups = []*Pickup{{X: pilot.X, Y: pilot.Y, Type: "starman", Life: 20}}
	players := testPlayers(2)
	g.step(tickDT, [maxTanks]Input{}, players)
	if len(g.Pickups) != 0 || pilot.StarmanTime != duration || pilot.Invulnerable != duration || pilot.GhostTime != duration {
		t.Fatalf("Starman pickup did not grant %d seconds of both effects: %+v", duration, pilot)
	}
	if hit, _ := g.projectileTankHit(&Bullet{Owner: opponent.ID, R: 3.5}, opponent.X, opponent.Y, 160, 0); hit != nil {
		t.Fatal("an enemy round stopped on an invincible tank")
	}
	if _, hit := g.traceLaser(opponent); hit != nil {
		t.Fatal("an enemy Laser stopped on an invincible tank")
	}
	g.detonate(&Bullet{Owner: opponent.ID, Kind: "grenade", X: pilot.X, Y: pilot.Y})
	if !pilot.Alive || shieldCount(pilot) != 1 {
		t.Fatal("an enemy blast damaged the tank or consumed its shield")
	}
	g.moveTank(pilot, 80, 0)
	if pilot.X != 290 {
		t.Fatal("Starman tank did not pass through an internal wall")
	}
	g.moveTank(pilot, -500, 0)
	if pilot.X != wallSize/2+pilot.R {
		t.Fatal("Starman tank escaped the maze rim")
	}
	pilot.X = 252
	spawn := pilot.SpawnSerial
	g.step(duration+.01, [maxTanks]Input{}, players)
	if pilot.StarmanTime != 0 || pilot.Invulnerable != 0 || pilot.GhostTime != 0 || !g.clearTankAt(pilot.X, pilot.Y, pilot.R) || pilot.SpawnSerial != spawn {
		t.Fatalf("Starman did not safely expire inside a wall: %+v", pilot)
	}
	g.hurt(pilot, &Bullet{Owner: opponent.ID})
	if !pilot.Alive || shieldCount(pilot) != 0 {
		t.Fatal("damage did not resume after Starman expiry")
	}
}

func TestStarmanRefreshKeepsExistingGearAndPublishesItsTimer(t *testing.T) {
	const duration = 5
	h, clients, room := makeRoom(t, 2)
	room.Game = ghostArena41()
	g := room.Game
	pilot := g.Tanks[0]
	action(t, h, clients[0], map[string]any{"type": "input", "seq": 4, "starmanTime": 30, "invulnerable": 30, "ghostTime": 30})
	if pilot.StarmanTime != 0 || pilot.Invulnerable != 0 || pilot.GhostTime != 0 {
		t.Fatal("client forged Starman")
	}
	for _, kind := range []string{"cannon", "shield", "speed", "ghost", "starman"} {
		g.grantPower(pilot, kind)
	}
	g.step(.5, [maxTanks]Input{}, testPlayers(2))
	ghostTime := pilot.GhostTime
	g.grantPower(pilot, "starman")
	if pilot.StarmanTime != duration || pilot.Invulnerable != duration || pilot.GhostTime != ghostTime || pilot.Power != "cannon" || pilot.Charges != 3 || shieldCount(pilot) != 1 || speedCount(pilot) != 1 {
		t.Fatalf("Starman refresh changed other pickups or stacked duration: %+v", pilot)
	}
	tanks := h.stateMessage(room)["tanks"].([]Tank)
	if tanks[0].StarmanTime != duration || tanks[0].GhostTime != ghostTime || tanks[0].Invulnerable != duration {
		t.Fatal("Starman and its movement and damage state are missing from snapshots")
	}
	g.respawnTank(pilot)
	if pilot.StarmanTime != 0 || pilot.GhostTime != 0 || pilot.Invulnerable != 1.2 {
		t.Fatal("respawn retained Starman")
	}
}

func TestStarmanContactEliminatesShieldedTankAndDropsItsFlag(t *testing.T) {
	g := battle(2)
	g.Rules.Mode, g.Rules.RespawnSeconds = "ctf", 3
	attacker, target := g.Tanks[0], g.Tanks[1]
	attacker.Team, target.Team = 1, 2
	target.X, target.Y = attacker.X+attacker.R+target.R, attacker.Y
	flag := &Flag{Team: 1, Carrier: target.ID}
	g.Objectives = &ObjectiveState{Mode: "ctf", Flags: []*Flag{flag}}
	g.grantPower(target, "shield")
	g.grantPower(attacker, "starman")
	g.step(tickDT, [maxTanks]Input{}, testPlayers(2))
	if target.Alive || !attacker.Alive || target.RespawnTime != 3 || flag.Carrier != -1 || flag.ReturnIn <= 0 {
		t.Fatalf("Starman contact failed to eliminate or drop the flag: attacker=%+v target=%+v flag=%+v", attacker, target, flag)
	}
	if attacker.stats.Eliminations != 1 || target.stats.Deaths != 1 {
		t.Fatal("Starman contact was not credited as a normal elimination")
	}
}

func TestStarmanContactRespectsWallsProtectionAndTeams(t *testing.T) {
	for _, tc := range []struct {
		name        string
		setup       func(g *Game, attacker, target *Tank)
		targetAlive bool
	}{
		{"outside contact", func(_ *Game, a, b *Tank) { b.X += .01 }, true},
		{"through wall", func(_ *Game, a, b *Tank) { a.X, b.X = 240, 273 }, true},
		{"inside wall", func(_ *Game, a, b *Tank) { a.X, b.X = 252, 273 }, true},
		{"spawn protected", func(_ *Game, a, b *Tank) { b.Invulnerable = 1 }, true},
		{"other Starman", func(g *Game, a, b *Tank) { g.grantPower(b, "starman") }, true},
		{"friendly fire off", func(g *Game, a, b *Tank) { a.Team, b.Team = 1, 1; g.Rules.FriendlyFire = false }, true},
		{"friendly fire on", func(g *Game, a, b *Tank) { a.Team, b.Team = 1, 1; g.Rules.FriendlyFire = true }, false},
		{"expired boost", func(_ *Game, a, b *Tank) { a.StarmanTime = tickDT }, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			g := ghostArena41()
			// Put the attacker in the higher seat to check both sides of the
			// tank-pair iteration across the Starman contact tests.
			attacker, target := g.Tanks[1], g.Tanks[0]
			attacker.X, attacker.Y = 120, 210
			target.X, target.Y = attacker.X+attacker.R+target.R, attacker.Y
			g.grantPower(attacker, "starman")
			tc.setup(g, attacker, target)
			g.step(tickDT, [maxTanks]Input{}, testPlayers(2))
			if !attacker.Alive || target.Alive != tc.targetAlive {
				t.Fatalf("attacker alive = %t, target alive = %t, want true and %t", attacker.Alive, target.Alive, tc.targetAlive)
			}
		})
	}
}

func TestStarmanWeaponsFireWithoutSpendingAmmoOrReloading(t *testing.T) {
	for _, kind := range []string{"regular", "rapid", "scatter", "homing", "grenade", "laser", "cannon"} {
		t.Run(kind, func(t *testing.T) {
			g := battle(2)
			pilot := g.Tanks[0]
			g.Tanks[1].X, g.Tanks[1].Y = 420, 350
			g.Pickups, g.SpawnClock = nil, 999
			if kind != "regular" {
				g.grantPower(pilot, kind)
				pilot.Charges, pilot.MachineRounds, pilot.PowerTime = 1, 1, 2*tickDT
			}
			pilot.Cooldown, pilot.CooldownTotal = 1, 1
			g.grantPower(pilot, "starman")
			if pilot.Cooldown != 0 || pilot.CooldownTotal != 0 {
				t.Fatal("Starman pickup left the old cooldown active")
			}
			power, charges, rounds, remaining := pilot.Power, pilot.Charges, pilot.MachineRounds, pilot.PowerTime
			players := testPlayers(2)
			for tick := range 16 {
				var input [maxTanks]Input
				input[0].Fire = kind != "grenade" || tick%2 == 0
				input[0].FirePressed = kind == "grenade" && input[0].Fire
				g.step(tickDT, input, players)
			}
			shots := uint64(16)
			if kind == "grenade" {
				shots = 4 // Presses alternate between throwing and detonating.
			}
			if pilot.ShotSerial != shots || pilot.Cooldown != 0 || pilot.Power != power || pilot.PowerTime != remaining || pilot.Charges != charges || pilot.MachineRounds != rounds {
				t.Fatalf("want %d volleys with full saved equipment while boosted, got %+v", shots, pilot)
			}
			pilot.StarmanTime = tickDT
			g.step(tickDT, [maxTanks]Input{}, players)
			if kind != "regular" && pilot.PowerTime != tickDT {
				t.Fatal("equipped weapon timer did not resume when Starman ended")
			}
		})
	}
}

func TestStarmanRetiresOldestProjectileAtSafetyLimit(t *testing.T) {
	g := battle(2)
	pilot, other := g.Tanks[0], g.Tanks[1]
	other.Y = 350
	for id := 1; id <= machineCapacity; id++ {
		g.Bullets = append(g.Bullets, &Bullet{ID: id, Owner: pilot.ID})
	}
	foreign := &Bullet{ID: machineCapacity + 1, Owner: other.ID}
	g.Bullets = append(g.Bullets, foreign)
	g.nextBullet = foreign.ID
	g.grantPower(pilot, "starman")
	if !g.fire(pilot) {
		t.Fatal("safety ceiling blocked Starman from firing")
	}
	if !g.Bullets[0].Dead || g.Bullets[1].Dead || foreign.Dead || g.Bullets[len(g.Bullets)-1].Dead {
		t.Fatal("ceiling did not retire exactly the oldest owned shot")
	}
}

func TestStarmanShotsDoNotOccupyWeaponSlotsAfterExpiry(t *testing.T) {
	g := battle(2)
	pilot, other := g.Tanks[0], g.Tanks[1]
	other.Y = 350
	g.SpawnClock = 999
	if !g.fire(pilot) {
		t.Fatal("fixture needs an ordinary shot before Starman")
	}
	ordinary := g.Bullets[0]
	g.grantPower(pilot, "starman")
	for range machineCapacity - 1 {
		if !g.fire(pilot) {
			t.Fatal("Starman unexpectedly ran out of slots")
		}
	}
	oldestBoosted, nextBoosted := g.Bullets[1], g.Bullets[2]
	if ordinary.boosted || !oldestBoosted.boosted || oldestBoosted.Dead {
		t.Fatal("Starman's volley did not distinguish bonus shots")
	}
	pilot.StarmanTime = tickDT
	inputs := [maxTanks]Input{{Fire: true}}
	g.step(tickDT, inputs, testPlayers(2))
	if pilot.StarmanTime != 0 || pilot.ShotSerial != uint64(machineCapacity+1) {
		t.Fatal("bonus rounds blocked the first shot after expiry")
	}
	if len(g.Bullets) != machineCapacity || ordinary.Dead || !oldestBoosted.Dead || nextBoosted.Dead || g.Bullets[len(g.Bullets)-1].boosted {
		t.Fatal("the safety cap must retain ordinary rounds and replace only the oldest bonus round")
	}
	for range capacity(pilot) - 2 {
		pilot.Cooldown = 0
		if !g.fire(pilot) {
			t.Fatal("a free ordinary slot was blocked")
		}
	}
	pilot.Cooldown = 0
	if g.fire(pilot) {
		t.Fatal("ordinary shots exceeded their usual slot limit")
	}
}

func TestBoostedBulletIDsCoverBothFixedMazeShotEncodings(t *testing.T) {
	g := battle(2)
	g.Bullets = []*Bullet{
		{ID: 1, boosted: true},
		{ID: 2, Kind: "rapid", boosted: true},
		{ID: 3},
		{ID: 4, boosted: true, Dead: true},
	}
	h, room := newHub(2), &Room{Game: g}
	wire := h.stateWire(room)
	if !slices.Equal(wire.BoostedBulletIDs, []int{1, 2}) || len(wire.MachineBullets) != 1 || wire.MachineBullets[0][0] != 2 {
		t.Fatalf("boosted ID list did not cover both live shot encodings: %+v", wire)
	}
	actual, err := json.Marshal(wire)
	if err != nil {
		t.Fatal(err)
	}
	canonical, err := json.Marshal(h.stateMessage(room))
	if err != nil {
		t.Fatal(err)
	}
	if string(actual) != string(canonical) {
		t.Fatalf("boosted snapshot differs from canonical wire: %s", actual)
	}
	g.Bullets = g.Bullets[2:3]
	if len(h.stateWire(room).BoostedBulletIDs) != 0 {
		t.Fatal("snapshot retained a previous boosted projectile ID")
	}
}
