package main

import (
	"encoding/json"
	"math"
	"math/rand"
)

const maxTanks = 8

const powerEffectDuration = 10.0

const (
	cellSize           = 84.0
	wallSize           = 8.0
	tankRadius         = 17.0
	goalScore          = 5
	roundDuration      = 75.0
	tickDT             = 1.0 / 60.0
	boostDuration      = powerEffectDuration
	boostSpeedPerStack = .65
	boostTurnPerStack  = .25
	boostSpeed         = 1.65 // one-stack compatibility constant
	boostTurn          = 1.25 // one-stack compatibility constant
	maxSpeedStacks     = 5
	missileSpeed       = 235.0
	missileTurn        = 4.8
	missileViewCos     = -.75 // Wider seeker cone; turn rate remains bounded.
	missileLockDelay   = .06
	missileWallDelay   = .04
	missileRange       = cellSize * 10
	grenadeSpeed       = 205.0
	grenadeFuse        = 10.0
	grenadeCruiseDrag  = .025
	grenadeBrakeStart  = 7.0
	grenadeBrakeDrag   = 2.0
	blastRadius        = 220.0
	laserMaxSegments   = 128
	laserRadius        = 3.0
	laserCooldown      = .85
	scopeDuration      = powerEffectDuration
	ghostDuration      = powerEffectDuration
	// Cannon scales normal round radius (and diameter) and speed, not damage.
	cannonRadius   = 3.5 * 4
	cannonSpeed    = 282.0 * 4
	cannonLifetime = 5.3
	cannonCooldown = .85
)

var tankColors = [maxTanks]string{"#d2f65a", "#ff9679", "#73cee4", "#c5a2ff", "#ffc46b", "#ff83bd", "#75f0cb", "#b7c6ee"}

type Wall struct {
	X    float64 `json:"x"`
	Y    float64 `json:"y"`
	W    float64 `json:"w"`
	H    float64 `json:"h"`
	Axis string  `json:"axis"`
	Line float64 `json:"line"`
}
type World struct {
	Cols   int     `json:"cols"`
	Rows   int     `json:"rows"`
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
	Walls  []Wall  `json:"walls"`
}
type mazeCell struct {
	n, e, s, w bool
	seen       bool
}
type Input struct {
	Seq         uint64  `json:"seq"`
	Forward     bool    `json:"forward"`
	Reverse     bool    `json:"reverse"`
	Left        bool    `json:"left"`
	Right       bool    `json:"right"`
	Fire        bool    `json:"fire"`
	FirePressed bool    `json:"-"` // Server-latched edge; clients cannot forge it.
	StickX      float64 `json:"stickX"`
	StickY      float64 `json:"stickY"`
}
type Tank struct {
	ShotSerial    uint64            `json:"shotSerial"` // Accepted volleys in this life; cosmetic reconciliation only.
	stats         *PlayerMatchStats // Participant ledger; intentionally absent from movement snapshots.
	suddenLife    bool              // Participated at sudden-death entry; replacements wait for the next match.
	RespawnTime   float64           `json:"respawnTime"`
	SpawnSerial   int               `json:"spawnSerial"`
	Team          int               `json:"team"`
	Bot           bool              `json:"bot"`
	Difficulty    string            `json:"difficulty,omitempty"`
	AI            *BotState         `json:"-"`
	fireHeld      bool              // Last simulated button state.
	fireBlocked   bool              // A grenade action consumes the entire hold, even after expiry.
	ID            int               `json:"id"`
	Name          string            `json:"name"`
	Color         string            `json:"color"`
	X             float64           `json:"x"`
	Y             float64           `json:"y"`
	Angle         float64           `json:"angle"`
	R             float64           `json:"r"`
	VX            float64           `json:"vx"`
	VY            float64           `json:"vy"`
	Alive         bool              `json:"alive"`
	Cooldown      float64           `json:"cooldown"`
	CooldownTotal float64           `json:"cooldownTotal"`
	Invulnerable  float64           `json:"invulnerable"`
	Shield        float64           `json:"shield"`
	ShieldCharges int               `json:"shieldCharges"`
	rapidTick     int
	rapidFired    bool
	Power         string  `json:"power"`
	SpeedTime     float64 `json:"speedTime"`
	SpeedStacks   int     `json:"speedStacks"`
	ScopeTime     float64 `json:"scopeTime"`
	GhostTime     float64 `json:"ghostTime"`
	PowerTime     float64 `json:"powerTime"`
	Charges       int     `json:"charges"`
	Recoil        float64 `json:"recoil"`
	Track         float64 `json:"track"`
	Ack           uint64  `json:"ack"`
	AckSteps      uint32  `json:"ackSteps"`
}

// Kind is empty for an ordinary round; special projectiles share the same
// bounded, authoritative collision and ownership system.
type Bullet struct {
	ShotSerial  uint64  `json:"shotSerial"`
	SpawnSerial int     `json:"spawnSerial"`
	Pellet      int     `json:"pellet"`
	rangeSet    bool    // Live simulation only; range cannot be supplied by clients.
	RangeLeft   float64 `json:"rangeLeft,omitempty"`
	SeekDelay   float64 `json:"seekDelay,omitempty"`
	Kind        string  `json:"kind,omitempty"`
	Target      int     `json:"target"`
	ID          int     `json:"id"`
	Owner       int     `json:"owner"`
	X           float64 `json:"x"`
	Y           float64 `json:"y"`
	VX          float64 `json:"vx"`
	VY          float64 `json:"vy"`
	R           float64 `json:"r"`
	Age         float64 `json:"age"`
	Life        float64 `json:"life"`
	Color       string  `json:"color"`
	Bounces     int     `json:"bounces"`
	Dead        bool    `json:"-"`
}
type Pickup struct {
	ID   int     `json:"id"`
	X    float64 `json:"x"`
	Y    float64 `json:"y"`
	Type string  `json:"type"`
	Age  float64 `json:"age"`
	Life float64 `json:"life"`
}
type BeamPoint struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
}

