package main

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestInfiniteShotBounceAndRespawn(t *testing.T) {
	a := newSeededInfiniteArena(16)
	now := time.Now()
	first, second := a.join(fakeClient(), "First", now), a.join(fakeClient(), "Second", now)
	a.nextBot = 1000
	a.tick = 60
	var wall Wall
	for _, candidate := range a.maze.wallsNear(-500, -500, 500, 500) {
		if candidate.Axis == "v" {
			wall = candidate
			break
		}
	}
	if wall.H == 0 {
		t.Fatal("test seed needs a vertical wall")
	}
	y := wall.Y + wall.H/2
	first.X, first.Y, first.Angle, first.Protected = wall.X-30, y, 0, false
	second.X, second.Y, second.Protected = wall.X+wall.W+30, y, false
	for range 40 {
		a.drive(first, Input{Forward: true})
	}
	if first.X > wall.X-tankRadius {
		t.Fatalf("tank moved through wall: x=%f, wall=%+v", first.X, wall)
	}

	bullet := infiniteBullet{Owner: first.ID, X: first.X, Y: y, VX: 282}
	if !a.advanceBullet(&bullet, 60, 0) || bullet.Bounces != 1 || bullet.VX >= 0 {
		t.Fatalf("expected a surviving reflected bullet, got %+v", bullet)
	}
	if first.HP != infiniteMaxHP || second.HP != infiniteMaxHP {
		t.Fatal("shot damaged its owner or a target behind a wall")
	}

	second.X, second.HP = wall.X-48, 1
	bullet = infiniteBullet{Owner: first.ID, X: first.X, Y: y}
	if a.advanceBullet(&bullet, -20, 0) || second.HP != 0 || first.Score != 1 || second.Score != -1 {
		t.Fatal("a lethal hit must consume the projectile, add a point, and deduct a point")
	}
	for range infiniteRespawnTicks - 1 {
		a.step(now)
	}
	if second.HP != 0 {
		t.Fatal("pilot respawned early")
	}
	a.step(now)
	if second.HP != infiniteMaxHP || second.Score != -1 || !second.Protected || a.maze.blocked(second.X, second.Y, tankRadius) {
		t.Fatalf("respawn lost score, protection, or a valid spawn position: %+v", second)
	}
}

func TestInfinitePauseHoldsRespawnAndKeepsArenaLive(t *testing.T) {
	a := newSeededInfiniteArena(37)
	now := time.Now()
	paused, other := a.join(fakeClient(), "Paused", now), a.join(fakeClient(), "Other", now)
	a.nextBot, a.nextPickup = 1000, 1000
	pausedX, pausedY, pausedAngle := paused.X, paused.Y, paused.Angle
	otherX, otherY := other.X, other.Y
	spawn := paused.Spawn

	a.setInput(paused, Input{Seq: 1, Fire: true}, false, now)
	a.setInput(paused, Input{Seq: 2, Fire: true, Forward: true, StickY: 1}, true, now)
	a.setInput(other, Input{Seq: 1, Forward: true}, false, now)
	a.step(now)
	if paused.X != pausedX || paused.Y != pausedY || paused.Angle != pausedAngle || a.nextBullet != 0 || paused.Ack != 2 {
		t.Fatalf("pause failed to neutralize and acknowledge movement, aim or a pending shot: %+v", paused)
	}
	if other.X == otherX && other.Y == otherY {
		t.Fatal("another pilot stopped moving when the menu opened")
	}

	paused.kit.Invulnerable, paused.Protected = 0, false
	a.hurt(paused, other.ID, other.Team)
	if paused.HP != 0 || paused.Score != -1 || other.Score != 1 {
		t.Fatal("a paused pilot must still take damage and lose a point on death")
	}
	for range infiniteRespawnTicks + 1 {
		a.step(now.Add(inputTimeout + time.Millisecond))
	}
	if paused.HP != 0 || paused.Spawn != spawn {
		t.Fatal("a paused pilot respawned after the timer or control timeout")
	}
	a.setInput(paused, Input{Seq: 3}, false, now.Add(inputTimeout+time.Millisecond))
	a.step(now.Add(inputTimeout + time.Millisecond))
	if paused.HP != infiniteMaxHP || paused.Spawn != spawn+1 || paused.Score != -1 || !paused.Protected {
		t.Fatalf("resuming after the respawn timer did not restore the pilot with score and protection: %+v", paused)
	}
}

