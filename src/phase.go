package main

import "math"

// rayBounds intersects only the four inner faces of the arena rim. Cannon
// ignores ALL interior walls; using a boundary rectangle avoids tile-seam hits.
func (g *Game) rayBoundsHit(x, y, dx, dy, r float64) (RayHit, bool) {
	minX, minY := wallSize/2+r, wallSize/2+r
	maxX, maxY := g.World.Width-minX, g.World.Height-minY
	var best RayHit
	hasBest := false
	consider := func(at, nx, ny float64) {
		if at < -1e-7 || at > 1+1e-7 {
			return
		}
		at = clamp(at, 0, 1)
		if !hasBest || at < best.T-1e-7 {
			best = RayHit{at, nx, ny}
			hasBest = true
		} else if math.Abs(at-best.T) < 1e-7 {
			if nx != 0 {
				best.NX = nx
			}
			if ny != 0 {
				best.NY = ny
			}
		}
	}
	if dx > 1e-9 {
		consider((maxX-x)/dx, -1, 0)
	} else if dx < -1e-9 {
		consider((minX-x)/dx, 1, 0)
	}
	if dy > 1e-9 {
		consider((maxY-y)/dy, 0, -1)
	} else if dy < -1e-9 {
		consider((minY-y)/dy, 0, 1)
	}
	return best, hasBest
}
func (g *Game) rayBounds(x, y, dx, dy, r float64) *RayHit {
	hit, ok := g.rayBoundsHit(x, y, dx, dy, r)
	if !ok {
		return nil
	}
	return &hit
}
func (g *Game) projectileWallHit(kind string, x, y, dx, dy, r float64) (RayHit, bool) {
	if kind == "cannon" {
		return g.rayBoundsHit(x, y, dx, dy, r)
	}
	return g.rayWallsHit(x, y, dx, dy, r)
}
func (g *Game) projectileWall(kind string, x, y, dx, dy, r float64) *RayHit {
	hit, ok := g.projectileWallHit(kind, x, y, dx, dy, r)
	if !ok {
		return nil
	}
	return &hit
}
func (g *Game) movementWallHit(ghost bool, x, y, dx, dy, r float64) (RayHit, bool) {
	if ghost {
		return g.rayBoundsHit(x, y, dx, dy, r)
	}
	return g.rayWallsHit(x, y, dx, dy, r)
}
func (g *Game) movementWall(ghost bool, x, y, dx, dy, r float64) *RayHit {
	hit, ok := g.movementWallHit(ghost, x, y, dx, dy, r)
	if !ok {
		return nil
	}
	return &hit
}

func (g *Game) clearTankAt(x, y, r float64) bool {
	margin := wallSize/2 + r
	if x < margin || x > g.World.Width-margin || y < margin || y > g.World.Height-margin {
		return false
	}
	for _, wi := range g.wallCandidates(x, y, 0, 0, r+.001) {
		w := g.World.Walls[wi]
		if dist(x, y, clamp(x, w.X, w.X+w.W), clamp(y, w.Y, w.Y+w.H)) < r+.0001 {
			return false
		}
	}
	return true
}

type projectileLaunch struct {
	x, y, ux, uy, distance, muzzle float64
	bounced, valid                 bool
}