type Event struct {
	Tick        int         `json:"tick"`
	ShotSerial  uint64      `json:"shotSerial,omitempty"`
	SpawnSerial int         `json:"spawnSerial,omitempty"`
	Angle       float64     `json:"angle,omitempty"`
	Points      []BeamPoint `json:"points,omitempty"` // Whole ricochet path in one bounded event.
	Generation  int         `json:"generation"`
	EndX        float64     `json:"endX,omitempty"`
	EndY        float64     `json:"endY,omitempty"`
	Radius      float64     `json:"radius,omitempty"`
	ID          int         `json:"id"`
	Type        string      `json:"type"`
	X           float64     `json:"x"`
	Y           float64     `json:"y"`
	Color       string      `json:"color"`
	Player      int         `json:"player"`
	Owner       int         `json:"owner"`
	Text        string      `json:"text,omitempty"`
}
type Game struct {
	stats                             *matchStatLedger
	matchReport                       *MatchReport
	matchReportWire                   json.RawMessage
	spatial                           *wallIndex
	Rules                             MatchRules
	Objectives                        *ObjectiveState
	objectiveEnded                    bool
	World                             World
	Neighbors                         [][]int
	Tanks                             [maxTanks]*Tank
	Bullets                           []*Bullet
	Pickups                           []*Pickup
	Scores                            [maxTanks]int
	Phase                             string
	PhaseTime, Clock, SpawnClock      float64
	Round, Winner, Generation, Tick   int
	events                            []Event
	nextEvent, nextBullet, nextPickup int
	rng                               *rand.Rand
}

func clamp(v, a, b float64) float64 { return math.Max(a, math.Min(b, v)) }

// Grenades keep most of their launch speed for the first seven seconds of the
// ten-second fuse, then brake progressively harder as detonation approaches.
// Integrating the time-varying drag exactly keeps Go and browser prediction
// consistent regardless of simulation/render step size.
func grenadeDragIntegral(age float64) float64 {
	age = clamp(age, 0, grenadeFuse)
	integral := grenadeCruiseDrag * age
	if age > grenadeBrakeStart {
		duration := grenadeFuse - grenadeBrakeStart
		x := age - grenadeBrakeStart
		integral += grenadeBrakeDrag * x * x * x / (3 * duration * duration)
	}
	return integral
}
func grenadeDragFactor(lifeBefore, lifeAfter float64) float64 {
	age0 := grenadeFuse - clamp(lifeBefore, 0, grenadeFuse)
	age1 := grenadeFuse - clamp(lifeAfter, 0, grenadeFuse)
	return math.Exp(-(grenadeDragIntegral(age1) - grenadeDragIntegral(age0)))
}
func delta(a, b float64) float64            { return math.Atan2(math.Sin(b-a), math.Cos(b-a)) }
func dist(x, y, xx, yy float64) float64     { return math.Hypot(x-xx, y-yy) }
func (g *Game) random(a, b float64) float64 { return a + g.rng.Float64()*(b-a) }
func newGame(seed int64) *Game {
	return &Game{Rules: defaultRules(), Phase: "lobby", Clock: roundDuration, Round: 1, Winner: -1, rng: rand.New(rand.NewSource(seed)), Bullets: []*Bullet{}, Pickups: []*Pickup{}}
}
func (g *Game) emit(kind string, t *Tank, owner int, text string) {
	g.nextEvent++
	e := Event{Tick: g.Tick, Generation: g.Generation, ID: g.nextEvent, Type: kind, Player: -1, Owner: owner, Text: text}
	if t != nil {
		e.Player = t.ID
		e.X = t.X
		e.Y = t.Y
		e.Color = t.Color
		e.ShotSerial = t.ShotSerial
		e.SpawnSerial = t.SpawnSerial
		e.Angle = t.Angle
	}
	g.events = append(g.events, e)
	if len(g.events) > 24 {
		g.events = g.events[len(g.events)-24:]
	}
}
func (g *Game) makeMaze(cols, rows int) {
	cells := make([]mazeCell, cols*rows)
	for i := range cells {
		cells[i] = mazeCell{n: true, e: true, s: true, w: true}
	}
	start := g.rng.Intn(len(cells))
	stack := []int{start}
	cells[start].seen = true
	for len(stack) > 0 {
		at := stack[len(stack)-1]
		x, y := at%cols, at/cols
		var dirs [4]int
		n := 0
		if y > 0 && !cells[at-cols].seen {
			dirs[n] = 0
			n++
		}
		if x < cols-1 && !cells[at+1].seen {
			dirs[n] = 1
			n++
		}
		if y < rows-1 && !cells[at+cols].seen {
			dirs[n] = 2
			n++
		}
		if x > 0 && !cells[at-1].seen {
			dirs[n] = 3
			n++
		}
		if n == 0 {
			stack = stack[:len(stack)-1]
			continue
		}
		d := dirs[g.rng.Intn(n)]
		next := at
		switch d {
		case 0:
			next -= cols
			cells[at].n = false
			cells[next].s = false
		case 1:
			next++
			cells[at].e = false
			cells[next].w = false
		case 2:
			next += cols
			cells[at].s = false
			cells[next].n = false
		case 3:
			next--
			cells[at].w = false
			cells[next].e = false
		}
		cells[next].seen = true
		stack = append(stack, next)
	}
	for y := 0; y < rows; y++ {
		for x := 0; x < cols; x++ {
			i := y*cols + x
			if x < cols-1 && cells[i].e && g.rng.Float64() < .25 {
				cells[i].e = false
				cells[i+1].w = false
			}
			if y < rows-1 && cells[i].s && g.rng.Float64() < .25 {
				cells[i].s = false
				cells[i+cols].n = false
			}
		}
	}
	g.World = World{Cols: cols, Rows: rows, Width: float64(cols) * cellSize, Height: float64(rows) * cellSize, Walls: []Wall{}}
	for y := 0; y < rows; y++ {
		for x := 0; x < cols; x++ {
			c := cells[y*cols+x]
			X, Y := float64(x)*cellSize, float64(y)*cellSize
			if c.n {
				g.World.Walls = append(g.World.Walls, Wall{X - wallSize/2, Y - wallSize/2, cellSize + wallSize, wallSize, "h", Y})
			}
			if c.w {
				g.World.Walls = append(g.World.Walls, Wall{X - wallSize/2, Y - wallSize/2, wallSize, cellSize + wallSize, "v", X})
			}
			if y == rows-1 {
				g.World.Walls = append(g.World.Walls, Wall{X - wallSize/2, g.World.Height - wallSize/2, cellSize + wallSize, wallSize, "h", g.World.Height})
			}
			if x == cols-1 {
				g.World.Walls = append(g.World.Walls, Wall{g.World.Width - wallSize/2, Y - wallSize/2, wallSize, cellSize + wallSize, "v", g.World.Width})
			}
		}
	}
}