func TestInfiniteFireEdgeAndProximitySnapshot(t *testing.T) {
	a := newSeededInfiniteArena(37)
	now := time.Now()
	c := fakeClient()
	p := a.join(c, "Pilot", now)
	other := a.join(fakeClient(), "Distant", now)
	other.X = p.X - infiniteSight*2
	a.nextBot = 1000
	drain(c)
	a.setInput(p, Input{Fire: true}, false, now)
	a.setInput(p, Input{}, false, now)
	a.step(now)
	if a.nextBullet != 1 {
		t.Fatal("press and release between ticks lost the shot")
	}
	a.step(now)
	if a.nextBullet != 1 {
		t.Fatal("one fire edge produced more than one shot")
	}
	a.broadcast()
	var packet infiniteSnapshot
	if err := json.Unmarshal(<-c.send, &packet); err != nil {
		t.Fatal(err)
	}
	if packet.Type != "state" || packet.Players != 2 || len(packet.Tanks) != 1 || packet.Tanks[0].ID != p.ID || packet.Leaders == nil {
		t.Fatalf("invalid proximity snapshot: %+v", packet)
	}

	a.remove(p)
	a.remove(other)
	if len(a.pilots)+len(a.bullets) != 0 {
		t.Fatal("empty arena retained match state")
	}
}

func TestInfiniteFireTimeoutPreservesPressIdentity(t *testing.T) {
	a := newSeededInfiniteArena(37)
	now := time.Now()
	p := a.join(fakeClient(), "Pilot", now)
	a.nextBot = 1000
	applyPower(&p.kit, "grenade", infinitePowerDuration, infiniteStarDuration)
	a.setInput(p, Input{Fire: true}, false, now)
	afterTimeout := now.Add(inputTimeout + time.Millisecond)
	a.setInput(p, Input{}, false, afterTimeout)
	a.step(afterTimeout)
	if a.nextBullet != 0 {
		t.Fatal("fresh neutral input revived an expired press")
	}

	a.setInput(p, Input{Fire: true}, false, afterTimeout)
	a.step(afterTimeout)
	if len(a.bullets) != 1 || a.bullets[0].Kind != "grenade" {
		t.Fatal("fresh press did not throw a grenade")
	}
	afterTimeout = afterTimeout.Add(inputTimeout + time.Millisecond)
	a.step(afterTimeout)
	a.setInput(p, Input{Fire: true}, false, afterTimeout)
	a.step(afterTimeout)
	if len(a.bullets) != 1 {
		t.Fatal("held heartbeat detonated a grenade after timeout")
	}
	a.setInput(p, Input{}, false, afterTimeout)
	a.setInput(p, Input{Fire: true}, false, afterTimeout)
	a.step(afterTimeout)
	if len(a.bullets) != 0 {
		t.Fatal("release and fresh press did not detonate the grenade")
	}
}

func TestInfinitePickupsAndOneHitCombat(t *testing.T) {
	a := newSeededInfiniteArena(37)
	now := time.Now()
	shooter := a.join(fakeClient(), "Shooter", now)
	target := a.join(fakeClient(), "Target", now)
	a.tick = 1
	a.populatePickups()
	if len(a.pickups) == 0 {
		t.Fatal("joining a live arena did not populate nearby pickups")
	}
	target.kit.Invulnerable, target.Protected = 0, false
	a.pickups = []Pickup{{X: target.X, Y: target.Y, Type: "shield", Life: 30}}
	a.collectPickup(target)
	if target.kit.ShieldCharges != 1 || a.pickups[0].Life != 0 {
		t.Fatal("a shield must be collected and removed exactly once")
	}
	a.hurt(target, shooter.ID, shooter.Team)
	if target.HP != 1 || target.kit.ShieldCharges != 0 || !target.Protected {
		t.Fatal("shield did not absorb the shot")
	}
	for range 21 {
		a.advanceEquipment(target)
	}
	a.hurt(target, target.ID, target.Team)
	if target.HP != 1 {
		t.Fatal("a tank damaged itself")
	}
	a.hurt(target, shooter.ID, shooter.Team)
	if target.HP != 0 || target.Score != -1 || shooter.Score != 1 {
		t.Fatal("one unshielded hit must kill and adjust both scores")
	}
}

func TestInfiniteGrenadeHomingTurnsAtMissileRate(t *testing.T) {
	a := newSeededInfiniteArena(37)
	a.pilots = []*infinitePilot{{infiniteTank: infiniteTank{ID: 1, X: 63, Y: 67, HP: 1}}}
	for _, weapon := range []struct {
		kind        string
		speed, turn float64
	}{
		{"homing", missileSpeed, missileTurn},
		{"grenade", grenadeSpeed, missileTurn},
	} {
		a.bullets = []infiniteBullet{{Kind: weapon.kind, X: 42, Y: 42, VX: weapon.speed, Life: 9, age: 1, radius: 6, target: -1}}
		a.advanceBullets()
		if len(a.bullets) != 1 || a.bullets[0].target != 1 {
			t.Fatalf("%s must keep flying and acquire the target, got %+v", weapon.kind, a.bullets)
		}
		b := a.bullets[0]
		if angle, want := math.Atan2(b.VY, b.VX), weapon.turn*tickDT; math.Abs(angle-want) > 1e-12 {
			t.Fatalf("%s turn = %v, want %v", weapon.kind, angle, want)
		}
	}
}

