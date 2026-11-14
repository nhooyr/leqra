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
	infiniteCapacity     = 32
	infiniteBotLimit     = 24
	infiniteSight        = 1200
	infiniteTankSpeed    = 128
	infiniteMaxHP        = 1
	infiniteRespawnTicks = 60
	infiniteBulletRadius = 3.5
	infiniteLeaderCount  = 10
)

type infiniteTank struct {
	ID         int     `json:"id"`
	X          float64 `json:"x"`
	Y          float64 `json:"y"`
	VX         float64 `json:"vx"`
	VY         float64 `json:"vy"`
	Angle      float64 `json:"angle"`
	HP         int     `json:"hp"`
	Bot        bool    `json:"bot"`
	Difficulty string  `json:"difficulty,omitempty"`
	ColorIndex int     `json:"colorIndex"`
	Team       int     `json:"team,omitempty"`
	Score      int     `json:"score"`
	Rank       int     `json:"rank,omitempty"`
	Name       string  `json:"name"`
	Protected  bool    `json:"protected,omitempty"`
	Ack        uint64  `json:"ack,omitempty"`
	AckSteps   uint32  `json:"ackSteps,omitempty"`
	Spawn      int     `json:"spawnSerial,omitempty"`
	Track      float64 `json:"track,omitempty"`
	Recoil     float64 `json:"recoil,omitempty"`
	Cooldown   float64 `json:"cooldown,omitempty"`
	Invuln     float64 `json:"invulnerable,omitempty"`
	Power      string  `json:"power,omitempty"`
	PowerTime  float64 `json:"powerTime,omitempty"`
	Charges    int     `json:"charges,omitempty"`
	Machine    int     `json:"machineRounds,omitempty"`
	Shield     float64 `json:"shield,omitempty"`
	Shields    int     `json:"shieldCharges,omitempty"`
	SpeedTime  float64 `json:"speedTime,omitempty"`
	Speed      int     `json:"speedStacks,omitempty"`
	Ghost      float64 `json:"ghostTime,omitempty"`
	Starman    float64 `json:"starmanTime,omitempty"`

	CooldownTotal float64 `json:"cooldownTotal,omitempty"`
	RespawnTime   float64 `json:"respawnTime,omitempty"`
	KilledBy      string  `json:"killedBy,omitempty"`
	KilledByColor string  `json:"killedByColor,omitempty"`
	AmmoUsed      int     `json:"ammoUsed,omitempty"`
	Grenades      int     `json:"grenades,omitempty"`
	GrenadeLife   float64 `json:"grenadeLife,omitempty"`
	Locked        bool    `json:"locked,omitempty"`

	SpawnProtected bool `json:"spawnProtected"`
}

type infinitePilot struct {
	infiniteTank
	client                 *Client
	local                  *infinitePilot // A controller's second seat shares this snapshot.
	input                  Input
	inputAt, activeAt      time.Time
	lastStickX, lastStickY float64
	fireDown, firePending  bool // Keep the physical button state across respawns.
	paused                 bool // Holds respawn independently of control expiry.
	disconnected           bool
	respawn                uint64
	kit                    Tank // Reuses fixed-maze equipment state and pickup rules.
	roomBot                *Player
	botLevel               int
	botThink, botShot      uint64
	botAim                 float64
	botTarget              int
	botHasAim              bool
	ambientNumber          int
	party                  infiniteRoom
	partyMember            uint64
	publicKey, publicToken string // Private bearer metadata, never part of a tank snapshot.

	waypoint, previous [2]int
	hasWaypoint        bool
}

type infiniteBullet struct {
	ID      int     `json:"id"`
	X       float64 `json:"x"`
	Y       float64 `json:"y"`
	Owner   int     `json:"owner"`
	Kind    string  `json:"kind,omitempty"`
	Color   int     `json:"colorIndex"`
	VX      float64 `json:"vx"`
	VY      float64 `json:"vy"`
	Life    float64 `json:"life"`
	Bounces int     `json:"bounces,omitempty"`
	Target  int     `json:"target,omitempty"` // Positive pilot ID when a seeker has a lock.

	radius, age, seekDelay float64
	ownerTeam              int
	ownerName              string
	dead                   bool
	boosted                bool
}

type infiniteSnapshot struct {
	Type          string                 `json:"type"`
	Tick          uint64                 `json:"tick"`
	Tanks         []infiniteTank         `json:"tanks"`
	Bullets       []infiniteBullet       `json:"bullets"`
	Pickups       []Pickup               `json:"pickups"`
	Effects       []infiniteEffect       `json:"effects,omitempty"`
	Players       int                    `json:"players"`
	TankCount     int                    `json:"tankCount"`
	Party         []infinitePartyLeader  `json:"party,omitempty"`
	Leaders       []infiniteLeader       `json:"leaderboard"`
	Rules         *infiniteRules         `json:"rules,omitempty"`
	Scores        *[4]int                `json:"teamScores,omitempty"`
	Result        *infiniteResult        `json:"result,omitempty"`
	GodlikeSpawns []infiniteGodlikeSpawn `json:"godlikeSpawns,omitempty"`
}

