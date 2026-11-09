package main

import (
	"cmp"
	"math"
	"math/rand/v2"
	"slices"
	"strconv"
	"sync"
	"time"
)

const (
	infiniteCapacity      = 32
	infiniteBotLimit      = 24
	infiniteSight         = 1200
	infiniteTankSpeed     = 128
	infiniteMaxHP         = 3
	infiniteRespawnTicks  = 150
	infiniteShieldTicks   = 60
	infiniteShotTicks     = 21
	infiniteBulletSpeed   = 282
	infiniteBulletRadius  = 3.5
	infiniteBulletTicks   = 318
	infiniteRicochetLimit = 3
	infiniteLeaderCount   = 10
)

type infiniteTank struct {
	ID         int     `json:"id"`
	X          float64 `json:"x"`
	Y          float64 `json:"y"`
	Angle      float64 `json:"angle"`
	HP         int     `json:"hp"`
	Bot        bool    `json:"bot"`
	ColorIndex int     `json:"colorIndex"`
	Score      int     `json:"score"`
	Name       string  `json:"name"`
	Protected  bool    `json:"protected,omitempty"`
}

type infinitePilot struct {
	infiniteTank
	client                    *Client
	input                     Input
	inputAt, activeAt         time.Time
	lastStickX, lastStickY    float64
	firePending               bool
	respawn, shield, nextShot uint64

	waypoint, previous [2]int
	hasWaypoint        bool
}

type infiniteBullet struct {
	ID    int     `json:"id"`
	X     float64 `json:"x"`
	Y     float64 `json:"y"`
	Owner int     `json:"owner"`

	vx, vy  float64
	expires uint64
	bounces int
}

type infiniteSnapshot struct {
	Type    string           `json:"type"`
	Tick    uint64           `json:"tick"`
	Tanks   []infiniteTank   `json:"tanks"`
	Bullets []infiniteBullet `json:"bullets"`
	Players int              `json:"players"`
	Leaders []infiniteLeader `json:"leaderboard"`
}

type infiniteLeader struct {
	ID    int    `json:"id"`
	Name  string `json:"name"`
	Score int    `json:"score"`
	Bot   bool   `json:"bot"`
}

type infiniteArena struct {
	mu                 sync.Mutex
	players            int
	pilots             []*infinitePilot
	bullets            []infiniteBullet
	seed               uint32
	maze               *infiniteMaze
	random             *rand.Rand
	tick, nextBot      uint64
	nextID, nextBullet int
	snapshot           infiniteSnapshot // Reused after immediate encoding under mu.
}

func newInfiniteArena() *infiniteArena {
	return newSeededInfiniteArena(rand.Uint32())
}

func newSeededInfiniteArena(seed uint32) *infiniteArena {
	return &infiniteArena{
		seed:   seed,
		maze:   newInfiniteMaze(seed),
		random: rand.New(rand.NewPCG(uint64(seed), 1)),
		snapshot: infiniteSnapshot{
			Type: "state", Tanks: []infiniteTank{}, Bullets: []infiniteBullet{}, Leaders: []infiniteLeader{},
		},
	}
}

func (a *infiniteArena) join(c *Client, name string, now time.Time) *infinitePilot {
	a.mu.Lock()
	defer a.mu.Unlock()
	x, y, minCells, maxCells := 0.0, 0.0, 0, 0
	for _, other := range a.pilots {
		if !other.Bot {
			x, y, minCells, maxCells = other.X, other.Y, 3, 6
			break
		}
	}
	p := a.addPilot(cleanName(name), false, x, y, minCells, maxCells)
	if !c.enqueue(map[string]any{"type": "welcome", "id": p.ID, "seed": a.seed}) {
		a.pilots = a.pilots[:len(a.pilots)-1]
		return nil
	}
	p.client, p.inputAt, p.activeAt = c, now, now
	a.players++
	return p
}

func (a *infiniteArena) remove(p *infinitePilot) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.players--
	a.pilots = slices.DeleteFunc(a.pilots, func(other *infinitePilot) bool { return p == other })
	a.bullets = slices.DeleteFunc(a.bullets, func(b infiniteBullet) bool { return b.Owner == p.ID })
	if a.players == 0 {
		clear(a.pilots)
		a.pilots, a.bullets = a.pilots[:0], a.bullets[:0]
		a.nextBot = a.tick
	}
}

