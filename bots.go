package main

import "math"

type BotState struct {
	Think, Shot, Bank, Recover, Stuck float64
	Aim, MoveAngle, Drive             float64
	HasAim                            bool
	Target, Goal                      int
	Path                              []int
	LastX, LastY                      float64

	// Reused Dijkstra scratch. A bot replans frequently, while the maze size is stable
	// for the whole round; keeping these buffers on the bot avoids per-think GC.
	pathCost       []float64
	pathPrev       []int
	pathPenalty    []float64
	pathScratch    []int
	pathHeap       []int
	pathHeapPos    []int
	dodgeThreats   []botProjectileThreat
	grenadeThreats []botGrenadeThreat
}
type botTuning struct {
	speed, turn, think, reaction, error, lead float64
	dodge, bank                               bool
}

func tuneBot(s string) botTuning {
	switch s {
	case "easy":
		return botTuning{89, 2.8, .30, .72, .10, .4, false, false}
	case "hard":
		return botTuning{123, 4.3, .13, .26, .012, 1, true, true}
	default:
		return botTuning{108, 3.4, .19, .42, .037, .85, true, true}
	}
}
func (g *Game) cellAt(x, y float64) int {
	return int(clamp(math.Floor(y/cellSize), 0, float64(g.World.Rows-1)))*g.World.Cols + int(clamp(math.Floor(x/cellSize), 0, float64(g.World.Cols-1)))
}
func (g *Game) cellCenter(i int) (float64, float64) {
	return (float64(i%g.World.Cols) + .5) * cellSize, (float64(i/g.World.Cols) + .5) * cellSize
}

// Build once per maze. The same collision query as the simulation verifies that
// the complete tank, not merely its centre, fits through a doorway.
func (g *Game) buildNavigation() {
	n := g.World.Cols * g.World.Rows
	g.Neighbors = make([][]int, n)
	for i := 0; i < n; i++ {
		x, y := g.cellCenter(i)
		for _, j := range []int{i - 1, i + 1, i - g.World.Cols, i + g.World.Cols} {
			if j < 0 || j >= n || (j == i-1 && i%g.World.Cols == 0) || (j == i+1 && i%g.World.Cols == g.World.Cols-1) {
				continue
			}
			xx, yy := g.cellCenter(j)
			if !g.rayBlocked(x, y, xx-x, yy-y, tankRadius+1) {
				g.Neighbors[i] = append(g.Neighbors[i], j)
			}
		}
	}
}

// Order equal-cost cells by index, matching the exhaustive search's tie breaks.
// An indexed heap avoids duplicate queue entries and reuses its storage across
// plans, reducing cell selection from quadratic scans to logarithmic updates.
func (a *BotState) pathLess(left, right int) bool {
	return a.pathCost[left] < a.pathCost[right] || (a.pathCost[left] == a.pathCost[right] && left < right)
}

func (a *BotState) queuePath(cell int) {
	at := a.pathHeapPos[cell]
	if at < 0 {
		at = len(a.pathHeap)
		a.pathHeap = append(a.pathHeap, cell)
	}
	// New entries and decreased costs can only move toward the root.
	for at > 0 {
		parent := (at - 1) / 2
		other := a.pathHeap[parent]
		if !a.pathLess(cell, other) {
			break
		}
		a.pathHeap[at] = other
		a.pathHeapPos[other] = at
		at = parent
	}
	a.pathHeap[at] = cell
	a.pathHeapPos[cell] = at
}

func (a *BotState) nextPathCell() int {
	cell := a.pathHeap[0]
	last := a.pathHeap[len(a.pathHeap)-1]
	a.pathHeap = a.pathHeap[:len(a.pathHeap)-1]
	a.pathHeapPos[cell] = -1
	if len(a.pathHeap) == 0 {
		return cell
	}
	at := 0
	for {
		child := at*2 + 1
		if child >= len(a.pathHeap) {
			break
		}
		if right := child + 1; right < len(a.pathHeap) && a.pathLess(a.pathHeap[right], a.pathHeap[child]) {
			child = right
		}
		other := a.pathHeap[child]
		if !a.pathLess(other, last) {
			break
		}
		a.pathHeap[at] = other
		a.pathHeapPos[other] = at
		at = child
	}
	a.pathHeap[at] = last
	a.pathHeapPos[last] = at
	return cell
}

