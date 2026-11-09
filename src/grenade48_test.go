package main

import (
	"math"
	"testing"
)

func TestGrenadeKeepsItsFuseThroughRepeatedRicochets(t *testing.T) {
	g := battle(1)
	g.World.Walls = append(g.World.Walls, Wall{X: 80, Y: 160, W: 8, H: 100}, Wall{X: 164, Y: 160, W: 8, H: 100})
	shooter := g.Tanks[0]
	shooter.X, shooter.Y = 126, 210
	g.grantPower(shooter, "grenade")
	if !g.fire(shooter) || len(g.Bullets) != 1 {
		t.Fatal("grenade did not launch into the corridor")
	}
	b := g.Bullets[0]
	for !b.Dead && b.Age < grenadeFuse {
		g.updateBullets(tickDT)
	}
	if b.Bounces <= 22 || !b.Dead || math.Abs(b.Age-grenadeFuse) > 1e-6 || blastCount(g) != 1 {
		t.Fatalf("expected one blast at the fuse after more than 22 bounces, got age %.3f, bounces %d, blasts %d", b.Age, b.Bounces, blastCount(g))
	}
}

func Test48GrenadeKeepsSpeedUntilLateFuse(t *testing.T) {
	g := &Game{World: World{Width: 10000, Height: 10000}}
	b := &Bullet{ID: 1, Owner: 7, Kind: "grenade", X: 5000, Y: 5000, VX: grenadeSpeed, R: 6, Life: grenadeFuse}
	g.Bullets = []*Bullet{b}
	advance := func(seconds float64) {
		for i := 0; i < int(math.Round(seconds/tickDT)); i++ {
			g.updateBullets(tickDT)
		}
	}
	advance(5)
	if got := math.Hypot(b.VX, b.VY) / grenadeSpeed; got < .87 {
		t.Fatalf("grenade slowed too early at 5s: %.3f of launch speed", got)
	}
	advance(3)
	if got := math.Hypot(b.VX, b.VY) / grenadeSpeed; got < .74 {
		t.Fatalf("grenade should still cruise with 2s left: %.3f of launch speed", got)
	}
	advance(1)
	if got := math.Hypot(b.VX, b.VY) / grenadeSpeed; got > .50 || got < .39 {
		t.Fatalf("grenade late-fuse braking unexpected with 1s left: %.3f", got)
	}
}

func Test48GrenadeDragCurveIsStepInvariant(t *testing.T) {
	whole := grenadeDragFactor(grenadeFuse, 0)
	stepped := 1.0
	life := grenadeFuse
	for i := 0; i < 600; i++ {
		next := math.Max(0, life-grenadeFuse/600)
		stepped *= grenadeDragFactor(life, next)
		life = next
	}
	if math.Abs(whole-stepped) > 1e-12 {
		t.Fatalf("drag curve changes with step size: whole %.15f stepped %.15f", whole, stepped)
	}
	if whole > .12 || whole < .09 {
		t.Fatalf("unexpected end-of-fuse speed fraction %.3f", whole)
	}
}

func TestGrenadeHomingTurnsAtMissileRateAndKeepsFuseBraking(t *testing.T) {
	g := battle(4)
	g.Rules.FriendlyFire = true
	g.Tanks[0].X, g.Tanks[0].Y, g.Tanks[0].Team = 60, 210, 1
	g.Tanks[1].X, g.Tanks[1].Y, g.Tanks[1].Team = 150, 185, 1
	g.Tanks[2].X, g.Tanks[2].Y, g.Tanks[2].Invulnerable = 147, 255, 1
	g.Tanks[3].X, g.Tanks[3].Y = 320, 300
	b := &Bullet{Kind: "grenade", Owner: 0, Target: -1, X: 100, Y: 210, VX: 80, R: 6, Age: 8.9, Life: 1.1}
	g.Bullets = []*Bullet{b}
	g.updateBullets(tickDT)
	if b.Target != 3 || b.Dead {
		t.Fatalf("grenade must steer toward the vulnerable opponent, got %+v", b)
	}
	if angle, want := math.Atan2(b.VY, b.VX), missileTurn*tickDT; math.Abs(angle-want) > 1e-12 {
		t.Fatalf("grenade turn = %v, want %v", angle, want)
	}
	if speed, want := math.Hypot(b.VX, b.VY), 80*grenadeDragFactor(1.1, 1.1-tickDT); math.Abs(speed-want) > 1e-12 {
		t.Fatalf("grenade speed = %v, want %v", speed, want)
	}
	g.Tanks[3].Invulnerable = 1
	g.updateBullets(tickDT)
	if b.Target != -1 || b.SeekDelay != missileLockDelay {
		t.Fatalf("grenade failed to coast on losing its lock: %+v", b)
	}
}

func TestGrenadeHomingCoastsAfterWallRebound(t *testing.T) {
	g := battle(2)
	g.Tanks[0].X, g.Tanks[0].Y = 60, 210
	g.Tanks[1].X, g.Tanks[1].Y = 160, 230
	g.World.Walls = append(g.World.Walls, Wall{X: 248, Y: 0, W: 8, H: 420, Axis: "v", Line: 252})
	b := &Bullet{Kind: "grenade", Owner: 0, Target: -1, X: 240, Y: 210, VX: grenadeSpeed, R: 6, Age: 1, Life: 9}
	g.Bullets = []*Bullet{b}
	g.updateBullets(tickDT)
	if b.Bounces != 1 || b.VX >= 0 || b.Target != -1 || b.SeekDelay != missileWallDelay {
		t.Fatalf("grenade failed to reset guidance at rebound: %+v", b)
	}
	g.updateBullets(missileWallDelay / 2)
	if b.Target != -1 || b.VY != 0 {
		t.Fatalf("grenade steered before rebound delay expired: %+v", b)
	}
	g.updateBullets(missileWallDelay / 2)
	if b.Target != 1 || b.VY <= 0 {
		t.Fatalf("grenade failed to reacquire after rebound: %+v", b)
	}
}