// Eight perimeter cells keep every tank separate on all supported map sizes.
func spawnCells(cols, rows int) [][2]int {
	return [][2]int{{0, rows - 1}, {cols - 1, 0}, {cols - 1, rows - 1}, {0, 0}, {cols / 2, 0}, {cols - 1, rows / 2}, {cols / 2, rows - 1}, {0, rows / 2}}
}

func (g *Game) startRound(players [maxTanks]*Player) {
	g.Generation++
	cols, rows := g.mapDimensions()
	g.makeMaze(cols, rows)
	g.buildNavigation()
	g.Bullets = []*Bullet{}
	g.Pickups = []*Pickup{}
	g.Clock = float64(g.settings().TimeLimit)
	g.SpawnClock = g.pickupDelay()
	g.Phase = "countdown"
	g.PhaseTime = 2.6
	g.Winner = -1
	spots := spawnCells(cols, rows)
	// Preserve the four-corner distribution for rosters using only legacy seats.
	highSeat := 0
	for id, p := range players {
		if p != nil && id > highSeat {
			highSeat = id
		}
	}
	if highSeat < 4 {
		spots = spots[:4]
	}
	g.rng.Shuffle(len(spots), func(i, j int) { spots[i], spots[j] = spots[j], spots[i] })
	for id, p := range players {
		g.Tanks[id] = nil
		if p == nil {
			continue
		}
		s := spots[id]
		g.Tanks[id] = &Tank{ID: id, Name: p.Name, Team: p.Team, Bot: p.Kind == "bot", Difficulty: p.Difficulty, Color: selectedColor(id, p.Team, p.ColorIndex, g.settings()), X: (float64(s[0]) + .5) * cellSize, Y: (float64(s[1]) + .5) * cellSize, Angle: -math.Pi / 2, R: tankRadius, Alive: participantAvailable(players, id), Invulnerable: .75}
		g.bindTankStats(g.Tanks[id], p)
		p.Input = Input{} // Held inputs never leak across rounds.
		p.FirePending = false
	}
	g.initObjectives()
	g.objectiveEnded = false
	g.seedPickups()
	g.emit("roundStart", nil, -1, "")
}
func (g *Game) startMatch(players [maxTanks]*Player) {
	g.resetMatchStats()
	g.Scores = [maxTanks]int{}
	g.Round = 1
	g.events = nil
	g.startRound(players)
}

type RayHit struct{ T, NX, NY float64 }

func (g *Game) rayWallsHit(x, y, dx, dy, r float64) (RayHit, bool) {
	var best RayHit
	hasBest := false
	nearest := 1.0 + 1e-8
	for _, wi := range g.wallCandidates(x, y, dx, dy, r) {
		w := g.World.Walls[wi]
		minX, maxX, minY, maxY := w.X-r, w.X+w.W+r, w.Y-r, w.Y+w.H+r
		if math.Max(x, x+dx) < minX || math.Min(x, x+dx) > maxX || math.Max(y, y+dy) < minY || math.Min(y, y+dy) > maxY {
			continue
		}
		tx1, tx2, ty1, ty2 := math.Inf(-1), math.Inf(1), math.Inf(-1), math.Inf(1)
		if math.Abs(dx) < 1e-9 {
			if x < minX || x > maxX {
				continue
			}
		} else {
			tx1 = (minX - x) / dx
			tx2 = (maxX - x) / dx
			if tx1 > tx2 {
				tx1, tx2 = tx2, tx1
			}
		}
		if math.Abs(dy) < 1e-9 {
			if y < minY || y > maxY {
				continue
			}
		} else {
			ty1 = (minY - y) / dy
			ty2 = (maxY - y) / dy
			if ty1 > ty2 {
				ty1, ty2 = ty2, ty1
			}
		}
		entry, exit := math.Max(tx1, ty1), math.Min(tx2, ty2)
		if entry > exit || exit < 0 || entry > 1 || entry < -.0001 {
			continue
		}
		hit := math.Max(0, entry)
		nx, ny := 0.0, 0.0
		if math.Abs(tx1-ty1) < 1e-7 {
			nx = 1
			ny = 1
			if dx > 0 {
				nx = -1
			}
			if dy > 0 {
				ny = -1
			}
		} else if tx1 > ty1 {
			nx = 1
			if dx > 0 {
				nx = -1
			}
		} else {
			ny = 1
			if dy > 0 {
				ny = -1
			}
		}
		if hit < nearest-1e-7 {
			nearest = hit
			best = RayHit{hit, nx, ny}
			hasBest = true
		} else if hasBest && math.Abs(hit-nearest) < 1e-7 {
			if nx != 0 {
				best.NX = nx
			}
			if ny != 0 {
				best.NY = ny
			}
		}
	}
	return best, hasBest
}

// Pointer compatibility is retained for test fixtures and low-frequency helpers.
// Simulation hot paths use rayWallsHit so collision checks do not allocate.
func (g *Game) rayWalls(x, y, dx, dy, r float64) *RayHit {
	hit, ok := g.rayWallsHit(x, y, dx, dy, r)
	if !ok {
		return nil
	}
	return &hit
}

func (g *Game) rayBlocked(x, y, dx, dy, r float64) bool {
	_, ok := g.rayWallsHit(x, y, dx, dy, r)
	return ok
}