func (g *Game) botPath(t, enemy *Tank) []int {
	n := g.World.Cols * g.World.Rows
	if n == 0 {
		return nil
	}
	if len(g.Neighbors) != n {
		g.buildNavigation()
	}
	from, to := g.cellAt(t.X, t.Y), g.cellAt(enemy.X, enemy.Y)
	if from == to {
		return nil
	}
	a := t.AI
	if a == nil {
		return nil
	}
	if cap(a.pathCost) < n {
		a.pathCost = make([]float64, n)
		a.pathPrev = make([]int, n)
		a.pathPenalty = make([]float64, n)
		a.pathHeap = make([]int, 0, n)
		a.pathHeapPos = make([]int, n)
	} else {
		a.pathCost = a.pathCost[:n]
		a.pathPrev = a.pathPrev[:n]
		a.pathPenalty = a.pathPenalty[:n]
		a.pathHeap = a.pathHeap[:0]
		a.pathHeapPos = a.pathHeapPos[:n]
	}
	cost, prev, penalty := a.pathCost, a.pathPrev, a.pathPenalty
	for i := 0; i < n; i++ {
		cost[i] = math.Inf(1)
		prev[i] = -1
		penalty[i] = 0
		a.pathHeapPos[i] = -1
	}
	cost[from] = 0
	// Allies reserve nearby routes, encouraging a second approach when available.
	for _, ally := range g.Tanks {
		if ally != nil && ally.Alive && ally.ID != t.ID && t.Team > 0 && ally.Team == t.Team && ally.AI != nil {
			for _, cell := range ally.AI.Path {
				if cell >= 0 && cell < n {
					penalty[cell] += .65
				}
			}
			penalty[g.cellAt(ally.X, ally.Y)] += 1
		}
	}
	a.queuePath(from)
	for len(a.pathHeap) > 0 {
		at := a.nextPathCell()
		if at == to {
			break
		}
		for _, next := range g.Neighbors[at] {
			v := cost[at] + 1 + penalty[next]
			if v < cost[next] {
				cost[next] = v
				prev[next] = at
				a.queuePath(next)
			}
		}
	}
	if prev[to] < 0 {
		return nil
	}
	path := a.pathScratch[:0]
	for at := to; at != from; at = prev[at] {
		if at < 0 || len(path) > n {
			a.pathScratch = path[:0]
			return nil
		}
		path = append(path, at)
	}
	for i, j := 0, len(path)-1; i < j; i, j = i+1, j-1 {
		path[i], path[j] = path[j], path[i]
	}
	a.pathScratch = path
	return path
}
func (g *Game) botLead(t, e *Tank, d botTuning) (float64, float64) {
	speed := 282.0
	if t.Power == "homing" {
		speed = missileSpeed
	}
	if t.Power == "rapid" || t.Power == "scatter" {
		speed = machineSpeed
	}
	if t.Power == "cannon" {
		speed = cannonSpeed
	}
	delay := math.Max(0, dist(t.X, t.Y, e.X, e.Y)-28) / speed
	if t.Power == "laser" {
		delay = 0
	}
	vx, vy := e.VX*d.lead*delay, e.VY*d.lead*delay
	f := 1.0
	if wall, ok := g.rayWallsHit(e.X, e.Y, vx, vy, e.R+1); ok {
		f = math.Max(0, wall.T-.01)
	}
	return e.X + vx*f, e.Y + vy*f
}