type infiniteLeader struct {
	ID         int    `json:"id"`
	Name       string `json:"name"`
	Score      int    `json:"score"`
	Bot        bool   `json:"bot"`
	Team       int    `json:"team,omitempty"`
	ColorIndex int    `json:"colorIndex"`
}

type infinitePartyLeader struct {
	ID         int    `json:"id"`
	Member     uint64 `json:"member"`
	Name       string `json:"name"`
	Score      int    `json:"score"`
	ColorIndex int    `json:"colorIndex"`
	Rank       int    `json:"rank"`
}

type infiniteRules struct {
	Target       int      `json:"infinityTarget"`
	TeamMode     string   `json:"teamMode"`
	TeamNames    []string `json:"teamNames"`
	TeamColors   []int    `json:"teamColors"`
	FriendlyFire bool     `json:"friendlyFire"`

	randomBots, randomDifficulty bool
	botLevel                     int
}

type infiniteResult struct {
	ID    int    `json:"id,omitempty"`
	Name  string `json:"name"`
	Team  int    `json:"team"`
	Score int    `json:"score"`
}

type infiniteSeat struct {
	name        string
	team        int
	colorIndex  int
	publicToken string
	saved       *infinitePublicEntry
	resumed     bool
}

type infiniteArena struct {
	mu                                      sync.Mutex
	players                                 int // Human seats in the arena, including reservations.
	connected                               int // Human seats with a live controller socket.
	pilots                                  []*infinitePilot
	inactiveBots                            []*infinitePilot // Preserve roaming identities while the connected-player budget is lower.
	bullets                                 []infiniteBullet
	pickups                                 []Pickup
	effects                                 []infiniteEffect
	seed                                    uint32
	maze                                    *infiniteMaze
	random                                  *rand.Rand
	tick, nextBot                           uint64
	publicBotLives                          uint64
	clock                                   time.Time
	godlikeSpawns                           []infiniteGodlikeSpawn
	nextPickup                              uint64
	nextID, nextBullet                      int
	pickupID, effectID                      int
	snapshot                                infiniteSnapshot // Reused after immediate encoding under mu.
	snapshotTankIndex                       map[int]int
	rules                                   *infiniteRules
	roomBots                                []infiniteRoomBot
	teamScores                              [4]int
	result                                  *infiniteResult
	publicEntries                           map[int]infinitePublicEntry
	publicPending                           map[int]infinitePublicEntry
	publicArchive                           []infiniteLeader
	publicActive                            map[int]bool
	publicArchiveDirty                      bool
	commitBeforeBroadcast, broadcastPending bool
}

func newInfiniteArena() *infiniteArena {
	return newSeededInfiniteArena(rand.Uint32())
}

func newRoomInfiniteArena(rules MatchRules, bots []infiniteRoomBot) *infiniteArena {
	a := newInfiniteArena()
	rules = normalizedRules(rules)
	a.rules = &infiniteRules{
		Target: rules.InfinityTarget, TeamMode: rules.TeamMode, TeamNames: rules.TeamNames,
		TeamColors: rules.TeamColors, FriendlyFire: rules.FriendlyFire,
		randomBots: rules.InfinityRandomBots, randomDifficulty: rules.InfinityRandomDifficulty,
		botLevel: infiniteBotLevel(rules.InfinityBotDifficulty),
	}
	a.roomBots = bots
	return a
}

func (a *infiniteArena) teams() bool { return a.rules != nil && a.rules.TeamMode == "teams" }

func newSeededInfiniteArena(seed uint32) *infiniteArena {
	return &infiniteArena{
		seed:     seed,
		maze:     newInfiniteMaze(seed),
		random:   rand.New(rand.NewPCG(uint64(seed), 1)),
		snapshot: emptyInfiniteSnapshot(),
	}
}

func emptyInfiniteSnapshot() infiniteSnapshot {
	return infiniteSnapshot{Type: "state", Tanks: []infiniteTank{}, Bullets: []infiniteBullet{}, Pickups: []Pickup{}, Leaders: []infiniteLeader{}}
}

func (a *infiniteArena) join(c *Client, name string, now time.Time) *infinitePilot {
	p, _ := a.joinSeats(c, infiniteSeat{name: name, colorIndex: -1}, nil, 0, now)
	return p
}

