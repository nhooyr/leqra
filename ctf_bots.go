package main

import "math"

// Give returning carriers the base and its approach. Search only the two-cell
// neighbourhood (at most 13 cells), then keep the cover position for 0.4s.
// Corner candidates let defenders yield behind a base in a dead-end cell.
func (g *Game) ctfCoverGoal(t *Tank, home *Flag, carrier *Tank) (float64, float64) {
	if t.AI == nil {
		t.AI = &BotState{Goal: -1, Target: -1}
	}
	a := t.AI
	a.ctfYield = true
	carrierCell := g.cellAt(carrier.X, carrier.Y)
	if a.ctfCoverClock > 0 && a.ctfCarrier == carrier.ID && a.ctfCarrierCell == carrierCell {
		return a.ctfCoverX, a.ctfCoverY
	}
	if len(g.Neighbors) != g.World.Cols*g.World.Rows {
		g.buildNavigation()
	}
	homeCell := g.cellAt(home.HomeX, home.HomeY)
	var cells [13]int
	var depth [13]int
	cells[0] = homeCell
	n := 1
	for i := 0; i < n; i++ {
		if depth[i] == 2 {
			continue
		}
		for _, next := range g.Neighbors[cells[i]] {
			seen := false
			for j := 0; j < n; j++ {
				if cells[j] == next {
					seen = true
					break
				}
			}
			if !seen && n < len(cells) {
				cells[n], depth[n] = next, depth[i]+1
				n++
			}
		}
	}
	vx, vy := carrier.X-home.HomeX, carrier.Y-home.HomeY
	length2 := vx*vx + vy*vy
	best, bx, by := math.Inf(1), t.X, t.Y
	consider := func(x, y float64) {
		if x < wallSize/2+t.R || y < wallSize/2+t.R || x > g.World.Width-wallSize/2-t.R || y > g.World.Height-wallSize/2-t.R {
			return
		}
		xx, yy := g.cellCenter(g.cellAt(x, y))
		if g.rayBlocked(xx, yy, x-xx, y-yy, t.R+1) {
			return
		}
		f := 0.0
		if length2 > 1 {
			f = clamp(((x-home.HomeX)*vx+(y-home.HomeY)*vy)/length2, 0, 1)
		}
		clearance := dist(x, y, home.HomeX+f*vx, home.HomeY+f*vy)
		cost := dist(x, y, t.X, t.Y)*.25 + dist(x, y, home.HomeX, home.HomeY)*.35 + math.Max(0, t.R+carrier.R+10-clearance)*12
		// A corner behind the base still leaves its front scoring edge clear;
		// one in front would obstruct the very last part of the return.
		if dist(x, y, home.HomeX, home.HomeY) < cellSize*.6 && (x-home.HomeX)*vx+(y-home.HomeY)*vy > 0 {
			cost += 300
		}
		for _, ally := range g.Tanks {
			if ally == nil || !ally.Alive || ally.ID == t.ID || ally.ID == carrier.ID || ally.Team != t.Team {
				continue
			}
			ax, ay := ally.X, ally.Y
			if ally.Bot && ally.AI != nil && ally.AI.ctfCoverClock > 0 && ally.AI.ctfCarrier == carrier.ID {
				ax, ay = ally.AI.ctfCoverX, ally.AI.ctfCoverY
			}
			cost += math.Max(0, t.R+ally.R+6-dist(x, y, ax, ay)) * 6
		}
		if cost < best {
			best, bx, by = cost, x, y
		}
	}
	for i := 1; i < n; i++ {
		x, y := g.cellCenter(cells[i])
		consider(x, y)
	}
	offset := cellSize/2 - wallSize/2 - t.R - 2
	for _, dx := range []float64{-offset, offset} {
		for _, dy := range []float64{-offset, offset} {
			consider(home.HomeX+dx, home.HomeY+dy)
		}
	}
	a.ctfCoverClock, a.ctfCarrier, a.ctfCarrierCell = .4, carrier.ID, carrierCell
	a.ctfCoverX, a.ctfCoverY = bx, by
	return bx, by
}
