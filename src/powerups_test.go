package main

import (
	"encoding/json"
	"math"
	"testing"
)

func TestNewPickupGrantsAndIndependentBuffs(t *testing.T) {
	for _, kind := range pickupTypes {
		t.Run(kind, func(t *testing.T) {
			g := battle(2)
			p := g.Tanks[0]
			g.grantPower(p, kind)
			switch kind {
			case "shield":
				if p.Shield != 10 {
					t.Fatal("shield duration")
				}
			case "ghost":
				if p.GhostTime != ghostDuration {
					t.Fatal("ghost duration")
				}
			case "scope":
				if p.ScopeTime != scopeDuration {
					t.Fatal("scope duration")
				}
			case "speed":
				if p.SpeedTime != boostDuration {
					t.Fatal("speed duration")
				}
			default:
				if p.Power != kind || p.Charges <= 0 {
					t.Fatal("weapon not granted")
				}
			}
		})
	}
	g := battle(2)
	p := g.Tanks[0]
	g.grantPower(p, "homing")
	g.grantPower(p, "speed")
	g.grantPower(p, "shield")
	if p.Power != "homing" || p.Charges != 3 || p.PowerTime != 10 || p.SpeedTime != boostDuration || p.Shield != 10 {
		t.Fatalf("buffs overwrite weapon: %+v", p)
	}
	g.grantPower(p, "grenade")
	if p.SpeedTime != boostDuration || p.Shield != 10 || p.Power != "grenade" {
		t.Fatal("weapon overwrote buffs")
	}
}
func TestAllPowerupsActuallySpawn(t *testing.T) {
	g := battle(2)
	seen := map[string]bool{}
	for i := 0; i < 200; i++ {
		g.Pickups = nil
		g.spawnPower()
		for _, p := range g.Pickups {
			seen[p.Type] = true
		}
	}
	if len(seen) != len(pickupTypes) {
		t.Fatalf("spawn set: %v", seen)
	}
}
func TestNewWeaponsChargesCapacityAndCooldown(t *testing.T) {
	for _, kind := range []string{"homing", "grenade"} {
		t.Run(kind, func(t *testing.T) {
			g := battle(2)
			p := g.Tanks[0]
			g.grantPower(p, kind)
			if capacity(p) != 3 {
				t.Fatal("special capacity")
			}
			if !g.fire(p) || g.fire(p) || len(g.Bullets) != 1 || p.Charges != 2 {
				t.Fatal("cooldown/charge enforcement")
			}
			if g.Bullets[0].Kind != kind {
				t.Fatal("missing projectile kind")
			}
			for i := 0; i < 2; i++ {
				p.Cooldown = 0
				if !g.fire(p) {
					t.Fatal("valid charge refused")
				}
			}
			if p.Power != "" || p.PowerTime != 0 || p.Charges != 0 {
				t.Fatal("weapon must expire after 3 charges")
			}
			for _, b := range g.Bullets {
				if b.Kind != kind {
					t.Fatal("existing projectile changed when weapon expired")
				}
			}
			g.Bullets = nil
			g.grantPower(p, kind)
			p.Cooldown = 0
			for i := 0; i < 3; i++ {
				g.Bullets = append(g.Bullets, &Bullet{Owner: p.ID})
			}
			if g.fire(p) || p.Charges != 3 {
				t.Fatal("blocked shot consumed charge")
			}
		})
	}
}
func TestMissileBoundedGuidanceAndTargetLock(t *testing.T) {
	g := battle(3)
	g.Tanks[0].X = 60
	g.Tanks[1].X = 260
	g.Tanks[1].Y = 260
	g.Tanks[2].X = 300
	g.Tanks[2].Y = 210
	b := &Bullet{Kind: "homing", Owner: 0, Target: -1, X: 110, Y: 210, VX: missileSpeed, R: 5, Age: .2, Life: 4.8}
	g.steerMissile(b, tickDT)
	if b.Target != 1 || b.VY <= 0 {
		t.Fatalf("did not home on nearest enemy: %+v", b)
	}
	if math.Abs(math.Atan2(b.VY, b.VX)) > missileTurn*tickDT+1e-8 {
		t.Fatal("instant turn")
	}
	if math.Abs(math.Hypot(b.VX, b.VY)-missileSpeed) > 1e-8 {
		t.Fatal("speed changed")
	}
	g.Tanks[2].X = 130
	g.steerMissile(b, tickDT)
	if b.Target != 1 {
		t.Fatal("valid lock switched needlessly")
	}
	g.Tanks[1].Alive = false
	g.steerMissile(b, tickDT)
	if b.Target != -1 || b.SeekDelay <= 0 {
		t.Fatal("lost lock must coast before reacquiring")
	}
	for i := 0; i < 23; i++ {
		g.steerMissile(b, tickDT)
	}
	if b.Target != 2 {
		t.Fatal("failed reacquisition")
	}
}
func TestMissileNeverLocksOwnerDeadOrInvulnerable(t *testing.T) {
	g := battle(2)
	g.Tanks[1].Invulnerable = 1
	b := &Bullet{Owner: 0, Target: -1, X: 100, Y: 210, VX: missileSpeed, Age: 1, R: 5}
	g.steerMissile(b, tickDT)
	if b.Target != -1 {
		t.Fatal("locked invulnerable enemy or owner")
	}
	g.Tanks[1].Invulnerable = 0
	g.Tanks[1].Alive = false
	g.steerMissile(b, tickDT)
	if b.Target != -1 {
		t.Fatal("locked dead enemy")
	}
}
func TestMissileWallsBreakLockAndReflectProjectile(t *testing.T) {
	g := battle(2)
	g.Tanks[1].X = 320
	g.World.Walls = append(g.World.Walls, Wall{X: 248, Y: 0, W: 8, H: 420, Axis: "v", Line: 252})
	b := &Bullet{Kind: "homing", Owner: 0, Target: 1, X: 230, Y: 210, VX: missileSpeed, R: 5, Age: .2, Life: 4.8}
	g.steerMissile(b, tickDT)
	if b.Target != -1 {
		t.Fatal("tracked through wall")
	}
	g.Bullets = []*Bullet{b}
	for i := 0; i < 12; i++ {
		g.updateBullets(tickDT)
	}
	if len(g.Bullets) != 1 || b.Dead || b.Bounces != 1 || b.VX >= 0 || b.X >= 243 || !g.Tanks[1].Alive {
		t.Fatalf("missile must survive and reflect on near face: %+v", b)
	}
	for _, e := range g.events {
		if e.Type == "impact" {
			t.Fatal("wall contact must not explode a live missile")
		}
	}
}
func TestMissileMuzzleAgainstWallCannotSpawnThroughIt(t *testing.T) {
	g := battle(2)
	p := g.Tanks[0]
	p.X = 480
	p.Y = 100
	g.grantPower(p, "homing")
	g.fire(p)
	if len(g.Bullets) != 1 || p.Charges != 2 || g.Bullets[0].X >= 495 || g.Bullets[0].VX >= 0 || g.Bullets[0].Bounces != 1 {
		t.Fatal("muzzle must reflect on near wall face without crossing it")
	}
}
func TestMissileHitsMovingOffAxisEnemy(t *testing.T) {
	g := battle(2)
	g.Tanks[0].X = 90
	g.Tanks[0].Y = 160
	g.Tanks[1].X = 330
	g.Tanks[1].Y = 210
	g.grantPower(g.Tanks[0], "homing")
	g.fire(g.Tanks[0])
	for i := 0; i < 180 && g.Tanks[1].Alive; i++ {
		g.Tanks[1].Y += .10
		g.updateBullets(tickDT)
	}
	if g.Tanks[1].Alive {
		t.Fatal("missile never hit off-axis moving target")
	}
}
func TestGrenadeBouncesSlowsAndWaitsForFuse(t *testing.T) {
	g := battle(2)
	g.Tanks = [maxTanks]*Tank{}
	b := &Bullet{Kind: "grenade", Owner: 0, X: 480, Y: 200, VX: grenadeSpeed, R: 6, Life: grenadeFuse, Target: -1}
	g.Bullets = []*Bullet{b}
	for i := 0; i < 30; i++ {
		g.updateBullets(tickDT)
	}
	if b.Dead || b.Bounces != 1 || b.VX >= 0 || math.Abs(b.VX) >= grenadeSpeed {
		t.Fatalf("bad rolling/bounce %+v", b)
	}
	for i := 30; i < int(grenadeFuse/tickDT)-1; i++ {
		g.updateBullets(tickDT)
	}
	if b.Dead {
		t.Fatal("premature fuse")
	}
	g.updateBullets(tickDT)
	if !b.Dead || len(g.Bullets) != 0 {
		t.Fatal("fuse failed")
	}
	count := 0
	for _, e := range g.events {
		if e.Type == "blast" {
			count++
			if e.Radius != blastRadius {
				t.Fatal("radius absent")
			}
		}
	}
	if count != 1 {
		t.Fatalf("blast events %d", count)
	}
}
func TestGrenadeContactDetonates(t *testing.T) {
	g := battle(2)
	b := &Bullet{Kind: "grenade", Owner: 0, X: 150, Y: 210, VX: grenadeSpeed, R: 6, Life: grenadeFuse}
	g.Bullets = []*Bullet{b}
	for i := 0; i < 24; i++ {
		g.updateBullets(tickDT)
	}
	if g.Tanks[1].Alive || !b.Dead || b.Life <= 0 {
		t.Fatal("grenade did not detonate on tank contact before fuse")
	}
}
func TestGrenadeBlastHitsAllInRangeIncludingOwner(t *testing.T) {
	g := battle(4)
	g.Tanks[0].X = 180
	g.Tanks[1].X = 210
	g.Tanks[2].X = 270
	g.Tanks[3].X = 470
	b := &Bullet{Kind: "grenade", Owner: 0, X: 210, Y: 210}
	g.detonate(b)
	for i := 0; i < 3; i++ {
		if g.Tanks[i].Alive {
			t.Fatalf("tank %d incorrectly immune", i)
		}
	}
	if !g.Tanks[3].Alive {
		t.Fatal("blast outside radius")
	}
	events := len(g.events)
	g.detonate(b)
	if len(g.events) != events {
		t.Fatal("double detonation")
	}
}
func TestGrenadeBlastBlockedByCover(t *testing.T) {
	g := battle(2)
	g.Tanks[0].X = 120
	g.Tanks[1].X = 280
	g.World.Walls = append(g.World.Walls, Wall{X: 248, Y: 0, W: 8, H: 420, Axis: "v", Line: 252})
	g.detonate(&Bullet{Kind: "grenade", Owner: 0, X: 225, Y: 210})
	if !g.Tanks[1].Alive || g.Tanks[0].Alive {
		t.Fatal("cover or uncovered blast incorrect")
	}
}
func TestGrenadeShieldAndSpawnProtection(t *testing.T) {
	g := battle(3)
	g.Tanks[0].X = 100
	g.Tanks[1].X = 140
	g.Tanks[2].X = 180
	g.Tanks[1].Shield = 10
	g.Tanks[2].Invulnerable = .5
	g.detonate(&Bullet{Kind: "grenade", Owner: 0, X: 140, Y: 210})
	if g.Tanks[0].Alive || !g.Tanks[1].Alive || g.Tanks[1].Shield != 0 || !g.Tanks[2].Alive {
		t.Fatal("shield/spawn grace not respected")
	}
}
func TestGrenadeDoubleKnockoutIsDraw(t *testing.T) {
	g := battle(2)
	g.Bullets = []*Bullet{{Kind: "grenade", Owner: 0, X: 140, Y: 210, R: 6, Life: tickDT}}
	g.step(tickDT, [maxTanks]Input{}, testPlayers(2))
	if g.Phase != "roundOver" || g.Winner != -1 || g.Scores != [maxTanks]int{} {
		t.Fatal("blast did not resolve simultaneously")
	}
}
func TestSpeedBoostKeyboardTouchAndReverse(t *testing.T) {
	for _, input := range []Input{{Forward: true}, {StickX: 1}, {Reverse: true}} {
		g := battle(2)
		p := g.Tanks[0]
		p.X = 230
		x := p.X
		g.grantPower(p, "speed")
		for i := 0; i < 30; i++ {
			g.control(p, input, tickDT)
		}
		want := 128 * boostSpeed * .5
		if input.Reverse {
			want *= -.72
		}
		if math.Abs(p.X-x-want) > 1e-7 {
			t.Fatalf("boost speed %+v: %f vs %f", input, p.X-x, want)
		}
	}
}
func TestBoostExpiryAndRefreshStacksToFive(t *testing.T) {
	g := battle(2)
	p := g.Tanks[0]
	p.SpeedTime = .025
	p.SpeedStacks = 1
	x := p.X
	g.control(p, Input{Forward: true}, tickDT)
	g.control(p, Input{Forward: true}, tickDT)
	if p.SpeedTime != 0 || p.SpeedStacks != 0 || math.Abs(p.X-x-128*tickDT*(boostSpeed+1)) > 1e-7 {
		t.Fatal("expiry tick incorrect")
	}
	for i := 1; i <= 7; i++ {
		g.grantPower(p, "speed")
		if speedCount(p) != min(i, 5) || p.SpeedTime != boostDuration {
			t.Fatalf("speed stack %d: %+v", i, p)
		}
	}
	x = p.X
	g.control(p, Input{Forward: true}, tickDT)
	wantScale := 1 + boostSpeedPerStack*5
	if math.Abs(p.X-x-128*wantScale*tickDT) > 1e-7 {
		t.Fatal("stacked boost speed")
	}
}
func TestBoostCannotTunnelThroughWall(t *testing.T) {
	g := battle(2)
	p := g.Tanks[0]
	g.World.Walls = append(g.World.Walls, Wall{X: 248, Y: 0, W: 8, H: 420, Axis: "v", Line: 252})
	g.grantPower(p, "speed")
	for i := 0; i < 300; i++ {
		g.control(p, Input{Forward: true}, tickDT)
	}
	if p.X > 248-p.R+.01 {
		t.Fatal("boost tunnels through wall")
	}
}
func TestPowerupsResetOnNewRound(t *testing.T) {
	g := battle(2)
	p := g.Tanks[0]
	g.grantPower(p, "homing")
	g.grantPower(p, "speed")
	g.grantPower(p, "shield")
	g.fire(p)
	g.startRound(testPlayers(2))
	p = g.Tanks[0]
	if p.Power != "" || p.SpeedTime != 0 || p.Shield != 0 || len(g.Bullets) != 0 {
		t.Fatal("powers survive round reset")
	}
}
func TestClientCannotForgePowerupsOrProjectileTypes(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	r.Game.startMatch(r.Players)
	r.Game.Phase = "playing"
	action(t, h, cs[0], map[string]any{"type": "input", "seq": 1, "power": "homing", "speedTime": 600, "kind": "grenade", "charges": 999, "fire": true})
	p := r.Game.Tanks[0]
	if p.Power != "" || p.SpeedTime != 0 {
		t.Fatal("trusted client power")
	}
	if len(r.Game.Bullets) != 0 {
		t.Fatal("input packet spawned projectile before simulation")
	}
}
func TestPowerupSnapshotMetadata(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	r.Game.startMatch(r.Players)
	p := r.Game.Tanks[0]
	r.Game.grantPower(p, "grenade")
	r.Game.grantPower(p, "speed")
	r.Game.fire(p)
	drain(cs[0])
	h.sendState(cs[0], r)
	var state map[string]any
	for _, m := range drain(cs[0]) {
		if m["type"] == "state" {
			state = m
		}
	}
	if state == nil {
		t.Fatal("no state")
	}
	data, _ := json.Marshal(state)
	var decoded struct {
		Tanks   []Tank   `json:"tanks"`
		Bullets []Bullet `json:"bullets"`
	}
	_ = json.Unmarshal(data, &decoded)
	if decoded.Tanks[0].SpeedTime != boostDuration || decoded.Tanks[0].Power != "grenade" || decoded.Tanks[0].Charges != 2 || len(decoded.Bullets) != 1 || decoded.Bullets[0].Kind != "grenade" {
		t.Fatal("snapshot lost new power fields")
	}
}
func TestSpecialProjectilesExpireBounded(t *testing.T) {
	for _, kind := range []string{"homing", "grenade"} {
		g := battle(2)
		g.grantPower(g.Tanks[0], kind)
		g.fire(g.Tanks[0])
		g.Tanks = [maxTanks]*Tank{}
		for i := 0; i < int(grenadeFuse/tickDT)+120; i++ {
			g.updateBullets(tickDT)
		}
		if len(g.Bullets) != 0 {
			t.Fatal("special projectile leaked")
		}
	}
}
func TestAllPowerupsStayFiniteAcrossSeededBattles(t *testing.T) {
	for seed := int64(1); seed <= 12; seed++ {
		g := newGame(seed)
		ps := testPlayers(4)
		g.startMatch(ps)
		for step := 0; step < 1800; step++ {
			var inputs [maxTanks]Input
			if step%120 == 0 {
				for id, p := range g.Tanks {
					if p != nil && p.Alive {
						g.grantPower(p, pickupTypes[(step/120+id)%len(pickupTypes)])
						g.grantPower(p, "speed")
					}
				}
			}
			for id := range inputs {
				inputs[id] = Input{Forward: true, Right: (step+id*60)%180 < 90, Fire: true}
			}
			g.step(tickDT, inputs, ps)
			for _, b := range g.Bullets {
				maxLife := 5.4
				if b.Kind == "homing" {
					maxLife = g.missileTravelRange()/missileSpeed + .5
					if b.RangeLeft < 0 || b.RangeLeft > g.missileTravelRange() {
						t.Fatal("invalid travel budget")
					}
				}
				if math.IsNaN(b.X) || math.IsInf(b.X, 0) || math.IsNaN(b.VX) || b.Life > maxLife {
					t.Fatal("invalid projectile")
				}
			}
			if len(g.Bullets) > maxTanks*machineCapacity {
				t.Fatal("unbounded projectiles")
			}
			for _, p := range g.Tanks {
				if p != nil && (math.IsNaN(p.X) || p.SpeedTime < 0 || p.SpeedTime > boostDuration+.001) {
					t.Fatal("invalid tank")
				}
			}
		}
	}
}
func TestBoostSnapshotKeepsExactExpiryPrecision(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	r.Game.startMatch(r.Players)
	p := r.Game.Tanks[0]
	p.SpeedTime = 1.0 / 60.0
	drain(cs[0])
	h.sendState(cs[0], r)
	for _, m := range drain(cs[0]) {
		if m["type"] == "state" {
			data, _ := json.Marshal(m)
			var s struct {
				Tanks []Tank `json:"tanks"`
			}
			_ = json.Unmarshal(data, &s)
			if s.Tanks[0].SpeedTime != p.SpeedTime {
				t.Fatal("rounded speed timer shifts prediction expiry tick")
			}
			return
		}
	}
	t.Fatal("state missing")
}
