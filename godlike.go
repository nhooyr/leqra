package main

import "math"

// Godlike changes decisions, not the tank's movement, ammunition or damage rules.
// Shared forecasts and fixed candidate/step budgets keep the planner bounded even
// in an eight-player, machine-gun-heavy ultrawide match.
const godlikeHorizon = 1.05
const godlikeSteps = 14
const godlikeThreatLimit = 48

type godlikeThreat struct {
	botProjectileThreat
	kind      string
	owner     int
	fuse, age float64
}

// An unproductive bank shot or oscillating turn must not pin an attacker in a
// doorway indefinitely. Advance for a moment, then reevaluate from a new angle.
// Deliberately holding a scoring hill is productive and must remain stationary.
func (g *Game) godlikeProgress(t, goal *Tank, dt float64) {
	a := t.AI
	if a.ProgressClock <= 0 {
		a.ProgressClock = 1.4
		a.ProgressX, a.ProgressY = t.X, t.Y
	}
	a.ProgressClock -= dt
	if a.ProgressClock > 0 {
		return
	}
	hold := g.Objectives != nil && !g.Objectives.SuddenDeath && g.Objectives.Mode == "koth" && dist(t.X, t.Y, g.Objectives.HillX, g.Objectives.HillY) <= g.Objectives.Radius
	if !hold && dist(t.X, t.Y, goal.X, goal.Y) > cellSize*.8 && dist(t.X, t.Y, a.ProgressX, a.ProgressY) < cellSize*.3 {
		a.Advance = 1.1
		a.RouteClock = 0
		a.HasBank = false
	}
}

func (g *Game) godlikeTargetCost(t, e *Tank, cost float64) float64 {
	if e.Invulnerable > .25 {
		cost += cellSize * 3
	}
	if !g.rayBlocked(t.X, t.Y, e.X-t.X, e.Y-t.Y, 3) {
		cost *= .7
	}
	if g.Objectives != nil && !g.Objectives.SuddenDeath {
		for _, f := range g.Objectives.Flags {
			if f.Team == t.Team && f.Carrier == e.ID {
				cost *= .3
			}
		}
		if g.Objectives.Mode == "koth" && dist(e.X, e.Y, g.Objectives.HillX, g.Objectives.HillY) < g.Objectives.Radius+e.R {
			cost *= .5
		}
	}
	return cost
}

// One reusable breadth-first search supplies actual maze distances to all
// pickups. A shiny item on the other side of a long wall is not a cheap detour.
func (g *Game) godlikeDistances(t *Tank, x, y float64) []int {
	n := g.World.Cols * g.World.Rows
	if n == 0 {
		return nil
	}
	if len(g.Neighbors) != n {
		g.buildNavigation()
	}
	a := t.AI
	if cap(a.goalDistances) < n {
		a.goalDistances = make([]int, n)
		a.goalQueue = make([]int, 0, n)
	}
	d := a.goalDistances[:n]
	for i := range d {
		d[i] = -1
	}
	start := g.cellAt(x, y)
	d[start] = 0
	q := a.goalQueue[:0]
	q = append(q, start)
	for i := 0; i < len(q); i++ {
		for _, next := range g.Neighbors[q[i]] {
			if d[next] < 0 {
				d[next] = d[q[i]] + 1
				q = append(q, next)
			}
		}
	}
	a.goalQueue = q
	return d
}