func TestInfiniteStarmanContactAwardsOneKillAndRespectsProtection(t *testing.T) {
	a := newSeededInfiniteArena(37)
	now := time.Now()
	attacker := a.join(fakeClient(), "Attacker", now)
	target := a.join(fakeClient(), "Target", now)
	a.nextBot, a.nextPickup = 1000, 1000
	a.pickups = nil
	attacker.X, attacker.Y = 24, 42
	target.X, target.Y = attacker.X+2*tankRadius, attacker.Y
	applyPower(&attacker.kit, "starman", infinitePowerDuration, infiniteStarDuration)
	applyPower(&target.kit, "starman", infinitePowerDuration, infiniteStarDuration)
	a.step(now)
	if attacker.HP == 0 || target.HP == 0 {
		t.Fatal("contact killed one of two active Starmen")
	}
	target.kit.StarmanTime, target.kit.GhostTime = 0, 0
	target.kit.Invulnerable = 1
	a.step(now)
	if target.HP == 0 {
		t.Fatal("contact ignored temporary invulnerability")
	}
	target.kit.Invulnerable = 0
	applyPower(&target.kit, "shield", infinitePowerDuration, infiniteStarDuration)
	a.step(now)
	if target.HP != 0 || target.respawn != a.tick+infiniteRespawnTicks || target.Score != -1 || attacker.Score != 1 {
		t.Fatalf("contact should bypass the shield and award a normal kill: attacker=%+v target=%+v", attacker, target)
	}
	a.step(now)
	if attacker.Score != 1 || target.Score != -1 {
		t.Fatal("continued contact with a dead tank scored more than once")
	}
}

func TestInfiniteStarmanContactCannotCrossWalls(t *testing.T) {
	a := newSeededInfiniteArena(37)
	now := time.Now()
	attacker := a.join(fakeClient(), "Attacker", now)
	target := a.join(fakeClient(), "Target", now)
	a.nextBot, a.nextPickup = 1000, 1000
	a.pickups = nil
	var wall Wall
	for _, candidate := range a.maze.wallsNear(-500, -500, 500, 500) {
		if candidate.Axis == "v" {
			wall = candidate
			break
		}
	}
	if wall.H == 0 {
		t.Fatal("fixture needs a vertical wall")
	}
	target.X, target.Y = wall.X+wall.W+tankRadius, wall.Y+wall.H/2
	target.kit.Invulnerable = 0
	attacker.Y = target.Y
	applyPower(&attacker.kit, "starman", infinitePowerDuration, infiniteStarDuration)
	for _, x := range []float64{wall.X - 1, wall.X + wall.W/2} {
		attacker.X = x
		a.step(now)
		if target.HP == 0 {
			t.Fatalf("contact from x=%f reached a tank through wall %+v", x, wall)
		}
	}
	attacker.X = wall.X + wall.W + 1
	a.step(now)
	if target.HP != 0 {
		t.Fatal("Starman did not eliminate a tank after reaching the same side of the wall")
	}
}

func TestInfiniteStarmanWeaponsFireWithoutSpendingAmmoOrReloading(t *testing.T) {
	for _, kind := range []string{"regular", "rapid", "scatter", "homing", "grenade", "laser", "cannon"} {
		t.Run(kind, func(t *testing.T) {
			a := newSeededInfiniteArena(37)
			now := time.Now()
			p := a.join(fakeClient(), "Pilot", now)
			a.nextBot, a.nextPickup = 1000, 1000
			k := &p.kit
			if kind != "regular" {
				applyPower(k, kind, infinitePowerDuration, infiniteStarDuration)
				k.Charges, k.MachineRounds, k.PowerTime = 1, 1, 2*tickDT
			}
			k.Cooldown = 1
			applyPower(k, "starman", infinitePowerDuration, infiniteStarDuration)
			if k.Cooldown != 0 {
				t.Fatal("Starman pickup left the old cooldown active")
			}
			power, charges, rounds, remaining := k.Power, k.Charges, k.MachineRounds, k.PowerTime
			for tick := range 16 {
				fire := kind != "grenade" || tick%2 == 0
				a.setInput(p, Input{Seq: uint64(tick + 1), Fire: fire}, false, now)
				a.step(now)
			}
			shots := uint64(16)
			if kind == "grenade" {
				shots = 4
			}
			if k.ShotSerial != shots || k.Cooldown != 0 || k.Power != power || k.PowerTime != remaining || k.Charges != charges || k.MachineRounds != rounds {
				t.Fatalf("want %d volleys with full saved equipment while boosted, got %+v", shots, k)
			}
			k.StarmanTime = tickDT
			a.setInput(p, Input{}, false, now)
			a.step(now)
			if kind != "regular" && k.PowerTime != tickDT {
				t.Fatal("equipped weapon timer did not resume when Starman ended")
			}
		})
	}
}