// First enemy along a reflected trajectory; teammates never consume the shot.
// For a moving target use its predicted intercept point, bounded by cover.
func (g *Game) botShot(t, e *Tank, angle, ex, ey float64, banks int) bool {
	x, y, ux, uy := t.X, t.Y, math.Cos(angle), math.Sin(angle)
	left := cellSize * 7
	radius, targetRadius := 3.5, e.R+2
	if t.Power == "rapid" {
		left = g.machineTravelRange()
		radius, targetRadius = machineRadius, e.R+machineRadius
	}
	if t.Power == "cannon" {
		left = cannonSpeed * cannonLifetime
		radius = cannonRadius
		targetRadius = e.R + cannonRadius
		banks = 22
	}
	if t.Power == "laser" {
		left = g.laserRange()
		banks = 127
	}
	for k := 0; k <= banks && left > 1; k++ {
		wall, wallOK := g.projectileWallHit(t.Power, x, y, ux*left, uy*left, radius)
		stop := 1.0
		if wallOK {
			stop = wall.T
		}
		if at, ok := circleHit(x, y, ux*left, uy*left, ex, ey, targetRadius); ok && at < stop {
			return true
		}
		length := left * stop
		x += ux * length
		y += uy * length
		left -= length
		if !wallOK {
			break
		}
		if wall.NX != 0 {
			ux = -ux
		}
		if wall.NY != 0 {
			uy = -uy
		}
		x += wall.NX * .12
		y += wall.NY * .12
	}
	return false
}
func (g *Game) botAim(t, e *Tank, d botTuning) (float64, bool) {
	ex, ey := g.botLead(t, e, d)
	a := math.Atan2(ey-t.Y, ex-t.X)
	if t.Power == "grenade" {
		return a, dist(t.X, t.Y, e.X, e.Y) < cellSize*3 && !g.rayBlocked(t.X, t.Y, e.X-t.X, e.Y-t.Y, 6)
	}
	if t.Power == "homing" {
		return a, dist(t.X, t.Y, e.X, e.Y) < missileRange && !g.rayBlocked(t.X, t.Y, e.X-t.X, e.Y-t.Y, 5)
	}
	banks := 0
	if d.bank {
		banks = 1
	}
	if g.botShot(t, e, a, ex, ey, banks) {
		return a, true
	}
	if !d.bank || t.AI.Bank > 0 {
		return a, false
	}
	t.AI.Bank = .55
	best, found, cost := a, false, math.Inf(1)
	for _, w := range g.World.Walls {
		if t.Power == "cannon" && w.Line != 0 && w.Line != g.World.Width && w.Line != g.World.Height {
			continue
		}
		if dist(t.X, t.Y, clamp(t.X, w.X, w.X+w.W), clamp(t.Y, w.Y, w.Y+w.H)) > cellSize*3 {
			continue
		}
		mx, my := ex, ey
		if w.Axis == "v" {
			face := w.X - 3.5
			if t.X > w.X {
				face = w.X + w.W + 3.5
			}
			mx = 2*face - ex
		} else {
			face := w.Y - 3.5
			if t.Y > w.Y {
				face = w.Y + w.H + 3.5
			}
			my = 2*face - ey
		}
		aim := math.Atan2(my-t.Y, mx-t.X)
		if g.botShot(t, e, aim, ex, ey, banks) {
			c := dist(t.X, t.Y, mx, my) + math.Abs(delta(t.Angle, aim))*35
			if c < cost {
				cost = c
				best = aim
				found = true
			}
		}
	}
	return best, found
}

type botProjectileThreat struct{ x, y, vx, vy, start, end, r float64 }