func (g *Game) godlikeObjective(t *Tank) (float64, float64, bool) {
	o := g.Objectives
	if o == nil || o.SuddenDeath {
		return 0, 0, false
	}
	if o.Mode == "koth" {
		return o.HillX, o.HillY, true
	}
	var own, enemy *Flag
	for _, f := range o.Flags {
		if f.Team == t.Team {
			own = f
		} else {
			enemy = f
		}
	}
	if own == nil || enemy == nil {
		return 0, 0, false
	}
	if enemy.Carrier == t.ID {
		if !own.Home && own.Carrier < 0 {
			return own.X, own.Y, true
		}
		// A lone carrier has to recover its own flag; otherwise both sides
		// can camp at home forever. With support, protect the carried flag.
		if !own.Home {
			support := false
			for _, ally := range g.Tanks {
				if ally != nil && ally.Alive && ally.ID != t.ID && ally.Team == t.Team {
					support = true
					break
				}
			}
			if !support {
				return own.X, own.Y, true
			}
		}
		return own.HomeX, own.HomeY, true
	}
	if !own.Home {
		// The closest available teammate returns/intercepts; the others retain
		// pressure on the enemy flag instead of all abandoning the attack.
		d := g.godlikeDistances(t, own.X, own.Y)
		nearest, best := t.ID, math.Inf(1)
		for _, ally := range g.Tanks {
			if ally == nil || !ally.Alive || ally.Team != t.Team || ally.ID == enemy.Carrier {
				continue
			}
			cell := g.cellAt(ally.X, ally.Y)
			if cell >= len(d) || d[cell] < 0 {
				continue
			}
			cost := float64(d[cell])*cellSize + dist(ally.X, ally.Y, own.X, own.Y)*.01
			if cost < best || cost == best && ally.ID < nearest {
				nearest, best = ally.ID, cost
			}
		}
		if nearest == t.ID || enemy.Carrier >= 0 {
			return own.X, own.Y, true
		}
	}
	if enemy.Carrier >= 0 && enemy.Carrier < maxTanks {
		carrier := g.Tanks[enemy.Carrier]
		if carrier != nil && carrier.Team == t.Team {
			// Meet threats to the returning carrier, or cover its route home.
			var threat *Tank
			best := cellSize * 4
			for _, e := range g.Tanks {
				if e != nil && e.Alive && g.isOpponent(t.ID, e) {
					if v := dist(e.X, e.Y, carrier.X, carrier.Y); v < best {
						best, threat = v, e
					}
				}
			}
			if threat != nil {
				return threat.X, threat.Y, true
			}
			return own.HomeX, own.HomeY, true
		}
	}
	return enemy.X, enemy.Y, true
}

func godlikePickupValue(t *Tank, kind string) float64 {
	switch kind {
	case "shield":
		if shieldCount(t) >= maxShieldCharges && t.Shield > 4 {
			return 0
		}
		return 5
	case "speed":
		if speedCount(t) >= maxSpeedStacks && t.SpeedTime > 4 {
			return 0
		}
		return 3.7
	case "ghost":
		if t.GhostTime > 4 {
			return 0
		}
		return 3.8
	case "scope":
		if t.ScopeTime > 3 {
			return 0
		}
		return .65
	}
	value := map[string]float64{"rapid": 3.7, "scatter": 3, "homing": 4.2, "grenade": 3, "laser": 5, "cannon": 5.2}[kind]
	if t.Power != "" && t.PowerTime > 3 && t.Charges > 0 && (t.Power != "rapid" || t.MachineRounds >= 120) {
		current := map[string]float64{"rapid": 3.7, "scatter": 3, "homing": 4.2, "grenade": 3, "laser": 5, "cannon": 5.2}[t.Power]
		if current >= value {
			return 0
		}
		value -= current * .6
	}
	return value
}

