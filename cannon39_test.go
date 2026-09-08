package main

import (
	"encoding/json"
	"fmt"
	"math"
	"testing"
)

func cannonBattle39(n int) *Game {
	g := battle(n)
	g.World.Walls = append(g.World.Walls,
		Wall{X: 142, Y: -4, W: 8, H: g.World.Height + 8, Axis: "v", Line: 146},
		Wall{X: 230, Y: -4, W: 32, H: g.World.Height + 8, Axis: "v", Line: 246})
	g.spatial = nil
	for i, p := range g.Tanks {
		if p != nil {
			p.Y = 100 + float64(i)*80
		}
	}
	return g
}
func launchCannon39(g *Game, owner int) *Bullet {
	p := g.Tanks[owner]
	g.grantPower(p, "cannon")
	p.Cooldown = 0
	if !g.fire(p) {
		panic("test Cannon failed to fire")
	}
	return g.Bullets[len(g.Bullets)-1]
}
func Test39CannonExactlyQuadrupleSizeAndSpeed(t *testing.T) {
	g := cannonBattle39(2)
	p := g.Tanks[0]
	p.Angle = .39
	g.fire(p)
	regular := g.Bullets[0]
	g.Bullets = nil
	b := launchCannon39(g, 0)
	if b.Kind != "cannon" || b.R != regular.R*4 || math.Abs(math.Hypot(b.VX, b.VY)-4*math.Hypot(regular.VX, regular.VY)) > 1e-8 {
		t.Fatal("not exactly 4x", b, regular)
	}
	if b.R != 14.0 || math.Abs(math.Hypot(b.VX, b.VY)-1128) > 1e-8 {
		t.Fatal("incorrect radius/speed")
	}
}
func Test39CannonCrossesMultipleWalls(t *testing.T) {
	for _, dt := range []float64{1.0 / 120, 1.0 / 60, .05, .2} {
		t.Run(fmt.Sprint(dt), func(t *testing.T) {
			g := cannonBattle39(2)
			p := g.Tanks[0]
			p.X = 80
			p.Y = 210
			g.Tanks[1].Alive = false
			b := launchCannon39(g, 0)
			x := b.X
			seconds := 0.0
			for seconds < .2-1e-9 {
				step := math.Min(dt, .2-seconds)
				g.updateBullets(step)
				seconds += step
			}
			if b.Dead || b.Bounces != 0 || b.VX != cannonSpeed || math.Abs(b.X-x-.2*cannonSpeed) > 1e-7 {
				t.Fatal("blocked/reflected by internal walls", b)
			}
		})
	}
}
func Test39CannonMuzzleInsideWallDoesNotReflect(t *testing.T) {
	for _, angle := range []float64{0, math.Pi / 2, math.Pi, math.Pi * 1.5} {
		t.Run(fmt.Sprint(angle), func(t *testing.T) {
			g := battle(1) // This fixture checks walls without an overlapping target tank.
			p := g.Tanks[0]
			p.X = 210
			p.Y = 210
			p.Angle = angle
			cs, sn := math.Cos(angle), math.Sin(angle)
			g.World.Walls = append(g.World.Walls, Wall{X: p.X + cs*32 - 6, Y: p.Y + sn*32 - 6, W: 12, H: 12})
			b := launchCannon39(g, 0)
			if b.Bounces != 0 || math.Abs(b.X-(p.X+cs*32)) > 1e-8 || math.Abs(b.Y-(p.Y+sn*32)) > 1e-8 || math.Abs(b.VX-cs*cannonSpeed) > 1e-8 || math.Abs(b.VY-sn*cannonSpeed) > 1e-8 {
				t.Fatal(b)
			}
		})
	}
}
func Test39CannonSweepsTankBehindCoverOnce(t *testing.T) {
	g := cannonBattle39(3)
	p, e, next := g.Tanks[0], g.Tanks[1], g.Tanks[2]
	p.X = 80
	p.Y = 210
	e.X = 320
	e.Y = 210
	next.X = 420
	next.Y = 210
	b := launchCannon39(g, 0)
	g.updateBullets(.5)
	if e.Alive || !next.Alive || !b.Dead || len(g.Bullets) != 0 {
		t.Fatal("missed tank or pierced extra tank")
	}
	if math.Abs(b.X-(e.X-e.R-cannonRadius)) > 1e-7 {
		t.Fatal("wrong swept contact", b.X)
	}
	if p.stats.Eliminations != 1 || e.stats.Deaths != 1 || next.stats.Deaths != 0 {
		t.Fatal("statistics mismatch")
	}
	g.updateBullets(.5)
	if p.stats.Eliminations != 1 {
		t.Fatal("duplicate kill")
	}
}
func Test39CannonGrazingHitUsesLargerRadius(t *testing.T) {
	for _, cannon := range []bool{false, true} {
		g := battle(2)
		p, e := g.Tanks[0], g.Tanks[1]
		p.X = 60
		p.Y = 150
		e.X = 250
		e.Y = 176
		if cannon {
			launchCannon39(g, 0)
		} else {
			g.fire(p)
		}
		g.updateBullets(.3)
		if e.Alive == cannon {
			t.Fatalf("cannon=%v wrong grazing collision", cannon)
		}
	}
}
func Test39CannonShieldStopsWithoutSplash(t *testing.T) {
	g := cannonBattle39(3)
	p, e, near := g.Tanks[0], g.Tanks[1], g.Tanks[2]
	p.X = 80
	p.Y = 210
	e.X = 320
	e.Y = 210
	e.Shield = 10
	near.X = 325
	near.Y = 245
	launchCannon39(g, 0)
	g.updateBullets(.5)
	if !e.Alive || e.Shield != 0 || !near.Alive || len(g.Bullets) != 0 || p.stats.Eliminations != 0 || e.stats.Deaths != 0 {
		t.Fatal("shield failed or splash/double hit")
	}
	impacts := 0
	for _, e := range g.events {
		if e.Type == "impact" {
			impacts++
		}
		if e.Type == "blast" {
			t.Fatal("Cannon must not explode like a grenade")
		}
	}
	if impacts != 1 {
		t.Fatal("wrong impact count", impacts)
	}
}
func Test39CannonFriendlyFireAllSeats(t *testing.T) {
	for seat := 0; seat < maxTanks; seat++ {
		for _, friendly := range []bool{false, true} {
			t.Run(fmt.Sprintf("seat%d/friendly%v", seat, friendly), func(t *testing.T) {
				g := battle(8)
				for _, p := range g.Tanks {
					p.Alive = false
				}
				owner, ally, enemy := g.Tanks[seat], g.Tanks[(seat+1)%8], g.Tanks[(seat+2)%8]
				owner.Alive = true
				ally.Alive = true
				enemy.Alive = true
				owner.Team = 2
				ally.Team = 2
				enemy.Team = 3
				owner.X = 80
				owner.Y = 210
				owner.Angle = 0
				ally.X = 220
				ally.Y = 210
				ally.Shield = 10
				enemy.X = 370
				enemy.Y = 210
				g.Rules.FriendlyFire = friendly
				launchCannon39(g, seat)
				g.updateBullets(.6)
				if friendly {
					if !enemy.Alive || ally.Shield != 0 || !ally.Alive {
						t.Fatal("friendly shield/stop")
					}
				} else {
					if enemy.Alive || !ally.Alive || ally.Shield != 10 {
						t.Fatal("friendly protection")
					}
				}
			})
		}
	}
}
func Test39CannonChargeCooldownAndWeaponExpiry(t *testing.T) {
	g := cannonBattle39(2)
	p := g.Tanks[0]
	g.grantPower(p, "scope")
	g.grantPower(p, "speed")
	g.grantPower(p, "shield")
	g.grantPower(p, "cannon")
	if p.Charges != 3 || p.PowerTime != 10 || capacity(p) != 3 || p.ScopeTime != 10 || p.SpeedTime != boostDuration || p.Shield != 10 {
		t.Fatal("grant/stacking")
	}
	if !g.fire(p) || g.fire(p) || p.Charges != 2 || p.Cooldown != cannonCooldown || p.CooldownTotal != cannonCooldown {
		t.Fatal("cooldown/charges")
	}
	for i := 0; i < 2; i++ {
		p.Cooldown = 0
		if !g.fire(p) {
			t.Fatal("shot refused")
		}
	}
	if p.Power != "" || p.PowerTime != 0 || p.Charges != 0 || len(g.Bullets) != 3 {
		t.Fatal("last-charge reset")
	}
	for _, b := range g.Bullets {
		if b.Kind != "cannon" || b.R != cannonRadius || b.VX != cannonSpeed {
			t.Fatal("fired round changed with power")
		}
	}
	p.Power = "cannon"
	p.Cooldown = 0
	p.Charges = 0
	if g.fire(p) {
		t.Fatal("zero charge fire")
	}
	g.Bullets = nil
	g.grantPower(p, "cannon")
	p.PowerTime = .001
	p.Invulnerable = 10
	g.Tanks[1].Invulnerable = 10
	g.step(tickDT, [maxTanks]Input{}, testPlayers(2))
	if p.Power != "" || p.PowerTime > 0 {
		t.Fatal("equip expiry")
	}
}
func Test39CannonRespectsActiveAmmoSlots(t *testing.T) {
	g := battle(2)
	p := g.Tanks[0]
	for i := 0; i < 3; i++ {
		p.Cooldown = 0
		g.fire(p)
	}
	g.grantPower(p, "cannon")
	p.Cooldown = 0
	if g.fire(p) || p.Charges != 3 {
		t.Fatal("bypassed active shot cap")
	}
	g.Bullets[0].Dead = true
	if !g.fire(p) || p.Charges != 2 {
		t.Fatal("freed slot not usable")
	}
}
func Test39CannonNoLifetimeOrArenaLeaks(t *testing.T) {
	for _, size := range []string{"compact", "standard", "large", "huge", "giant", "ultrawide"} {
		t.Run(size, func(t *testing.T) {
			g := newGame(390)
			g.Rules.MapSize = size
			g.startMatch(testPlayers(2))
			p := g.Tanks[0]
			p.X = 60
			p.Y = 60
			p.Invulnerable = 0
			p.Angle = 0
			g.Tanks[1].Alive = false
			b := launchCannon39(g, 0)
			for i := 0; i < 600; i++ {
				g.updateBullets(tickDT)
			}
			if !b.Dead || len(g.Bullets) != 0 || b.Bounces == 0 {
				t.Fatal("leaked past boundary")
			}
		})
	}
	g := battle(2)
	g.Tanks[1].Alive = false
	b := launchCannon39(g, 0)
	b.Life = .002
	x := b.X
	g.updateBullets(.1)
	if !b.Dead || math.Abs(b.X-x-cannonSpeed*.002) > 1e-7 {
		t.Fatal("subtick expiry")
	}
}
func Test39NormalShotsStillBounce(t *testing.T) {
	g := cannonBattle39(2)
	g.Tanks[1].Alive = false
	g.fire(g.Tanks[0])
	b := g.Bullets[0]
	g.updateBullets(.1)
	if b.Bounces == 0 || b.VX >= 0 || b.R != 3.5 {
		t.Fatal("normal shot changed")
	}
}
func Test39CannonBotsAimThroughCover(t *testing.T) {
	for _, difficulty := range []string{"easy", "normal", "hard"} {
		t.Run(difficulty, func(t *testing.T) {
			g := cannonBattle39(2)
			p, e := g.Tanks[0], g.Tanks[1]
			p.X = 80
			p.Y = 210
			e.X = 320
			e.Y = 210
			p.Bot = true
			p.Difficulty = difficulty
			p.AI = &BotState{}
			if g.botShot(p, e, 0, e.X, e.Y, 0) {
				t.Fatal("regular round crosses wall")
			}
			g.grantPower(p, "cannon")
			a, ok := g.botAim(p, e, tuneBot(difficulty))
			if !ok || math.Abs(a) > 1e-8 || !g.botShot(p, e, 0, e.X, e.Y, 0) {
				t.Fatal("cannon bot refuses covered enemy")
			}
			e.VY = 90
			_, lead := g.botLead(p, e, tuneBot(difficulty))
			if lead <= e.Y || lead-e.Y > 30 {
				t.Fatal("wrong high-speed lead", lead)
			}
		})
	}
}
func Test39CannonSettingsAndClientAuthority(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	rules := defaultRules()
	found := false
	for _, s := range rules.Weapons {
		if s == "cannon" {
			found = true
		}
	}
	if !found || len(rules.Weapons) != 10 {
		t.Fatal("default Cannon missing")
	}
	rules.Weapons = []string{"cannon"}
	action(t, h, cs[1], map[string]any{"type": "rules", "rules": rules})
	if !hasError(cs[1], "not_host") {
		t.Fatal("guest changed rules")
	}
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	if len(r.Game.Rules.Weapons) != 1 || r.Game.Rules.Weapons[0] != "cannon" {
		t.Fatal("host cannot select Cannon")
	}
	rules.Weapons = []string{"cannon", "cannon"}
	if validateRules(rules) == nil {
		t.Fatal("duplicate accepted")
	}
	r.Game = battle(2)
	action(t, h, cs[0], map[string]any{"type": "input", "seq": 1, "power": "cannon", "charges": 999, "radius": 999, "speed": 999})
	if r.Game.Tanks[0].Power != "" || r.Game.Tanks[0].Charges != 0 {
		t.Fatal("client forged Cannon")
	}
}
func Test39CannonSpawnsWithFiltersAndDensity(t *testing.T) {
	for _, v := range sizeCases38 {
		g := newGame(39)
		g.Rules.MapSize = v.name
		g.Rules.Weapons = []string{"cannon"}
		g.startMatch(testPlayers(8))
		if len(g.Pickups) != v.start {
			t.Fatal("start count")
		}
		for i := 0; i < 400; i++ {
			g.spawnPower()
		}
		if len(g.Pickups) != v.cap {
			t.Fatal("cap", v.name, len(g.Pickups))
		}
		for _, p := range g.Pickups {
			if p.Type != "cannon" {
				t.Fatal("filter")
			}
		}
	}
}
func Test39CannonWireCarriesKindAndTrueSize(t *testing.T) {
	g := battle(2)
	b := launchCannon39(g, 0)
	data, _ := json.Marshal(b)
	var v map[string]any
	json.Unmarshal(data, &v)
	if v["kind"] != "cannon" || v["r"] != 14.0 || v["vx"] != 1128.0 || v["owner"] != float64(0) {
		t.Fatal("wire payload", v)
	}
}
func Test39CannonEliminationOutcomeAndStats(t *testing.T) {
	g := cannonBattle39(2)
	p, e := g.Tanks[0], g.Tanks[1]
	p.X = 80
	p.Y = 210
	e.X = 320
	e.Y = 210
	g.Rules.ScoreTarget = 1
	launchCannon39(g, 0)
	ps := testPlayers(2)
	for i := 0; i < 45; i++ {
		g.step(tickDT, [maxTanks]Input{}, ps)
	}
	if e.Alive || g.Scores[0] != 1 || p.stats.Eliminations != 1 || e.stats.Deaths != 1 {
		t.Fatal("kill/score", g.Scores)
	}
}