func circleHit(x, y, dx, dy, tx, ty, r float64) (float64, bool) {
	a := dx*dx + dy*dy
	ox, oy := x-tx, y-ty
	c := ox*ox + oy*oy - r*r
	if c <= 0 {
		return 0, true
	}
	if a < 1e-12 {
		return 0, false
	}
	b := 2 * (ox*dx + oy*dy)
	disc := b*b - 4*a*c
	if disc < 0 {
		return 0, false
	}
	n := (-b - math.Sqrt(disc)) / (2 * a)
	return n, n >= 0 && n <= 1
}
func (g *Game) resolveWalls(t *Tank) {
	for pass := 0; pass < 2; pass++ {
		candidates := g.wallCandidates(t.X, t.Y, 0, 0, t.R)
		for at := 0; at < len(candidates); at++ {
			wi := candidates[at]
			w := g.World.Walls[wi]
			qx, qy := clamp(t.X, w.X, w.X+w.W), clamp(t.Y, w.Y, w.Y+w.H)
			dx, dy := t.X-qx, t.Y-qy
			ds := dx*dx + dy*dy
			if ds >= t.R*t.R {
				continue
			}
			if ds > .000001 {
				d := math.Sqrt(ds)
				push := t.R - d + .002
				t.X += dx / d * push
				t.Y += dy / d * push
			} else {
				v := []float64{t.X - w.X, w.X + w.W - t.X, t.Y - w.Y, w.Y + w.H - t.Y}
				i := 0
				for n := 1; n < 4; n++ {
					if v[n] < v[i] {
						i = n
					}
				}
				switch i {
				case 0:
					t.X -= v[i] + t.R + .002
				case 1:
					t.X += v[i] + t.R + .002
				case 2:
					t.Y -= v[i] + t.R + .002
				case 3:
					t.Y += v[i] + t.R + .002
				}
			}
			// A collision push can introduce new contacts at later wall indices.
			candidates = g.wallCandidates(t.X, t.Y, 0, 0, t.R)
			at = 0
			for at < len(candidates) && candidates[at] <= wi {
				at++
			}
			at--

		}
	}
}
func (g *Game) moveTank(t *Tank, dx, dy float64) {
	if t.GhostTime > 0 {
		t.X = clamp(t.X+dx, wallSize/2+t.R, g.World.Width-wallSize/2-t.R)
		t.Y = clamp(t.Y+dy, wallSize/2+t.R, g.World.Height-wallSize/2-t.R)
		return
	}
	t.X += dx
	g.resolveWalls(t)
	t.Y += dy
	g.resolveWalls(t)
	t.X = clamp(t.X, wallSize/2+t.R, g.World.Width-wallSize/2-t.R)
	t.Y = clamp(t.Y, wallSize/2+t.R, g.World.Height-wallSize/2-t.R)
}
func (g *Game) control(t *Tank, in Input, dt float64) {
	// Decrement here (also mirrored by the prediction client) so input replay
	// crosses boost expiry on exactly the same simulation step.
	t.SpeedTime = math.Max(0, t.SpeedTime-dt)
	if t.SpeedTime <= 0 {
		t.SpeedStacks = 0
	}
	g.advanceGhost(t, dt)
	n := speedCount(t)
	speedScale, turnScale := 1+boostSpeedPerStack*float64(n), 1+boostTurnPerStack*float64(n)
	throttle := 0.0
	if in.Forward {
		throttle++
	}
	if in.Reverse {
		throttle -= .72
	}
	mag := math.Hypot(in.StickX, in.StickY)
	if mag > .1 {
		desired := math.Atan2(in.StickY, in.StickX)
		diff := delta(t.Angle, desired)
		t.Angle += clamp(diff, -5.8*turnScale*dt, 5.8*turnScale*dt)
		throttle = math.Min(1, mag) * math.Max(0, math.Cos(diff))
	} else {
		turn := 0.0
		if in.Right {
			turn++
		}
		if in.Left {
			turn--
		}
		t.Angle += turn * 3.65 * turnScale * dt
	}
	t.Angle = math.Atan2(math.Sin(t.Angle), math.Cos(t.Angle))
	g.moveTank(t, math.Cos(t.Angle)*128*speedScale*throttle*dt, math.Sin(t.Angle)*128*speedScale*throttle*dt)
	// Count server simulation ticks under this held input, not received packets.
	// The browser uses (ack, ackSteps) to replay only movement not included here.
	if t.Ack != in.Seq {
		t.Ack = in.Seq
		t.AckSteps = 0
	}
	if t.AckSteps < 1<<30 {
		t.AckSteps++
	}
	pressed := in.FirePressed // Only the hub may create an online press edge.
	t.fireHeld = in.Fire
	g.weaponControl(t, in.Fire, pressed)
}

