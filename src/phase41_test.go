package main

import (
	"encoding/json"
	"math"
	"os"
	"testing"
)

func Test41CannonBoundaryAllMaps(t *testing.T) {
	for _, size := range []string{"compact", "standard", "large", "huge", "giant", "ultrawide"} {
		for _, angle := range []float64{0, .3, math.Pi / 4, math.Pi / 2, 2.3, math.Pi, 4.7, 5.8} {
			g := newGame(41)
			g.Rules.MapSize = size
			g.startMatch(testPlayers(1))
			p := g.Tanks[0]
			p.Angle = angle
			p.X = 84
			p.Y = 84
			b := launchCannon39(g, 0)
			p.Alive = false
			for i := 0; i < 400 && !b.Dead; i++ {
				g.updateBullets(tickDT)
				if b.X < 18-1e-7 || b.Y < 18-1e-7 || b.X > g.World.Width-18+1e-7 || b.Y > g.World.Height-18+1e-7 {
					t.Fatalf("outside %s %+v", size, b)
				}
				if math.Abs(math.Hypot(b.VX, b.VY)-1128) > 1e-6 {
					t.Fatal("bounce changed speed")
				}
			}
			if !b.Dead || b.Bounces < 1 || b.Bounces > 22 {
				t.Fatalf("lifetime/bounds %s %+v", size, b)
			}
		}
	}
}
func Test41CannonCornerAndMuzzle(t *testing.T) {
	g := battle(2)
	g.Tanks[1].Alive = false
	p := g.Tanks[0]
	p.X = 21
	p.Y = 21
	p.Angle = -3 * math.Pi / 4
	b := launchCannon39(g, 0)
	if b.Bounces != 1 || b.VX <= 0 || b.VY <= 0 || b.X < 18 || b.Y < 18 {
		t.Fatalf("corner launch %+v", b)
	}
	p.Alive = false
	g.updateBullets(.1)
	if b.Dead {
		t.Fatal("muzzle died")
	}
	hit := g.rayBounds(100, 100, -200, -200, 14)
	if hit == nil || hit.NX != 1 || hit.NY != 1 || math.Abs(hit.T-.41) > 1e-8 {
		t.Fatal(hit)
	}
}
func Test41ReturningCannonSelfDamageAllSeats(t *testing.T) {
	for id := 0; id < maxTanks; id++ {
		g := battle(8)
		g.Rules.FriendlyFire = false
		for _, p := range g.Tanks {
			p.Alive = false
		}
		p := g.Tanks[id]
		p.Alive = true
		p.Team = 2
		p.X = 80
		p.Y = 80
		p.Angle = 0
		p.Invulnerable = 0
		b := launchCannon39(g, id)
		for i := 0; i < 180 && p.Alive; i++ {
			g.updateBullets(tickDT)
		}
		if p.Alive || !b.Dead || p.stats.SelfDestructs != 1 || p.stats.Deaths != 1 {
			t.Fatalf("self damage slot %d", id)
		}
	}
}
func ghostArena41() *Game {
	g := battle(2)
	g.World = World{Cols: 12, Rows: 10, Width: 1008, Height: 840, Walls: []Wall{{-4, -4, 1016, 8, "h", 0}, {-4, 836, 1016, 8, "h", 840}, {-4, -4, 8, 848, "v", 0}, {1004, -4, 8, 848, "v", 1008}, {248, -4, 8, 848, "v", 252}, {-4, 332, 1016, 8, "h", 336}}}
	g.spatial = nil
	g.Tanks[0].X = 210
	g.Tanks[0].Y = 210
	g.Tanks[1].X = 800
	g.Tanks[1].Y = 600
	return g
}
func Test41GhostIndependentRefreshAndSpeed(t *testing.T) {
	for _, order := range [][]string{{"cannon", "scope", "shield", "speed", "ghost"}, {"ghost", "speed", "cannon", "shield", "scope"}} {
		g := ghostArena41()
		p := g.Tanks[0]
		for _, power := range order {
			g.grantPower(p, power)
		}
		if p.GhostTime != 10 || p.SpeedTime != boostDuration || p.ScopeTime != 10 || p.Shield != 10 || p.Power != "cannon" || p.Charges != 3 {
			t.Fatal("stacking")
		}
		for i := 0; i < 30; i++ {
			g.control(p, Input{Forward: true}, tickDT)
		}
		if math.Abs(p.X-(210+128*1.65*.5)) > 1e-6 || p.X < 256 {
			t.Fatal("speed+ghost blocked", p.X)
		}
		old := p.SpeedTime
		g.grantPower(p, "ghost")
		if p.GhostTime != 10 || p.SpeedTime != old {
			t.Fatal("refresh interferes")
		}
	}
}
func Test41GhostOuterRimStillSolid(t *testing.T) {
	g := ghostArena41()
	p := g.Tanks[0]
	p.GhostTime = 10
	g.moveTank(p, 99999, -99999)
	if p.X != 987 || p.Y != 21 {
		t.Fatal(p)
	}
	g.moveTank(p, -99999, 99999)
	if p.X != 21 || p.Y != 819 {
		t.Fatal(p)
	}
}
func Test41GhostSolidifiesSafelyAcrossGeneratedMazes(t *testing.T) {
	for _, size := range sizeCases38 {
		for seed := int64(0); seed < 10; seed++ {
			g := newGame(seed)
			g.Rules.MapSize = size.name
			g.startMatch(testPlayers(8))
			p := g.Tanks[0]
			for wi, w := range g.World.Walls {
				if wi%5 != 0 {
					continue
				}
				p.X = clamp(w.X+w.W/2, 21, g.World.Width-21)
				p.Y = clamp(w.Y+w.H/2, 21, g.World.Height-21)
				x, y := p.X, p.Y
				p.GhostTime = .001
				before := p.SpawnSerial
				g.advanceGhost(p, tickDT)
				if p.GhostTime != 0 || !g.clearTankAt(p.X, p.Y, p.R) || p.SpawnSerial != before || p.Invulnerable != .75 {
					t.Fatalf("unsafe expiry %s wall %d", size.name, wi)
				}
				if dist(x, y, p.X, p.Y) > 45 {
					t.Fatal("distant exit", dist(x, y, p.X, p.Y))
				}
			}
		}
	}
}
func Test41GhostExpiryInOpenSpaceNoTeleport(t *testing.T) {
	g := ghostArena41()
	p := g.Tanks[0]
	p.GhostTime = .001
	x, y := p.X, p.Y
	g.advanceGhost(p, tickDT)
	if p.X != x || p.Y != y {
		t.Fatal("open exit moved")
	}
}
func Test41GhostExpiryRestoresWallCollision(t *testing.T) {
	g := ghostArena41()
	p := g.Tanks[0]
	p.X = 252
	p.Y = 210
	p.GhostTime = .001
	g.control(p, Input{Forward: true}, tickDT)
	if p.GhostTime != 0 || !g.clearTankAt(p.X, p.Y, p.R) {
		t.Fatal("not solid")
	}
	for i := 0; i < 60; i++ {
		g.control(p, Input{Forward: true}, tickDT)
	}
	if p.X > 231.001 {
		t.Fatal("phasing survived expiry", p.X)
	}
}
func Test41GhostNotInvulnerableOrWeaponPiercing(t *testing.T) {
	g := ghostArena41()
	p := g.Tanks[0]
	g.grantPower(p, "ghost")
	p.X = 252
	p.Y = 210
	if g.fire(p) {
		t.Fatal("normal round can fire from within wall")
	}
	g.grantPower(p, "cannon")
	if !g.fire(p) {
		t.Fatal("cannon blocked")
	}
	p.Cooldown = 0
	p.X = 210
	p.Power = ""
	if !g.fire(p) {
		t.Fatal("ghost cannot fire in open")
	}
	g.hurt(p, &Bullet{Owner: 1})
	if p.Alive || p.stats.Deaths != 1 {
		t.Fatal("ghost immunity")
	}
}
func Test41GhostLivesAndObjectivesReset(t *testing.T) {
	for _, mode := range []string{"elimination", "ctf", "koth"} {
		g := newGame(41)
		ps := testPlayers(4)
		for i, p := range ps {
			if p != nil {
				p.Team = 1 + i%2
			}
		}
		g.Rules.Mode = mode
		g.Rules.TeamMode = "teams"
		g.startMatch(ps)
		g.Phase = "playing"
		p := g.Tanks[0]
		g.grantPower(p, "ghost")
		g.grantPower(p, "speed")
		p.Alive = false
		if mode != "elimination" {
			g.respawnTank(p)
			if p.GhostTime != 0 || p.SpeedTime != 0 {
				t.Fatal("respawn retained ghost")
			}
		}
		g.grantPower(p, "ghost")
		g.startRound(ps)
		if g.Tanks[0].GhostTime != 0 {
			t.Fatal("new round retained ghost")
		}
	}
}
func Test41GhostRulesWireAndNoClientGrant(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	rules := defaultRules()
	rules.Weapons = []string{"ghost", "speed"}
	action(t, h, cs[1], map[string]any{"type": "rules", "rules": rules})
	if !hasError(cs[1], "not_host") {
		t.Fatal("guest changed ghost")
	}
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	if len(r.Game.Rules.Weapons) != 2 {
		t.Fatal("host rule")
	}
	r.Game = ghostArena41()
	action(t, h, cs[0], map[string]any{"type": "input", "room": r.Code, "seq": 12, "ghostTime": 999, "power": "ghost"})
	if r.Game.Tanks[0].GhostTime != 0 {
		t.Fatal("forged ghost")
	}
	g := r.Game
	g.grantPower(g.Tanks[0], "ghost")
	data, _ := json.Marshal(g.Tanks[0])
	var v map[string]any
	json.Unmarshal(data, &v)
	if v["ghostTime"] != 10.0 {
		t.Fatal("ghost missing from snapshots")
	}
}
func Test41GhostEnabledAndMapPickupCounts(t *testing.T) {
	for _, s := range sizeCases38 {
		g := newGame(41)
		g.Rules.MapSize = s.name
		g.Rules.Weapons = []string{"ghost"}
		g.startMatch(testPlayers(8))
		if len(g.Pickups) != s.start {
			t.Fatal("starting stock")
		}
		for i := 0; i < 400; i++ {
			g.spawnPower()
		}
		if len(g.Pickups) != s.cap {
			t.Fatal("cap")
		}
		for _, p := range g.Pickups {
			if p.Type != "ghost" {
				t.Fatal("wrong pickup")
			}
		}
	}
}
func Test41GhostBotCrossesWall(t *testing.T) {
	g := ghostArena41()
	p, e := g.Tanks[0], g.Tanks[1]
	p.Bot = true
	p.Difficulty = "easy"
	p.GhostTime = 10
	e.X = 600
	e.Y = 210
	for i := 0; i < 180; i++ {
		g.botControl(p, tickDT)
	}
	if p.X < 300 || p.GhostTime >= 10 {
		t.Fatal("bot did not use Ghost", p.X)
	}
}

