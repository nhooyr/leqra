package main

import (
	"math"
	"sort"
)

// Objective state is authoritative; snapshots carry only read-only presentation.
type Flag struct {
	Team     int     `json:"team"`
	HomeX    float64 `json:"homeX"`
	HomeY    float64 `json:"homeY"`
	X        float64 `json:"x"`
	Y        float64 `json:"y"`
	Carrier  int     `json:"carrier"`
	Home     bool    `json:"home"`
	ReturnIn float64 `json:"returnIn"`
}
type ObjectiveState struct {
	Survival    *SurvivalState `json:"survival,omitempty"`
	SuddenDeath bool           `json:"suddenDeath"`
	Showdown    int            `json:"showdown"`
	Mode        string         `json:"mode"`
	Flags       []*Flag        `json:"flags"`
	HillX       float64        `json:"hillX"`
	HillY       float64        `json:"hillY"`
	Radius      float64        `json:"radius"`
	Owner       int            `json:"owner"`
	Contested   bool           `json:"contested"`
	Hold        float64        `json:"hold"`
}

func (g *Game) initObjectives() {
	g.Objectives = nil
	if g.survivalMode() {
		g.Objectives = &ObjectiveState{Mode: "survival", Flags: []*Flag{}, Survival: &SurvivalState{Wave: 1, WaveTarget: g.settings().ScoreTarget, Status: "wave"}}
		return
	}
	if !g.objectiveMode() {
		return
	}
	o := &ObjectiveState{Mode: g.settings().Mode, Flags: []*Flag{}, Owner: 0, Radius: 32}
	g.Objectives = o
	o.HillX, o.HillY = g.cellCenter((g.World.Rows/2)*g.World.Cols + g.World.Cols/2)
	if o.Mode == "ctf" {
		teams := []int{}
		for _, t := range g.Tanks {
			if t != nil && t.Team > 0 {
				found := false
				for _, v := range teams {
					if v == t.Team {
						found = true
					}
				}
				if !found {
					teams = append(teams, t.Team)
				}
			}
		}
		sort.Ints(teams)
		for i, team := range teams {
			if i >= 2 {
				break
			}
			x, y := cellSize*1.5, g.World.Height-cellSize*1.5
			if i == 1 {
				x, y = g.World.Width-cellSize*1.5, cellSize*1.5
			}
			o.Flags = append(o.Flags, &Flag{Team: team, HomeX: x, HomeY: y, X: x, Y: y, Carrier: -1, Home: true})
		}
		for _, t := range g.Tanks {
			if t != nil && t.Alive {
				g.respawnTank(t)
			}
		}
	}
}
func resetFlag(f *Flag) { f.X = f.HomeX; f.Y = f.HomeY; f.Carrier = -1; f.Home = true; f.ReturnIn = 0 }
func (g *Game) dropFlags(id int) {
	if g.Objectives == nil {
		return
	}
	for _, f := range g.Objectives.Flags {
		if f.Carrier != id {
			continue
		}
		if id >= 0 && id < maxTanks && g.Tanks[id] != nil {
			f.X = g.Tanks[id].X
			f.Y = g.Tanks[id].Y
		}
		f.Carrier = -1
		f.Home = false
		f.ReturnIn = 12
		g.emit("objective", nil, id, "Flag dropped · touch to return")
	}
}

