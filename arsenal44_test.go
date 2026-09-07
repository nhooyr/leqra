package main

import (
	"encoding/json"
	"math"
	"testing"
)

func Test44ShieldFiveChargesRefreshAndOneHitAtATime(t *testing.T) {
	g := battle(2)
	tank := g.Tanks[1]
	for i := 1; i <= 7; i++ {
		tank.Shield = math.Max(0, tank.Shield-1)
		g.grantPower(tank, "shield")
		if shieldCount(tank) != min(i, 5) || tank.Shield != 10 {
			t.Fatalf("pickup %d: %+v", i, tank)
		}
	}
	for i := 4; i >= 0; i-- {
		tank.Invulnerable = 0
		g.hurt(tank, &Bullet{Owner: 0})
		if !tank.Alive || shieldCount(tank) != i {
			t.Fatalf("hit needs one charge, remaining %d: %+v", i, tank)
		}
		g.hurt(tank, &Bullet{Owner: 0})
		if !tank.Alive || shieldCount(tank) != i {
			t.Fatal("hit grace failed")
		}
	}
	if tank.Shield != 0 || tank.ShieldCharges != 0 || tank.stats.Deaths != 0 {
		t.Fatal("shield depleted incorrectly or counted death")
	}
	tank.Invulnerable = 0
	g.hurt(tank, &Bullet{Owner: 0})
	g.hurt(tank, &Bullet{Owner: 0})
	if tank.Alive || tank.stats.Deaths != 1 || g.Tanks[0].stats.Eliminations != 1 {
		t.Fatal("unshielded death should count exactly once")
	}
}
func Test44ShieldExpiresAndRespawnClearsStack(t *testing.T) {
	g := battle(2)
	tank := g.Tanks[0]
	for i := 0; i < 5; i++ {
		g.grantPower(tank, "shield")
	}
	tank.Shield = .001
	g.step(tickDT, [maxTanks]Input{}, testPlayers(2))
	if shieldCount(tank) != 0 || tank.ShieldCharges != 0 {
		t.Fatal("expired charges retained")
	}
	for i := 0; i < 5; i++ {
		g.grantPower(tank, "shield")
	}
	g.startRound(testPlayers(2))
	if shieldCount(g.Tanks[0]) != 0 || g.Tanks[0].ShieldCharges != 0 {
		t.Fatal("new life inherited shields")
	}
}
func Test44FriendlyHitsAndShotgunSelfHitsKeepAllShields(t *testing.T) {
	for _, ff := range []bool{false, true} {
		g := battle(2)
		g.Rules.FriendlyFire = ff
		g.Tanks[0].Team = 1
		g.Tanks[1].Team = 1
		tank := g.Tanks[1]
		for i := 0; i < 5; i++ {
			g.grantPower(tank, "shield")
		}
		g.hurt(tank, &Bullet{Kind: "scatter", Owner: 1})
		if shieldCount(tank) != 5 {
			t.Fatal("shotgun self hit consumed shields")
		}
		g.hurt(tank, &Bullet{Owner: 0})
		want := 5
		if ff {
			want = 4
		}
		if shieldCount(tank) != want {
			t.Fatal("friendly fire wrong")
		}
	}
}
func Test44ShieldWeightThreeAndSelectionHonorsEnabledKinds(t *testing.T) {
	g := newGame(4401)
	types := []string{"shield", "speed", "rapid", "scatter"}
	counts := map[string]int{}
	for i := 0; i < 60000; i++ {
		counts[g.choosePickup(types)]++
	}
	for _, kind := range types {
		want := 7500
		if kind == "shield" || kind == "speed" {
			want = 22500
		}
		if math.Abs(float64(counts[kind]-want)) > 800 {
			t.Fatalf("weighted distribution %v", counts)
		}
	}
	for _, kind := range pickupTypes {
		if pickupWeight(kind) != 1 && kind != "shield" && kind != "speed" {
			t.Fatal("other weight changed")
		}
		for i := 0; i < 30; i++ {
			if g.choosePickup([]string{kind}) != kind {
				t.Fatal("single type")
			}
		}
	}
	for i := 0; i < 1000; i++ {
		if k := g.choosePickup([]string{"rapid", "scatter"}); k == "shield" || k == "speed" {
			t.Fatal("disabled shield spawned")
		}
	}
	if g.choosePickup(nil) != "" {
		t.Fatal("empty selection")
	}
}
func Test44ShotgunThreeTimesSpeedAndSameRadius(t *testing.T) {
	g := battle(2)
	tank := g.Tanks[0]
	g.grantPower(tank, "scatter")
	if !g.fire(tank) || len(g.Bullets) != 3 {
		t.Fatal("not three pellets")
	}
	for _, b := range g.Bullets {
		if b.Kind != "scatter" || b.R != 3.5 || math.Abs(math.Hypot(b.VX, b.VY)-846) > 1e-8 || b.Life != 3.9 {
			t.Fatalf("wrong pellet %+v", b)
		}
	}
	if tank.Cooldown != .54 || tank.Charges != 4 {
		t.Fatal("shotgun equip/volley cooldown changed unexpectedly")
	}
}
func Test44ShotgunOwnerImmunityAllSeatsAfterWeaponChange(t *testing.T) {
	for owner := 0; owner < maxTanks; owner++ {
		g := battle(maxTanks)
		tank := g.Tanks[owner]
		g.grantPower(tank, "shield")
		tank.Power = "cannon"
		b := &Bullet{ID: 1, Owner: owner, Kind: "scatter", X: tank.X - 25, Y: tank.Y, VX: 846, R: 3.5, Age: 2, Life: 2}
		g.Bullets = []*Bullet{b}
		g.updateBullets(tickDT)
		if !tank.Alive || shieldCount(tank) != 1 || b.Dead {
			t.Fatalf("owner %d hit own shotgun", owner)
		}
		g.hurt(tank, b)
		if shieldCount(tank) != 1 {
			t.Fatal("damage bypass")
		}
	}
}
func Test44ShotgunKillsEnemyOnlyOnceAndRicochets(t *testing.T) {
	g := battle(2)
	tank := g.Tanks[0]
	g.grantPower(tank, "scatter")
	g.fire(tank)
	for i := 0; i < 10; i++ {
		g.updateBullets(tickDT)
	}
	if g.Tanks[1].Alive || g.Tanks[1].stats.Deaths != 1 || tank.stats.Eliminations != 1 {
		t.Fatal("pellet kill accounting")
	}
	g = battle(2)
	tank = g.Tanks[0]
	tank.X = 480
	tank.Angle = 0
	g.grantPower(tank, "scatter")
	g.fire(tank)
	if g.Bullets[1].VX >= 0 || g.Bullets[1].Bounces != 1 {
		t.Fatal("shotgun failed wall reflection")
	}
}
func Test44MachineGunExactSizeSpeedAndZeroCooldown(t *testing.T) {
	g := battle(2)
	tank := g.Tanks[0]
	tank.Cooldown = .3
	g.grantPower(tank, "rapid")
	if !g.fire(tank) || tank.Cooldown != 0 || tank.CooldownTotal != 0 {
		t.Fatal("machine gun retained cooldown")
	}
	b := g.Bullets[0]
	wantLife := (g.machineTravelRange() - 28) / machineSpeed
	if b.Kind != "rapid" || math.Abs(b.R-3.5/3) > 1e-12 || math.Abs(math.Hypot(b.VX, b.VY)-846) > 1e-9 || math.Abs(b.Life-wantLife) > 1e-9 {
		t.Fatal(b)
	}
	if g.fire(tank) {
		t.Fatal("multiple calls in one tick bypass rate bound")
	}
	g.Tick++
	if !g.fire(tank) {
		t.Fatal("next tick blocked by cooldown")
	}
}
func Test44MachineGunContinuousSixHundredShotsAndFiniteCloud(t *testing.T) {
	g := battle(2)
	tank := g.Tanks[0]
	for _, v := range g.Tanks {
		if v != nil {
			v.Invulnerable = 99
		}
	}
	g.grantPower(tank, "rapid")
	high := 0
	for i := 0; i < 600; i++ {
		g.Tick++
		if !g.fire(tank) {
			t.Fatalf("unnecessary firing gap tick %d live %d", i, len(g.Bullets))
		}
		g.updateBullets(tickDT)
		high = max(high, len(g.Bullets))
		for _, b := range g.Bullets {
			if math.IsNaN(b.X) || b.Life > g.machineTravelRange()/machineSpeed+1e-9 {
				t.Fatal("unbounded round")
			}
		}
	}
	maxLive := int(math.Ceil((g.machineTravelRange()/machineSpeed)/tickDT)) + 2
	if tank.ShotSerial != 600 || high > maxLive || len(g.events) > 24 {
		t.Fatalf("bad stream %d %d", tank.ShotSerial, high)
	}
	for i := 0; i < maxLive+4; i++ {
		g.updateBullets(tickDT)
	}
	if len(g.Bullets) != 0 {
		t.Fatal("shots survived lifetime")
	}
}
func Test44MachineGunCapacityCannotBeBypassed(t *testing.T) {
	g := battle(2)
	tank := g.Tanks[0]
	g.grantPower(tank, "rapid")
	for i := 0; i < machineCapacity; i++ {
		g.Tick++
		if !g.fire(tank) {
			t.Fatal("premature capacity")
		}
	}
	g.Tick++
	if g.fire(tank) || tank.ShotSerial != machineCapacity {
		t.Fatal("capacity bypass")
	}
}
func Test44MachineGunShooterImmunity(t *testing.T) {
	g := battle(2)
	tank := g.Tanks[0]
	g.Bullets = []*Bullet{{Owner: 0, Kind: "rapid", X: tank.X - 20, Y: tank.Y, VX: 846, R: machineRadius, Age: .5, Life: 1}}
	g.updateBullets(tickDT)
	if !tank.Alive || tank.stats.SelfDestructs != 0 {
		t.Fatal("machine gun should be shooter-safe")
	}
}
func Test44MachineGunEightTanksStressAndCompactWire(t *testing.T) {
	g := battle(8)
	for _, tank := range g.Tanks {
		tank.Invulnerable = 100
		g.grantPower(tank, "rapid")
	}
	high := 0
	for i := 0; i < 240; i++ {
		g.Tick++
		for _, tank := range g.Tanks {
			if !g.fire(tank) {
				t.Fatalf("stream gap at %d", i)
			}
		}
		g.updateBullets(tickDT)
		high = max(high, len(g.Bullets))
	}
	maxLive := int(math.Ceil((g.machineTravelRange()/machineSpeed)/tickDT)) + 2
	if high > 8*maxLive {
		t.Fatal("projectile cloud unbounded")
	}
	h := newHub(2)
	wire := h.stateMessage(&Room{Game: g})
	packed := wire["machineBullets"].([][12]float64)
	if len(packed) != len(g.Bullets) || len(wire["bullets"].([]Bullet)) != 0 {
		t.Fatal("packing dropped/duplicated bullets")
	}
	for i, row := range packed {
		b := g.Bullets[i]
		if row[0] != float64(b.ID) || row[1] != float64(b.Owner) || row[2] != float64(b.ShotSerial) || row[3] != float64(b.SpawnSerial) || row[4] != rounded(b.X) || row[8] != rounded(b.Age) {
			t.Fatal("wire state changed")
		}
	}
	compact, _ := json.Marshal(packed)
	full := make([]Bullet, 0, len(g.Bullets))
	for _, b := range g.Bullets {
		v := *b
		v.X = rounded(v.X)
		v.Y = rounded(v.Y)
		v.VX = rounded(v.VX)
		v.VY = rounded(v.VY)
		v.Age = rounded(v.Age)
		v.Life = rounded(v.Life)
		full = append(full, v)
	}
	verbose, _ := json.Marshal(full)
	if len(compact) >= len(verbose)/2 {
		t.Fatalf("packing ineffective %d / %d", len(compact), len(verbose))
	}
	t.Logf("eight-stream peak=%d records=%d compact=%d legacy=%d bytes", high, len(packed), len(compact), len(verbose))
}
func Test44MachineGunShieldStackSurvivesBurstGrace(t *testing.T) {
	g := battle(2)
	tank := g.Tanks[1]
	for i := 0; i < 5; i++ {
		g.grantPower(tank, "shield")
	}
	for i := 0; i < 25; i++ {
		g.hurt(tank, &Bullet{Owner: 0, Kind: "rapid"})
	}
	if !tank.Alive || shieldCount(tank) != 4 {
		t.Fatal("burst bypassed shield grace")
	}
}
