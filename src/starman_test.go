package main

import "testing"

func TestStarmanBlocksHitsAndSafelyEndsWallPhasing(t *testing.T) {
	g := ghostArena41()
	pilot, opponent := g.Tanks[0], g.Tanks[1]
	opponent.X, opponent.Y = 100, pilot.Y
	g.grantPower(pilot, "shield")
	g.Pickups = []*Pickup{{X: pilot.X, Y: pilot.Y, Type: "starman", Life: 20}}
	players := testPlayers(2)
	g.step(tickDT, [maxTanks]Input{}, players)
	if len(g.Pickups) != 0 || pilot.StarmanTime != 3 || pilot.Invulnerable != 3 || pilot.GhostTime != 3 {
		t.Fatalf("Starman pickup did not grant three seconds of both effects: %+v", pilot)
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
	g.step(starmanDuration+.01, [maxTanks]Input{}, players)
	if pilot.StarmanTime != 0 || pilot.Invulnerable != 0 || pilot.GhostTime != 0 || !g.clearTankAt(pilot.X, pilot.Y, pilot.R) || pilot.SpawnSerial != spawn {
		t.Fatalf("Starman did not safely expire inside a wall: %+v", pilot)
	}
	g.hurt(pilot, &Bullet{Owner: opponent.ID})
	if !pilot.Alive || shieldCount(pilot) != 0 {
		t.Fatal("damage did not resume after Starman expiry")
	}
}

func TestStarmanRefreshKeepsExistingGearAndPublishesItsTimer(t *testing.T) {
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
	if pilot.StarmanTime != 3 || pilot.Invulnerable != 3 || pilot.GhostTime != ghostTime || pilot.Power != "cannon" || pilot.Charges != 3 || shieldCount(pilot) != 1 || speedCount(pilot) != 1 {
		t.Fatalf("Starman refresh changed other pickups or stacked duration: %+v", pilot)
	}
	tanks := h.stateMessage(room)["tanks"].([]Tank)
	if tanks[0].StarmanTime != 3 || tanks[0].GhostTime != ghostTime || tanks[0].Invulnerable != 3 {
		t.Fatal("Starman and its movement and damage state are missing from snapshots")
	}
	g.respawnTank(pilot)
	if pilot.StarmanTime != 0 || pilot.GhostTime != 0 || pilot.Invulnerable != 1.2 {
		t.Fatal("respawn retained Starman")
	}
}