// The usual sweep intentionally ignores initial overlaps. A phased pilot can
// start inside one, so resolve only that launch onto a nearby incoming face.
// General movement, visibility and projectile sweeps retain their old rules.
func wallLaunch(x, y, ux, uy, radius, muzzle float64, walls []Wall, clearBounds func(float64, float64) bool) projectileLaunch {
	launch := projectileLaunch{x: x, y: y, ux: ux, uy: uy, muzzle: muzzle, valid: true}
	inside := func(px, py float64, w Wall) bool {
		return px >= w.X-radius && px <= w.X+w.W+radius && py >= w.Y-radius && py <= w.Y+w.H+radius
	}
	var xs, ys []float64
	for _, w := range walls {
		if inside(x, y, w) {
			if xs == nil {
				xs, ys = []float64{x}, []float64{y}
			}
			xs = append(xs, w.X-radius-.12, w.X+w.W+radius+.12)
			ys = append(ys, w.Y-radius-.12, w.Y+w.H+radius+.12)
		}
	}
	if xs == nil {
		return launch
	}
	launch.bounced, launch.valid = true, false
	best := math.Inf(1)
	for _, px := range xs {
		for _, py := range ys {
			dx, dy := px-x, py-y
			distance := dx*dx + dy*dy
			if distance > 32*32 || dx*ux+dy*uy > 1e-7 || clearBounds != nil && !clearBounds(px, py) {
				continue
			}
			clear := true
			for _, w := range walls {
				if inside(px, py, w) {
					clear = false
					break
				}
			}
			if !clear || distance > best+1e-7 || math.Abs(distance-best) <= 1e-7 &&
				(px > launch.x+1e-7 || math.Abs(px-launch.x) <= 1e-7 && py >= launch.y) {
				continue
			}
			best, launch.x, launch.y, launch.valid = distance, px, py, true
		}
	}
	if !launch.valid {
		return launch // Invalid/fully solid geometry absorbs the legal shot.
	}
	launch.distance = math.Sqrt(best)
	launch.muzzle = max(0, muzzle-launch.distance)
	if (launch.x-x)*ux < -1e-9 {
		launch.ux = -ux
	}
	if (launch.y-y)*uy < -1e-9 {
		launch.uy = -uy
	}
	return launch
}

func (g *Game) projectileLaunch(t *Tank, angle, radius, muzzle float64) projectileLaunch {
	ux, uy := math.Cos(angle), math.Sin(angle)
	if t.GhostTime <= 0 || t.Power == "cannon" {
		return projectileLaunch{x: t.X, y: t.Y, ux: ux, uy: uy, muzzle: muzzle, valid: true}
	}
	var storage [32]Wall
	walls := storage[:0]
	for _, index := range g.wallCandidates(t.X, t.Y, 0, 0, radius+32) {
		walls = append(walls, g.World.Walls[index])
	}
	margin := wallSize/2 + radius
	return wallLaunch(t.X, t.Y, ux, uy, radius, muzzle, walls, func(x, y float64) bool {
		return x >= margin && x <= g.World.Width-margin && y >= margin && y <= g.World.Height-margin
	})
}

// Expiry is not a new life and does not grant invulnerability. If the tank is
// embedded, choose the nearest clear point in a cell's safe interior. All maps
// are grid mazes; no distant random teleport or repeated wall-push loop occurs.
// This deterministic calculation is mirrored by browser prediction and local play.
func (g *Game) finishGhost(t *Tank) {
	if g.clearTankAt(t.X, t.Y, t.R) {
		return
	}
	x, y, best := t.X, t.Y, math.Inf(1)
	margin := wallSize/2 + t.R + .01
	for row := 0; row < g.World.Rows; row++ {
		for col := 0; col < g.World.Cols; col++ {
			xx := clamp(t.X, float64(col)*cellSize+margin, float64(col+1)*cellSize-margin)
			yy := clamp(t.Y, float64(row)*cellSize+margin, float64(row+1)*cellSize-margin)
			d := (xx-t.X)*(xx-t.X) + (yy-t.Y)*(yy-t.Y)
			if d < best-1e-8 && g.clearTankAt(xx, yy, t.R) {
				x, y, best = xx, yy, d
			}
		}
	}
	if !math.IsInf(best, 1) {
		t.X, t.Y = x, y
	} else {
		g.resolveWalls(t)
	}
	if t.AI != nil {
		t.AI.Path = nil
		t.AI.Think = 0
		t.AI.Recover = 0
	}
}
func (g *Game) advanceGhost(t *Tank, dt float64) {
	was := t.GhostTime > 0
	t.GhostTime = math.Max(0, t.GhostTime-dt)
	if was && t.GhostTime == 0 {
		g.finishGhost(t)
	}
}
