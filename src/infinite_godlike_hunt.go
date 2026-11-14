package main

import "math"

// Public bosses pursue a living human. Bots can intercept the shot or be
// cleared from the route, but never replace that human as the hunt target.
func (a *infiniteArena) godlikeHuntInput(p *infinitePilot) Input {
	target := a.nearestActivePilot(p, math.Inf(1))
	if target == nil {
		p.botTarget = 0
		return a.botRoam(p, nil, infiniteBotTunings[p.botLevel].roam)
	}
	p.botTarget = target.ID
	dx, dy := target.X-p.X, target.Y-p.Y
	angle := math.Atan2(dy, dx)
	visible := !a.rayBlocked(p.X, p.Y, dx, dy, infiniteBulletRadius)
	goalX, goalY := target.X, target.Y
	if visible || p.kit.GhostTime > 0 {
		p.hasWaypoint = false
	} else {
		cx, cy := infiniteCell(p.X, p.Y)
		centerX, centerY := infiniteCenter(cx, cy)
		if p.hasWaypoint {
			x, y := infiniteCenter(p.waypoint[0], p.waypoint[1])
			if math.Hypot(x-p.X, y-p.Y) <= 4 {
				p.hasWaypoint = false
			}
		}
		if !p.hasWaypoint && math.Hypot(centerX-p.X, centerY-p.Y) > 4 {
			goalX, goalY = centerX, centerY
		} else {
			if !p.hasWaypoint {
				p.waypoint, p.hasWaypoint = a.huntWaypoint(cx, cy, target)
			}
			if !p.hasWaypoint {
				return a.botRoam(p, target, infiniteBotTunings[p.botLevel].roam)
			}
			goalX, goalY = infiniteCenter(p.waypoint[0], p.waypoint[1])
		}
	}
	route := math.Atan2(goalY-p.Y, goalX-p.X)
	fire := visible && !target.Protected && math.Abs(delta(p.Angle, angle)) < .054
	if !fire {
		for _, other := range a.pilots {
			if !other.Bot || other == p || other.HP == 0 || other.Protected {
				continue
			}
			x, y := other.X-p.X, other.Y-p.Y
			bearing := math.Atan2(y, x)
			if math.Hypot(x, y) < 4*cellSize && math.Abs(delta(route, bearing)) < .2 &&
				math.Abs(delta(p.Angle, bearing)) < .054 && !a.rayBlocked(p.X, p.Y, x, y, infiniteBulletRadius) {
				fire = true
				break
			}
		}
	}
	if p.kit.fireBlocked {
		fire = false
	}
	if visible && math.Hypot(dx, dy) <= 1.5*cellSize {
		return Input{StickX: math.Cos(angle), StickY: math.Sin(angle), AimOnly: true, Fire: fire}
	}
	return Input{StickX: .936 * math.Cos(route), StickY: .936 * math.Sin(route), Fire: fire}
}

// Search actual corridor connectivity rather than drifting toward a human on
// the far side of a wall. Work is bounded and cached until the next waypoint.
func (a *infiniteArena) huntWaypoint(cx, cy int, target *infinitePilot) ([2]int, bool) {
	start := [2]int{cx, cy}
	tx, ty := infiniteCell(target.X, target.Y)
	goal := [2]int{tx, ty}
	type node struct{ cell, first [2]int }
	queue := make([]node, 1, 128)
	queue[0] = node{cell: start}
	visited := map[[2]int]bool{start: true}
	directions := [4][2]int{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}
	best, bestDistance := start, math.Inf(1)
	for head := 0; head < len(queue) && head < 2048; head++ {
		current := queue[head]
		x, y := infiniteCenter(current.cell[0], current.cell[1])
		if current.cell != start {
			distance := math.Hypot(target.X-x, target.Y-y)
			if distance < bestDistance {
				best, bestDistance = current.first, distance
			}
			if current.cell == goal {
				return current.first, true
			}
		}
		for _, direction := range directions {
			next := [2]int{current.cell[0] + direction[0], current.cell[1] + direction[1]}
			if visited[next] || next[0] < cx-24 || next[0] > cx+24 || next[1] < cy-24 || next[1] > cy+24 {
				continue
			}
			nx, ny := infiniteCenter(next[0], next[1])
			if a.maze.blocked((x+nx)/2, (y+ny)/2, tankRadius) {
				continue
			}
			visited[next] = true
			first := current.first
			if current.cell == start {
				first = next
			}
			queue = append(queue, node{next, first})
		}
	}
	return best, best != start
}