func (a *infiniteArena) joinSeats(c *Client, first infiniteSeat, second *infiniteSeat, generation uint64, now time.Time) (*infinitePilot, *infinitePilot) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.clock = now
	if a.maze == nil {
		a.maze = newInfiniteMaze(a.seed)
	}
	x, y, minCells, maxCells := 0.0, 0.0, 0, 0
	for _, other := range a.pilots {
		if !other.Bot {
			x, y, minCells, maxCells = other.X, other.Y, 3, 6
			break
		}
	}
	before := len(a.pilots)
	p := a.addPilot(cleanName(first.name), false, x, y, minCells, maxCells)
	a.setSeat(p, first, now)
	if first.saved != nil {
		p.ID = first.saved.ID
		p.Name = first.saved.Name
		p.Score = first.saved.Score
		p.ColorIndex = first.saved.ColorIndex
	}
	p.publicToken = first.publicToken
	if first.publicToken != "" {
		p.publicKey, _ = publicTokenHash(first.publicToken)
	}
	var local *infinitePilot
	if second != nil {
		name := cleanCallsign(second.name)
		if name == "" {
			name = "CO-PILOT"
		}
		local = a.addPilot(name, false, p.X, p.Y, 1, 3)
		a.setSeat(local, *second, now)
		if second.saved != nil {
			local.ID = second.saved.ID
			local.Name = second.saved.Name
			local.Score = second.saved.Score
			local.ColorIndex = second.saved.ColorIndex
		}
		local.publicKey = p.publicKey
		if second.publicToken != "" {
			local.publicToken = second.publicToken
			local.publicKey, _ = publicTokenHash(second.publicToken)
		}
	}
	if !a.welcome(c, p, local, generation, first.resumed) {
		clear(a.pilots[before:])
		a.pilots = a.pilots[:before]
		return nil, nil
	}
	p.client, p.local = c, local
	a.players += len(a.pilots) - before
	a.connected += len(a.pilots) - before
	if a.result != nil {
		a.broadcast()
	} else if before == 0 {
		for _, spec := range a.roomBots {
			bot := a.addPilot(spec.seat.name, true, p.X, p.Y, 3, 6)
			bot.roomBot, bot.botLevel = spec.member, infiniteBotLevel(spec.difficulty)
			a.setSeat(bot, spec.seat, now)
		}
	}
	return p, local
}

func (a *infiniteArena) welcome(c *Client, primary, local *infinitePilot, generation uint64, resumed bool) bool {
	packet := struct {
		Type             string `json:"type"`
		ID               int    `json:"id"`
		Seed             uint32 `json:"seed"`
		LocalID          int    `json:"localId,omitempty"`
		Generation       uint64 `json:"generation,omitempty"`
		Resumed          bool   `json:"resumed,omitempty"`
		PublicToken      string `json:"publicToken,omitempty"`
		LocalPublicToken string `json:"localPublicToken,omitempty"`
		Public           bool   `json:"public,omitempty"`
	}{Type: "welcome", ID: primary.ID, Seed: a.seed, Generation: generation, Resumed: resumed, PublicToken: primary.publicToken, Public: a.publicEntries != nil}
	if local != nil {
		packet.LocalID = local.ID
		if local.publicToken != primary.publicToken {
			packet.LocalPublicToken = local.publicToken
		}
	}
	return c.enqueue(packet)
}

// Party identity is authenticated by the room socket, never supplied by a
// public pilot. The next state includes the complete party's score summary.
func (a *infiniteArena) bindParty(primary, local *infinitePilot, party infiniteRoom, member, localMember uint64) {
	a.mu.Lock()
	defer a.mu.Unlock()
	primary.party, primary.partyMember = party, member
	if local != nil {
		local.party, local.partyMember = party, localMember
	}
}

func (a *infiniteArena) suspend(p *infinitePilot) {
	a.mu.Lock()
	defer a.mu.Unlock()
	p.client = nil
	for _, seat := range [2]*infinitePilot{p, p.local} {
		if seat != nil {
			a.connected--
			seat.disconnected = true
			seat.clearControls()
		}
	}
	a.trimRoamingBots()
}

func (a *infiniteArena) resume(c *Client, p *infinitePilot, generation uint64, now time.Time) string {
	a.mu.Lock()
	defer a.mu.Unlock()
	if p.client != nil {
		// A half-open socket may not notice a change of networks. Only
		// replace it when its application heartbeats have gone quiet.
		select {
		case <-p.client.done:
		default:
			if now.Sub(p.inputAt) < infiniteResumeIdle || p.local != nil && now.Sub(p.local.inputAt) < infiniteResumeIdle {
				return infiniteSessionActive
			}
		}
	}
	if !a.welcome(c, p, p.local, generation, true) {
		return "Could not join Infinity."
	}
	for _, seat := range [2]*infinitePilot{p, p.local} {
		if seat != nil {
			if seat.disconnected {
				a.connected++
			}
			seat.disconnected = false
			seat.clearControls()
			seat.Ack, seat.AckSteps = 0, 0
			seat.inputAt, seat.activeAt = now, now
		}
	}
	p.client = c
	if a.result != nil {
		a.broadcast()
	}
	return ""
}

