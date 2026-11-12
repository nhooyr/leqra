package main

import (
	"encoding/json"
	"math"
	"testing"
)

func Test427PowerDurationByArenaForEveryPickup(t *testing.T) {
	for _, size := range []struct {
		cols, rows                int
		duration, ground, starman float64
	}{
		{7, 7, 10, 30, 4}, {9, 8, 10, 30, 4}, {12, 10, 10, 32, 5},
		{14, 12, 15, 45, 6}, {16, 14, 15, 61, 7}, {24, 14, 15, 90, 8},
	} {
		g := battle(2)
		g.World.Cols, g.World.Rows = size.cols, size.rows
		if got := pickupLifetime(size.cols, size.rows); got != size.ground {
			t.Fatalf("ground %dx%d: %v", size.cols, size.rows, got)
		}
		for _, kind := range pickupTypes {
			p := &Tank{Alive: true}
			g.grantPower(p, kind)
			got, want := p.PowerTime, size.duration
			switch kind {
			case "shield":
				got = p.Shield
			case "speed":
				got = p.SpeedTime
			case "ghost":
				got = p.GhostTime
			case "starman":
				got, want = p.StarmanTime, size.starman
				if p.GhostTime != want || p.Invulnerable != want {
					t.Fatalf("Starman on %dx%d: wall phasing=%v invulnerability=%v, want %v", size.cols, size.rows, p.GhostTime, p.Invulnerable, want)
				}
			}
			if got != want {
				t.Fatalf("%s on %dx%d: %v, want %v", kind, size.cols, size.rows, got, want)
			}
		}
		g.World.Cols, g.World.Rows = size.rows, size.cols
		p := &Tank{Alive: true}
		g.grantPower(p, "starman")
		if p.StarmanTime != size.starman {
			t.Fatalf("Starman on portrait %dx%d: %v, want %v", size.rows, size.cols, p.StarmanTime, size.starman)
		}
	}
	if pickupLifetime(0, 0) != 0 {
		t.Fatal("invalid arena gained pickups")
	}
}

func Test427LargeArenaBuffRefreshKeepsIndependentCapsAndCharges(t *testing.T) {
	g := battle(2)
	g.World.Cols, g.World.Rows = 14, 12
	p := g.Tanks[0]
	g.grantPower(p, "cannon")
	for _, kind := range []string{"shield", "speed", "ghost"} {
		for n := 0; n < 7; n++ {
			g.grantPower(p, kind)
		}
	}
	if p.Power != "cannon" || p.Charges != 3 || p.PowerTime != 15 || p.SpeedStacks != 5 || p.ShieldCharges != 5 || p.SpeedTime != 15 || p.Shield != 15 || p.GhostTime != 15 {
		t.Fatalf("lost independent power state: %+v", p)
	}
	g.grantPower(p, "rapid")
	p.MachineRounds = 12
	p.PowerTime = 2
	g.grantPower(p, "rapid")
	if p.MachineRounds != 180 || p.PowerTime != 15 || p.SpeedStacks != 5 || p.ShieldCharges != 5 {
		t.Fatalf("refresh failed: %+v", p)
	}
	if grenadeFuse != 10 {
		t.Fatal("equipped duration must not change a thrown grenade fuse")
	}
}

func Test427MachineGunSpendsOnlySuccessfulRounds(t *testing.T) {
	g := battle(2)
	p := g.Tanks[0]
	g.grantPower(p, "rapid")
	for n := 0; n < 100; n++ {
		g.Tick++
		p.Cooldown = 1
		if g.fire(p) {
			t.Fatal("fired during cooldown")
		}
	}
	p.Cooldown = 0
	for n := 0; n < machineCapacity; n++ {
		g.Bullets = append(g.Bullets, &Bullet{Owner: p.ID})
	}
	if g.fire(p) || p.MachineRounds != 180 {
		t.Fatal("capacity-blocked attempt consumed firing time")
	}
	g.Bullets = nil
	for n := 0; n < 180; n++ {
		g.Tick++
		if !g.fire(p) {
			t.Fatalf("productive shot %d was blocked", n)
		}
		if g.Bullets[0].Kind != "rapid" {
			t.Fatalf("shot %d lost rapid power", n)
		}
		if n < 179 && g.fire(p) {
			t.Fatal("same-tick attempt bypassed 60 Hz")
		}
		if p.MachineRounds != 179-n {
			t.Fatalf("budget after shot %d: %d", n, p.MachineRounds)
		}
		g.Bullets = nil
		// Idle time / released fire is not a separate firing-budget clock.
		g.Tick += 30
	}
	if p.Power != "" || p.PowerTime != 0 || p.MachineRounds != 0 || p.Charges != 0 {
		t.Fatalf("exhaustion did not return to standard: %+v", p)
	}
}

func Test427MachineGunReflectedInsideWallSpendsOneRound(t *testing.T) {
	g := battle(2)
	p := g.Tanks[0]
	g.grantPower(p, "rapid")
	p.GhostTime, p.X = 10, 104
	g.World.Walls = append(g.World.Walls, Wall{X: 100, Y: 180, W: 8, H: 80})
	if !g.fire(p) || p.MachineRounds != 179 || len(g.Bullets) != 1 || g.Bullets[0].VX >= 0 {
		t.Fatal("wall-reflected fire did not consume exactly one round")
	}
	if g.fire(p) || p.MachineRounds != 179 {
		t.Fatal("same-tick attempt consumed a second round")
	}
	g.Tick++
	p.X = 70
	if !g.fire(p) || p.MachineRounds != 178 {
		t.Fatal("clear muzzle failed after reflected shot")
	}
}

func Test427UnusedMachineGunStillExpiresAtRegularMapDuration(t *testing.T) {
	for _, size := range []struct {
		cols, rows int
		duration   float64
	}{{12, 10, 10}, {14, 12, 15}} {
		g := battle(2)
		g.World.Cols, g.World.Rows = size.cols, size.rows
		g.Rules.PickupRate = "off"
		g.Pickups = nil
		p := g.Tanks[0]
		g.grantPower(p, "rapid")
		for n := 0; n < int(size.duration*60)-1; n++ {
			g.step(tickDT, [maxTanks]Input{}, testPlayers(2))
		}
		if p.Power != "rapid" || p.MachineRounds != 180 || math.Abs(p.PowerTime-tickDT) > 1e-8 {
			t.Fatalf("idle duration/budget changed early: %+v", p)
		}
		g.step(tickDT*2, [maxTanks]Input{}, testPlayers(2))
		if p.Power != "" || p.MachineRounds != 0 {
			t.Fatal("unused weapon survived equipped expiry")
		}
	}
}

func Test427MachineGunBudgetSerializedAndClearedOnRespawn(t *testing.T) {
	g := battle(2)
	p := g.Tanks[0]
	g.grantPower(p, "rapid")
	g.fire(p)
	encoded, err := json.Marshal(newHub(2).stateMessage(&Room{Game: g}))
	if err != nil {
		t.Fatal(err)
	}
	var state struct {
		Tanks []struct {
			ID            int `json:"id"`
			MachineRounds int `json:"machineRounds"`
		}
	}
	if err = json.Unmarshal(encoded, &state); err != nil {
		t.Fatal(err)
	}
	if len(state.Tanks) != 2 || state.Tanks[0].MachineRounds != 179 {
		t.Fatalf("budget absent in snapshot: %s", encoded)
	}
	g.makeMaze(9, 8)
	g.respawnTank(p)
	if p.MachineRounds != 0 {
		t.Fatal("respawn carried an old weapon budget")
	}
}
