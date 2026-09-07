package main

import (
	"encoding/json"
	"math"
	"os"
	"strings"
	"testing"
)

func missileFor(g *Game, x, y, angle float64) *Bullet {
	return &Bullet{Kind: "homing", Owner: 0, Target: -1, X: x, Y: y, VX: missileSpeed * math.Cos(angle), VY: missileSpeed * math.Sin(angle), R: 5, Age: .2, Life: g.missileTravelRange()/missileSpeed + .5, RangeLeft: g.missileTravelRange(), rangeSet: true}
}
func TestMissileTravelBudgetUsesActualHalfPerimeter(t *testing.T) {
	for _, size := range [][2]float64{{504, 420}, {756, 672}, {588, 1008}, {1008, 672}} {
		g := battle(2)
		g.World.Width = size[0]
		g.World.Height = size[1]
		g.World.Walls = nil
		g.grantPower(g.Tanks[0], "homing")
		g.fire(g.Tanks[0])
		b := g.Bullets[0]
		if math.Abs(b.RangeLeft+28-(size[0]+size[1])) > 1e-8 {
			t.Fatalf("budget not half perimeter: %+v", b)
		}
		if b.Life < b.RangeLeft/missileSpeed {
			t.Fatal("old short fuse truncates flight")
		}
	}
}
func TestMissileRangeExhaustionStopsExactlyMidTick(t *testing.T) {
	g := battle(0)
	g.events = nil
	b := missileFor(g, 100, 200, 0)
	b.RangeLeft = 1.25
	g.Bullets = []*Bullet{b}
	g.updateBullets(tickDT)
	if !b.Dead || b.RangeLeft != 0 || math.Abs(b.X-101.25) > 1e-7 || len(g.Bullets) != 0 {
		t.Fatalf("overshot distance cap %+v", b)
	}
	if len(g.events) != 1 || g.events[0].Type != "impact" {
		t.Fatal("missing range expiry visual")
	}
	g.updateBullets(tickDT)
	if len(g.events) != 1 {
		t.Fatal("expiry repeated")
	}
}
func TestMissileRangeExpiresBeforeEnemyOutsideBudget(t *testing.T) {
	g := battle(2)
	g.Tanks[0].Alive = false
	g.Tanks[1].X = 145
	g.Tanks[1].Y = 210
	b := missileFor(g, 100, 210, 0)
	b.RangeLeft = 10
	g.Bullets = []*Bullet{b}
	for i := 0; i < 8; i++ {
		g.updateBullets(tickDT)
	}
	if !g.Tanks[1].Alive || !b.Dead || math.Abs(b.X-110) > 1e-7 {
		t.Fatal("damage beyond path budget")
	}
}
func TestMissileReflectionsSpendOneContinuousBudget(t *testing.T) {
	g := battle(0)
	b := missileFor(g, 80, 180, .7)
	g.Bullets = []*Bullet{b}
	spent := 0.0
	for i := 0; i < 600 && !b.Dead; i++ {
		before := b.RangeLeft
		x, y := b.X, b.Y
		g.updateBullets(tickDT)
		debit := before - b.RangeLeft
		spent += debit
		if debit < -1e-9 || math.Hypot(b.X-x, b.Y-y) > debit+1e-6 {
			t.Fatal("travel not debited")
		}
	}
	if !b.Dead || b.RangeLeft > 1e-7 || math.Abs(spent-g.missileTravelRange()) > 1e-6 || b.Bounces < 2 {
		t.Fatalf("bad reflected budget %+v", b)
	}
}
func TestMissileCornerReflectionAndBudget(t *testing.T) {
	g := battle(0)
	b := missileFor(g, 480, 396, math.Pi/4)
	g.Bullets = []*Bullet{b}
	before := b.RangeLeft
	for i := 0; i < 8; i++ {
		g.updateBullets(tickDT)
	}
	if b.Dead || b.VX >= 0 || b.VY >= 0 || b.Bounces != 1 || b.RangeLeft >= before || b.X > 495 || b.Y > 411 {
		t.Fatalf("bad corner reflection: %+v", b)
	}
}
func TestMissileNearWallExpiryCannotNudgeBeyondRange(t *testing.T) {
	g := battle(0)
	b := missileFor(g, 494, 210, 0)
	b.RangeLeft = 1.02
	g.Bullets = []*Bullet{b}
	g.updateBullets(tickDT)
	if !b.Dead || b.RangeLeft != 0 || b.X < 494.979999 || b.X > 495 {
		t.Fatalf("range ignored by nudge: %+v", b)
	}
}
func TestMissileNarrowCorridorDoesNotUseShellBounceLimit(t *testing.T) {
	g := battle(0)
	g.World.Walls = append(g.World.Walls, Wall{X: 120, Y: 0, W: 8, H: 420})
	b := missileFor(g, 110, 210, 0)
	b.Bounces = 22
	g.Bullets = []*Bullet{b}
	for i := 0; i < 3; i++ {
		g.updateBullets(tickDT)
	}
	if b.Dead || b.Bounces != 23 {
		t.Fatal("missile incorrectly inherits 22-bounce shell limit")
	}
}
func TestMissileForwardSeekerRejectsTargetBehind(t *testing.T) {
	g := battle(2)
	g.Tanks[1].X = 100
	b := missileFor(g, 200, 210, 0)
	g.steerMissile(b, tickDT)
	if b.Target != -1 || b.VY != 0 {
		t.Fatal("missile turns around on target behind")
	}
}
func TestMissileLosesLockAfterNoseDodge(t *testing.T) {
	g := battle(2)
	g.Tanks[1].X = 300
	b := missileFor(g, 200, 210, 0)
	g.steerMissile(b, tickDT)
	if b.Target != 1 {
		t.Fatal("no initial lock")
	}
	g.Tanks[1].X = 140
	g.Tanks[1].Y = 160
	g.steerMissile(b, tickDT)
	if b.Target != -1 || b.SeekDelay < missileLockDelay-.001 || b.VY != 0 {
		t.Fatal("missile snapped around after passing target")
	}
	g.Tanks[1].X = 300
	g.steerMissile(b, missileWallDelay*.5)
	if b.Target != -1 {
		t.Fatal("immediate reacquisition makes dodge ineffective")
	}
	g.steerMissile(b, .3)
	if b.Target != 1 {
		t.Fatal("cannot reacquire after cooldown")
	}
}
func TestMissileReboundKeepsOutgoingHeadingDuringGrace(t *testing.T) {
	g := battle(2)
	g.Tanks[1].X = 470
	g.Tanks[1].Y = 310
	b := missileFor(g, 493, 210, 0)
	g.Bullets = []*Bullet{b}
	g.updateBullets(tickDT)
	if b.VX >= 0 || b.SeekDelay <= 0 || b.Target != -1 {
		t.Fatal("did not reflect or clear seeker")
	}
	a := math.Atan2(b.VY, b.VX)
	g.steerMissile(b, missileWallDelay*.5)
	if math.Abs(delta(a, math.Atan2(b.VY, b.VX))) > 1e-8 {
		t.Fatal("guidance fights fresh bounce")
	}
}
func TestAggressiveMissileCatchesPreviousEasyDodge(t *testing.T) {
	// This is the same close crossing that escaped the old 1.2 rad/s seeker.
	// The requested stronger 2.8 rad/s seeker should now catch it, not guarantee a dodge.
	g := battle(2)
	g.Tanks[0].Alive = false
	target := g.Tanks[1]
	target.X = 330
	target.Y = 300
	b := missileFor(g, 250, 300, 0)
	g.Bullets = []*Bullet{b}
	for i := 0; i < 60 && target.Alive; i++ {
		g.moveTank(target, 0, -128*tickDT)
		g.updateBullets(tickDT)
	}
	if target.Alive || !b.Dead {
		t.Fatal("aggressive tracking did not intercept the crossing")
	}
}
func TestAggressiveMissileWiderConeAndBoundedTurn(t *testing.T) {
	g := battle(2)
	g.Tanks[1].X = 180
	g.Tanks[1].Y = 310
	b := missileFor(g, 200, 210, 0)
	g.steerMissile(b, tickDT)
	if b.Target != 1 {
		t.Fatal("new off-axis acquisition cone did not acquire")
	}
	turn := math.Abs(math.Atan2(b.VY, b.VX))
	if turn > missileTurn*tickDT+1e-8 || turn < 1.2*tickDT*1.5 {
		t.Fatalf("turn is not stronger but bounded: %g", turn)
	}
	g.World.Walls = append(g.World.Walls, Wall{X: 100, Y: 260, W: 280, H: 8})
	g.steerMissile(b, tickDT)
	if b.Target != -1 || b.SeekDelay <= 0 {
		t.Fatal("seeker tracked through cover")
	}
}
func TestMissileReflectedOwnerDamageAndShield(t *testing.T) {
	for _, shield := range []float64{0, 10} {
		g := battle(2)
		p := g.Tanks[0]
		p.X = 370
		p.Y = 210
		p.Shield = shield
		g.Tanks[1].Alive = false
		b := missileFor(g, 480, 210, 0)
		g.Bullets = []*Bullet{b}
		for i := 0; i < 60 && !b.Dead; i++ {
			g.updateBullets(tickDT)
		}
		if !b.Dead || b.Bounces < 1 || p.Alive != (shield > 0) || p.Shield != 0 {
			t.Fatalf("owner damage/shield wrong %+v", p)
		}
	}
}
func TestMissileRangeAndReboundDelaySerialized(t *testing.T) {
	g := battle(0)
	b := missileFor(g, 493, 210, 0)
	g.Bullets = []*Bullet{b}
	g.updateBullets(tickDT)
	data, _ := json.Marshal(b)
	var state map[string]any
	_ = json.Unmarshal(data, &state)
	if state["rangeLeft"].(float64) <= 0 || state["seekDelay"].(float64) <= 0 || state["bounces"].(float64) != 1 {
		t.Fatal("client missing authoritative flight fields")
	}
	if strings.Contains(string(data), "rangeSet") {
		t.Fatal("internal range state leaked")
	}
}
func TestLegendUsesSharedCanvasIconForEveryPower(t *testing.T) {
	html, _ := os.ReadFile("web/index.html")
	js, _ := os.ReadFile("web/game.js")
	for _, kind := range pickupTypes {
		if strings.Count(string(html), `data-power-icon="`+kind+`"`) != 1 {
			t.Fatalf("missing or duplicate legend icon %s", kind)
		}
	}
	if !strings.Contains(string(js), "powerIcon(kind,c)") || !strings.Contains(string(js), "powerIcon(p.type)") {
		t.Fatal("legend/maze do not share renderer")
	}
	if strings.Contains(string(html), ">↗</div>") || strings.Contains(string(html), ">⌁</div>") {
		t.Fatal("font stand-ins still present")
	}
}
