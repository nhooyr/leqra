package main

import (
	"encoding/json"
	"math"
	"testing"
	"time"
)

func preparedRoom(t *testing.T, n int) (*Hub, *Room, []*Client) {
	h, cs, r := makeRoom(t, n)
	r.Game = battle(n)
	r.Game.Pickups = nil
	r.Game.SpawnClock = 999
	return h, r, cs
}

func beamLength(points []BeamPoint) float64 {
	length := 0.0
	for i := 1; i < len(points); i++ {
		length += dist(points[i-1].X, points[i-1].Y, points[i].X, points[i].Y)
	}
	return length
}
func TestRicochetLaserHitsAfterVerticalBounce(t *testing.T) {
	g := battle(2)
	p, q := g.Tanks[0], g.Tanks[1]
	p.X, p.Y, p.Angle = 120, 100, math.Atan2(200, 654) // Reflect q through x=497.
	q.X, q.Y = 220, 300
	g.grantPower(p, "laser")
	g.fire(p)
	e := laserEvent(t, g)
	if q.Alive || !p.Alive || len(e.Points) != 3 {
		t.Fatalf("no bank hit: %+v", e)
	}
	if math.Abs(e.Points[1].X-497) > 1e-6 || e.EndX >= e.Points[1].X {
		t.Fatal("wrong reflection")
	}
}
func TestRicochetLaserHitsAfterHorizontalBounce(t *testing.T) {
	g := battle(2)
	p, q := g.Tanks[0], g.Tanks[1]
	p.X, p.Y, p.Angle = 100, 180, math.Atan2(-466, 240) // Reflect q through y=7.
	q.X, q.Y = 340, 300
	g.grantPower(p, "laser")
	g.fire(p)
	e := laserEvent(t, g)
	if q.Alive || len(e.Points) != 3 || math.Abs(e.Points[1].Y-7) > 1e-6 {
		t.Fatalf("no horizontal hit: %+v", e)
	}
}
func TestRicochetLaserPerimeterBudgetAcrossManyBounces(t *testing.T) {
	for _, angle := range []float64{0, .17, math.Pi / 4, math.Pi / 2, 2.91, math.Pi, -1.21} {
		g := battle(1)
		p := g.Tanks[0]
		p.Angle = angle
		g.grantPower(p, "laser")
		g.fire(p)
		e := laserEvent(t, g)
		got, want := beamLength(e.Points), 2*(g.World.Width+g.World.Height)-28
		if len(e.Points) < 4 || math.Abs(got-want) > 1e-5 {
			t.Fatalf("angle %.3f: path %.9f want %.9f, points %d", angle, got, want, len(e.Points))
		}
		if !p.Alive {
			t.Fatal("owner immunity changed")
		}
	}
}
func TestRicochetLaserRangeUsesCurrentMazeDimensions(t *testing.T) {
	for _, size := range [][2]float64{{588, 1008}, {756, 672}, {1008, 672}, {40, 30}} {
		g := battle(1)
		g.World = World{Width: size[0], Height: size[1]}
		p := g.Tanks[0]
		p.X, p.Y, p.Angle = 0, 0, 0
		pts, _ := g.traceLaser(p)
		if math.Abs(beamLength(pts)-(2*(size[0]+size[1])-28)) > 1e-6 {
			t.Fatal("range not perimeter", size)
		}
	}
}
func TestRicochetLaserCornerReflectsBothAxes(t *testing.T) {
	g := battle(1)
	p := g.Tanks[0]
	p.X, p.Y = 120, 100
	p.Angle = math.Atan2(313, 377)
	pts, _ := g.traceLaser(p)
	if len(pts) < 3 || math.Abs(pts[1].X-497) > 1e-6 || math.Abs(pts[1].Y-413) > 1e-6 || pts[2].X >= 497 || pts[2].Y >= 413 {
		t.Fatal("bad corner", pts)
	}
	if beamLength(pts) > g.laserRange()+1e-6 {
		t.Fatal("corner added range")
	}
}
func TestRicochetLaserShieldAndInvulnerabilityAfterBounce(t *testing.T) {
	g := battle(2)
	p, q := g.Tanks[0], g.Tanks[1]
	p.X, p.Y, p.Angle = 120, 100, math.Atan2(200, 654)
	q.X, q.Y, q.Shield = 220, 300, 10
	g.grantPower(p, "laser")
	g.fire(p)
	if !q.Alive || q.Shield != 0 || q.Invulnerable <= 0 {
		t.Fatal("bank shot bypassed shield")
	}
	p.Cooldown = 0
	g.fire(p)
	if !q.Alive {
		t.Fatal("invulnerable tank hit")
	}
}
func TestRicochetLaserSegmentsBoundedAndNoWallTunneling(t *testing.T) {
	for seed := int64(0); seed < 32; seed++ {
		g := newGame(seed)
		g.startMatch(testPlayers(1))
		p := g.Tanks[0]
		p.Invulnerable = 0
		for i := 0; i < 36; i++ {
			p.Angle = float64(i) * math.Pi / 18
			pts, _ := g.traceLaser(p)
			if len(pts) > laserMaxSegments+1 || beamLength(pts) > g.laserRange()+1e-5 {
				t.Fatal("unbounded beam")
			}
			for k := 1; k < len(pts); k++ {
				a, b := pts[k-1], pts[k]
				dx, dy := b.X-a.X, b.Y-a.Y
				length := math.Hypot(dx, dy)
				if length < .003 {
					continue
				}
				if w := g.rayWalls(a.X+dx/length*.001, a.Y+dy/length*.001, dx*(1-.002/length), dy*(1-.002/length), laserRadius); w != nil && w.T < 1-1e-6 {
					t.Fatalf("beam tunnels seed %d angle %d segment %d %+v", seed, i, k, w)
				}
			}
		}
	}
}
func TestRicochetLaserFullPolylineSerializedInOneEvent(t *testing.T) {
	g := battle(1)
	g.grantPower(g.Tanks[0], "laser")
	g.fire(g.Tanks[0])
	e := laserEvent(t, g)
	data, err := json.Marshal(e)
	if err != nil {
		t.Fatal(err)
	}
	var decoded Event
	if err = json.Unmarshal(data, &decoded); err != nil {
		t.Fatal(err)
	}
	if len(decoded.Points) != len(e.Points) || len(decoded.Points) < 4 {
		t.Fatal("missing beam segments")
	}
	n := 0
	for _, event := range g.events {
		if event.Type == "laser" {
			n++
		}
	}
	if n != 1 || len(data) > 20000 {
		t.Fatal("unbounded per-shot event fanout", n, len(data))
	}
}