func (g *Game) botDodge(t *Tank, d botTuning, angle, drive float64) (float64, float64) {
	horizon := .6
	if t.Difficulty == "hard" {
		horizon = .85
	}
	threats := t.AI.dodgeThreats[:0]
	for _, b := range g.Bullets {
		if b.Dead || !g.canDamage(b.Owner, t) || ((b.Kind == "scatter" || b.Kind == "rapid") && b.Owner == t.ID) || dist(t.X, t.Y, b.X, b.Y) > math.Max(350, math.Hypot(b.VX, b.VY)*horizon+80) {
			continue
		}
		if b.Kind == "grenade" {
			continue // Grenade bodies are handled separately; bots do not flee the whole blast radius.
		}
		x, y, vx, vy, left, elapsed := b.X, b.Y, b.VX, b.VY, math.Min(horizon, b.Life), 0.0
		for k := 0; k < 3 && left > .001; k++ {
			w, wallOK := g.projectileWallHit(b.Kind, x, y, vx*left, vy*left, b.R)
			span := left
			if wallOK {
				span *= w.T
			}
			threats = append(threats, botProjectileThreat{x, y, vx, vy, elapsed, elapsed + span, b.R})
			if !wallOK {
				break
			}
			x += vx*span + w.NX*.12
			y += vy*span + w.NY*.12
			if w.NX != 0 {
				vx = -vx
			}
			if w.NY != 0 {
				vy = -vy
			}
			left -= span
			elapsed += span
		}
	}
	t.AI.dodgeThreats = threats
	if len(threats) == 0 {
		return angle, drive
	}
	risk := func(a, v float64) float64 {
		x, y, h := t.X, t.Y, t.Angle
		risk := 0.0
		step := horizon / 8
		for k := 0; k < 8; k++ {
			start, end := float64(k)*step, float64(k+1)*step
			diff := delta(h, a)
			h += clamp(diff, -d.turn*step, d.turn*step)
			dx, dy := math.Cos(h)*d.speed*v*math.Max(0, math.Cos(diff))*step, math.Sin(h)*d.speed*v*math.Max(0, math.Cos(diff))*step
			f := 1.0
			if w, ok := g.movementWallHit(t.GhostTime > end, x, y, dx, dy, t.R+.5); ok {
				f = math.Max(0, w.T-.01)
			}
			dx *= f
			dy *= f
			for _, s := range threats {
				lo, hi := math.Max(start, s.start), math.Min(end, s.end)
				if hi <= lo {
					continue
				}
				rx, ry := x+dx*(lo-start)/step-s.x-s.vx*(lo-s.start), y+dy*(lo-start)/step-s.y-s.vy*(lo-s.start)
				rdx, rdy := dx*(hi-lo)/step-s.vx*(hi-lo), dy*(hi-lo)/step-s.vy*(hi-lo)
				den := rdx*rdx + rdy*rdy
				q := 0.0
				if den > 1e-9 {
					q = clamp(-(rx*rdx+ry*rdy)/den, 0, 1)
				}
				clearance := math.Hypot(rx+rdx*q, ry+rdy*q) - t.R - s.r
				if clearance < 0 {
					risk += 1400 + (horizon-lo)*600
				} else if clearance < 10 {
					risk += (10 - clearance) * 9
				}
			}
			x += dx
			y += dy
		}
		return risk
	}
	baseline := risk(angle, drive)
	if baseline < 30 {
		return angle, drive
	}
	cross := math.Atan2(threats[0].vy, threats[0].vx) + math.Pi/2
	bestA, bestV, best := angle, drive, baseline
	for _, c := range [][2]float64{{t.Angle, -.8}, {t.Angle, 1}, {angle, 0}, {cross, 1}, {cross + math.Pi, 1}, {angle + .8, 1}, {angle - .8, 1}} {
		cost := risk(c[0], c[1]) + math.Abs(delta(angle, c[0]))*4
		if cost < best {
			best = cost
			bestA = c[0]
			bestV = c[1]
		}
	}
	return bestA, bestV
}

const botGrenadeAvoidPadding = 10.0

type botGrenadeThreat struct {
	x, y, vx, vy, start, end, r float64
}