// A press launches a grenade; the next fresh press detonates owned live grenades.
// Detonation is independent of the current weapon/charges/cooldown. Holding never
// immediately detonates, repeats a throw, or falls through to an ordinary shot.
func (g *Game) weaponControl(t *Tank, held, pressed bool) {
	if !t.Alive {
		return
	}
	if !held {
		t.fireBlocked = false
	}
	if pressed {
		if g.detonateOwned(t) {
			t.fireBlocked = held
			return
		}
		if t.Power == "grenade" {
			t.fireBlocked = held
			g.fire(t)
			return
		}
	}
	if !t.fireBlocked && t.Power != "grenade" && (held || pressed) {
		g.fire(t)
	}
}
func (g *Game) detonateOwned(t *Tank) bool {
	if !t.Alive {
		return false
	}
	// Capture the set first: the first explosion can kill its owner, but all
	// grenades selected by the same valid detonation press still go off.
	var owned [3]*Bullet
	count := 0
	for _, b := range g.Bullets {
		if !b.Dead && b.Owner == t.ID && b.Kind == "grenade" && count < len(owned) {
			owned[count] = b
			count++
		}
	}
	for i := 0; i < count; i++ {
		g.detonate(owned[i])
	}
	return count > 0
}
func capacity(t *Tank) int {
	if t.Power == "homing" || t.Power == "grenade" || t.Power == "laser" || t.Power == "cannon" {
		return 3
	}
	if t.Power == "rapid" {
		return machineCapacity
	}
	if t.Power == "scatter" {
		return 12
	}
	return 5
}
func (g *Game) fire(t *Tank) bool {
	if !t.Alive || t.Cooldown > 0 || (t.GhostTime > 0 && t.Power != "cannon" && !g.clearTankAt(t.X, t.Y, 0)) {
		return false
	}
	if t.Power == "rapid" && t.rapidFired && t.rapidTick == g.Tick {
		return false
	}
	if t.Power == "laser" {
		return g.fireLaser(t)
	}
	if t.Power == "cannon" && t.Charges <= 0 {
		return false
	}
	ammo := 0
	for _, b := range g.Bullets {
		if !b.Dead && b.Owner == t.ID {
			ammo++
		}
	}
	spread := []float64{0}
	if t.Power == "scatter" {
		spread = []float64{-.21, 0, .21}
	}
	if capacity(t)-ammo < len(spread) {
		return false
	}
	t.Cooldown = .34
	speed, life := 282.0, 5.3
	if t.Power == "rapid" {
		t.Cooldown = 0
		speed = machineSpeed
		life = g.machineTravelRange() / machineSpeed
	}
	if t.Power == "scatter" {
		t.Cooldown = .54
		life = 3.9
		speed = shotgunSpeed
	}
	kind, radius := "", regularRadius
	if t.Power == "scatter" {
		kind = "scatter"
	}
	if t.Power == "rapid" {
		kind, radius = "rapid", machineRadius
		t.rapidTick = g.Tick
		t.rapidFired = true
	}
	if t.Power == "homing" {
		kind, radius, speed, life, t.Cooldown = "homing", 5, missileSpeed, g.missileTravelRange()/missileSpeed+.5, .72
	}
	if t.Power == "grenade" {
		kind, radius, speed, life, t.Cooldown = "grenade", 6, grenadeSpeed, grenadeFuse, .8
	}
	if t.Power == "cannon" {
		kind, radius, speed, life, t.Cooldown = "cannon", cannonRadius, cannonSpeed, cannonLifetime, cannonCooldown
	}
	t.ShotSerial++
	t.Recoil = 1
	t.CooldownTotal = t.Cooldown
	muzzle := 28.0
	if kind == "cannon" {
		muzzle = math.Max(muzzle, t.R+radius+1)
	}
	for pellet, offset := range spread {
		a := t.Angle + offset
		cs, sn := math.Cos(a), math.Sin(a)
		g.nextBullet++
		b := &Bullet{ShotSerial: t.ShotSerial, SpawnSerial: t.SpawnSerial, Pellet: pellet, ID: g.nextBullet, Owner: t.ID, X: t.X + cs*muzzle, Y: t.Y + sn*muzzle, VX: cs * speed, VY: sn * speed, R: radius, Life: life, Color: t.Color, Kind: kind, Target: -1}
		// Cannon ignores internal walls, but even its muzzle respects the arena rim.
		hit, hitOK := g.projectileWallHit(kind, t.X, t.Y, cs*muzzle, sn*muzzle, b.R)
		if hitOK {
			b.X = t.X + cs*muzzle*hit.T + hit.NX*.12
			b.Y = t.Y + sn*muzzle*hit.T + hit.NY*.12
			if hit.NX != 0 {
				b.VX = -b.VX
			}
			if hit.NY != 0 {
				b.VY = -b.VY
			}
			b.Bounces++
		}
		if kind == "homing" || kind == "rapid" {
			// Count the hidden muzzle section toward total path budgets, matching Laser/Scope semantics.
			launchDistance := muzzle
			if hitOK {
				launchDistance = muzzle*hit.T + math.Hypot(hit.NX, hit.NY)*.12
				if kind == "homing" {
					b.SeekDelay = missileWallDelay
				}
			}
			if kind == "homing" {
				b.RangeLeft = math.Max(0, g.missileTravelRange()-launchDistance)
				b.rangeSet = true
			} else {
				b.Life = math.Max(0, (g.machineTravelRange()-launchDistance)/machineSpeed)
			}
		}
		g.Bullets = append(g.Bullets, b)
	}
	// Throttle cosmetic machine-gun events, never the authoritative bullets.
	if kind != "rapid" || t.ShotSerial%4 == 1 {
		g.emit("shot", t, t.ID, kind)
	}
	if t.Power == "scatter" || t.Power == "homing" || t.Power == "grenade" || t.Power == "cannon" {
		t.Charges--
		if t.Charges <= 0 {
			t.Power = ""
			t.PowerTime = 0
		}
	}
	return true
}

// Weapon path budgets are TOTAL travel distances, not fresh allowances at each bounce.
func (g *Game) machineTravelRange() float64 { return (g.World.Width + g.World.Height) / 2 }
func (g *Game) laserRange() float64         { return 2 * (g.World.Width + g.World.Height) }

