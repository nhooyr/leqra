package main

import (
	"encoding/json"
	"math"
	"testing"
)

var sizeCases38 = []struct {
	name                   string
	cols, rows, start, cap int
}{
	{"compact", 7, 7, 2, 5}, {"standard", 9, 8, 3, 7}, {"large", 12, 10, 4, 12}, {"huge", 14, 12, 5, 17}, {"giant", 16, 14, 6, 23}, {"ultrawide", 24, 14, 7, 34},
}

func Test38SizesAndPickupCounts(t *testing.T) {
	for _, v := range sizeCases38 {
		t.Run(v.name, func(t *testing.T) {
			g := newGame(38)
			g.Rules.MapSize = v.name
			if err := validateRules(g.Rules); err != nil {
				t.Fatal(err)
			}
			c, r := g.mapDimensions()
			if c != v.cols || r != v.rows {
				t.Fatal("wrong dimensions")
			}
			if pickupCap(c, r) != v.cap || startingPickups(c, r) != v.start {
				t.Fatalf("counts: %d, %d", startingPickups(c, r), pickupCap(c, r))
			}
		})
	}
	if defaultRules().MapSize != "large" {
		t.Fatal("default map must remain 12x10")
	}
	if pickupCap(0, 14) != 0 || startingPickups(0, 14) != 0 {
		t.Fatal("uninitialized maze must not spawn")
	}
}
func Test38StartsAndCapsEveryModeEightTanks(t *testing.T) {
	for _, v := range sizeCases38 {
		for _, mode := range []string{"elimination", "ctf", "koth"} {
			t.Run(v.name+"/"+mode, func(t *testing.T) {
				for seed := int64(0); seed < 20; seed++ {
					g := newGame(seed)
					g.Rules.MapSize = v.name
					g.Rules.Mode = mode
					g.Rules.TeamMode = "teams"
					ps := testPlayers(8)
					for i, p := range ps {
						p.Team = 1 + i%2
					}
					g.startMatch(ps)
					if len(g.Pickups) != v.start {
						t.Fatalf("seed %d: got %d starts, want %d", seed, len(g.Pickups), v.start)
					}
					for i := 0; i < 400; i++ {
						g.spawnPower()
					}
					if len(g.Pickups) != v.cap {
						t.Fatalf("seed %d: got %d cap, want %d", seed, len(g.Pickups), v.cap)
					}
					for i, p := range g.Pickups {
						for _, tank := range g.Tanks {
							if tank.Alive && dist(p.X, p.Y, tank.X, tank.Y) < cellSize*.85 {
								t.Fatal("pickup on tank")
							}
						}
						for j, q := range g.Pickups {
							if i != j && dist(p.X, p.Y, q.X, q.Y) < cellSize*1.1 {
								t.Fatal("pickups too close")
							}
						}
					}
				}
			})
		}
	}
}
func Test38DisabledPickupsAndFilteredLaser(t *testing.T) {
	for _, v := range sizeCases38 {
		for _, off := range []bool{true, false} {
			g := newGame(38)
			g.Rules.MapSize = v.name
			if off {
				g.Rules.PickupRate = "off"
			} else {
				g.Rules.Weapons = []string{}
			}
			g.startMatch(testPlayers(2))
			for i := 0; i < 100; i++ {
				g.spawnPower()
			}
			if len(g.Pickups) != 0 {
				t.Fatal("disabled pickups spawned")
			}
		}
	}
	g := newGame(38)
	g.Rules.MapSize = "giant"
	g.Rules.Weapons = []string{"laser"}
	g.startMatch(testPlayers(8))
	for i := 0; i < 100; i++ {
		g.spawnPower()
	}
	if len(g.Pickups) != 23 {
		t.Fatal("laser did not fill capacity")
	}
	for _, p := range g.Pickups {
		if p.Type != "laser" {
			t.Fatal("filter bypassed")
		}
	}
}
func Test38GiantConnectedAndHighSeats(t *testing.T) {
	for seed := int64(0); seed < 30; seed++ {
		g := newGame(seed)
		g.Rules.MapSize = "giant"
		g.startMatch(testPlayers(8))
		if len(g.Neighbors) != 224 || g.World.Width != 1344 || g.World.Height != 1176 {
			t.Fatal("giant world")
		}
		seen := map[int]bool{0: true}
		queue := []int{0}
		for i := 0; i < len(queue); i++ {
			for _, n := range g.Neighbors[queue[i]] {
				if !seen[n] {
					seen[n] = true
					queue = append(queue, n)
				}
			}
		}
		if len(seen) != 224 {
			t.Fatal("disconnected maze")
		}
		positions := map[[2]float64]bool{}
		for _, p := range g.Tanks {
			if p == nil || !p.Alive {
				t.Fatal("missing tank")
			}
			key := [2]float64{p.X, p.Y}
			if positions[key] {
				t.Fatal("stacked spawn")
			}
			positions[key] = true
		}
	}
}
func TestLaserRefreshKeepsIndependentBuffs(t *testing.T) {
	g := battle(2)
	p := g.Tanks[0]
	g.grantPower(p, "laser")
	g.grantPower(p, "shield")
	g.grantPower(p, "speed")
	p.Cooldown = .5
	p.Charges, p.PowerTime = 1, 2
	g.grantPower(p, "laser")
	if p.Power != "laser" || p.PowerTime != 10 || p.Charges != 3 || p.ShieldCharges != 1 || p.SpeedStacks != 1 || p.Cooldown != .5 {
		t.Fatalf("laser refresh changed unrelated state: %+v", p)
	}
}
func TestLaserTickExpiryRespawnAndNewRound(t *testing.T) {
	for _, slot := range []int{0, 1, 7} {
		t.Run(string(rune('0'+slot)), func(t *testing.T) {
			g := battle(8)
			ps := testPlayers(8)
			g.Pickups = nil
			p := g.Tanks[slot]
			g.grantPower(p, "laser")
			g.Phase = "countdown"
			g.PhaseTime = 2
			g.step(tickDT, [maxTanks]Input{}, ps)
			if p.PowerTime != 10 {
				t.Fatal("countdown drained laser")
			}
			g.Phase = "playing"
			g.step(.1, [maxTanks]Input{}, ps)
			if math.Abs(p.PowerTime-9.9) > 1e-8 {
				t.Fatal("wrong timer")
			}
			p.PowerTime = .001
			g.step(tickDT, [maxTanks]Input{}, ps)
			if p.Power != "" || p.PowerTime != 0 {
				t.Fatal("expired laser stayed equipped")
			}
			g.grantPower(p, "laser")
			g.respawnTank(p)
			if p.Power != "" || p.PowerTime != 0 {
				t.Fatal("respawn retained laser")
			}
			g.grantPower(p, "laser")
			g.startRound(ps)
			if next := g.Tanks[slot]; next.Power != "" || next.PowerTime != 0 {
				t.Fatal("new round retained laser")
			}
		})
	}
	g, ps := objectiveFixture("ctf")
	for _, p := range g.Tanks {
		if p != nil {
			g.grantPower(p, "laser")
		}
	}
	g.beginSuddenDeath(ps, false)
	for _, p := range g.Tanks {
		if p != nil && (p.Power != "" || p.PowerTime != 0) {
			t.Fatal("sudden death retained laser")
		}
	}
}
func TestLaserCollectionAndSnapshot(t *testing.T) {
	g := battle(2)
	p := g.Tanks[1]
	g.Pickups = []*Pickup{{X: p.X, Y: p.Y, Type: "laser", Life: pickupLifetime(g.World.Cols, g.World.Rows)}}
	g.step(tickDT, [maxTanks]Input{}, testPlayers(2))
	if p.Power != "laser" || p.PowerTime != 10 || p.Charges != 3 || len(g.Pickups) != 0 {
		t.Fatal("collection failed")
	}
	data, err := json.Marshal(p)
	if err != nil {
		t.Fatal(err)
	}
	var wire map[string]any
	json.Unmarshal(data, &wire)
	if wire["power"] != "laser" || wire["powerTime"] != float64(10) || wire["charges"] != float64(3) {
		t.Fatal("laser missing in tank snapshot")
	}
	if _, ok := wire["scopeTime"]; ok {
		t.Fatal("tank snapshot still carries a separate scope timer")
	}
}
func Test38HostRulesAndPresetValidation(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	rules := defaultRules()
	rules.MapSize = "giant"
	action(t, h, cs[1], map[string]any{"type": "rules", "rules": rules})
	if !hasError(cs[1], "not_host") {
		t.Fatal("guest edited rules")
	}
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	if r.Game.Rules.MapSize != "giant" || len(r.Game.Rules.Weapons) != len(pickupTypes) {
		t.Fatal("giant map and pickup settings not saved")
	}
	for _, bad := range []string{"", "18x16", "unbounded"} {
		rules.MapSize = bad
		if validateRules(rules) == nil {
			t.Fatal("invalid map accepted")
		}
	}
	rules.MapSize = "giant"
	rules.Weapons = []string{"scope"}
	if validateRules(rules) == nil {
		t.Fatal("retired scope pickup accepted")
	}
	rules.Weapons = []string{"laser"}
	if validateRules(rules) != nil {
		t.Fatal("laser-only rejected")
	}
	data, _ := json.Marshal(rules)
	var loaded MatchRules
	json.Unmarshal(data, &loaded)
	if loaded.MapSize != "giant" || loaded.Weapons[0] != "laser" {
		t.Fatal("preset lost fields")
	}
}
func TestLaserDoesNotChangeMovement(t *testing.T) {
	a, b := battle(2), battle(2)
	a.grantPower(a.Tanks[0], "laser")
	for i := 0; i < 20; i++ {
		in := Input{Forward: true, Right: i > 5}
		a.control(a.Tanks[0], in, tickDT)
		b.control(b.Tanks[0], in, tickDT)
	}
	x, y := a.Tanks[0], b.Tanks[0]
	if x.X != y.X || x.Y != y.Y || x.Angle != y.Angle {
		t.Fatal("laser changed movement")
	}
}