func TestInfiniteStarmanRetiresOldestProjectileAtSafetyLimit(t *testing.T) {
	a := newSeededInfiniteArena(37)
	p := a.join(fakeClient(), "Pilot", time.Now())
	for id := 1; id <= machineCapacity; id++ {
		a.bullets = append(a.bullets, infiniteBullet{ID: id, Owner: p.ID})
	}
	a.bullets = append(a.bullets, infiniteBullet{ID: machineCapacity + 1, Owner: p.ID + 1})
	a.nextBullet = machineCapacity + 1
	applyPower(&p.kit, "starman", infinitePowerDuration, infiniteStarDuration)
	a.fire(p)
	if a.nextBullet != machineCapacity+2 {
		t.Fatal("safety ceiling blocked Starman from firing")
	}
	if !a.bullets[0].dead || a.bullets[1].dead || a.bullets[machineCapacity].dead || a.bullets[len(a.bullets)-1].dead {
		t.Fatal("ceiling did not retire exactly the oldest owned shot")
	}
}

func TestInfiniteStarmanShotsDoNotOccupyWeaponSlotsAfterExpiry(t *testing.T) {
	a := newSeededInfiniteArena(37)
	p := a.join(fakeClient(), "Pilot", time.Now())
	a.fire(p)
	applyPower(&p.kit, "starman", infinitePowerDuration, infiniteStarDuration)
	for range machineCapacity - 1 {
		a.fire(p)
	}
	if len(a.bullets) != machineCapacity || a.bullets[0].boosted || !a.bullets[1].boosted {
		t.Fatal("fixture needs ordinary and Starman shots at the safety limit")
	}
	p.kit.StarmanTime = tickDT
	a.advanceEquipment(p)
	a.fire(p)
	if p.kit.StarmanTime != 0 || p.kit.ShotSerial != uint64(machineCapacity+1) {
		t.Fatal("bonus rounds blocked the first shot after expiry")
	}
	if a.bullets[0].dead || !a.bullets[1].dead || a.bullets[2].dead || a.bullets[len(a.bullets)-1].boosted {
		t.Fatal("the safety cap must retain ordinary rounds and replace only the oldest bonus round")
	}
	for range capacity(&p.kit) - 2 {
		p.kit.Cooldown = 0
		a.fire(p)
	}
	p.kit.Cooldown = 0
	a.fire(p)
	if p.kit.ShotSerial != uint64(machineCapacity+capacity(&p.kit)-1) {
		t.Fatal("ordinary slots did not return to their usual limit")
	}
}

func TestInfiniteSimultaneousLaserPriorityRotates(t *testing.T) {
	for winner := range 2 {
		a := newSeededInfiniteArena(37)
		now := time.Now()
		pilots := []*infinitePilot{a.join(fakeClient(), "First", now), a.join(fakeClient(), "Second", now)}
		a.nextBot, a.nextPickup = 1000, 1000
		a.tick = uint64(99 + winner)
		foundLane := false
		for x := range 8 {
			px, py := infiniteCenter(x, 0)
			if _, blocked := a.rayWalls(px, py, cellSize, 0, laserRadius); blocked {
				continue
			}
			pilots[0].X, pilots[0].Y, pilots[0].Angle = px, py, 0
			pilots[1].X, pilots[1].Y, pilots[1].Angle = px+cellSize, py, math.Pi
			foundLane = true
			break
		}
		if !foundLane {
			t.Fatal("fixture needs a clear two-cell lane")
		}
		for _, p := range pilots {
			p.kit.Invulnerable = 0
			applyPower(&p.kit, "laser", infinitePowerDuration, infiniteStarDuration)
			a.setInput(p, Input{Fire: true}, false, now)
		}
		a.step(now)
		if pilots[winner].Score != 1 || pilots[1-winner].Score != -1 {
			t.Fatalf("tick %d wanted pilot %d to win the simultaneous attack, got %d / %d", a.tick, winner, pilots[0].Score, pilots[1].Score)
		}
	}
}

