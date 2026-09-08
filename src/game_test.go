package main

import (
	"math"
	"testing"
)

func testPlayers(n int) [maxTanks]*Player {
	var ps [maxTanks]*Player
	for i := 0; i < n; i++ {
		ps[i] = &Player{ID: i, Name: []string{"ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT"}[i], Client: &Client{}}
	}
	return ps
}
func openArena(g *Game) {
	g.World = World{Cols: 6, Rows: 5, Width: 504, Height: 420, Walls: []Wall{
		{X: -4, Y: -4, W: 512, H: 8, Axis: "h", Line: 0}, {X: -4, Y: 416, W: 512, H: 8, Axis: "h", Line: 420},
		{X: -4, Y: -4, W: 8, H: 428, Axis: "v", Line: 0}, {X: 500, Y: -4, W: 8, H: 428, Axis: "v", Line: 504},
	}}
}
func battle(n int) *Game {
	g := newGame(42)
	g.startMatch(testPlayers(n))
	openArena(g)
	if n > 4 {
		g.World.Cols = n + 2
		g.World.Width = float64(g.World.Cols) * cellSize
		g.World.Walls[0].W = g.World.Width + 8
		g.World.Walls[1].W = g.World.Width + 8
		g.World.Walls[3].X = g.World.Width - 4
		g.World.Walls[3].Line = g.World.Width
	}
	g.Phase = "playing"
	for i, t := range g.Tanks {
		if t != nil {
			t.X = 90 + float64(i)*100
			t.Y = 210
			t.Angle = 0
			t.Invulnerable = 0
		}
	}
	return g
}
func TestMazeConnectedAndSpawnSafe(t *testing.T) {
	for seed := int64(0); seed < 80; seed++ {
		g := newGame(seed)
		g.startMatch(testPlayers(maxTanks))
		seen := map[int]bool{0: true}
		q := []int{0}
		w := g.World
		for len(q) > 0 {
			at := q[0]
			q = q[1:]
			x, y := at%w.Cols, at/w.Cols
			for _, d := range [][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}} {
				nx, ny := x+d[0], y+d[1]
				if nx < 0 || ny < 0 || nx >= w.Cols || ny >= w.Rows {
					continue
				}
				id := ny*w.Cols + nx
				if seen[id] {
					continue
				}
				if g.rayWalls((float64(x)+.5)*cellSize, (float64(y)+.5)*cellSize, float64(d[0])*cellSize, float64(d[1])*cellSize, tankRadius+1) == nil {
					seen[id] = true
					q = append(q, id)
				}
			}
		}
		if len(seen) != w.Cols*w.Rows {
			t.Fatalf("seed %d: only %d reachable cells", seed, len(seen))
		}
		for _, tank := range g.Tanks {
			beforeX, beforeY := tank.X, tank.Y
			g.resolveWalls(tank)
			if dist(beforeX, beforeY, tank.X, tank.Y) > .01 {
				t.Fatalf("spawn embedded in wall seed %d", seed)
			}
		}
	}
}
func TestMovementSpeedAndWallClamping(t *testing.T) {
	g := battle(2)
	tank := g.Tanks[0]
	x := tank.X
	for i := 0; i < 60; i++ {
		g.control(tank, Input{Forward: true}, tickDT)
	}
	if math.Abs(tank.X-x-128) > .001 {
		t.Fatalf("speed %f", tank.X-x)
	}
	for i := 0; i < 500; i++ {
		g.control(tank, Input{Forward: true}, tickDT)
	}
	if tank.X > g.World.Width-wallSize/2-tank.R+.01 {
		t.Fatal("crossed outer wall")
	}
	g.World.Walls = append(g.World.Walls, Wall{X: 248, Y: 0, W: 8, H: 420, Axis: "v", Line: 252})
	tank.X = 210
	for i := 0; i < 100; i++ {
		g.control(tank, Input{Forward: true}, tickDT)
	}
	if tank.X > 248-tank.R+.01 {
		t.Fatal("crossed internal wall")
	}
}
func TestTouchStickSpeedBound(t *testing.T) {
	g := battle(2)
	tank := g.Tanks[0]
	x := tank.X
	for i := 0; i < 30; i++ {
		g.control(tank, Input{StickX: 1, StickY: 0}, tickDT)
	}
	if math.Abs(tank.X-x-64) > .001 {
		t.Fatal("touch speed does not match keyboard")
	}
}
func TestRicochetReflectsWithoutTunneling(t *testing.T) {
	g := battle(2)
	g.Tanks = [maxTanks]*Tank{}
	b := &Bullet{Owner: 0, X: 480, Y: 160, VX: 282, VY: 0, R: 3.5, Life: 5, Age: 1}
	g.Bullets = []*Bullet{b}
	for i := 0; i < 30; i++ {
		g.updateBullets(tickDT)
	}
	if b.Bounces != 1 || b.VX >= 0 || b.X >= g.World.Width {
		t.Fatalf("bad reflection %+v", b)
	}
}
func TestProjectileDamageAndSelfRicochet(t *testing.T) {
	for _, owner := range []int{0, 1} {
		g := battle(2)
		tank := g.Tanks[1]
		b := &Bullet{Owner: owner, X: tank.X - 35, Y: tank.Y, VX: 282, R: 3.5, Life: 5, Age: 1}
		g.Bullets = []*Bullet{b}
		for i := 0; i < 8; i++ {
			g.updateBullets(tickDT)
		}
		if tank.Alive {
			t.Fatalf("owner %d did not damage target", owner)
		}
	}
}
func TestShieldAbsorbsExactlyOneHit(t *testing.T) {
	g := battle(2)
	tank := g.Tanks[1]
	tank.Shield = 10
	b := &Bullet{Owner: 0}
	g.hurt(tank, b)
	if !tank.Alive || tank.Shield != 0 {
		t.Fatal("shield failed")
	}
	g.hurt(tank, b)
	if !tank.Alive {
		t.Fatal("brief shield grace missing")
	}
	tank.Invulnerable = 0
	g.hurt(tank, b)
	if tank.Alive {
		t.Fatal("second hit should eliminate")
	}
}
func TestMuzzleGraceThenSelfDamage(t *testing.T) {
	g := battle(2)
	tank := g.Tanks[0]
	b := &Bullet{Owner: 0, X: tank.X, Y: tank.Y, R: 3.5, Life: 5}
	g.Bullets = []*Bullet{b}
	g.updateBullets(tickDT)
	if !tank.Alive {
		t.Fatal("muzzle grace failed")
	}
	b.Age = .3
	g.updateBullets(tickDT)
	if tank.Alive {
		t.Fatal("owner incorrectly immune")
	}
}
func TestCooldownAndAmmoCapacity(t *testing.T) {
	g := battle(2)
	tank := g.Tanks[0]
	if !g.fire(tank) || g.fire(tank) {
		t.Fatal("cooldown not enforced")
	}
	for i := 0; i < 20; i++ {
		tank.Cooldown = 0
		g.fire(tank)
	}
	if len(g.Bullets) != 5 {
		t.Fatalf("standard cap %d", len(g.Bullets))
	}
	g.Bullets = nil
	g.grantPower(tank, "rapid")
	for i := 0; i < machineCapacity+20; i++ {
		g.Tick++
		tank.Cooldown = 0
		g.fire(tank)
	}
	if len(g.Bullets) != machineCapacity {
		t.Fatal("machine-gun cap")
	}
	g.Bullets = nil
	tank.Power = "scatter"
	tank.Charges = 5
	for i := 0; i < 20; i++ {
		tank.Cooldown = 0
		g.fire(tank)
	}
	if len(g.Bullets) != 12 {
		t.Fatalf("scatter cap %d", len(g.Bullets))
	}
}
func TestScatterHasThreeDirections(t *testing.T) {
	g := battle(2)
	tank := g.Tanks[0]
	tank.Power = "scatter"
	tank.Charges = 5
	g.fire(tank)
	if len(g.Bullets) != 3 || g.Bullets[0].VY >= 0 || g.Bullets[2].VY <= 0 || tank.Charges != 4 {
		t.Fatal("scatter fan")
	}
}
func TestBulletLifetimeBound(t *testing.T) {
	g := battle(2)
	g.fire(g.Tanks[0])
	g.Tanks = [maxTanks]*Tank{}
	for i := 0; i < 400; i++ {
		g.updateBullets(tickDT)
	}
	if len(g.Bullets) != 0 {
		t.Fatal("bullets never expire")
	}
}
func TestRoundAndMatchScoring(t *testing.T) {
	g := battle(2)
	g.Scores[0] = 4
	g.Tanks[1].Alive = false
	g.step(tickDT, [maxTanks]Input{}, testPlayers(2))
	if g.Phase != "roundOver" || g.Winner != 0 || g.Scores[0] != 5 {
		t.Fatal("round result")
	}
	g.finishRound(0)
	if g.Scores[0] != 5 {
		t.Fatal("double scoring")
	}
	for i := 0; i < 170; i++ {
		g.step(tickDT, [maxTanks]Input{}, testPlayers(2))
	}
	if g.Phase != "matchOver" {
		t.Fatal("match did not finish")
	}
}
func TestSimultaneousEliminationsDraw(t *testing.T) {
	g := battle(2)
	for _, tank := range g.Tanks {
		if tank != nil {
			g.Bullets = append(g.Bullets, &Bullet{Owner: 1 - tank.ID, X: tank.X, Y: tank.Y, R: 3.5, Age: 1, Life: 3})
		}
	}
	g.step(tickDT, [maxTanks]Input{}, testPlayers(2))
	if g.Phase != "roundOver" || g.Winner != -1 || g.Scores != [maxTanks]int{} {
		t.Fatal("simultaneous knockout not a draw")
	}
}
func TestTimeoutDraw(t *testing.T) {
	g := battle(2)
	g.Clock = 0
	g.step(tickDT, [maxTanks]Input{}, testPlayers(2))
	if g.Phase != "roundOver" || g.Winner != -1 {
		t.Fatal("timeout scoring")
	}
}
func TestPickupConsumedOnce(t *testing.T) {
	g := battle(2)
	g.Tanks[1].X = g.Tanks[0].X + 35
	g.Pickups = []*Pickup{{ID: 1, X: g.Tanks[0].X, Y: 210, Type: "shield", Life: 10}}
	g.step(tickDT, [maxTanks]Input{}, testPlayers(2))
	if len(g.Pickups) != 0 || g.Tanks[0].Shield <= 0 || g.Tanks[1].Shield > 0 {
		t.Fatal("pickup duplicate grant")
	}
}
func TestDisconnectedPlayerDoesNotFarmRounds(t *testing.T) {
	g := battle(2)
	ps := testPlayers(2)
	ps[1].Client = nil
	g.Tanks[1].Alive = false
	g.step(tickDT, [maxTanks]Input{}, ps)
	for i := 0; i < 200; i++ {
		g.step(tickDT, [maxTanks]Input{}, ps)
	}
	if g.Phase != "lobby" || g.Scores[0] != 1 {
		t.Fatal("lone pilot kept farming points")
	}
}
func TestSimulationFiniteOverManyRounds(t *testing.T) {
	for seed := int64(1); seed <= 12; seed++ {
		g := newGame(seed)
		ps := testPlayers(4)
		g.startMatch(ps)
		for frame := 0; frame < 1800; frame++ {
			var in [maxTanks]Input
			for i := range in {
				in[i] = Input{Forward: true, Right: frame%180 > 90, Fire: true}
			}
			g.step(tickDT, in, ps)
			for _, tank := range g.Tanks {
				if tank != nil && (math.IsNaN(tank.X) || math.IsInf(tank.X, 0) || tank.X < 20 || tank.X > g.World.Width-20) {
					t.Fatal("invalid simulation position")
				}
			}
		}
	}
}