func (p *infinitePilot) clearControls() {
	p.input, p.fireDown, p.firePending = Input{}, false, false
	p.VX, p.VY = 0, 0
	p.kit.fireHeld, p.kit.fireBlocked = false, false
	p.lastStickX, p.lastStickY = 0, 0
}

func (a *infiniteArena) setSeat(p *infinitePilot, seat infiniteSeat, now time.Time) {
	p.Team, p.inputAt, p.activeAt = seat.team, now, now
	if seat.colorIndex >= 0 {
		p.ColorIndex = seat.colorIndex
	}
}

func (a *infiniteArena) removeRoomBots(removed uint64) {
	a.mu.Lock()
	defer a.mu.Unlock()
	for i := len(a.roomBots) - 1; i >= 0; i-- {
		if removed&(1<<i) == 0 {
			continue
		}
		member := a.roomBots[i].member
		a.roomBots = slices.Delete(a.roomBots, i, i+1)
		for j, pilot := range a.pilots {
			if pilot.roomBot == member {
				a.pilots = slices.Delete(a.pilots, j, j+1)
				a.bullets = slices.DeleteFunc(a.bullets, func(b infiniteBullet) bool { return b.Owner == pilot.ID })
				break
			}
		}
	}
	if a.result != nil {
		a.broadcast()
	}
}

func (a *infiniteArena) removeLocal(primary *infinitePilot) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.rememberPublicLocked()
	local := primary.local
	primary.local = nil
	a.players--
	if !local.disconnected {
		a.connected--
	}
	a.pilots = slices.DeleteFunc(a.pilots, func(p *infinitePilot) bool { return p == local })
	a.bullets = slices.DeleteFunc(a.bullets, func(b infiniteBullet) bool { return b.Owner == local.ID })
	a.trimRoamingBots()
}

func (a *infiniteArena) remove(p *infinitePilot) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.rememberPublicLocked()
	p.client = nil
	a.players--
	if !p.disconnected {
		a.connected--
	}
	localID := 0
	if p.local != nil {
		localID = p.local.ID
		a.players--
		if !p.local.disconnected {
			a.connected--
		}
	}
	a.pilots = slices.DeleteFunc(a.pilots, func(other *infinitePilot) bool { return p == other || p.local == other })
	a.bullets = slices.DeleteFunc(a.bullets, func(b infiniteBullet) bool { return b.Owner == p.ID || localID != 0 && b.Owner == localID })
	a.trimRoamingBots()
	if a.players == 0 {
		// A scored private room may retain its totals/result after all
		// controllers leave. Release the world and snapshot buffers until it
		// has viewers again; the maze is reproducible from the seed.
		a.pilots, a.bullets, a.pickups, a.effects = nil, nil, nil, nil
		if a.publicEntries == nil {
			a.inactiveBots = nil
		}
		a.maze = nil
		a.snapshot = emptyInfiniteSnapshot()
		a.snapshotTankIndex = nil
		a.nextBot = a.tick
		a.nextPickup = a.tick
	}
}

// Call with a.mu held when the arena is shared.
func (a *infiniteArena) setInput(p *infinitePilot, input Input, paused bool, now time.Time) {
	p.paused = paused
	if paused {
		input = Input{Seq: input.Seq}
		p.firePending = false
	}
	input.StickX = clamp(input.StickX, -1, 1)
	input.StickY = clamp(input.StickY, -1, 1)
	if now.Sub(p.inputAt) > inputTimeout {
		p.firePending = false
	}
	// A timeout suppresses stale controls, but a held heartbeat remains held.
	// Wait for a release and a new press before throwing or detonating.
	if p.HP > 0 && input.Fire && !p.fireDown {
		p.firePending = true
	}
	p.fireDown = input.Fire
	// An idle desktop pointer keeps sending its last aim direction.
	aimChanged := input.StickX != p.lastStickX || input.StickY != p.lastStickY
	if infiniteButtonsDown(input) || (math.Hypot(input.StickX, input.StickY) > .1 && (!input.AimOnly || aimChanged)) {
		p.activeAt = now
	}
	p.lastStickX, p.lastStickY = input.StickX, input.StickY
	p.input, p.inputAt = input, now
}

func (a *infiniteArena) setConnectionInput(c *Client, controller, seat *infinitePilot, input Input, paused bool, now time.Time) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if controller.client == c && (seat == controller || seat == controller.local) {
		a.setInput(seat, input, paused, now)
	}
}

func (a *infiniteArena) idle(p *infinitePilot, now time.Time) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	return now.Sub(p.activeAt) >= infinitePublicIdle && (p.local == nil || now.Sub(p.local.activeAt) >= infinitePublicIdle)
}