func TestInfiniteLeaderboardRanksTenIncludingBots(t *testing.T) {
	a := newSeededInfiniteArena(51)
	now := time.Now()
	p := a.join(fakeClient(), "Pilot", now)
	bot := a.addPilot("Top bot", true, p.X, p.Y, 3, 6)
	bot.Score, bot.HP = 2, 0
	p.Score = -1
	for range 12 {
		a.addPilot("Other bot", true, p.X, p.Y, 3, 6)
	}
	leaders := a.leaderboard(nil)
	if len(leaders) != 10 || leaders[0].Name != "Top bot" || leaders[0].Score != 2 || !leaders[0].Bot || leaders[9].ID != 11 {
		t.Fatalf("unexpected leaders: %+v", leaders)
	}
	a.pilots = a.pilots[:3]
	leaders = a.leaderboard(leaders)
	if leaders[0].ID != bot.ID || leaders[1].Score != 0 || leaders[2].ID != p.ID || leaders[2].Score != -1 {
		t.Fatalf("leaderboard dropped a respawning bot, zero, or negative score: %+v", leaders)
	}
}

func TestInfiniteWebSocketSharesAnAuthoritativeArena(t *testing.T) {
	app := newApp(4, nil)
	app.infinite.public = newSeededInfiniteArena(99)
	done := make(chan struct{})
	go app.infinite.run(done)
	t.Cleanup(func() {
		close(done)
		app.infinite.close()
	})
	server := httptest.NewServer(app.handler())
	t.Cleanup(server.Close)

	_, bad := dialInfinite(t, server.URL, map[string]string{"type": "join", "version": "outdated"}, false)
	var refusal infiniteMessage
	readInfinitePacket(t, bad, &refusal)
	if refusal.Type != "error" {
		t.Fatalf("outdated client accepted: %+v", refusal)
	}

	type welcome struct {
		Type string `json:"type"`
		ID   int    `json:"id"`
		Seed uint32 `json:"seed"`
	}
	var clients [2]welcome
	for i, name := range []string{"First", "Second"} {
		_, reader := dialInfinite(t, server.URL, map[string]string{"type": "join", "version": version, "name": name}, false)
		w := &clients[i]
		readInfinitePacket(t, reader, w)
		if w.Type != "welcome" || w.Seed != 99 || w.ID == 0 {
			t.Fatalf("invalid welcome: %+v", w)
		}
		var state infiniteSnapshot
		if readInfinitePacket(t, reader, &state) || state.Type != "state" || state.Players != i+1 {
			t.Fatalf("invalid initial world state: %+v", state)
		}
		for _, client := range clients[:i+1] {
			found := false
			for _, tank := range state.Tanks {
				found = found || tank.ID == client.ID
			}
			if !found {
				t.Fatalf("nearby pilot %d absent from state: %+v", client.ID, state)
			}
		}
	}
	if clients[0].ID == clients[1].ID {
		t.Fatal("two connections acquired the same pilot ID")
	}
}

func TestInfiniteWebSocketNegotiatesSnapshotDeflate(t *testing.T) {
	app := newApp(4, nil)
	t.Cleanup(app.infinite.close)
	server := httptest.NewServer(app.handler())
	t.Cleanup(server.Close)
	_, reader := dialInfinite(t, server.URL, map[string]string{"type": "join", "version": version, "name": "Pilot"}, true)
	var welcome infiniteMessage
	if readInfinitePacket(t, reader, &welcome) || welcome.Type != "welcome" {
		t.Fatalf("expected a plain reliable welcome, got %+v", welcome)
	}
	a := app.infinite.public
	a.mu.Lock()
	p := a.pilots[0]
	for i := range 30 {
		a.bullets = append(a.bullets, infiniteBullet{ID: i + 1, X: p.X, Y: p.Y, Owner: p.ID, Kind: "rapid", Life: 2})
	}
	a.broadcast()
	a.mu.Unlock()
	var state infiniteSnapshot
	if !readInfinitePacket(t, reader, &state) || state.Type != "state" || len(state.Bullets) != 30 {
		t.Fatalf("expected compressed state with 30 projectiles, got %s with %d", state.Type, len(state.Bullets))
	}
}