func (a *infiniteArena) setInput(p *infinitePilot, input Input, now time.Time) {
	a.mu.Lock()
	defer a.mu.Unlock()
	input.StickX = clamp(input.StickX, -1, 1)
	input.StickY = clamp(input.StickY, -1, 1)
	if p.HP > 0 && input.Fire && (!p.input.Fire || now.Sub(p.inputAt) > inputTimeout) {
		p.firePending = true
	}
	// An idle desktop pointer keeps sending its last aim direction.
	aimChanged := input.StickX != p.lastStickX || input.StickY != p.lastStickY
	if infiniteButtonsDown(input) || (math.Hypot(input.StickX, input.StickY) > .1 && (!input.AimOnly || aimChanged)) {
		p.activeAt = now
	}
	p.lastStickX, p.lastStickY = input.StickX, input.StickY
	p.input, p.inputAt = input, now
}

func (a *infiniteArena) idle(p *infinitePilot, now time.Time) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	return now.Sub(p.activeAt) >= infinitePublicIdle
}

func (a *infiniteArena) addPilot(name string, bot bool, nearX, nearY float64, minCells, maxCells int) *infinitePilot {
	a.nextID++
	p := &infinitePilot{infiniteTank: infiniteTank{ID: a.nextID, Name: name, Bot: bot, ColorIndex: (a.nextID - 1) % len(tankColors)}}
	a.spawn(p, nearX, nearY, minCells, maxCells)
	a.pilots = append(a.pilots, p)
	return p
}

func (a *infiniteArena) spawn(p *infinitePilot, nearX, nearY float64, minCells, maxCells int) {
	cx, cy := infiniteCell(nearX, nearY)
	best := -1.0
	bestX, bestY := infiniteCenter(cx+minCells, cy)
	for range 48 {
		dx, dy := a.random.IntN(2*maxCells+1)-maxCells, a.random.IntN(2*maxCells+1)-maxCells
		if dx*dx+dy*dy < minCells*minCells || dx*dx+dy*dy > maxCells*maxCells {
			continue
		}
		x, y := infiniteCenter(cx+dx, cy+dy)
		closest := math.Inf(1)
		for _, other := range a.pilots {
			if other != p && other.HP > 0 {
				closest = math.Min(closest, math.Hypot(x-other.X, y-other.Y))
			}
		}
		if closest > best {
			best, bestX, bestY = closest, x, y
		}
		if closest >= cellSize*1.5 {
			break
		}
	}
	p.X, p.Y, p.Angle = bestX, bestY, a.random.Float64()*2*math.Pi-math.Pi
	p.HP, p.Protected, p.hasWaypoint = infiniteMaxHP, true, false
	p.input, p.firePending = Input{}, false
	p.shield = a.tick + infiniteShieldTicks
}

func infiniteCell(x, y float64) (int, int) {
	return int(math.Floor(x / cellSize)), int(math.Floor(y / cellSize))
}

func infiniteCenter(x, y int) (float64, float64) {
	return (float64(x) + .5) * cellSize, (float64(y) + .5) * cellSize
}

func (a *infiniteArena) step(now time.Time) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.players == 0 {
		return
	}
	a.tick++
	a.populate()
	for _, p := range a.pilots {
		p.Protected = p.HP > 0 && a.tick < p.shield
	}
	for _, p := range a.pilots {
		if p.HP == 0 {
			if a.tick >= p.respawn {
				a.spawn(p, p.X, p.Y, 2, 5)
			}
			continue
		}
		input := p.input
		if p.Bot {
			input = a.botInput(p)
		} else if now.Sub(p.inputAt) > inputTimeout {
			input = Input{}
		} else {
			input.Fire = input.Fire || p.firePending
		}
		p.firePending = false
		a.drive(p, input)
		if input.Fire && a.tick >= p.nextShot {
			a.fire(p)
		}
	}
	// Bullets may outlive a bot or a player's previous life. Owner IDs are
	// never reused, so a late bounce cannot damage its original shooter.
	a.bullets = slices.DeleteFunc(a.bullets, func(b infiniteBullet) bool {
		return a.tick >= b.expires
	})
	alive := a.bullets[:0]
	for _, b := range a.bullets {
		if a.advanceBullet(&b, b.vx*tickDT, b.vy*tickDT) {
			alive = append(alive, b)
		}
	}
	a.bullets = alive
	if a.tick%3 == 0 {
		a.broadcast()
	}
}

