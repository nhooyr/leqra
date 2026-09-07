package main

import "math"

// rayBounds intersects only the four inner faces of the arena rim. Cannon
// ignores ALL interior walls; using a boundary rectangle avoids tile-seam hits.
func (g *Game) rayBounds(x, y, dx, dy, r float64) *RayHit {
	minX, minY := wallSize/2+r, wallSize/2+r
	maxX, maxY := g.World.Width-minX, g.World.Height-minY
	var best *RayHit
	consider := func(at, nx, ny float64) {
		if at < -1e-7 || at > 1+1e-7 {
			return
		}
		at = clamp(at, 0, 1)
		if best == nil || at < best.T-1e-7 {
			best = &RayHit{at, nx, ny}
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
	return best
}
func (g *Game) projectileWall(kind string, x, y, dx, dy, r float64) *RayHit {
	if kind == "cannon" {
		return g.rayBounds(x, y, dx, dy, r)
	}
	return g.rayWalls(x, y, dx, dy, r)
}
func (g *Game) movementWall(ghost bool, x, y, dx, dy, r float64) *RayHit {
	if ghost {
		return g.rayBounds(x, y, dx, dy, r)
	}
	return g.rayWalls(x, y, dx, dy, r)
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