func TestInfinitySocketControlsTwoPilotsAndUnionsTheirViews(t *testing.T) {
	app := newApp(4, nil)
	t.Cleanup(app.infinite.close)
	server := httptest.NewServer(app.handler())
	t.Cleanup(server.Close)
	conn, reader := dialInfinite(t, server.URL, map[string]string{"type": "join", "version": version, "name": "FIRST", "localName": "SECOND"}, false)
	var welcome struct {
		Type  string `json:"type"`
		ID    int    `json:"id"`
		Local int    `json:"localId"`
	}
	readInfinitePacket(t, reader, &welcome)
	if welcome.Type != "welcome" || welcome.ID == 0 || welcome.Local == 0 || welcome.ID == welcome.Local {
		t.Fatalf("invalid two-seat welcome: %+v", welcome)
	}
	for _, input := range []string{
		`{"type":"input","seq":11,"paused":true,"forward":true}`,
		`{"type":"input","seq":22,"local":true,"left":true}`,
	} {
		if _, err := conn.Write(maskedFrame(1, true, []byte(input))); err != nil {
			t.Fatal(err)
		}
	}
	a := app.infinite.public
	deadline := time.Now().Add(time.Second)
	for {
		a.mu.Lock()
		first, local := a.pilots[0], a.pilots[1]
		if first.input.Seq == 11 && local.input.Seq == 22 {
			if !first.paused || first.input.Forward || local.paused || !local.input.Left {
				t.Fatalf("controllers shared pause or input: %v %v", first.input, local.input)
			}
			first.X, local.X = 42, 5000
			first.Y, local.Y = 42, 42
			a.pickups = []Pickup{{X: first.X, Y: first.Y, Life: 1}, {X: local.X, Y: local.Y, Life: 1}, {X: 2500, Y: 42, Life: 1}}
			a.broadcast()
			a.mu.Unlock()
			break
		}
		a.mu.Unlock()
		if time.Now().After(deadline) {
			t.Fatal("independent input sequences never reached both pilots")
		}
		time.Sleep(time.Millisecond)
	}
	var state infiniteSnapshot
	readInfinitePacket(t, reader, &state)
	if state.Players != 2 || len(state.Tanks) != 2 || len(state.Pickups) != 2 ||
		state.Tanks[0].ID != welcome.ID || state.Tanks[1].ID != welcome.Local || state.Tanks[1].Name != "SECOND" ||
		state.Rules != nil || state.Result != nil {
		t.Fatalf("incorrect combined public snapshot: %+v", state)
	}
}

func TestPrivateInfinityTeamsCreditDepartedBotAndFreezeAtTarget(t *testing.T) {
	rules := defaultRules()
	rules.Infinity, rules.TeamMode, rules.InfinityTarget = true, "teams", 2
	rules.TeamNames[0] = "Amber"
	a := newRoomInfiniteArena(rules)
	now := time.Now()
	first, _ := a.joinSeats(fakeClient(), infiniteSeat{name: "First", team: 1}, nil, now)
	second, _ := a.joinSeats(fakeClient(), infiniteSeat{name: "Second", team: 2}, nil, now)
	ally, _ := a.joinSeats(fakeClient(), infiniteSeat{name: "Ally", team: 1}, nil, now)
	ally.Protected, second.Protected = false, false
	a.hurt(ally, first.ID, first.Team)
	if ally.HP == 0 || first.Score != 0 {
		t.Fatal("friendly fire off did not protect an ally")
	}
	a.hurt(second, a.nextID+1, 1) // A departed bot's projectile still belongs to its team.
	if a.teamScores != [4]int{1, -1, 0, 0} || a.result != nil || first.Score != 0 || second.Score != -1 {
		t.Fatalf("unexpected team scores: %v", a.teamScores)
	}
	second.HP, second.kit.Invulnerable = 1, 0
	a.rules.FriendlyFire = true
	a.hurt(ally, first.ID, first.Team)
	if ally.HP != 0 || a.teamScores != [4]int{1, -1, 0, 0} || a.result != nil {
		t.Fatal("a permitted friendly kill should net zero team points")
	}
	first.X, first.Y, second.X, second.Y = 35, 42, 65, 42
	applyPower(&first.kit, "starman", infinitePowerDuration, infiniteStarDuration)
	a.nextBot, a.nextPickup = 1<<32, 1<<32
	a.step(now)
	if a.result == nil || *a.result != (infiniteResult{Team: 1, Name: "Amber", Score: 2}) ||
		a.teamScores != [4]int{2, -2, 0, 0} || first.Score != 2 || second.Score != -2 {
		t.Fatalf("wrong final score or winner: %v %+v", a.teamScores, a.result)
	}
	if got := drain(first.client); len(got) != 2 || got[1]["type"] != "state" || got[1]["result"] == nil {
		t.Fatalf("the score target did not send a final state: %v", got)
	}
	tick := a.tick
	a.step(now.Add(time.Second))
	if a.tick != tick || len(first.client.send) != 0 {
		t.Fatal("completed arena continued simulating or broadcasting")
	}
}