func (g *Game) godlikePickup(t *Tank, d botTuning, goal *Tank, objective bool) *Pickup {
	if len(g.Pickups) == 0 {
		return nil
	}
	// Do not leave a scoring hill or interrupt a capture for a weapon swap.
	if objective && g.Objectives != nil {
		if g.Objectives.Mode == "koth" && dist(t.X, t.Y, g.Objectives.HillX, g.Objectives.HillY) <= g.Objectives.Radius {
			return nil
		}
		for _, f := range g.Objectives.Flags {
			if f.Carrier == t.ID {
				return nil
			}
		}
	}
	distances := g.godlikeDistances(t, t.X, t.Y)
	if len(distances) == 0 {
		return nil
	}
	var best *Pickup
	bestScore := 0.0
	goalDistance := dist(t.X, t.Y, goal.X, goal.Y)
	for _, p := range g.Pickups {
		if p == nil || p.Life <= 0 {
			continue
		}
		value := godlikePickupValue(t, p.Type)
		if value <= 0 {
			continue
		}
		n := distances[g.cellAt(p.X, p.Y)]
		if n < 0 {
			continue
		}
		route := math.Max(dist(t.X, t.Y, p.X, p.Y), float64(n)*cellSize)
		if route/d.speed+.3 > p.Life || route > cellSize*7 {
			continue
		}
		if objective && route+dist(p.X, p.Y, goal.X, goal.Y)-goalDistance > cellSize*.8 {
			continue
		}
		safe := true
		for _, b := range g.Bullets {
			if b == nil || b.Dead || !g.canDamage(b.Owner, t) {
				continue
			}
			if b.Kind == "grenade" && dist(p.X, p.Y, b.X, b.Y) < blastRadius+t.R+20 && !g.rayBlocked(b.X, b.Y, p.X-b.X, p.Y-b.Y, 0) {
				safe = false
				break
			}
			if b.Kind != "grenade" && dist(p.X, p.Y, b.X, b.Y) < 75 && !g.rayBlocked(b.X, b.Y, p.X-b.X, p.Y-b.Y, 0) {
				safe = false
				break
			}
		}
		if !safe {
			continue
		}
		score := value / (1 + route/cellSize)
		// Avoid racing an enemy who can collect the item much sooner.
		for _, e := range g.Tanks {
			if e != nil && e.Alive && g.isOpponent(t.ID, e) && dist(e.X, e.Y, p.X, p.Y) < route*.65 {
				score *= .45
				break
			}
		}
		if score > bestScore && score > .45 {
			bestScore, best = score, p
		}
	}
	return best
}

func (g *Game) godlikeRoutePenalty(t *Tank, penalty []float64) {
	for _, b := range g.Bullets {
		if b == nil || b.Dead || b.Kind != "grenade" || !g.canDamage(b.Owner, t) {
			continue
		}
		if b.Owner == t.ID && b.Life > 2 {
			continue
		}
		for cell := range penalty {
			x, y := g.cellCenter(cell)
			r := dist(x, y, b.X, b.Y)
			if r < blastRadius+t.R+12 && !g.rayBlocked(b.X, b.Y, x-b.X, y-b.Y, 0) {
				penalty[cell] += 4 + 6*(1-r/(blastRadius+t.R+12))
			}
		}
	}
}

func (g *Game) godlikeCanDetonate(t *Tank) bool {
	hit := false
	for _, b := range g.Bullets {
		if b == nil || b.Dead || b.Owner != t.ID || b.Kind != "grenade" {
			continue
		}
		for _, other := range g.Tanks {
			if other == nil || !other.Alive || !g.canDamage(t.ID, other) || dist(b.X, b.Y, other.X, other.Y) > blastRadius+other.R || g.rayBlocked(b.X, b.Y, other.X-b.X, other.Y-b.Y, 0) {
				continue
			}
			if other.ID == t.ID || !g.isOpponent(t.ID, other) {
				return false
			}
			if b.Age > .22 && other.Invulnerable <= 0 {
				hit = true
			}
		}
	}
	return hit
}