// Flags are ground markers, not spawn locations. Search reachable cells from
// the team's base, skipping its entire home cell and any current friendly flag.
func (g *Game) flagSafeSpawn(t *Tank, cell int, x, y float64) bool {
	if g.Objectives == nil || g.Objectives.Mode != "ctf" {
		return true
	}
	for _, f := range g.Objectives.Flags {
		if f.Team != t.Team {
			continue
		}
		if cell == g.cellAt(f.HomeX, f.HomeY) || dist(x, y, f.X, f.Y) < t.R+32 {
			return false
		}
	}
	return true
}
func (g *Game) respawnTank(t *Tank) {
	base := g.World.Cols * (g.World.Rows - 1)
	if g.Objectives != nil && g.Objectives.Mode == "ctf" {
		for _, f := range g.Objectives.Flags {
			if f.Team == t.Team {
				base = g.cellAt(f.HomeX, f.HomeY)
			}
		}
	} else {
		spots := spawnCells(g.World.Cols, g.World.Rows)
		s := spots[t.ID%len(spots)]
		base = s[1]*g.World.Cols + s[0]
	}
	q := []int{base}
	seen := make([]bool, g.World.Cols*g.World.Rows)
	seen[base] = true
	bestX, bestY := g.cellCenter(base)
	best := math.Inf(-1)
	for at := 0; at < len(q); at++ {
		cell := q[at]
		if cell < len(g.Neighbors) {
			for _, n := range g.Neighbors[cell] {
				if !seen[n] {
					seen[n] = true
					q = append(q, n)
				}
			}
		}
		x, y := g.cellCenter(cell)
		if !g.flagSafeSpawn(t, cell, x, y) {
			continue
		}
		clearance := 500.0
		for _, other := range g.Tanks {
			if other != nil && other.ID != t.ID && other.Alive {
				clearance = math.Min(clearance, dist(x, y, other.X, other.Y)-other.R-t.R)
			}
		}
		for _, b := range g.Bullets {
			if !b.Dead {
				clearance = math.Min(clearance, dist(x, y, b.X, b.Y)-50)
			}
		}
		if clearance > best {
			best, bestX, bestY = clearance, x, y
		}
		if clearance > 70 {
			break
		}
	}
	// Defensive fallback for incomplete test/navigation data; production mazes are
	// connected. Never silently fall back to a forbidden flag cell.
	if math.IsInf(best, -1) {
		found := false
		for cell := 0; cell < len(seen); cell++ {
			x, y := g.cellCenter(cell)
			if g.flagSafeSpawn(t, cell, x, y) {
				bestX, bestY, found = x, y, true
				break
			}
		}
		if !found {
			t.Alive = false
			t.RespawnTime = .1
			return
		}
	}
	t.X = bestX
	t.Y = bestY
	t.VX = 0
	t.VY = 0
	t.Alive = true
	t.RespawnTime = 0
	t.SpawnSerial++
	t.Angle = -math.Pi / 2
	t.Power = ""
	t.PowerTime = 0
	t.MachineRounds = 0
	t.Charges = 0
	t.Shield = 0
	t.ShieldCharges = 0
	t.SpeedTime = 0
	t.SpeedStacks = 0
	t.ScopeTime = 0
	t.GhostTime = 0
	t.Cooldown = 0
	t.CooldownTotal = 0
	t.Invulnerable = 1.2
	t.AI = nil
	t.fireHeld = false
	t.fireBlocked = false
	g.emit("respawn", t, t.ID, "")
}
func (g *Game) respawnPlayers(dt float64, players [maxTanks]*Player) (respawned [maxTanks]bool) {
	if g.Objectives == nil || g.suddenDeath() || g.survivalMode() {
		return respawned
	}
	for id, t := range g.Tanks {
		if t == nil || t.Alive || players[id] == nil || !participantAvailable(players, id) {
			continue
		}
		t.RespawnTime = math.Max(0, t.RespawnTime-dt)
		if t.RespawnTime <= 0 {
			t.Team = players[id].Team
			t.Color = selectedColor(id, t.Team, players[id].ColorIndex, g.settings())
			g.respawnTank(t)
			respawned[id] = t.Alive
			// Held controls still belong to the current socket and expire through
			// the hub's normal timeout. Keep their sequence too: clearing this
			// record stopped movement and rewound acknowledgements one tick later.
			players[id].FirePending = false
		}
	}
	return respawned
}
func (g *Game) addObjectivePoint(id int) {
	if g.suddenDeath() || g.Phase != "playing" || id < 0 || id >= maxTanks {
		return
	}
	t := g.Tanks[id]
	if t == nil {
		return
	}
	for i, other := range g.Tanks {
		if other != nil && t.Team > 0 && other.Team == t.Team && g.Scores[i] > g.Scores[id] {
			g.Scores[id] = g.Scores[i]
		}
	}
	g.Scores[id]++
	for i, other := range g.Tanks {
		if other != nil && i != id && t.Team > 0 && t.Team == other.Team {
			g.Scores[i] = g.Scores[id]
		}
	}
	if g.Scores[id] >= g.settings().ScoreTarget {
		g.endObjective(id)
	}
}
func (g *Game) endObjective(winner int) {
	if g.Phase != "playing" {
		return
	}
	g.finishMatchStats(winner)
	g.Winner = winner
	g.Phase = "matchOver"
	g.PhaseTime = 0
	g.Bullets = []*Bullet{}
	g.emit("matchEnd", nil, winner, "")
	g.objectiveEnded = true
}
func (g *Game) objectiveLeader(players [maxTanks]*Player) int {
	top, winner := -1, -1
	seen := map[int]bool{}
	tie := false
	for id, t := range g.Tanks {
		if t == nil || players[id] == nil {
			continue
		}
		side := sideKey(t.ID, t.Team)
		if seen[side] {
			continue
		}
		seen[side] = true
		if g.Scores[id] > top {
			top = g.Scores[id]
			winner = id
			tie = false
		} else if g.Scores[id] == top {
			tie = true
		}
	}
	if tie {
		return -1
	}
	return winner
}
func (g *Game) stepObjectives(dt float64, players [maxTanks]*Player) {
	o := g.Objectives
	if o == nil || g.Phase != "playing" || g.survivalMode() {
		return
	}
	if o.SuddenDeath {
		g.stepSuddenDeath(players)
		return
	}
	// Drop immediately on death, including deaths from departure or test fixtures.
	for _, f := range o.Flags {
		if f.Carrier >= 0 {
			t := g.Tanks[f.Carrier]
			if t == nil || !t.Alive || players[f.Carrier] == nil {
				g.dropFlags(f.Carrier)
			} else {
				f.X = t.X
				f.Y = t.Y
			}
		}
		if !f.Home && f.Carrier < 0 {
			f.ReturnIn -= dt
			if f.ReturnIn <= 0 {
				resetFlag(f)
				g.emit("objective", nil, -1, "Flag returned to base")
			}
		}
	}
	if o.Mode == "ctf" {
		// Return friendly flags before capture checks: touching your dropped flag
		// while carrying an enemy flag can legitimately enable a capture this tick.
		for _, t := range g.Tanks {
			if t == nil || !t.Alive || t.Invulnerable > 0 {
				continue
			}
			for _, f := range o.Flags {
				if f.Team == t.Team && !f.Home && f.Carrier < 0 && dist(t.X, t.Y, f.X, f.Y) < t.R+14 && !g.rayBlocked(t.X, t.Y, f.X-t.X, f.Y-t.Y, 0) {
					g.recordFlagReturn(t)
					resetFlag(f)
					g.emit("objective", t, t.ID, "Flag returned")
				}
			}
		}
		for _, t := range g.Tanks {
			if t == nil || !t.Alive || t.Invulnerable > 0 {
				continue
			}
			var own, carried *Flag
			for _, f := range o.Flags {
				if f.Team == t.Team {
					own = f
				}
				if f.Carrier == t.ID {
					carried = f
				}
			}
			if own == nil {
				continue
			}
			if carried == nil {
				for _, f := range o.Flags {
					if f.Team != t.Team && f.Carrier < 0 && dist(t.X, t.Y, f.X, f.Y) < t.R+14 && !g.rayBlocked(t.X, t.Y, f.X-t.X, f.Y-t.Y, 0) {
						f.Carrier = t.ID
						f.Home = false
						f.ReturnIn = 0
						f.X = t.X
						f.Y = t.Y
						carried = f
						g.emit("objective", t, t.ID, "Enemy flag taken")
						break
					}
				}
			}
			if carried != nil && own.Home && dist(t.X, t.Y, own.HomeX, own.HomeY) < t.R+17 && !g.rayBlocked(t.X, t.Y, own.HomeX-t.X, own.HomeY-t.Y, 0) {
				g.recordCapture(t)
				resetFlag(carried)
				g.addObjectivePoint(t.ID)
				g.emit("objective", t, t.ID, "FLAG CAPTURED · +1")
				if g.Phase != "playing" {
					return
				}
			}
		}
	} else if o.Mode == "koth" {
		var occupants [maxTanks]*Tank
		occupantCount, sideCount, owner, id := 0, 0, 0, -1
		for _, t := range g.Tanks {
			if t == nil || !t.Alive || t.Invulnerable > 0 || dist(t.X, t.Y, o.HillX, o.HillY) > o.Radius || g.rayBlocked(o.HillX, o.HillY, t.X-o.HillX, t.Y-o.HillY, 0) {
				continue
			}
			occupants[occupantCount] = t
			occupantCount++
			side := sideKey(t.ID, t.Team)
			if sideCount == 0 {
				owner, id, sideCount = side, t.ID, 1
			} else if side != owner {
				sideCount = 2 // Only zero / one / contested matters below.
			}
		}
		o.Contested = sideCount > 1
		if sideCount != 1 {
			o.Owner = 0
			o.Hold = 0
		} else {
			if o.Owner != owner {
				o.Hold = 0
			}
			for i := 0; i < occupantCount; i++ {
				g.recordHillTime(occupants[i], dt)
			}
			o.Owner = owner
			o.Hold += dt
			for o.Hold >= 1-1e-9 {
				o.Hold = math.Max(0, o.Hold-1)
				g.addObjectivePoint(id)
				if g.Phase != "playing" {
					return
				}
			}
		}
	}
	if g.Clock <= 0 {
		leader := g.objectiveLeader(players)
		if leader >= 0 {
			g.endObjective(leader)
		} else {
			g.beginSuddenDeath(players, false)
		}
		return
	}
	sides := map[int]int{}
	for id, p := range players {
		if p != nil {
			sides[sideKey(id, p.Team)] = id
		}
	}
	if len(sides) < 2 {
		winner := -1
		for _, id := range sides {
			winner = id
		}
		g.endObjective(winner)
	}
}