func TestPrivateInfinityFreeForAllReachesPersonalTarget(t *testing.T) {
	rules := defaultRules()
	rules.Infinity, rules.InfinityTarget = true, 1
	a := newRoomInfiniteArena(rules)
	now := time.Now()
	winner, target := a.join(fakeClient(), "Winner", now), a.join(fakeClient(), "Target", now)
	target.Protected = false
	a.hurt(target, winner.ID, winner.Team)
	if a.result == nil || *a.result != (infiniteResult{ID: winner.ID, Name: winner.Name, Score: 1}) {
		t.Fatalf("incorrect free-for-all result: %+v", a.result)
	}
}

func TestInfiniteSnapshotSharesOnlyEqualVisibility(t *testing.T) {
	a := newSeededInfiniteArena(9)
	now := time.Now()
	for i, x := range []float64{0, 0, 0, 1} {
		c := fakeClient()
		c.updates = make(chan snapshotFrame, 1)
		c.ws = &wsConn{deflate: i != 2}
		p := a.join(c, "Pilot", now)
		p.X, p.Y = x, 0
	}
	for i := range 30 {
		a.bullets = append(a.bullets, infiniteBullet{ID: i + 1, Owner: 1, Kind: "rapid", Life: 2})
	}
	a.pickups = append(a.pickups, Pickup{ID: 1, X: -infiniteSight, Life: 1})
	a.broadcast()
	first, same, plain, edge := <-a.pilots[0].client.updates, <-a.pilots[1].client.updates, <-a.pilots[2].client.updates, <-a.pilots[3].client.updates
	if !first.compressed || !same.compressed || plain.compressed || !edge.compressed || &first.data[0] != &same.data[0] {
		t.Fatal("equal views did not share an encoded snapshot across compatible peers")
	}
	if decoded, err := inflateMessage(first.data, lenLimitForTest); err != nil || !bytes.Equal(decoded, plain.data) {
		t.Fatalf("compressed and plain views differ: %v", err)
	}
	var nearState, edgeState infiniteSnapshot
	if err := json.Unmarshal(plain.data, &nearState); err != nil {
		t.Fatal(err)
	}
	edgeData, err := inflateMessage(edge.data, lenLimitForTest)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(edgeData, &edgeState); err != nil {
		t.Fatal(err)
	}
	if len(nearState.Pickups) != 1 || len(edgeState.Pickups) != 0 || len(edgeState.Tanks) != 4 || len(edgeState.Bullets) != 30 {
		t.Fatal("sharing snapshots changed the viewport at the edge of sight")
	}
}

func dialInfinite(t *testing.T, url string, first map[string]string, deflate bool) (net.Conn, *bufio.Reader) {
	t.Helper()
	host := strings.TrimPrefix(url, "http://")
	c, err := net.Dial("tcp", host)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = c.Close() })
	if err := c.SetDeadline(time.Now().Add(3 * time.Second)); err != nil {
		t.Fatal(err)
	}
	extension := ""
	if deflate {
		extension = "Sec-WebSocket-Extensions: permessage-deflate; client_max_window_bits\r\n"
	}
	_, err = fmt.Fprintf(c, "GET /ws/infinite HTTP/1.1\r\nHost: %s\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nOrigin: %s\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n%s\r\n", host, url, extension)
	if err != nil {
		t.Fatal(err)
	}
	reader := bufio.NewReader(c)
	response, err := http.ReadResponse(reader, &http.Request{Method: "GET"})
	if err != nil {
		t.Fatal(err)
	}
	if response.StatusCode != http.StatusSwitchingProtocols {
		t.Fatalf("expected WebSocket upgrade, got %s", response.Status)
	}
	want := ""
	if deflate {
		want = "permessage-deflate; server_no_context_takeover; client_no_context_takeover"
	}
	if got := response.Header.Get("Sec-WebSocket-Extensions"); got != want {
		t.Fatalf("unexpected negotiated extension %q, want %q", got, want)
	}
	message, err := json.Marshal(first)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := c.Write(maskedFrame(1, true, message)); err != nil {
		t.Fatal(err)
	}
	return c, reader
}

func readInfinitePacket(t *testing.T, reader *bufio.Reader, target any) bool {
	t.Helper()
	var header [2]byte
	if _, err := io.ReadFull(reader, header[:]); err != nil {
		t.Fatal(err)
	}
	if header[0]&^wsCompressed != 129 {
		t.Fatalf("expected a text frame, got %d", header[0])
	}
	compressed := header[0]&wsCompressed != 0
	size := int(header[1])
	if size == 126 {
		if _, err := io.ReadFull(reader, header[:]); err != nil {
			t.Fatal(err)
		}
		size = int(binary.BigEndian.Uint16(header[:]))
	}
	packet := make([]byte, size)
	if _, err := io.ReadFull(reader, packet); err != nil {
		t.Fatal(err)
	}
	if compressed {
		var err error
		packet, err = inflateMessage(packet, lenLimitForTest)
		if err != nil {
			t.Fatal(err)
		}
	}
	if err := json.Unmarshal(packet, target); err != nil {
		t.Fatalf("decoding %q: %v", packet, err)
	}
	return compressed
}