func (g *Game) godlikeSafeShot(t, e *Tank, angle float64) bool {
	if t.Power == "grenade" {
		// Contact detonation makes close-range grenade shots suicidal even
		// before the owner can press detonate. Leave time and room to escape.
		if dist(t.X, t.Y, e.X, e.Y) < blastRadius+t.R+35 {
			return false
		}
		ux, uy := math.Cos(angle), math.Sin(angle)
		unsafeRange := blastRadius + t.R + 35
		for _, other := range g.Tanks {
			if other == nil || !other.Alive || other.ID == t.ID {
				continue
			}
			// All living tanks trigger contact blasts, even protected enemies
			// and allies with friendly fire disabled.
			if _, hit := circleHit(t.X, t.Y, ux*unsafeRange, uy*unsafeRange, other.X, other.Y, other.R+6); hit {
				return false
			}
		}
		return !g.rayBlocked(t.X, t.Y, ux*cellSize*1.5, uy*cellSize*1.5, 6)
	}
	if t.Power == "homing" {
		return !g.rayBlocked(t.X, t.Y, math.Cos(angle)*35, math.Sin(angle)*35, 5)
	}
	radius, speed, left := regularRadius, 282.0, cellSize*7
	if t.Power == "cannon" {
		radius, speed, left = cannonRadius, cannonSpeed, cannonSpeed*cannonLifetime
	}
	if t.Power == "laser" {
		radius, left = laserRadius, g.laserRange()
	}
	if t.Power == "rapid" {
		radius, speed, left = machineRadius, machineSpeed, g.machineTravelRange()
	}
	if t.Power == "scatter" {
		speed = shotgunSpeed
	}
	ex, ey := g.botLead(t, e, tuneBot("godlike"))
	x, y, ux, uy, travel := t.X, t.Y, math.Cos(angle), math.Sin(angle), 0.0
	for k := 0; k < 24 && left > 1; k++ {
		w, ok := g.projectileWallHit(t.Power, x, y, ux*left, uy*left, radius)
		span := left
		if ok {
			span *= w.T
		}
		hit := 2.0
		if at, yes := circleHit(x, y, ux*span, uy*span, ex, ey, e.R+radius); yes {
			hit = at
		}
		for _, ally := range g.Tanks {
			if ally == nil || !ally.Alive || g.isOpponent(t.ID, ally) || !g.canDamage(t.ID, ally) {
				continue
			}
			if ally.ID == t.ID && (k == 0 || t.Power == "laser" || t.Power == "rapid" || t.Power == "scatter") {
				continue
			}
			if at, yes := circleHit(x, y, ux*span, uy*span, ally.X, ally.Y, ally.R+radius); yes && at < hit {
				if ally.ID != t.ID || travel+at*span >= speed*.2 {
					return false
				}
			}
		}
		if hit <= 1 {
			return true
		}
		if !ok {
			break
		}
		x += ux*span + w.NX*.12
		y += uy*span + w.NY*.12
		left -= span
		travel += span
		if w.NX != 0 {
			ux = -ux
		}
		if w.NY != 0 {
			uy = -uy
		}
	}
	return false
}

// Each ballistic segment is generated once and then reused by every candidate.
// Homing missiles are evaluated separately because their path changes in
// response to the candidate's own movement.
func (g *Game) godlikeForecast(t *Tank, d botTuning) ([]godlikeThreat, []*Bullet) {
	var selected [godlikeThreatLimit]*Bullet
	var priority [godlikeThreatLimit]float64
	n := 0
	for _, b := range g.Bullets {
		if b == nil || b.Dead || b.Life <= 0 || !g.canDamage(b.Owner, t) || (b.Owner == t.ID && (b.Kind == "rapid" || b.Kind == "scatter")) {
			continue
		}
		reach := math.Hypot(b.VX, b.VY)*godlikeHorizon + d.speed*godlikeHorizon + t.R + b.R + 30
		if b.Kind == "grenade" {
			reach += blastRadius
		}
		r := dist(t.X, t.Y, b.X, b.Y)
		if r > reach {
			continue
		}
		p := (r - t.R - b.R) / (math.Hypot(b.VX, b.VY) + 123)
		if b.Kind == "grenade" {
			p = (r - blastRadius) / (math.Hypot(b.VX, b.VY) + 123)
		}
		at := n
		if at == len(selected) {
			at--
			if p >= priority[at] {
				continue
			}
		} else {
			n++
		}
		for at > 0 && p < priority[at-1] {
			selected[at], priority[at] = selected[at-1], priority[at-1]
			at--
		}
		selected[at], priority[at] = b, p
	}
	threats := t.AI.tacticalThreats[:0]
	// Reuse the small guided-threat list and candidate tank copies between thinks.
	missiles := t.AI.tacticalMissiles[:0]
	for _, source := range selected[:n] {
		if source.Kind == "homing" && len(missiles) < 6 {
			missiles = append(missiles, source)
			continue
		}
		b := *source
		for k := 0; k < godlikeSteps && b.Life > 0; k++ {
			start := float64(k) * godlikeHorizon / godlikeSteps
			dt := math.Min(godlikeHorizon/godlikeSteps, b.Life)
			before := b.Life
			b.Life -= dt
			if b.Kind == "grenade" {
				drag := grenadeDragFactor(before, b.Life)
				b.VX *= drag
				b.VY *= drag
			}
			left := dt
			elapsed := 0.0
			for j := 0; j < 4 && left > 1e-6; j++ {
				w, ok := g.projectileWallHit(b.Kind, b.X, b.Y, b.VX*left, b.VY*left, b.R)
				span := left
				if ok {
					span *= w.T
				}
				threats = append(threats, godlikeThreat{botProjectileThreat: botProjectileThreat{b.X, b.Y, b.VX, b.VY, start + elapsed, start + elapsed + span, b.R}, kind: b.Kind, owner: b.Owner, fuse: source.Life, age: source.Age})
				b.X += b.VX * span
				b.Y += b.VY * span
				left -= span
				elapsed += span
				if !ok {
					break
				}
				b.X += w.NX * .08
				b.Y += w.NY * .08
				if w.NX != 0 {
					b.VX = -b.VX
				}
				if w.NY != 0 {
					b.VY = -b.VY
				}
			}
		}
	}
	t.AI.tacticalThreats = threats
	t.AI.tacticalMissiles = missiles
	return threats, missiles
}