func grenadeGame() (*Game, *Tank) {
	g := battle(2)
	p := g.Tanks[0]
	g.Tanks[1].Y = 350
	g.Pickups = nil
	g.SpawnClock = 999
	g.grantPower(p, "grenade")
	return g, p
}
func TestRemoteGrenadeLaunchHoldThenPress(t *testing.T) {
	g, p := grenadeGame()
	g.weaponControl(p, true, true)
	if len(g.Bullets) != 1 || g.Bullets[0].Life != grenadeFuse || p.Charges != 2 {
		t.Fatal("wrong launch/fuse")
	}
	b := g.Bullets[0]
	b.X, b.Y = 300, 50
	for i := 0; i < 120; i++ {
		p.Cooldown = 0
		g.Tick++ // Held Machine gun fires once on each authoritative simulation tick.
		g.weaponControl(p, true, false)
	}
	if b.Dead || p.Charges != 2 || len(g.Bullets) != 1 {
		t.Fatal("hold detonates or repeats")
	}
	g.weaponControl(p, false, false)
	g.weaponControl(p, true, true)
	if !b.Dead || p.Charges != 2 {
		t.Fatal("next press did not detonate without a charge")
	}
	for i := 0; i < 90; i++ {
		p.Cooldown = 0
		g.Tick++ // Held Machine gun fires once on each authoritative simulation tick.
		g.weaponControl(p, true, false)
	}
	if len(g.Bullets) != 1 {
		t.Fatal("detonate hold also launched")
	}
	g.weaponControl(p, false, false)
	g.weaponControl(p, true, true)
	if len(g.Bullets) != 2 || p.Charges != 1 {
		t.Fatal("next throw failed")
	}
}
func TestRemoteGrenadeDetonatesDuringLaunchCooldown(t *testing.T) {
	g, p := grenadeGame()
	g.weaponControl(p, true, true)
	b := g.Bullets[0]
	b.X, b.Y = 350, 50
	g.weaponControl(p, false, false)
	g.weaponControl(p, true, true)
	if !b.Dead || p.Cooldown != .8 {
		t.Fatal("detonation should ignore throw cooldown")
	}
}
func TestRemoteGrenadeOnlyOwnerAndOnlyGrenades(t *testing.T) {
	g, p := grenadeGame()
	g.Bullets = []*Bullet{{Kind: "grenade", Owner: 0, X: 300, Y: 50, Life: 5}, {Kind: "grenade", Owner: 1, X: 350, Y: 50, Life: 5}, {Kind: "homing", Owner: 0, X: 350, Y: 50, Life: 5}, {Owner: 0, X: 350, Y: 50, Life: 5}}
	if !g.detonateOwned(p) || !g.Bullets[0].Dead {
		t.Fatal("own grenade not detonated")
	}
	for _, b := range g.Bullets[1:] {
		if b.Dead {
			t.Fatal("wrong owner/kind detonated")
		}
	}
}
func TestRemoteGrenadeLastChargeWeaponSwitchAndExpiry(t *testing.T) {
	for _, next := range []string{"last", "expired", "laser", "rapid"} {
		t.Run(next, func(t *testing.T) {
			g, p := grenadeGame()
			if next == "last" {
				p.Charges = 1
			}
			g.weaponControl(p, true, true)
			b := g.Bullets[0]
			b.X, b.Y = 350, 50
			if next == "expired" {
				p.Power = ""
				p.PowerTime = 0
			} else if next != "last" {
				g.grantPower(p, next)
			}
			before := p.Charges
			g.weaponControl(p, false, false)
			g.weaponControl(p, true, true)
			if !b.Dead || p.Charges != before {
				t.Fatal("lost ownership or spent a new-weapon charge")
			}
			for i := 0; i < 120; i++ {
				p.Cooldown = 0
				g.weaponControl(p, true, false)
			}
			if len(g.Bullets) != 1 {
				t.Fatal("detonation fell through to current weapon")
			}
		})
	}
}
func TestRemoteGrenadeHoldThroughFuseDoesNotRepeat(t *testing.T) {
	for _, charges := range []int{1, 3} {
		g, p := grenadeGame()
		p.Charges = charges
		g.weaponControl(p, true, true)
		g.Bullets[0].X, g.Bullets[0].Y, g.Bullets[0].VX = 350, 50, 0
		for i := 0; i < int(grenadeFuse/tickDT)+60; i++ {
			p.Cooldown = 0
			g.weaponControl(p, true, false)
			g.updateBullets(tickDT)
		}
		if len(g.Bullets) != 0 || p.Charges != charges-1 {
			t.Fatal("held throw auto-fired after fuse")
		}
	}
}
func TestRemoteGrenadeDeadOwnerCannotPressButFuseStillWorks(t *testing.T) {
	g, p := grenadeGame()
	g.fire(p)
	b := g.Bullets[0]
	b.X, b.Y, b.VX = 350, 50, 0
	p.Alive = false
	if g.detonateOwned(p) {
		t.Fatal("dead tank triggered grenade")
	}
	g.weaponControl(p, true, true)
	if b.Dead {
		t.Fatal("dead input triggered grenade")
	}
	for i := 0; i < int(grenadeFuse/tickDT)+30; i++ {
		g.updateBullets(tickDT)
	}
	if !b.Dead {
		t.Fatal("dead owner cancelled fuse")
	}
}
func TestRemoteGrenadeBlastRetainsWallAndShieldRules(t *testing.T) {
	g := battle(3)
	p := g.Tanks[0]
	g.Tanks[1].X = 220
	g.Tanks[1].Shield = 10
	g.Tanks[2].X = 300
	g.World.Walls = append(g.World.Walls, Wall{250, 0, 8, 420, "v", 254})
	g.Bullets = []*Bullet{{Kind: "grenade", Owner: 0, X: 210, Y: 210, Life: 5}}
	g.weaponControl(p, false, true)
	if p.Alive || !g.Tanks[1].Alive || g.Tanks[1].Shield != 0 || !g.Tanks[2].Alive {
		t.Fatal("remote blast altered damage rules")
	}
}
func TestRemoteGrenadeMultipleOwnedDetonateTogether(t *testing.T) {
	g, p := grenadeGame()
	g.Bullets = []*Bullet{{Kind: "grenade", Owner: 0, X: p.X, Y: p.Y, Life: 5}, {Kind: "grenade", Owner: 0, X: 350, Y: 50, Life: 5}}
	g.detonateOwned(p)
	if p.Alive || !g.Bullets[0].Dead || !g.Bullets[1].Dead {
		t.Fatal("owner death interrupted one valid detonation")
	}
}
func TestRemoteGrenadeRoundResetClearsPendingPress(t *testing.T) {
	g, p := grenadeGame()
	g.weaponControl(p, true, true)
	ps := testPlayers(2)
	ps[0].FirePending = true
	ps[0].Input.Fire = true
	g.startRound(ps)
	if len(g.Bullets) != 0 || ps[0].FirePending || ps[0].Input.Fire || g.Tanks[0].fireBlocked {
		t.Fatal("old grenade/input leaked across rounds")
	}
}
func TestRemoteGrenadeRegularWeaponsStillAutoFire(t *testing.T) {
	for _, kind := range []string{"", "rapid", "scatter", "homing", "laser"} {
		g, p := grenadeGame()
		p.Power = kind
		if kind == "rapid" {
			g.grantPower(p, kind)
		}
		p.Charges = 3
		p.Angle = -math.Pi / 2
		g.weaponControl(p, true, true)
		first := g.nextBullet + g.nextEvent
		p.Cooldown = 0
		g.Tick++ // Held Machine gun fires once on each authoritative simulation tick.
		g.weaponControl(p, true, false)
		if g.nextBullet+g.nextEvent <= first {
			t.Fatal("auto fire stopped", kind)
		}
	}
}
func TestRemoteGrenadeHubPreservesTapBetweenTicks(t *testing.T) {
	h, r, cs := preparedRoom(t, 2)
	p := r.Game.Tanks[0]
	r.Game.grantPower(p, "grenade")
	action(t, h, cs[0], map[string]any{"type": "input", "seq": 1, "fire": true})
	action(t, h, cs[0], map[string]any{"type": "input", "seq": 2, "fire": false})
	h.tick(time.Now())
	if len(r.Game.Bullets) != 1 || r.Players[0].FirePending {
		t.Fatal("tap was dropped or not consumed")
	}
	b := r.Game.Bullets[0]
	b.X, b.Y, b.VX = 350, 50, 0
	action(t, h, cs[0], map[string]any{"type": "input", "seq": 3, "fire": true})
	action(t, h, cs[0], map[string]any{"type": "input", "seq": 4, "fire": false})
	h.tick(time.Now())
	if !b.Dead || p.Charges != 2 {
		t.Fatal("fast second tap didn't detonate")
	}
}
func TestRemoteGrenadeHubRejectsForgedEdgeAndOtherOwner(t *testing.T) {
	h, r, cs := preparedRoom(t, 2)
	g := r.Game
	g.grantPower(g.Tanks[0], "grenade")
	g.fire(g.Tanks[0])
	b := g.Bullets[0]
	b.X, b.Y, b.VX = 350, 50, 0
	action(t, h, cs[1], map[string]any{"type": "input", "seq": 1, "fire": true, "owner": 0, "target": 0})
	action(t, h, cs[0], map[string]any{"type": "input", "seq": 1, "fire": false, "FirePressed": true, "firePressed": true, "detonate": true})
	h.tick(time.Now())
	if b.Dead {
		t.Fatal("forged edge or another player detonated grenade")
	}
}
func TestRemoteGrenadeHubStaleAndRepeatedInputsDoNotDetonate(t *testing.T) {
	h, r, cs := preparedRoom(t, 2)
	g := r.Game
	g.grantPower(g.Tanks[0], "grenade")
	action(t, h, cs[0], map[string]any{"type": "input", "seq": 1, "fire": true})
	h.tick(time.Now())
	b := g.Bullets[0]
	b.X, b.Y, b.VX = 350, 50, 0
	action(t, h, cs[0], map[string]any{"type": "input", "seq": 2, "fire": true})
	h.tick(time.Now())
	if b.Dead {
		t.Fatal("hold heartbeat detonated")
	}
	action(t, h, cs[0], map[string]any{"type": "input", "seq": 1, "fire": false})
	if !r.Players[0].Input.Fire {
		t.Fatal("stale release accepted")
	}
	h.tick(time.Now().Add(inputTimeout + time.Millisecond))
	action(t, h, cs[0], map[string]any{"type": "input", "seq": 3, "fire": true})
	h.tick(time.Now())
	if b.Dead {
		t.Fatal("input timeout turned held heartbeat into detonation")
	}
}