func (a *infiniteArena) drive(p *infinitePilot, input Input) {
	angle, throttle := steerTank(p.Angle, input, 1, tickDT)
	p.Angle = angle
	dx, dy := math.Cos(angle)*infiniteTankSpeed*throttle*tickDT, math.Sin(angle)*infiniteTankSpeed*throttle*tickDT
	if dx != 0 && !a.maze.blocked(p.X+dx, p.Y, tankRadius) {
		p.X += dx
	}
	if dy != 0 && !a.maze.blocked(p.X, p.Y+dy, tankRadius) {
		p.Y += dy
	}
}

func (a *infiniteArena) populate() {
	if a.tick < a.nextBot {
		return
	}
	a.nextBot = a.tick + uint64(60+a.random.IntN(61))
	bots := 0
	a.pilots = slices.DeleteFunc(a.pilots, func(p *infinitePilot) bool {
		if !p.Bot {
			return false
		}
		if a.nearestHuman(p, cellSize*13, true) == nil {
			return true
		}
		bots++
		return false
	})
	if bots >= min(infiniteBotLimit, a.players*4) {
		return
	}
	var pilots [infiniteCapacity]*infinitePilot
	n := 0
	for _, p := range a.pilots {
		if !p.Bot && p.HP > 0 {
			pilots[n] = p
			n++
		}
	}
	if n > 0 {
		p := pilots[a.random.IntN(n)]
		a.addPilot("Bot "+strconv.Itoa(a.nextID+1), true, p.X, p.Y, 3, 6)
	}
}

func (a *infiniteArena) nearestHuman(p *infinitePilot, maxDist float64, includeRespawning bool) *infinitePilot {
	var nearest *infinitePilot
	for _, other := range a.pilots {
		if other.Bot || (other.HP == 0 && !includeRespawning) {
			continue
		}
		if d := math.Hypot(other.X-p.X, other.Y-p.Y); d < maxDist {
			maxDist, nearest = d, other
		}
	}
	return nearest
}

func (a *infiniteArena) botInput(p *infinitePilot) Input {
	target := a.nearestHuman(p, cellSize*8, false)
	if target != nil {
		dx, dy := target.X-p.X, target.Y-p.Y
		if _, wall := a.rayWalls(p.X, p.Y, dx, dy, infiniteBulletRadius); !wall {
			angle := math.Atan2(dy, dx)
			return Input{StickX: math.Cos(angle), StickY: math.Sin(angle), AimOnly: true, Fire: !target.Protected && math.Abs(delta(p.Angle, angle)) < .12}
		}
	}
	cx, cy := infiniteCell(p.X, p.Y)
	if p.hasWaypoint {
		x, y := infiniteCenter(p.waypoint[0], p.waypoint[1])
		if math.Hypot(x-p.X, y-p.Y) > 4 {
			angle := math.Atan2(y-p.Y, x-p.X)
			return Input{StickX: .72 * math.Cos(angle), StickY: .72 * math.Sin(angle)}
		}
		p.hasWaypoint = false
	}
	// Use adjacent cell centers for roaming so bots can take a corner at
	// corridor width without relying on a wall to steer them.
	centerX, centerY := infiniteCenter(cx, cy)
	if math.Hypot(centerX-p.X, centerY-p.Y) > 4 {
		p.waypoint, p.hasWaypoint = [2]int{cx, cy}, true
		return Input{}
	}
	directions := [4][2]int{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}
	best := math.Inf(1)
	for _, d := range directions {
		next := [2]int{cx + d[0], cy + d[1]}
		x, y := infiniteCenter(next[0], next[1])
		if a.maze.blocked((x+centerX)/2, (y+centerY)/2, tankRadius) {
			continue
		}
		cost := a.random.Float64()
		if target != nil {
			cost += math.Hypot(target.X-x, target.Y-y) / (2 * cellSize)
		}
		if next == p.previous {
			cost += 3
		}
		if cost < best {
			best, p.waypoint, p.hasWaypoint = cost, next, true
		}
	}
	p.previous = [2]int{cx, cy}
	return Input{}
}