// Trace from the tank centre to avoid tunneling with a barrel against a wall.
// Only the first hidden barrel segment is cropped for rendering. The shooter
// stays immune as before; the first vulnerable opponent/shield ends the shot.
func (g *Game) traceLaser(t *Tank) ([]BeamPoint, *Tank) {
	x, y, ux, uy := t.X, t.Y, math.Cos(t.Angle), math.Sin(t.Angle)
	remaining := g.laserRange()
	points := make([]BeamPoint, 0, 16)
	for segment := 0; segment < laserMaxSegments && remaining > 1e-7; segment++ {
		dx, dy := ux*remaining, uy*remaining
		wall, wallOK := g.rayWallsHit(x, y, dx, dy, laserRadius)
		stop := 1.0
		if wallOK {
			stop = wall.T
		}
		var target *Tank
		for _, other := range g.Tanks {
			if other == nil || other.ID == t.ID || !g.canDamage(t.ID, other) || !other.Alive || other.Invulnerable > 0 {
				continue
			}
			if at, ok := circleHit(x, y, dx, dy, other.X, other.Y, other.R+laserRadius); ok && at < stop {
				stop, target = at, other
			}
		}
		length := remaining * stop
		if segment == 0 {
			start := math.Min(28, length)
			points = append(points, BeamPoint{x + ux*start, y + uy*start})
		}
		x += ux * length
		y += uy * length
		points = append(points, BeamPoint{x, y})
		remaining -= length
		if target != nil {
			return points, target
		}
		if !wallOK || remaining <= 1e-7 {
			break
		}
		if wall.NX != 0 {
			ux = -ux
		}
		if wall.NY != 0 {
			uy = -uy
		}
		// Skip a tiny distance ALONG the reflected ray, charging it to the same
		// budget. This avoids zero-distance wall hits without adding beam length.
		nudge := math.Min(.001, remaining)
		x += ux * nudge
		y += uy * nudge
		remaining -= nudge
	}
	return points, nil
}
func (g *Game) fireLaser(t *Tank) bool {
	if !t.Alive || t.Cooldown > 0 || t.Power != "laser" || t.Charges <= 0 {
		return false
	}
	points, target := g.traceLaser(t)
	if len(points) < 2 {
		return false
	}
	start, end := points[0], points[len(points)-1]
	t.ShotSerial++
	g.nextEvent++
	g.events = append(g.events, Event{Tick: g.Tick, ShotSerial: t.ShotSerial, SpawnSerial: t.SpawnSerial, Angle: t.Angle, Generation: g.Generation, ID: g.nextEvent, Type: "laser", X: start.X, Y: start.Y, EndX: end.X, EndY: end.Y, Points: points, Color: "#f57cff", Player: t.ID, Owner: t.ID})
	if len(g.events) > 24 {
		g.events = g.events[len(g.events)-24:]
	}
	t.Cooldown = laserCooldown
	t.CooldownTotal = laserCooldown
	t.Recoil = 1
	g.emit("shot", t, t.ID, "laser")
	if target != nil {
		g.hurt(target, &Bullet{Owner: t.ID, Kind: "laser"})
	}
	t.Charges--
	if t.Charges <= 0 {
		t.Power = ""
		t.PowerTime = 0
	}
	return true
}

func (g *Game) hurt(t *Tank, b *Bullet) {
	if !t.Alive || t.Invulnerable > 0 || !g.canDamage(b.Owner, t) || ((b.Kind == "scatter" || b.Kind == "rapid") && b.Owner == t.ID) {
		return
	}
	if t.Shield > 0 {
		t.ShieldCharges = shieldCount(t) - 1
		if t.ShieldCharges == 0 {
			t.Shield = 0
		}
		t.Invulnerable = .35
		g.emit("shield", t, b.Owner, "")
		return
	}
	g.recordDeath(t, b.Owner)
	t.Alive = false
	if g.objectiveMode() && !g.suddenDeath() {
		t.RespawnTime = float64(g.settings().RespawnSeconds)
		g.dropFlags(t.ID)
	}
	t.VX = 0
	t.VY = 0
	text := t.Name + " was eliminated."
	if b.Owner == t.ID {
		text = t.Name + " caught their own ricochet."
		if b.Kind == "grenade" {
			text = t.Name + " was caught in their own blast."
		}
	} else if owner := g.Tanks[b.Owner]; owner != nil {
		text = owner.Name + " eliminated " + t.Name + "."
	}
	g.emit("hit", t, b.Owner, text)
}

// One distance budget for the entire flight, including every bend and bounce.
// A half-perimeter is width + height, not half of the diagonal or a straight radius.
func (g *Game) missileTravelRange() float64 { return g.World.Width + g.World.Height }