// Optional reproducible cross-language fixture; the normal test asserts the Go
// behavior above. Browser/Node suites replay these exact controls through Net.move.
func Test41WriteMovementParity(t *testing.T) {
	path := os.Getenv("LEQRA_PHASE_PARITY")
	if path == "" {
		t.Skip("fixture export only")
	}
	type trial struct {
		World   World   `json:"world"`
		Initial Tank    `json:"initial"`
		Inputs  []Input `json:"inputs"`
		States  []Tank  `json:"states"`
	}
	var out []trial
	for _, start := range []struct{ x, y, ghost, speed float64 }{{210, 210, 10, 6}, {252, 336, .005, 6}, {252, 210, .02, 0}, {970, 800, 1, 6}} {
		g := ghostArena41()
		p := g.Tanks[0]
		p.X = start.x
		p.Y = start.y
		p.GhostTime = start.ghost
		p.SpeedTime = start.speed
		tr := trial{World: g.World, Initial: *p}
		for i := 0; i < 120; i++ {
			in := Input{Forward: i < 85, Reverse: i >= 100, Right: i >= 30 && i < 50, Left: i >= 80 && i < 90}
			g.control(p, in, tickDT)
			tr.Inputs = append(tr.Inputs, in)
			tr.States = append(tr.States, *p)
		}
		out = append(out, tr)
	}
	data, _ := json.Marshal(out)
	if err := os.WriteFile(path, data, 0644); err != nil {
		t.Fatal(err)
	}
}
