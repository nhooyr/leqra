package main

import "testing"

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