// Grenades are treated like moving physical obstacles. Bots deliberately keep
// a small clearance from the grenade body so they do not trigger impact
// detonation, but they do not flee the grenade's full blast radius.
func (g *Game) botGrenadeThreats(t *Tank, d botTuning, horizon float64) []botGrenadeThreat {
	var threats []botGrenadeThreat
	if t.AI != nil {
		threats = t.AI.grenadeThreats[:0] // zero allocation after the first relevant grenade
	}
	for _, b := range g.Bullets {
		if b == nil || b.Dead || b.Kind != "grenade" || b.Life <= 0 {
			continue
		}
		// Avoid enemy grenades and our own grenade body. Friendly grenades are
		// harmless obstacles when friendly fire is off, so do not steer away from
		// them merely because an ally threw them.
		if b.Owner != t.ID && !g.canDamage(b.Owner, t) {
			continue
		}
		reach := d.speed*horizon + math.Hypot(b.VX, b.VY)*horizon + t.R + b.R + botGrenadeAvoidPadding + 24
		if dist(t.X, t.Y, b.X, b.Y) > reach {
			continue
		}
		x, y, vx, vy, life, elapsed := b.X, b.Y, b.VX, b.VY, b.Life, 0.0
		for elapsed < horizon-1e-9 && life > 1e-9 {
			dt := math.Min(1.0/30.0, horizon-elapsed)
			dt = math.Min(dt, life)
			before := life
			life = math.Max(0, life-dt)
			drag := grenadeDragFactor(before, life)
			vx *= drag
			vy *= drag
			rest, segmentStart := dt, elapsed
			for step := 0; step < 4 && rest > 1e-6; step++ {
				dx, dy := vx*rest, vy*rest
				wall, wallOK := g.rayWallsHit(x, y, dx, dy, b.R)
				fraction := 1.0
				if wallOK {
					fraction = wall.T
				}
				span := rest * fraction
				threats = append(threats, botGrenadeThreat{x: x, y: y, vx: vx, vy: vy, start: segmentStart, end: segmentStart + span, r: b.R + botGrenadeAvoidPadding})
				x += dx * fraction
				y += dy * fraction
				segmentStart += span
				rest -= span
				if !wallOK {
					break
				}
				x += wall.NX * .08
				y += wall.NY * .08
				if wall.NX != 0 {
					vx = -vx
				}
				if wall.NY != 0 {
					vy = -vy
				}
			}
			elapsed += dt
		}
	}
	if t.AI != nil {
		t.AI.grenadeThreats = threats
	}
	return threats
}

func (g *Game) botAvoidGrenades(t *Tank, d botTuning, angle, drive float64) (float64, float64) {
	horizon := .7
	if t.Difficulty == "hard" {
		horizon = .85
	}
	threats := g.botGrenadeThreats(t, d, horizon)
	if len(threats) == 0 {
		return angle, drive
	}
	risk := func(a, v float64) (float64, float64) {
		x, y, heading := t.X, t.Y, t.Angle
		total, moved := 0.0, 0.0
		step := horizon / 10
		for k := 0; k < 10; k++ {
			start, end := float64(k)*step, float64(k+1)*step
			diff := delta(heading, a)
			heading += clamp(diff, -d.turn*step, d.turn*step)
			speed := d.speed * v * math.Max(0, math.Cos(diff))
			dx, dy := math.Cos(heading)*speed*step, math.Sin(heading)*speed*step
			f := 1.0
			if w, ok := g.movementWallHit(t.GhostTime > end, x, y, dx, dy, t.R+.5); ok {
				f = math.Max(0, w.T-.01)
			}
			nx, ny := x+dx*f, y+dy*f
			for _, s := range threats {
				lo, hi := math.Max(start, s.start), math.Min(end, s.end)
				if hi <= lo {
					continue
				}
				f0, f1 := (lo-start)/step, (hi-start)/step
				rx := x + (nx-x)*f0 - s.x - s.vx*(lo-s.start)
				ry := y + (ny-y)*f0 - s.y - s.vy*(lo-s.start)
				rdx := (nx-x)*(f1-f0) - s.vx*(hi-lo)
				rdy := (ny-y)*(f1-f0) - s.vy*(hi-lo)
				den := rdx*rdx + rdy*rdy
				q := 0.0
				if den > 1e-9 {
					q = clamp(-(rx*rdx+ry*rdy)/den, 0, 1)
				}
				clearance := math.Hypot(rx+rdx*q, ry+rdy*q) - t.R - s.r
				if clearance < 0 {
					total += 1800 + (horizon-lo)*500
				} else if clearance < 6 {
					total += (6 - clearance) * 12
				}
			}
			moved += math.Hypot(nx-x, ny-y)
			x, y = nx, ny
		}
		return total, moved
	}
	baseline, _ := risk(angle, drive)
	if baseline < 20 {
		return angle, drive
	}
	nearest := threats[0]
	bestDist := dist(t.X, t.Y, nearest.x, nearest.y)
	for _, s := range threats[1:] {
		if d0 := dist(t.X, t.Y, s.x, s.y); d0 < bestDist {
			nearest, bestDist = s, d0
		}
	}
	away := math.Atan2(t.Y-nearest.y, t.X-nearest.x)
	cross := away + math.Pi/2
	if math.Hypot(nearest.vx, nearest.vy) > 5 {
		cross = math.Atan2(nearest.vy, nearest.vx) + math.Pi/2
	}
	candidates := [][2]float64{
		{angle, drive}, {angle, 0}, {t.Angle, -.7}, {away, 1},
		{cross, 1}, {cross + math.Pi, 1}, {angle + .8, 1}, {angle - .8, 1},
	}
	bestA, bestV, best := angle, drive, baseline
	for _, c := range candidates[1:] {
		r, moved := risk(c[0], c[1])
		cost := r + math.Abs(delta(angle, c[0]))*3
		if c[1] == 0 {
			cost += 4
		}
		cost -= math.Min(moved, 55) * .03
		if cost < best {
			best, bestA, bestV = cost, c[0], c[1]
		}
	}
	if best < baseline-5 {
		return bestA, bestV
	}
	return angle, drive
}