func closestRelative(rx, ry, dx, dy float64) float64 {
	q := 0.0
	if den := dx*dx + dy*dy; den > 1e-9 {
		q = clamp(-(rx*dx+ry*dy)/den, 0, 1)
	}
	return math.Hypot(rx+dx*q, ry+dy*q)
}

func (g *Game) godlikeDodge(t *Tank, d botTuning, angle, drive float64) (float64, float64) {
	threats, missiles := g.godlikeForecast(t, d)
	var lasers [maxTanks]*Tank
	laserCount := 0
	for _, e := range g.Tanks {
		if e != nil && e.Alive && g.isOpponent(t.ID, e) && e.Invulnerable <= 0 && e.Power == "laser" && e.Cooldown < godlikeHorizon && dist(t.X, t.Y, e.X, e.Y) < cellSize*6 {
			lasers[laserCount] = e
			laserCount++
		}
	}
	if len(threats) == 0 && len(missiles) == 0 && laserCount == 0 {
		return angle, drive
	}
	risk := func(a, v, ceiling float64) float64 {
		var path [godlikeSteps + 1][2]float64
		path[0] = [2]float64{t.X, t.Y}
		heading := t.Angle
		total := 0.0
		step := godlikeHorizon / godlikeSteps
		for k := 0; k < godlikeSteps; k++ {
			end := float64(k+1) * step
			x, y := path[k][0], path[k][1]
			diff := delta(heading, a)
			heading += clamp(diff, -d.turn*step, d.turn*step)
			dx, dy := math.Cos(heading)*d.speed*v*math.Max(0, math.Cos(diff))*step, math.Sin(heading)*d.speed*v*math.Max(0, math.Cos(diff))*step
			if w, ok := g.movementWallHit(t.GhostTime > end, x, y, dx, dy, t.R+.5); ok {
				f := math.Max(0, w.T-.01)
				dx *= f
				dy *= f
			}
			path[k+1] = [2]float64{x + dx, y + dy}
			for _, e := range lasers[:laserCount] {
				if e.Cooldown > end || t.Invulnerable > end {
					continue
				}
				// Instantaneous beams cannot be dodged after firing; step out of
				// a ready enemy's visible firing line while its turret is turning.
				ux, uy := math.Cos(e.Angle), math.Sin(e.Angle)
				projection := (x+dx-e.X)*ux + (y+dy-e.Y)*uy
				if projection > 0 && projection < g.laserRange() && math.Abs((x+dx-e.X)*uy-(y+dy-e.Y)*ux) < t.R+laserRadius+8 && !g.rayBlocked(e.X, e.Y, x+dx-e.X, y+dy-e.Y, laserRadius) {
					total += 400
				}
			}
		}
		for _, s := range threats {
			// Risks only increase. Once this candidate cannot beat the current
			// winner, skip its remaining segment and guided-missile forecasts.
			if total > ceiling {
				return total
			}
			k := min(godlikeSteps-1, int((s.start+1e-9)/step))
			start := float64(k) * step
			x, y := path[k][0], path[k][1]
			dx, dy := path[k+1][0]-x, path[k+1][1]-y
			lo, hi := s.start, s.end
			if hi <= lo {
				continue
			}
			rx, ry := x+dx*(lo-start)/step-s.x-s.vx*(lo-s.start), y+dy*(lo-start)/step-s.y-s.vy*(lo-s.start)
			rdx, rdy := dx*(hi-lo)/step-s.vx*(hi-lo), dy*(hi-lo)/step-s.vy*(hi-lo)
			clearance := closestRelative(rx, ry, rdx, rdy) - t.R - s.r
			if s.kind != "grenade" {
				if t.Invulnerable > hi {
					continue
				}
				if clearance < 0 {
					total += 2400 + (godlikeHorizon-lo)*1200
				} else if clearance < 12 {
					total += (12 - clearance) * 12
				}
				continue
			}
			bx, by := s.x+s.vx*(hi-s.start), s.y+s.vy*(hi-s.start)
			r := dist(x+dx, y+dy, bx, by)
			if r > blastRadius+t.R+24 || g.rayBlocked(bx, by, x+dx-bx, y+dy-by, 0) {
				continue
			}
			if t.Invulnerable > hi {
				continue
			}
			remote := s.owner != t.ID && s.owner >= 0 && s.owner < maxTanks && g.Tanks[s.owner] != nil && g.Tanks[s.owner].Alive
			fusing := s.fuse <= godlikeHorizon+.4
			if remote || fusing {
				penetration := clamp((blastRadius+t.R+24-r)/(blastRadius+t.R+24), 0, 1)
				total += (50 + penetration*320) * (hi - lo) / step
				if s.fuse <= hi+1e-7 && r < blastRadius+t.R {
					total += 4500 + penetration*2000
				}
			}
			if clearance < 10 && (s.owner != t.ID || s.age+lo >= .2) {
				total += 3000 + (10-clearance)*70
			}
		}
		for _, b := range missiles {
			if total > ceiling {
				return total
			}
			total += g.godlikeMissileRisk(t, b, &path)
		}
		return total
	}
	baseline := risk(angle, drive, math.Inf(1))
	// Near misses and remote possible shots do not justify abandoning progress.
	// Actual collisions/blasts cost thousands, and still trigger immediately.
	if baseline < 120 {
		t.AI.DodgeTime = 0
		return angle, drive
	}
	away := t.Angle + math.Pi
	cross := angle + math.Pi/2
	if len(threats) > 0 {
		s := threats[0]
		away = math.Atan2(t.Y-s.y, t.X-s.x)
		cross = math.Atan2(s.vy, s.vx) + math.Pi/2
	}
	if len(missiles) > 0 {
		b := missiles[0]
		away = math.Atan2(t.Y-b.Y, t.X-b.X)
		cross = math.Atan2(b.VY, b.VX) + math.Pi/2
	}
	penalty := func(a, v float64) float64 {
		cost := math.Abs(delta(angle, a))*16 + math.Abs(drive-v)*12
		if v == 0 && drive != 0 {
			cost += 18
		}
		if t.AI.DodgeTime > 0 {
			cost += math.Abs(delta(t.AI.DodgeAngle, a))*24 + math.Abs(t.AI.DodgeDrive-v)*18
		}
		return cost
	}
	baseline += penalty(angle, drive)
	bestA, bestV, best := angle, drive, baseline
	for i, c := range [][2]float64{{t.AI.DodgeAngle, t.AI.DodgeDrive}, {t.Angle, -1}, {t.Angle, 1}, {angle, 0}, {away, 1}, {away + math.Pi, -1}, {cross, 1}, {cross + math.Pi, 1}, {angle + .65, 1}, {angle - .65, 1}, {angle + 1.3, 1}, {angle - 1.3, 1}, {cross, -1}} {
		if i == 0 && t.AI.DodgeTime <= 0 {
			continue
		}
		changeCost := penalty(c[0], c[1])
		cost := risk(c[0], c[1], best-changeCost) + changeCost
		if cost < best {
			best, bestA, bestV = cost, c[0], c[1]
		}
	}
	if best >= baseline-35 {
		return angle, drive
	}
	t.AI.DodgeAngle, t.AI.DodgeDrive, t.AI.DodgeTime = bestA, bestV, .28
	return bestA, bestV
}

