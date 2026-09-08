package main

import (
	"fmt"
	"math"
)

const survivalMaxPlayers = 4
const survivalBreakSeconds = roundEndSeconds

// Wave enemies are simulation entities, never authenticated room members. Their
// slots cannot be claimed by joins, role changes or client-supplied inputs.
type SurvivalState struct {
	Wave             int     `json:"wave"`
	WavesCleared     int     `json:"wavesCleared"`
	WaveTarget       int     `json:"waveTarget"`
	EnemiesRemaining int     `json:"enemiesRemaining"`
	Boss             bool    `json:"boss"`
	BreakTime        float64 `json:"breakTime"`
	Status           string  `json:"status"`
}

func (g *Game) survivalMode() bool { return g.settings().Mode == "survival" }
func (g *Game) survivalState() *SurvivalState {
	if g.Objectives != nil && g.Objectives.Mode == "survival" {
		return g.Objectives.Survival
	}
	return nil
}
func (r *Room) survivalRunning() bool {
	return r.Game.survivalMode() && r.Game.Phase != "lobby" && r.Game.Phase != "matchOver"
}
func (r *Room) combatCapacity() int {
	if r.Game.survivalMode() {
		return survivalMaxPlayers
	}
	return maxTanks
}
func participantCount(players [maxTanks]*Player) int {
	n := 0
	for _, p := range players {
		if p != nil {
			n++
		}
	}
	return n
}
func survivalParticipantPresent(players [maxTanks]*Player) bool {
	for id, p := range players {
		if p != nil && participantAvailable(players, id) {
			return true
		}
	}
	return false
}
func (g *Game) survivalLineupError(players [maxTanks]*Player) string {
	if participantCount(players) > survivalMaxPlayers {
		return "Survival supports up to four allied tanks. Remove extra tanks or move players to Spectators."
	}
	if !survivalParticipantPresent(players) {
		return "Survival needs at least one available squad tank."
	}
	for _, p := range players {
		if p != nil && p.Team != 1 {
			return "Survival players share Team 1."
		}
	}
	return ""
}
func (g *Game) clearSurvivalInput(players [maxTanks]*Player) {
	for id, p := range players {
		if p != nil {
			p.Input = Input{Seq: p.Input.Seq}
			p.FirePending = false
		}
		if t := g.Tanks[id]; t != nil {
			t.VX, t.VY = 0, 0
			t.fireHeld, t.fireBlocked = false, false
		}
	}
}

func survivalDifficulty(wave int) string {
	if wave <= 5 {
		return "easy"
	}
	if wave <= 10 {
		return "normal"
	}
	if wave <= 15 {
		return "hard"
	}
	return "godlike"
}

// A new skill tier first appears as the preceding five-wave block's boss.
func survivalBossDifficulty(wave int) string { return survivalDifficulty(wave + 1) }

func survivalBossName(wave int) string {
	switch survivalBossDifficulty(wave) {
	case "normal":
		return "NORMAL BOSS"
	case "hard":
		return "FIERCE BOSS"
	default:
		return "GODLIKE BOSS"
	}
}

// Maximize the distance to the nearest live tank, rather than accepting the
// first nominally empty cell. A full scan is bounded by the largest 336-cell map
// and happens only once per enemy at a wave boundary.
func (g *Game) survivalEnemySpawn(t *Tank) {
	best, bestCell := math.Inf(-1), 0
	for cell := 0; cell < g.World.Cols*g.World.Rows; cell++ {
		x, y := g.cellCenter(cell)
		clearance := math.Inf(1)
		for _, other := range g.Tanks {
			if other != nil && other != t && other.Alive {
				clearance = math.Min(clearance, dist(x, y, other.X, other.Y)-t.R-other.R)
			}
		}
		if clearance > best {
			best, bestCell = clearance, cell
		}
	}
	t.X, t.Y = g.cellCenter(bestCell)
}

func (g *Game) survivalBossPower(t *Tank, wave int) {
	rules := g.settings()
	if rules.PickupRate == "off" {
		return
	}
	enabled := func(kind string) bool {
		for _, w := range rules.Weapons {
			if w == kind {
				return true
			}
		}
		return false
	}
	strength := min(3, max(1, wave/5))
	if enabled("shield") {
		for i := 0; i < strength; i++ {
			g.grantPower(t, "shield")
		}
	}
	if strength >= 2 && enabled("speed") {
		g.grantPower(t, "speed")
	}
	weapons := []string{"homing", "cannon", "laser"}
	for i := 0; i < len(weapons); i++ {
		w := weapons[(wave/5-1+i)%len(weapons)]
		if enabled(w) {
			g.grantPower(t, w)
			break
		}
	}
}

func (g *Game) spawnSurvivalEnemies(players [maxTanks]*Player) {
	s := g.survivalState()
	if s == nil {
		return
	}
	count := min(4, 2+(s.Wave-1)/2)
	s.Boss = s.Wave%5 == 0
	if s.Boss {
		// Boss-wave protection is a squad starting bonus, independent of which
		// pickups are enabled. Keep any stronger shield already on the tank.
		for id, p := range players {
			tank := g.Tanks[id]
			if p != nil && participantAvailable(players, id) && tank != nil && tank.Alive && !tank.SurvivalEnemy && shieldCount(tank) == 0 {
				g.grantPower(tank, "shield")
			}
		}
	}
	s.EnemiesRemaining = 0
	for id, p := range players {
		if p != nil || s.EnemiesRemaining >= count {
			continue
		}
		boss := s.Boss && s.EnemiesRemaining == 0
		name, difficulty := fmt.Sprintf("RAIDER %d", s.EnemiesRemaining+1), survivalDifficulty(s.Wave)
		if boss {
			name, difficulty = survivalBossName(s.Wave), survivalBossDifficulty(s.Wave)
		}
		t := &Tank{ID: id, Name: name, Team: 2, Color: selectedColor(id, 2, nil, g.settings()), Bot: true, Difficulty: difficulty, SurvivalEnemy: true, SurvivalBoss: boss, R: tankRadius, Alive: true, Angle: -math.Pi / 2, Invulnerable: 1.2, SpawnSerial: s.Wave}
		g.Tanks[id] = t
		g.Scores[id] = 0
		g.survivalEnemySpawn(t)
		if boss {
			g.survivalBossPower(t, s.Wave)
		}
		s.EnemiesRemaining++
	}
}