func (a *infiniteArena) addPilot(name string, bot bool, nearX, nearY float64, minCells, maxCells int) *infinitePilot {
	a.nextID++
	p := &infinitePilot{infiniteTank: infiniteTank{ID: a.nextID, Name: name, Bot: bot, ColorIndex: (a.nextID - 1) % len(tankColors)}, botLevel: infiniteNormalBot}
	a.spawn(p, nearX, nearY, minCells, maxCells)
	if bot {
		a.startBotLife(p)
	}
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
	p.VX, p.VY = 0, 0
	p.HP, p.Protected, p.hasWaypoint = infiniteMaxHP, true, false
	p.KilledBy = ""
	p.KilledByColor = ""
	p.input, p.firePending = Input{Seq: p.input.Seq}, false
	p.kit = Tank{Invulnerable: 1, SpawnProtected: true}
	p.Spawn++
	p.Track = 0
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
	a.clock = now
	if a.players == 0 || a.result != nil {
		return
	}
	a.tick++
	a.populate()
	a.populatePickups()
	for _, p := range a.pilots {
		if p.HP == 0 {
			if a.tick >= p.respawn && !p.paused && !p.disconnected {
				x, y := p.X, p.Y
				if p.Bot && p.roomBot == nil {
					anchor := a.nearestActivePilot(p, math.Inf(1))
					if anchor == nil {
						continue
					}
					x, y = anchor.X, anchor.Y
				}
				a.spawn(p, x, y, 2, 5)
				if p.Bot {
					a.startBotLife(p)
				}
			}
			continue
		}
		a.advanceEquipment(p)
	}
	// Rotate live actors so a simultaneous hit does not always favor the
	// first pilot to join, matching the fixed-maze simulation.
	var actors [infiniteCapacity + infiniteBotLimit]*infinitePilot
	count := 0
	for _, p := range a.pilots {
		if p.HP > 0 {
			actors[count] = p
			count++
		}
	}
	for i := 0; i < count; i++ {
		if a.result != nil {
			break
		}
		p := actors[(a.tick+uint64(i))%uint64(count)]
		// An earlier attack can eliminate this actor. Reserved tanks stay
		// vulnerable while they have no controller.
		if p.HP == 0 || p.disconnected {
			continue
		}
		input := p.input
		if p.Bot {
			input = a.botInput(p)
		} else if now.Sub(p.inputAt) > inputTimeout {
			input = Input{Seq: input.Seq}
		} else {
			input.FirePressed = p.firePending
		}
		p.firePending = false
		if p.Ack != input.Seq {
			p.Ack, p.AckSteps = input.Seq, 0
		}
		if p.AckSteps < 1<<30 {
			p.AckSteps++
		}
		a.drive(p, input)
		a.collectPickup(p)
		a.weaponControl(p, input.Fire, input.FirePressed || p.Bot && input.Fire && !p.kit.fireHeld)
	}
	if a.result == nil {
		a.resolveStarmanContacts(actors[:count])
	}
	// Bullets may outlive a bot or a player's previous life. Owner IDs are
	// never reused, so a late bounce cannot damage its original shooter.
	if a.result == nil {
		a.advanceBullets()
	}
	a.effects = slices.DeleteFunc(a.effects, func(e infiniteEffect) bool { return a.tick-e.tick >= 9 })
	if a.tick%2 == 0 || a.result != nil {
		if a.commitBeforeBroadcast {
			a.broadcastPending = true
		} else {
			a.broadcast()
		}
	}
}

func (a *infiniteArena) drive(p *infinitePilot, input Input) {
	boost := float64(speedCount(&p.kit))
	angle, throttle := steerTank(p.Angle, input, 1+boostTurnPerStack*boost, tickDT)
	p.Angle = angle
	speed := infiniteTankSpeed * (1 + boostSpeedPerStack*boost)
	dx, dy := math.Cos(angle)*speed*throttle*tickDT, math.Sin(angle)*speed*throttle*tickDT
	x, y := p.X, p.Y
	if dx != 0 && (p.kit.GhostTime > 0 || !a.maze.blocked(p.X+dx, p.Y, tankRadius)) {
		p.X += dx
	}
	if dy != 0 && (p.kit.GhostTime > 0 || !a.maze.blocked(p.X, p.Y+dy, tankRadius)) {
		p.Y += dy
	}
	p.Track += math.Hypot(p.X-x, p.Y-y)
	p.VX, p.VY = (p.X-x)/tickDT, (p.Y-y)/tickDT
}

func (a *infiniteArena) roamingBotBudget() int {
	if a.rules != nil && !a.rules.randomBots {
		return 0
	}
	return min(infiniteBotLimit, a.connected*8)
}