// Run the actual lock/turn/bounce rules against a temporary predicted tank
// array. The authoritative tanks and missile are never mutated by planning.
func (g *Game) godlikeMissileRisk(t *Tank, source *Bullet, path *[godlikeSteps + 1][2]float64) float64 {
	b := *source
	forecast := *g
	if len(t.AI.missileTanks) != maxTanks {
		t.AI.missileTanks = make([]Tank, maxTanks)
	}
	predicted := t.AI.missileTanks
	for id, e := range g.Tanks {
		if e != nil {
			predicted[id] = *e
			forecast.Tanks[id] = &predicted[id]
		}
	}
	step := godlikeHorizon / godlikeSteps
	total := 0.0
	if !b.rangeSet && b.RangeLeft <= 0 {
		b.RangeLeft = g.missileTravelRange()
	}
	for k := 0; k < godlikeSteps && b.Life > 0 && b.RangeLeft > 0; k++ {
		dt := math.Min(step, math.Min(b.Life, b.RangeLeft/missileSpeed))
		for id, e := range g.Tanks {
			if e == nil {
				continue
			}
			p := forecast.Tanks[id]
			if id == t.ID {
				p.X, p.Y = path[k][0], path[k][1]
			} else {
				dx, dy := e.VX*float64(k)*step, e.VY*float64(k)*step
				if w, ok := g.movementWallHit(e.GhostTime > float64(k)*step, e.X, e.Y, dx, dy, e.R); ok {
					dx *= w.T
					dy *= w.T
				}
				p.X, p.Y = e.X+dx, e.Y+dy
			}
			p.Invulnerable = math.Max(0, e.Invulnerable-float64(k)*step)
		}
		b.Age += dt
		b.Life -= dt
		forecast.steerMissile(&b, dt)
		left, elapsed := dt, 0.0
		for j := 0; j < 4 && left > 1e-6; j++ {
			w, ok := g.projectileWallHit(b.Kind, b.X, b.Y, b.VX*left, b.VY*left, b.R)
			span := left
			if ok {
				span *= w.T
			}
			x := path[k][0] + (path[k+1][0]-path[k][0])*elapsed/step
			y := path[k][1] + (path[k+1][1]-path[k][1])*elapsed/step
			dx := (path[k+1][0]-path[k][0])*span/step - b.VX*span
			dy := (path[k+1][1]-path[k][1])*span/step - b.VY*span
			clearance := closestRelative(x-b.X, y-b.Y, dx, dy) - t.R - b.R
			if t.Invulnerable <= float64(k)*step+elapsed+span {
				if clearance < 0 {
					total += 4000 + (godlikeHorizon-float64(k)*step)*1500
				} else if clearance < 18 {
					total += (18 - clearance) * 15
				}
			}
			b.X += b.VX * span
			b.Y += b.VY * span
			b.RangeLeft -= missileSpeed * span
			left -= span
			elapsed += span
			if !ok {
				break
			}
			b.X += w.NX * .08
			b.Y += w.NY * .08
			if w.NX != 0 {
				b.VX = -b.VX
			}
			if w.NY != 0 {
				b.VY = -b.VY
			}
			b.Target = -1
			b.SeekDelay = missileWallDelay
			b.RangeLeft -= .08
		}
	}
	return total
}