func (g *Game) nextSurvivalWave(players [maxTanks]*Player) {
	s := g.survivalState()
	s.Wave++
	s.Status, s.BreakTime = "wave", 0
	g.Round = s.Wave
	g.Clock, g.PhaseTime = float64(g.settings().TimeLimit), .55
	g.SpawnClock = g.pickupDelay()
	g.Bullets, g.Pickups = []*Bullet{}, []*Pickup{}
	for id, t := range g.Tanks {
		if t == nil {
			continue
		}
		if t.SurvivalEnemy || players[id] == nil {
			g.Tanks[id] = nil
			continue
		}
		t.Alive = false
	}
	for id, t := range g.Tanks {
		if t != nil && participantAvailable(players, id) {
			g.respawnTank(t)
		}
	}
	g.spawnSurvivalEnemies(players)
	g.clearSurvivalInput(players)
	g.seedPickups()
	g.checkpointSurvivalWave()
	g.emit("objective", nil, -1, fmt.Sprintf("WAVE %d · %d enemies", s.Wave, s.EnemiesRemaining))
}

func (g *Game) endSurvival(players [maxTanks]*Player, won bool) {
	s := g.survivalState()
	if s == nil || s.Status == "won" || s.Status == "lost" {
		return
	}
	winner, message := -1, "SURVIVAL ENDED"
	s.Status, s.BreakTime = "lost", 0
	if won {
		s.Status, message = "won", "SURVIVAL COMPLETE"
		for id, p := range players {
			if p != nil && g.Tanks[id] != nil {
				winner = id
				break
			}
		}
	}
	g.finishMatchStats(winner)
	g.Winner, g.Phase, g.PhaseTime = winner, "matchOver", 0
	g.Bullets, g.Pickups = []*Bullet{}, []*Pickup{}
	g.clearSurvivalInput(players)
	g.emit("matchEnd", nil, winner, message)
}

// Returns true when the wave boundary consumed this step. Disconnects remove
// the current life; reconnecting can restore it only at the next wave. A squad
// can be entirely bots, but an empty or unavailable squad cannot continue.
func (g *Game) prepareSurvival(dt float64, players [maxTanks]*Player) bool {
	s := g.survivalState()
	if s == nil {
		return false
	}
	for id, t := range g.Tanks {
		if t != nil && !t.SurvivalEnemy && !participantAvailable(players, id) {
			t.Alive = false
			t.RespawnTime = 0
			t.VX, t.VY = 0, 0
		}
	}
	if !survivalParticipantPresent(players) {
		g.endSurvival(players, false)
		return true
	}
	if s.Status == "break" {
		g.clearSurvivalInput(players)
		s.BreakTime = math.Max(0, s.BreakTime-dt)
		if s.BreakTime <= 1e-9 {
			s.BreakTime = 0
			g.nextSurvivalWave(players)
		}
		return true
	}
	return false
}

func (g *Game) stepSurvival(players [maxTanks]*Player) {
	s := g.survivalState()
	if s == nil || s.Status != "wave" {
		return
	}
	allies := 0
	s.EnemiesRemaining = 0
	s.Boss = false
	for id, t := range g.Tanks {
		if t == nil || !t.Alive {
			continue
		}
		if t.SurvivalEnemy {
			s.EnemiesRemaining++
			s.Boss = s.Boss || t.SurvivalBoss
		} else if participantAvailable(players, id) {
			allies++
		}
	}
	// Mutual destruction is a loss; clearing a wave requires a surviving ally.
	if allies == 0 {
		g.endSurvival(players, false)
		return
	}
	if s.EnemiesRemaining == 0 {
		s.WavesCleared++
		for id, t := range g.Tanks {
			if t != nil && !t.SurvivalEnemy && players[id] != nil {
				g.Scores[id] = s.WavesCleared
			}
		}
		if s.WavesCleared >= s.WaveTarget {
			g.endSurvival(players, true)
			return
		}
		s.Status, s.BreakTime = "break", survivalBreakSeconds
		g.Bullets, g.Pickups = []*Bullet{}, []*Pickup{}
		g.clearSurvivalInput(players)
		g.emit("objective", nil, -1, fmt.Sprintf("WAVE %d CLEAR · squad revives in %gs", s.Wave, float64(survivalBreakSeconds)))
	} else if g.Clock <= 0 {
		g.endSurvival(players, false)
	}
}

// Read-only snapshots must not alias live wave counters or flag state.
func snapshotObjectives(o *ObjectiveState) *ObjectiveState {
	if o == nil {
		return nil
	}
	v := *o
	v.Flags = make([]*Flag, len(o.Flags))
	for i, f := range o.Flags {
		if f != nil {
			copyFlag := *f
			v.Flags[i] = &copyFlag
		}
	}
	if o.Survival != nil {
		s := *o.Survival
		v.Survival = &s
	}
	return &v
}