func (a *infiniteArena) trimRoamingBots() int {
	bots := 0
	for _, p := range a.pilots {
		if p.Bot && p.roomBot == nil {
			bots++
		}
	}
	budget := a.roamingBotBudget()
	for i := len(a.pilots) - 1; i >= 0 && bots > budget; i-- {
		p := a.pilots[i]
		if p.Bot && p.roomBot == nil {
			a.inactiveBots = append(a.inactiveBots, p)
			a.pilots = slices.Delete(a.pilots, i, i+1)
			bots--
		}
	}
	a.enforcePublicGodlikeLimit()
	return bots
}

func (a *infiniteArena) nearestActivePilot(p *infinitePilot, maxDist float64) *infinitePilot {
	var nearest *infinitePilot
	for _, other := range a.pilots {
		if other.Bot || other.HP == 0 || other.disconnected {
			continue
		}
		if d := math.Hypot(other.X-p.X, other.Y-p.Y); d < maxDist {
			maxDist, nearest = d, other
		}
	}
	return nearest
}

func (a *infiniteArena) outsideActiveViews(p *infinitePilot) bool {
	for _, viewer := range a.pilots {
		if !viewer.Bot && !viewer.disconnected && math.Abs(p.X-viewer.X) <= cellSize*16 && math.Abs(p.Y-viewer.Y) <= cellSize*16 {
			return false
		}
	}
	return true
}

func (a *infiniteArena) pilotByID(id int) *infinitePilot {
	for _, pilots := range [2][]*infinitePilot{a.pilots, a.inactiveBots} {
		for _, p := range pilots {
			if p.ID == id {
				return p
			}
		}
	}
	return nil
}

func (a *infiniteArena) populate() {
	bots := a.trimRoamingBots()
	if a.roamingBotBudget() == 0 || a.tick < a.nextBot {
		return
	}
	a.nextBot = a.tick + uint64(60+a.random.IntN(61))
	var pilots [infiniteCapacity]*infinitePilot
	n := 0
	for _, p := range a.pilots {
		if !p.Bot && p.HP > 0 && !p.disconnected {
			pilots[n] = p
			n++
		}
	}
	if n > 0 {
		for _, bot := range a.pilots {
			if bot.Bot && bot.roomBot == nil && bot.HP > 0 && a.outsideActiveViews(bot) {
				anchor := pilots[a.random.IntN(n)]
				a.spawn(bot, anchor.X, anchor.Y, 3, 6)
			}
		}
		if bots >= a.roamingBotBudget() {
			return
		}
		p := pilots[a.random.IntN(n)]
		if len(a.inactiveBots) > 0 {
			i := len(a.inactiveBots) - 1
			bot := a.inactiveBots[i]
			a.inactiveBots = slices.Delete(a.inactiveBots, i, i+1)
			if bot.HP > 0 {
				a.spawn(bot, p.X, p.Y, 3, 6)
			}
			a.pilots = append(a.pilots, bot)
			return
		}
		var used [infiniteBotLimit + 1]bool
		for _, bot := range a.pilots {
			if bot.ambientNumber > 0 {
				used[bot.ambientNumber] = true
			}
		}
		number := 1
		for used[number] {
			number++
		}
		bot := a.addPilot("Bot "+strconv.Itoa(number), true, p.X, p.Y, 3, 6)
		bot.ambientNumber = number
		if a.rules != nil {
			bot.botLevel = a.rules.botLevel
			if a.rules.randomDifficulty {
				bot.botLevel = a.random.IntN(bot.botLevel + 1)
			}
		} else {
			bot.publicBotName()
			a.recordGodlikeSpawn(bot)
		}
		if a.teams() {
			var counts [5]int
			for _, other := range a.pilots {
				counts[other.Team]++
			}
			// Always populate two sides. Extra numbered sides participate if
			// the room roster assigned someone to them.
			team := 1
			for i := 2; i < len(counts); i++ {
				if (i == 2 || counts[i] > 0) && counts[i] < counts[team] {
					team = i
				}
			}
			bot.Team, bot.ColorIndex = team, a.rules.TeamColors[team-1]
		}
	}
}

func (a *infiniteArena) nearestPilot(p *infinitePilot, maxDist float64, findOpponent bool) *infinitePilot {
	var nearest *infinitePilot
	for _, other := range a.pilots {
		if (!findOpponent || !a.teams()) && other.Bot ||
			findOpponent && (other.HP == 0 || !infiniteOpposes(p.ID, p.Team, other)) {
			continue
		}
		if d := math.Hypot(other.X-p.X, other.Y-p.Y); d < maxDist {
			maxDist, nearest = d, other
		}
	}
	return nearest
}

const infiniteNormalBot = 2

var infiniteBotTunings = [...]struct {
	name             string
	sight, roam, aim float64
}{
	{"dumb", .35, .4, 3},
	{"easy", .7, .75, 1.65},
	{"normal", 1, 1, 1},
	{"hard", 1.15, 1.15, .7},
	{"godlike", 1.3, 1.3, .45},
}