func (g *Game) botControl(t *Tank, dt float64) {
	d := tuneBot(t.Difficulty)
	t.SpeedTime = math.Max(0, t.SpeedTime-dt)
	if t.SpeedTime <= 0 {
		t.SpeedStacks = 0
	}
	g.advanceGhost(t, dt)
	if n := speedCount(t); n > 0 {
		d.speed *= 1 + boostSpeedPerStack*float64(n)
		d.turn *= 1 + boostTurnPerStack*float64(n)
	}
	if t.AI == nil {
		t.AI = &BotState{Think: g.random(.1, .35), Shot: g.random(.3, .9), Goal: -1, Target: -1, LastX: t.X, LastY: t.Y}
	}
	a := t.AI
	a.Think -= dt
	a.Shot -= dt
	a.Bank -= dt
	a.Recover -= dt
	var enemy *Tank
	best := math.Inf(1)
	for _, e := range g.Tanks {
		if e == nil || !e.Alive || e.ID == t.ID || !g.isOpponent(t.ID, e) {
			continue
		}
		cost := dist(t.X, t.Y, e.X, e.Y)
		if e.ID == a.Target {
			cost *= .85
		}
		if cost < best {
			best = cost
			enemy = e
		}
	}
	gx, gy, objective := g.objectiveGoal(t)
	if enemy == nil && !objective {
		a.Target = -1
		return
	}
	if enemy == nil {
		enemy = &Tank{ID: -1, X: gx, Y: gy, R: tankRadius, Invulnerable: 1}
	}
	destination := enemy
	if objective {
		destination = &Tank{X: gx, Y: gy, R: tankRadius}
	}
	a.Target = enemy.ID
	// Remotely detonate against an exposed opponent, not an ally or a guessed hit.
	if a.Shot <= 0 {
		for _, b := range g.Bullets {
			if !b.Dead && b.Owner == t.ID && b.Kind == "grenade" && b.Age > .22 && dist(b.X, b.Y, enemy.X, enemy.Y) < blastRadius+enemy.R && !g.rayBlocked(b.X, b.Y, enemy.X-b.X, enemy.Y-b.Y, 0) {
				g.detonateOwned(t)
				if !t.Alive {
					return
				}
				a.Shot = d.reaction
				break
			}
		}
	}
	if a.Think <= 0 {
		a.Think = d.think * g.random(.9, 1.1)
		a.HasAim = false
		if enemy.Alive {
			a.Aim, a.HasAim = g.botAim(t, enemy, d)
		}
		if a.HasAim {
			a.Aim += g.random(-d.error, d.error)
		}
		goal := g.cellAt(destination.X, destination.Y)
		if t.GhostTime <= 0 && (goal != a.Goal || len(a.Path) == 0 || g.rng.Float64() < .35) {
			a.Goal = goal
			a.Path = g.botPath(t, destination)
		}
		angle, drive := t.Angle, 0.0
		if a.HasAim && (!objective || dist(t.X, t.Y, gx, gy) < 26 || (g.Tick/30+t.ID)%5 == 0 && dist(t.X, t.Y, enemy.X, enemy.Y) < cellSize*2) {
			angle = a.Aim
			r := dist(t.X, t.Y, enemy.X, enemy.Y)
			if r < cellSize*.95 {
				drive = -.6
			} else if r > cellSize*2.7 {
				drive = .4
			}
		} else if t.GhostTime > 0 {
			angle = math.Atan2(destination.Y-t.Y, destination.X-t.X)
			if dist(t.X, t.Y, destination.X, destination.Y) > 12 {
				drive = 1
			}
		} else {
			for len(a.Path) > 0 {
				x, y := g.cellCenter(a.Path[0])
				if dist(t.X, t.Y, x, y) >= 10 {
					break
				}
				a.Path = a.Path[1:]
			}
			x, y := destination.X, destination.Y
			if len(a.Path) > 0 {
				x, y = g.cellCenter(a.Path[0])
				for i := 1; i < len(a.Path) && i < 4; i++ {
					nx, ny := g.cellCenter(a.Path[i])
					if g.rayBlocked(t.X, t.Y, nx-t.X, ny-t.Y, t.R+2) {
						break
					}
					x, y = nx, ny
				}
			}
			if g.rayBlocked(t.X, t.Y, x-t.X, y-t.Y, t.R+1) {
				cx, cy := g.cellCenter(g.cellAt(t.X, t.Y))
				if dist(t.X, t.Y, cx, cy) > 5 {
					x, y = cx, cy
				}
			}
			angle = math.Atan2(y-t.Y, x-t.X)
			drive = 1
			if objective && dist(t.X, t.Y, gx, gy) < 10 {
				drive = 0
			}
		}
		if d.dodge {
			angle, drive = g.botDodge(t, d, angle, drive)
		}
		a.MoveAngle = angle
		a.Drive = drive
	}
	angle, drive := a.MoveAngle, a.Drive
	if a.Recover > 0 {
		angle = t.Angle
		drive = -.8
	}
	angle, drive = g.botAvoidGrenades(t, d, angle, drive)
	diff := delta(t.Angle, angle)
	t.Angle += clamp(diff, -d.turn*dt, d.turn*dt)
	throttle := drive * math.Max(0, math.Cos(diff))
	g.moveTank(t, math.Cos(t.Angle)*d.speed*throttle*dt, math.Sin(t.Angle)*d.speed*throttle*dt)
	if a.HasAim && a.Shot <= 0 && a.Recover <= 0 && math.Abs(delta(t.Angle, a.Aim)) < .13 && enemy.Invulnerable < .05 {
		a.Shot = .09
		ex, ey := g.botLead(t, enemy, d)
		bank := 0
		if d.bank {
			bank = 1
		}
		safe := g.botShot(t, enemy, t.Angle, ex, ey, bank)
		if t.Power == "homing" || t.Power == "grenade" {
			safe = !g.rayBlocked(t.X, t.Y, enemy.X-t.X, enemy.Y-t.Y, 5)
		}
		hasGrenade := false
		for _, b := range g.Bullets {
			if !b.Dead && b.Kind == "grenade" && b.Owner == t.ID {
				hasGrenade = true
			}
		}
		if safe && !hasGrenade && g.fire(t) {
			a.Shot = d.reaction * g.random(.9, 1.15)
			if t.Power == "rapid" {
				a.Shot = 0
			}
		}
	}
	if math.Abs(throttle) > .25 && dist(t.X, t.Y, a.LastX, a.LastY) < .12 {
		a.Stuck += dt
	} else {
		a.Stuck = math.Max(0, a.Stuck-dt*1.5)
	}
	if a.Stuck > .55 {
		a.Recover = .38
		a.Stuck = 0
		a.Path = nil
		a.HasAim = false
		a.Think = 0
	}
	a.LastX, a.LastY = t.X, t.Y
}