func (a *infiniteArena) fire(p *infinitePilot) {
	p.nextShot = a.tick + infiniteShotTicks
	cs, sn := math.Cos(p.Angle), math.Sin(p.Angle)
	a.nextBullet++
	b := infiniteBullet{ID: a.nextBullet, Owner: p.ID, X: p.X, Y: p.Y, vx: cs * infiniteBulletSpeed, vy: sn * infiniteBulletSpeed, expires: a.tick + infiniteBulletTicks}
	if a.advanceBullet(&b, cs*28, sn*28) {
		a.bullets = append(a.bullets, b)
	}
}

func (a *infiniteArena) rayWalls(x, y, dx, dy, radius float64) (RayHit, bool) {
	var nearest RayHit
	found := false
	a.maze.visitWalls(min(x, x+dx)-radius, min(y, y+dy)-radius, max(x, x+dx)+radius, max(y, y+dy)+radius, func(wall Wall) bool {
		hit, ok := sweepWall(wall, x, y, dx, dy, radius)
		if !ok {
			return false
		}
		if !found || hit.T < nearest.T-1e-7 {
			nearest, found = hit, true
		} else if math.Abs(hit.T-nearest.T) < 1e-7 {
			if hit.NX != 0 {
				nearest.NX = hit.NX
			}
			if hit.NY != 0 {
				nearest.NY = hit.NY
			}
		}
		return false
	})
	return nearest, found
}

func (a *infiniteArena) advanceBullet(b *infiniteBullet, dx, dy float64) bool {
	for {
		wall, wallHit := a.rayWalls(b.X, b.Y, dx, dy, infiniteBulletRadius)
		nearest := 1.0 + 1e-8
		if wallHit {
			nearest = wall.T
		}
		var target *infinitePilot
		for _, p := range a.pilots {
			if p.ID == b.Owner || p.HP == 0 || p.Protected {
				continue
			}
			if hit, ok := circleHit(b.X, b.Y, dx, dy, p.X, p.Y, tankRadius+infiniteBulletRadius); ok && hit < nearest {
				nearest, target = hit, p
			}
		}
		if target != nil {
			target.HP--
			if target.HP == 0 {
				target.Score--
				target.respawn = a.tick + infiniteRespawnTicks
				for _, pilot := range a.pilots {
					if pilot.ID == b.Owner {
						pilot.Score++
						break
					}
				}
			}
			return false
		}
		if !wallHit {
			b.X += dx
			b.Y += dy
			return true
		}
		if b.bounces >= infiniteRicochetLimit {
			return false
		}
		b.bounces++
		b.X += dx*wall.T + wall.NX*.12
		b.Y += dy*wall.T + wall.NY*.12
		dx, dy = dx*(1-wall.T), dy*(1-wall.T)
		if wall.NX != 0 {
			dx, b.vx = -dx, -b.vx
		}
		if wall.NY != 0 {
			dy, b.vy = -dy, -b.vy
		}
		if wall.T == 1 {
			return true
		}
	}
}

func (a *infiniteArena) leaderboard(entries []infiniteLeader) []infiniteLeader {
	entries = entries[:0]
	for _, p := range a.pilots {
		entries = append(entries, infiniteLeader{ID: p.ID, Name: p.Name, Score: p.Score, Bot: p.Bot})
	}
	slices.SortFunc(entries, func(left, right infiniteLeader) int {
		if order := cmp.Compare(right.Score, left.Score); order != 0 {
			return order
		}
		return cmp.Compare(left.ID, right.ID)
	})
	return entries[:min(len(entries), infiniteLeaderCount)]
}

func (a *infiniteArena) broadcast() {
	packet := &a.snapshot
	packet.Tick, packet.Players = a.tick, a.players
	packet.Leaders = a.leaderboard(packet.Leaders)
	for _, viewer := range a.pilots {
		if viewer.Bot {
			continue
		}
		packet.Tanks, packet.Bullets = packet.Tanks[:0], packet.Bullets[:0]
		for _, p := range a.pilots {
			if math.Abs(p.X-viewer.X) <= infiniteSight && math.Abs(p.Y-viewer.Y) <= infiniteSight {
				packet.Tanks = append(packet.Tanks, p.infiniteTank)
			}
		}
		for _, b := range a.bullets {
			if math.Abs(b.X-viewer.X) <= infiniteSight && math.Abs(b.Y-viewer.Y) <= infiniteSight {
				packet.Bullets = append(packet.Bullets, b)
			}
		}
		viewer.client.enqueueState(packet, false)
	}
}