// Guidance is server-owned. Limited turn rate and a forward-facing seeker let
// a tank dodge across the missile's nose. A lost lock does not instantly reacquire.
// Walls reflect the missile and briefly inhibit steering away from that reflection.
func (g *Game) steerMissile(b *Bullet, dt float64) {
	b.SeekDelay = math.Max(0, b.SeekDelay-dt)
	if b.Age < .1 || b.SeekDelay > 0 {
		return
	}
	visible := func(t *Tank) bool {
		if t == nil || t.ID == b.Owner || !g.isOpponent(b.Owner, t) || !t.Alive || t.Invulnerable > 0 {
			return false
		}
		rx, ry := t.X-b.X, t.Y-b.Y
		d := math.Hypot(rx, ry)
		if d > missileRange {
			return false
		}
		if d > 1e-8 && rx*b.VX+ry*b.VY < missileViewCos*d*math.Hypot(b.VX, b.VY) {
			return false
		}
		return !g.rayBlocked(b.X, b.Y, rx, ry, b.R)
	}
	var target *Tank
	if b.Target >= 0 {
		if b.Target < len(g.Tanks) && visible(g.Tanks[b.Target]) {
			target = g.Tanks[b.Target]
		} else {
			b.Target = -1
			b.SeekDelay = missileLockDelay
			return
		}
	}
	if target == nil {
		best := math.Inf(1)
		for _, t := range g.Tanks {
			if !visible(t) {
				continue
			}
			d := dist(b.X, b.Y, t.X, t.Y)
			if d < best {
				best, target = d, t
			}
		}
	}
	b.Target = -1
	if target == nil {
		return
	}
	b.Target = target.ID
	a := math.Atan2(b.VY, b.VX)
	a += clamp(delta(a, math.Atan2(target.Y-b.Y, target.X-b.X)), -missileTurn*dt, missileTurn*dt)
	b.VX, b.VY = math.Cos(a)*missileSpeed, math.Sin(a)*missileSpeed
}
func (g *Game) projectileEvent(kind string, b *Bullet, radius float64) {
	g.nextEvent++
	g.events = append(g.events, Event{Tick: g.Tick, Generation: g.Generation, ID: g.nextEvent, Type: kind, X: b.X, Y: b.Y, Color: b.Color, Player: -1, Owner: b.Owner, Radius: radius})
	if len(g.events) > 24 {
		g.events = g.events[len(g.events)-24:]
	}
}
func (g *Game) detonate(b *Bullet) {
	if b.Dead {
		return
	}
	b.Dead = true
	g.projectileEvent("blast", b, blastRadius)
	// Resolve the complete blast before checking the round winner. A single
	// explosion may remove several tanks, including its owner, or cause a draw.
	for _, t := range g.Tanks {
		if t == nil || !t.Alive || dist(b.X, b.Y, t.X, t.Y) > blastRadius+t.R {
			continue
		}
		if g.rayBlocked(b.X, b.Y, t.X-b.X, t.Y-b.Y, 0) {
			continue
		}
		g.hurt(t, b)
	}
}
func (g *Game) updateBullets(dt float64) {
	for _, b := range g.Bullets {
		if b.Dead {
			continue
		}
		if b.Kind == "homing" && !b.rangeSet {
			if b.RangeLeft <= 0 {
				b.RangeLeft = g.missileTravelRange()
			}
			b.rangeSet = true
		}
		span := math.Min(dt, math.Max(0, b.Life))
		if b.Kind == "homing" {
			span = math.Min(span, math.Max(0, b.RangeLeft)/missileSpeed)
		}
		lifeBefore := b.Life
		b.Age += span
		b.Life -= span
		if b.Kind == "homing" {
			g.steerMissile(b, span)
		}
		if b.Kind == "grenade" {
			drag := grenadeDragFactor(lifeBefore, b.Life)
			b.VX *= drag
			b.VY *= drag
		}
		remaining := span
		for step := 0; step < 4 && remaining > .00001 && !b.Dead; step++ {
			if b.Kind == "homing" {
				remaining = math.Min(remaining, math.Max(0, b.RangeLeft)/missileSpeed)
			}
			dx, dy := b.VX*remaining, b.VY*remaining
			wall, wallOK := g.projectileWallHit(b.Kind, b.X, b.Y, dx, dy, b.R)
			var target *Tank
			first := 2.0
			// A grenade makes one blast at first living-tank contact. Physical
			// contact also counts on allies or spawn-protected tanks; damage still
			// passes through canDamage / invulnerability / shield checks. A short
			// owner grace keeps a wall-adjacent launch from detonating in the barrel.
			for _, t := range g.Tanks {
				if t == nil || !t.Alive || (t.ID == b.Owner && (b.Age < .20 || b.Kind == "scatter" || b.Kind == "rapid")) {
					continue
				}
				if b.Kind != "grenade" && (!g.canDamage(b.Owner, t) || t.Invulnerable > 0) {
					continue
				}
				if at, ok := circleHit(b.X, b.Y, dx, dy, t.X, t.Y, t.R+b.R); ok && at < first {
					first, target = at, t
				}
			}
			if target != nil && (!wallOK || first <= wall.T) {
				b.X += dx * first
				b.Y += dy * first
				if b.Kind == "grenade" {
					g.detonate(b) // Not contact damage plus blast: shields absorb one hit.
				} else {
					b.Dead = true
					if b.Kind == "homing" {
						b.RangeLeft = math.Max(0, b.RangeLeft-math.Hypot(dx, dy)*first)
						g.projectileEvent("impact", b, 25)
					}
					if b.Kind == "cannon" {
						g.projectileEvent("impact", b, 32) // Cosmetic only, no splash damage.
					}
					g.hurt(target, b)
				}
				break
			}
			if wallOK {
				nudge := .08
				if b.Kind == "homing" {
					b.RangeLeft = math.Max(0, b.RangeLeft-math.Hypot(dx, dy)*wall.T)
					nudge = math.Min(nudge, b.RangeLeft/math.Max(1, math.Hypot(wall.NX, wall.NY)))
					b.RangeLeft = math.Max(0, b.RangeLeft-nudge*math.Hypot(wall.NX, wall.NY))
					b.Target = -1
					b.SeekDelay = missileWallDelay
				}
				b.X += dx*wall.T + wall.NX*nudge
				b.Y += dy*wall.T + wall.NY*nudge
				if wall.NX != 0 {
					b.VX = -b.VX
				}
				if wall.NY != 0 {
					b.VY = -b.VY
				}
				b.Bounces++
				remaining *= 1 - wall.T
				if (b.Kind != "homing" && b.Kind != "rapid" && b.Bounces > 22) || b.Bounces > 128 {
					if b.Kind == "grenade" {
						g.detonate(b)
					} else {
						b.Dead = true
					}
				}
			} else {
				b.X += dx
				b.Y += dy
				if b.Kind == "homing" {
					b.RangeLeft = math.Max(0, b.RangeLeft-math.Hypot(dx, dy))
				}
				remaining = 0
			}
		}
		if !b.Dead && (b.Life <= 1e-9 || (b.Kind == "homing" && b.RangeLeft <= 1e-7)) {
			if b.Kind == "grenade" {
				g.detonate(b)
			} else {
				b.Dead = true
				if b.Kind == "homing" {
					g.projectileEvent("impact", b, 20)
				}
			}
		}
		if b.X < -15 || b.X > g.World.Width+15 || b.Y < -15 || b.Y > g.World.Height+15 {
			b.Dead = true
		}
	}
	live := g.Bullets[:0]
	for _, b := range g.Bullets {
		if !b.Dead {
			live = append(live, b)
		}
	}
	g.Bullets = live
}

var pickupTypes = []string{"rapid", "scatter", "shield", "homing", "grenade", "speed", "laser", "scope", "cannon", "ghost"}