func infiniteBotLevel(name string) int {
	for level, tuning := range infiniteBotTunings {
		if name == tuning.name {
			return level
		}
	}
	return infiniteNormalBot
}

func (a *infiniteArena) botInput(p *infinitePilot) Input {
	tuning := infiniteBotTunings[p.botLevel]
	if tuning.name == "dumb" {
		return a.dumbBotInput(p, tuning.sight, tuning.roam, tuning.aim)
	}
	target := a.nearestPilot(p, cellSize*8*tuning.sight, true)
	if target != nil {
		dx, dy := target.X-p.X, target.Y-p.Y
		if !a.rayBlocked(p.X, p.Y, dx, dy, infiniteBulletRadius) {
			angle := math.Atan2(dy, dx)
			fire := !target.Protected && math.Abs(delta(p.Angle, angle)) < .12*tuning.aim
			// Alternate the AI's trigger after a grenade throw so a fresh
			// press can detonate it without cancelling the launch immediately.
			if p.kit.fireBlocked {
				fire = false
			}
			return Input{StickX: math.Cos(angle), StickY: math.Sin(angle), AimOnly: true, Fire: fire}
		}
	}
	return a.botRoam(p, target, tuning.roam)
}

func (a *infiniteArena) botRoam(p, target *infinitePilot, roam float64) Input {
	cx, cy := infiniteCell(p.X, p.Y)
	if p.hasWaypoint {
		x, y := infiniteCenter(p.waypoint[0], p.waypoint[1])
		if math.Hypot(x-p.X, y-p.Y) > 4 {
			angle := math.Atan2(y-p.Y, x-p.X)
			return Input{StickX: .72 * roam * math.Cos(angle), StickY: .72 * roam * math.Sin(angle)}
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

func (a *infiniteArena) rayWalls(x, y, dx, dy, radius float64) (RayHit, bool) {
	return a.rayWallsQuery(x, y, dx, dy, radius, false)
}

func (a *infiniteArena) rayBlocked(x, y, dx, dy, radius float64) bool {
	_, blocked := a.rayWallsQuery(x, y, dx, dy, radius, true)
	return blocked
}

func (a *infiniteArena) rayWallsQuery(x, y, dx, dy, radius float64, firstOnly bool) (RayHit, bool) {
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
		return firstOnly
	})
	return nearest, found
}

func (a *infiniteArena) rankedLeaders(entries []infiniteLeader) []infiniteLeader {
	if a.publicEntries != nil {
		return a.publicRankedLeaders(entries)
	}
	entries = entries[:0]
	for _, p := range a.pilots {
		entries = append(entries, infiniteLeader{ID: p.ID, Name: p.Name, Score: p.Score, Bot: p.Bot, Team: p.Team, ColorIndex: p.ColorIndex})
	}
	slices.SortFunc(entries, func(left, right infiniteLeader) int {
		if order := cmp.Compare(right.Score, left.Score); order != 0 {
			return order
		}
		return cmp.Compare(left.ID, right.ID)
	})
	return entries
}

func (a *infiniteArena) leaderboard(entries []infiniteLeader) []infiniteLeader {
	entries = a.rankedLeaders(entries)
	return entries[:min(len(entries), infiniteLeaderCount)]
}

func (a *infiniteArena) broadcast() {
	if a.connected == 0 {
		return
	}
	now := a.spawnNoticeTime()
	a.pruneGodlikeSpawns(now)
	packet := &a.snapshot
	packet.Tick, packet.Players, packet.TankCount = a.tick, a.connected, len(a.pilots)
	packet.Rules, packet.Result = a.rules, a.result
	if a.teams() {
		packet.Scores = &a.teamScores
	}
	leaders := a.rankedLeaders(packet.Leaders)
	packet.Leaders = leaders[:min(len(leaders), infiniteLeaderCount)]
	var tanks [infiniteCapacity + infiniteBotLimit]infiniteTank
	if a.snapshotTankIndex == nil {
		a.snapshotTankIndex = make(map[int]int, len(a.pilots))
	}
	tankIndex := a.snapshotTankIndex
	clear(tankIndex)
	for i, p := range a.pilots {
		tanks[i] = p.wireTank(a.tick)
		if a.result != nil {
			tanks[i].VX, tanks[i].VY = 0, 0
		}
		tankIndex[p.ID] = i
	}
	var parties map[infiniteRoom][]infinitePartyLeader
	for i, pilot := range a.pilots {
		if !tanks[i].Bot {
			rank := 0
			if a.publicEntries != nil {
				rank = a.publicRank(pilot)
			} else {
				for j, leader := range leaders {
					if leader.ID == pilot.ID {
						rank = j + 1
						break
					}
				}
			}
			tanks[i].Rank = rank
			if pilot.party.room != nil && pilot.party.generation != 0 && pilot.partyMember != 0 {
				if parties == nil {
					parties = make(map[infiniteRoom][]infinitePartyLeader)
				}
				parties[pilot.party] = append(parties[pilot.party], infinitePartyLeader{
					ID: pilot.ID, Member: pilot.partyMember, Name: pilot.Name, Score: pilot.Score,
					ColorIndex: pilot.ColorIndex, Rank: rank,
				})
			}
		}
	}
	// A projectile can leave a pilot's view and still occupy an ammo slot.
	// Summarize the arena once so views with identical entities share the wire.
	for _, b := range a.bullets {
		if b.dead || b.Life <= 1e-9 {
			continue
		}
		if i, ok := tankIndex[b.Owner]; ok {
			if !b.boosted {
				tanks[i].AmmoUsed++
			}
			if b.Kind == "grenade" {
				tanks[i].Grenades++
				tanks[i].GrenadeLife = max(tanks[i].GrenadeLife, infinitePrecision(b.Life))
			}
		}
		if b.Kind == "grenade" || b.Kind == "homing" {
			if i, ok := tankIndex[b.Target]; ok && infiniteOpposes(b.Owner, b.ownerTeam, a.pilots[i]) {
				tanks[i].Locked = true
			}
		}
	}
	// Pilots with the same visible entities can share the encoded snapshot.
	// The mask represents exact membership, including at the edge of sight.
	type encodedView struct{ plain, deflated snapshotFrame }
	type viewKey struct {
		mask        string
		party       infiniteRoom
		deathViewer int
	}
	views := make(map[viewKey]encodedView, a.connected)
	pickupOffset := len(a.pilots)
	effectOffset := pickupOffset + len(a.pickups)
	bulletOffset := effectOffset + len(a.effects)
	spawnOffset := bulletOffset + len(a.bullets)
	mask := make([]byte, (spawnOffset+len(a.godlikeSpawns)+7)/8)
	mark := func(index int) { mask[index/8] |= 1 << (index % 8) }
	for _, viewer := range a.pilots {
		if viewer.client == nil {
			continue
		}
		clear(mask)
		packet.Party = parties[viewer.party]
		packet.Tanks, packet.Bullets, packet.Pickups, packet.Effects = packet.Tanks[:0], packet.Bullets[:0], packet.Pickups[:0], packet.Effects[:0]
		packet.GodlikeSpawns = packet.GodlikeSpawns[:0]
		if a.rules == nil {
			for i, event := range a.godlikeSpawns {
				if viewer.nearGodlikeSpawn(event, now) {
					mark(spawnOffset + i)
					packet.GodlikeSpawns = append(packet.GodlikeSpawns, event)
				}
			}
		}
		for i, p := range a.pilots {
			if viewer.sees(p.X, p.Y) {
				mark(i)
				body := tanks[i]
				if p != viewer && p != viewer.local {
					body.KilledByColor = ""
				}
				packet.Tanks = append(packet.Tanks, body)
			}
		}
		for i, pickup := range a.pickups {
			if pickup.Life > 0 && viewer.sees(pickup.X, pickup.Y) {
				pickup.Life, pickup.Age = infinitePrecision(pickup.Life), infinitePrecision(pickup.Age)
				mark(pickupOffset + i)
				packet.Pickups = append(packet.Pickups, pickup)
			}
		}
		for i, effect := range a.effects {
			if viewer.sees(effect.X, effect.Y) {
				mark(effectOffset + i)
				packet.Effects = append(packet.Effects, effect)
			}
		}
		for i, b := range a.bullets {
			if viewer.sees(b.X, b.Y) {
				b.X, b.Y, b.VX, b.VY, b.Life = infinitePrecision(b.X), infinitePrecision(b.Y), infinitePrecision(b.VX), infinitePrecision(b.VY), infinitePrecision(b.Life)
				mark(bulletOffset + i)
				packet.Bullets = append(packet.Bullets, b)
			}
		}
		deathViewer := 0
		if viewer.KilledByColor != "" || viewer.local != nil && viewer.local.KilledByColor != "" {
			deathViewer = viewer.ID
		}
		key := viewKey{string(mask), viewer.party, deathViewer}
		view := views[key]
		if view.plain.data == nil {
			data, ok := encodePacket(packet)
			if !ok {
				continue
			}
			view.plain.data = data
		}
		frame := view.plain
		if viewer.client.supportsSnapshotDeflate() {
			if view.deflated.data == nil {
				view.deflated = compressSnapshot(view.plain.data)
			}
			frame = view.deflated
		}
		views[key] = view
		viewer.client.enqueueStateFrame(frame, false)
	}
}

func (p *infinitePilot) sees(x, y float64) bool {
	if math.Abs(x-p.X) <= infiniteSight && math.Abs(y-p.Y) <= infiniteSight {
		return true
	}
	return p.local != nil && math.Abs(x-p.local.X) <= infiniteSight && math.Abs(y-p.local.Y) <= infiniteSight
}