func TestPublicInfinityReclaimsIdleSeat(t *testing.T) {
	server := newInfiniteServer(newHub(4))
	now := time.Now()
	c := fakeClient()
	if !server.admit(c) {
		t.Fatal("could not open a test Infinity connection")
	}
	conn, reject := server.join(c, infiniteMessage{}, now)
	if reject != "" {
		t.Fatal(reject)
	}
	server.public.setInput(conn.pilot, Input{}, false, now.Add(4*time.Minute))
	aim := Input{AimOnly: true, StickX: 1}
	aimedAt := now.Add(4*time.Minute + 30*time.Second)
	server.public.setInput(conn.pilot, aim, false, aimedAt)
	expiry := aimedAt.Add(infinitePublicIdle)
	server.public.spawn(conn.pilot, conn.pilot.X, conn.pilot.Y, 2, 5)
	server.public.setInput(conn.pilot, aim, false, expiry.Add(-time.Second))
	server.step(expiry.Add(-time.Nanosecond))
	if server.public.players != 1 {
		t.Fatal("pilot was removed before five minutes elapsed from the last active control")
	}
	server.public.setInput(conn.pilot, Input{}, false, expiry)
	server.step(expiry)
	select {
	case <-c.done:
	default:
		t.Fatal("neutral keepalive or stationary aim retained a public socket")
	}
	if server.public.players != 0 || len(server.connections) != 0 {
		t.Fatal("idle public pilot still occupies admission capacity")
	}
}

func TestPrivateInfinityAuthenticatesAndIsolatesRoomPilots(t *testing.T) {
	h, clients, firstRoom := makeRoom(t, 2)
	otherHost := fakeClient()
	h.addClient(otherHost)
	action(t, h, otherHost, map[string]any{"type": "create", "name": "Other host"})
	otherRoom := otherHost.room
	h.mu.Lock()
	firstRoom.Game.Rules.Infinity = true
	otherRoom.Game.Rules.Infinity = true
	h.startRoomInfinity(firstRoom)
	h.startRoomInfinity(otherRoom)
	h.mu.Unlock()
	server := newInfiniteServer(h)
	now := time.Now()
	join := func(code, token string) (infiniteConnection, *Client, string) {
		t.Helper()
		c := fakeClient()
		if !server.admit(c) {
			t.Fatal("could not open a test Infinity connection")
		}
		m, reject := server.join(c, infiniteMessage{Name: "Forged name", Code: code, Token: token}, now)
		if reject != "" {
			server.remove(c)
		}
		return m, c, reject
	}
	if _, _, reject := join(firstRoom.Code, otherHost.player.Token); reject == "" {
		t.Fatal("cross-room token admitted")
	}
	if _, _, reject := join(firstRoom.Code, ""); reject == "" {
		t.Fatal("private room join without token admitted")
	}
	first, firstSocket, reject := join(firstRoom.Code, clients[0].player.Token)
	if reject != "" || first.pilot.Name != clients[0].player.Name {
		t.Fatalf("authorized pilot rejected or caller name trusted: %s", reject)
	}
	second, _, reject := join(firstRoom.Code, clients[1].player.Token)
	if reject != "" || second.arena != first.arena {
		t.Fatalf("pilots in the same room did not share an arena: %s", reject)
	}
	if _, _, reject := join(firstRoom.Code, clients[1].player.Token); reject == "" {
		t.Fatal("one room member joined twice")
	}
	other, _, reject := join(otherRoom.Code, otherHost.player.Token)
	if reject != "" || other.arena == first.arena {
		t.Fatalf("distinct rooms shared an arena: %s", reject)
	}
	public, _, reject := join("", "")
	if reject != "" || public.arena == first.arena || public.arena == other.arena {
		t.Fatalf("public and private pilots shared an arena: %s", reject)
	}
	first.pilot.Score++
	if other.arena.leaderboard(nil)[0].Score != 0 || public.arena.leaderboard(nil)[0].Score != 0 {
		t.Fatal("private kill leaked to another arena")
	}
	server.step(now.Add(infinitePublicIdle))
	if first.arena.players != 2 || other.arena.players != 1 {
		t.Fatal("public idle timer affected a private arena")
	}
	action(t, h, clients[0], map[string]any{"type": "leave"})
	server.step(now)
	select {
	case <-firstSocket.done:
	default:
		t.Fatal("room departure did not revoke the Infinity socket")
	}
	if first.arena.players > 1 {
		t.Fatal("room departure retained a private pilot")
	}
}