func (g *Game) grantPower(t *Tank, kind string) {
	switch kind {
	case "shield":
		t.ShieldCharges = min(maxShieldCharges, shieldCount(t)+1)
		t.Shield = shieldDuration
	case "speed":
		t.SpeedStacks = min(maxSpeedStacks, speedCount(t)+1)
		t.SpeedTime = boostDuration
	case "scope":
		t.ScopeTime = scopeDuration // Independent aiming buff; no weapon-slot changes.
	case "ghost":
		t.GhostTime = ghostDuration // Refresh only. Weapon, speed, scope and shield stay intact.
	case "rapid", "scatter":
		if kind == "rapid" {
			t.Cooldown = 0
			t.CooldownTotal = 0
		}
		t.Power = kind
		t.PowerTime = powerEffectDuration
		t.Charges = 5
	case "homing", "grenade", "laser", "cannon":
		t.Power = kind
		t.PowerTime = powerEffectDuration
		t.Charges = 3
	default:
		return
	}
	g.emit("pickup", t, t.ID, kind)
}
func (g *Game) spawnPower() {
	if len(g.Pickups) >= pickupCap(g.World.Cols, g.World.Rows) || g.World.Cols == 0 || g.settings().PickupRate == "off" || len(g.settings().Weapons) == 0 {
		return
	}
	for tries := 0; tries < 60; tries++ {
		x := (float64(g.rng.Intn(g.World.Cols)) + .5) * cellSize
		y := (float64(g.rng.Intn(g.World.Rows)) + .5) * cellSize
		ok := true
		for _, t := range g.Tanks {
			if t != nil && t.Alive && dist(x, y, t.X, t.Y) < cellSize*.85 {
				ok = false
			}
		}
		for _, p := range g.Pickups {
			if dist(x, y, p.X, p.Y) < cellSize*1.1 {
				ok = false
			}
		}
		if !ok {
			continue
		}
		types := g.settings().Weapons
		g.nextPickup++
		g.Pickups = append(g.Pickups, &Pickup{ID: g.nextPickup, X: x, Y: y, Type: g.choosePickup(types), Life: pickupLifetime(g.World.Cols, g.World.Rows)})
		return
	}
}
func (g *Game) finishRound(winner int) {
	if g.Phase != "playing" {
		return
	}
	g.Winner = winner
	g.Phase = "roundOver"
	g.PhaseTime = 2.7
	if winner >= 0 {
		g.Scores[winner]++
		if t := g.Tanks[winner]; t != nil && t.Team > 0 {
			for id, other := range g.Tanks {
				if other != nil && other.Team == t.Team {
					g.Scores[id] = g.Scores[winner]
				}
			}
		}
	}
	g.emit("roundEnd", nil, winner, "")
}
func (g *Game) step(dt float64, inputs [maxTanks]Input, players [maxTanks]*Player) {
	g.Tick++
	switch g.Phase {
	case "lobby", "matchOver":
		return
	case "countdown":
		g.PhaseTime -= dt
		if g.PhaseTime <= 0 {
			g.Phase = "playing"
			g.PhaseTime = .55
		}
		return
	case "roundOver":
		g.PhaseTime -= dt
		if g.PhaseTime > 0 {
			return
		}
		if g.Winner >= 0 && g.Scores[g.Winner] >= g.settings().ScoreTarget {
			g.finishMatchStats(g.Winner)
			g.Phase = "matchOver"
			g.emit("matchEnd", nil, g.Winner, "")
			return
		}
		if availableSides(players) < 2 {
			g.Phase = "lobby"
			for _, p := range players {
				if p != nil {
					p.Ready = false
				}
			}
			return
		}
		g.Round++
		g.startRound(players)
		return
	}
	if g.objectiveMode() && !g.suddenDeath() {
		if g.Clock <= 0 {
			if leader := g.objectiveLeader(players); leader >= 0 {
				g.endObjective(leader)
			} else {
				g.beginSuddenDeath(players, false)
			}
			return
		}
		dt = math.Min(dt, g.Clock)
	}
	if g.liveStats() {
		g.stats.duration += dt
	}
	g.PhaseTime = math.Max(0, g.PhaseTime-dt)
	g.Clock = math.Max(0, g.Clock-dt)
	g.SpawnClock -= dt
	if g.SpawnClock <= 0 {
		g.spawnPower()
		lo, hi := g.pickupInterval()
		g.SpawnClock = g.random(lo, hi)
	}
	if g.objectiveMode() {
		g.respawnPlayers(dt, players)
	}
	// Alternating order avoids always giving slot zero the first shot/move.
	for i := 0; i < maxTanks; i++ {
		id := (i + g.Tick) % maxTanks
		t := g.Tanks[id]
		if t == nil || !t.Alive {
			continue
		}
		t.Cooldown = math.Max(0, t.Cooldown-dt)
		t.Invulnerable = math.Max(0, t.Invulnerable-dt)
		t.Shield = math.Max(0, t.Shield-dt)
		if t.Shield <= 0 {
			t.ShieldCharges = 0
		}
		t.ScopeTime = math.Max(0, t.ScopeTime-dt)
		t.Recoil = math.Max(0, t.Recoil-dt*9)
		if t.Power != "" {
			t.PowerTime -= dt
			if t.PowerTime <= 0 {
				t.Power = ""
				t.PowerTime = 0
			}
		}
		x, y := t.X, t.Y
		if t.Bot {
			g.botControl(t, dt)
		} else {
			g.control(t, inputs[id], dt)
		}
		t.VX = (t.X - x) / dt
		t.VY = (t.Y - y) / dt
		t.Track += dist(t.X, t.Y, x, y)
	}
	for i := 0; i < maxTanks; i++ {
		for j := i + 1; j < maxTanks; j++ {
			a, b := g.Tanks[i], g.Tanks[j]
			if a == nil || b == nil || !a.Alive || !b.Alive {
				continue
			}
			dx, dy := b.X-a.X, b.Y-a.Y
			d := math.Hypot(dx, dy)
			over := a.R + b.R - d
			if over > 0 {
				if d < .001 {
					dx = 1
					dy = 0
					d = 1
				}
				g.moveTank(a, -dx/d*over*.5, -dy/d*over*.5)
				g.moveTank(b, dx/d*over*.5, dy/d*over*.5)
			}
		}
	}
	g.updateBullets(dt)
	livePickups := g.Pickups[:0]
	for _, p := range g.Pickups {
		p.Age += dt
		p.Life -= dt
		if p.Life <= 0 {
			continue
		}
		for i := 0; i < maxTanks; i++ {
			t := g.Tanks[(i+g.Tick)%maxTanks]
			if t != nil && t.Alive && dist(t.X, t.Y, p.X, p.Y) < t.R+13 {
				g.grantPower(t, p.Type)
				p.Life = 0
				break
			}
		}
		if p.Life > 0 {
			livePickups = append(livePickups, p)
		}
	}
	g.Pickups = livePickups
	if g.objectiveMode() {
		g.stepObjectives(dt, players)
		return
	}
	sideCount, winner, owner := 0, -1, 0
	for _, t := range g.Tanks {
		if t == nil || !t.Alive {
			continue
		}
		key := sideKey(t.ID, t.Team)
		if sideCount == 0 {
			owner, winner, sideCount = key, t.ID, 1
		} else if key != owner {
			sideCount = 2
			break
		}
	}
	if sideCount <= 1 {
		g.finishRound(winner)
	} else if g.Clock <= 0 {
		g.finishRound(-1)
	}
}