// Bots pursue flags, return dropped friendly flags, intercept their carrier,
// and hold the hill instead of abandoning an objective to chase distant enemies.
func (g *Game) objectiveGoal(t *Tank) (float64, float64, bool) {
	o := g.Objectives
	if o == nil || o.SuddenDeath {
		return 0, 0, false
	}
	if o.Mode == "koth" {
		return o.HillX, o.HillY, true
	}
	var own, enemy, carried *Flag
	for _, f := range o.Flags {
		if f.Team == t.Team {
			own = f
		} else {
			enemy = f
		}
		if f.Carrier == t.ID {
			carried = f
		}
	}
	if own == nil || enemy == nil {
		return 0, 0, false
	}
	if !own.Home && (carried != nil || t.ID%2 == 0) {
		return own.X, own.Y, true
	}
	if carried != nil {
		return own.HomeX, own.HomeY, true
	}
	if enemy.Carrier >= 0 {
		carrier := g.Tanks[enemy.Carrier]
		if carrier != nil && carrier.Alive && carrier.Team == t.Team {
			if !own.Home {
				return own.X, own.Y, true
			}
			x, y := g.ctfCoverGoal(t, own, carrier)
			return x, y, true
		}
	}
	return enemy.X, enemy.Y, true
}

// A tied objective clock becomes elimination on the SAME maze. At entry every
// connected combatant gets one fresh final life, including pilots waiting to
// respawn. Scores stop; old projectiles/pickups cannot kill during the transition.
// Spectators never enter, and joining/swapping later cannot buy an extra life.
func (g *Game) suddenDeath() bool { return g.Objectives != nil && g.Objectives.SuddenDeath }
func (g *Game) beginSuddenDeath(players [maxTanks]*Player, replay bool) {
	if g.Objectives == nil || g.Phase != "playing" {
		return
	}
	o := g.Objectives
	o.SuddenDeath = true
	o.Showdown++
	o.Owner, o.Hold, o.Contested = 0, 0, false
	g.Clock, g.PhaseTime = 0, 0
	g.Bullets, g.Pickups = []*Bullet{}, []*Pickup{}
	g.SpawnClock = g.pickupDelay()
	for _, f := range o.Flags {
		resetFlag(f)
	}
	// Clear all positions first so spawn safety does not depend on stale wrecks.
	for id, t := range g.Tanks {
		if t == nil {
			continue
		}
		if !replay {
			t.suddenLife = players[id] != nil && participantAvailable(players, id)
		}
		t.Alive = false
		t.RespawnTime = 0
	}
	for id, t := range g.Tanks {
		if t == nil || !t.suddenLife || players[id] == nil || !participantAvailable(players, id) {
			continue
		}
		g.respawnTank(t)
		players[id].Input = Input{}
		players[id].FirePending = false
	}
	text := "SUDDEN DEATH · final lives · no respawns"
	if replay {
		text = "MUTUAL DESTRUCTION · sudden-death rematch"
	}
	g.emit("suddenDeath", nil, -1, text)
	g.stepSuddenDeath(players)
}
func (g *Game) stepSuddenDeath(players [maxTanks]*Player) {
	if !g.suddenDeath() || g.Phase != "playing" {
		return
	}
	live := map[int]int{}
	eligible := map[int]int{}
	for id, t := range g.Tanks {
		if t == nil || players[id] == nil || !t.suddenLife {
			continue
		}
		side := sideKey(id, t.Team)
		eligible[side] = id
		if t.Alive {
			live[side] = id
		}
	}
	if len(live) == 1 {
		for _, id := range live {
			g.endObjective(id)
		}
		return
	}
	if len(live) > 1 {
		return
	}
	// No arbitrary slot-order winner for simultaneous destruction. Only original,
	// still-connected contestants may take part in the repeated showdown.
	available := map[int]int{}
	for id, t := range g.Tanks {
		if t != nil && t.suddenLife && participantAvailable(players, id) {
			available[sideKey(id, t.Team)] = id
		}
	}
	if len(available) >= 2 {
		g.beginSuddenDeath(players, true)
		return
	}
	winner := -1
	// If only one side remains in the room, a departure resolves the match. If
	// nobody is left, report an abandoned draw rather than recurse forever.
	if len(eligible) == 1 {
		for _, id := range eligible {
			winner = id
		}
	}
	g.endObjective(winner)
}
