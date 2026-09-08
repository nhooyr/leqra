package main

import (
	"fmt"
	"time"
)

// Only a wave boundary copies the bounded participant ledger. Failed attempts
// are discarded without losing statistics from earlier completed waves. Player
// pointers preserve identity through seat swaps; rows never belong to a seat.
type survivalWaveCheckpoint struct {
	wave     int
	rows     []PlayerMatchStats
	duration float64
	limited  bool
}

func (g *Game) checkpointSurvivalWave() {
	s := g.survivalState()
	if s == nil || g.stats == nil {
		return
	}
	cp := &survivalWaveCheckpoint{wave: s.Wave, duration: g.stats.duration, limited: g.stats.limited, rows: make([]PlayerMatchStats, len(g.stats.rows))}
	for i, row := range g.stats.rows {
		cp.rows[i] = *row
		for _, tank := range g.Tanks {
			if tank != nil && tank.stats == row {
				cp.rows[i].Score = g.Scores[tank.ID]
				break
			}
		}
	}
	g.survivalCheckpoint = cp
}

func (g *Game) restoreSurvivalStats() {
	cp := g.survivalCheckpoint
	g.stats = &matchStatLedger{members: make(map[*Player]*PlayerMatchStats, len(cp.rows)), duration: cp.duration, limited: cp.limited, rows: make([]*PlayerMatchStats, 0, len(cp.rows))}
	for _, saved := range cp.rows {
		row := saved
		row.Active, row.Winner = false, false
		g.stats.rows = append(g.stats.rows, &row)
		g.stats.members[row.participant] = &row
	}
	g.matchReport, g.matchReportWire = nil, nil
}

func (g *Game) survivalRestartError(players [maxTanks]*Player, generation, wave int) (string, string) {
	s := g.survivalState()
	if !g.survivalMode() || s == nil || !(s.Status == "wave" && (g.Phase == "playing" || g.Phase == "countdown") || s.Status == "lost" && g.Phase == "matchOver") {
		return "wave_unavailable", "Restart is available during a Survival wave or after losing one."
	}
	if generation != g.Generation || wave != s.Wave {
		return "stale_wave", "The wave has changed. Try again with the current wave."
	}
	if g.survivalCheckpoint == nil || g.survivalCheckpoint.wave != wave {
		return "wave_unavailable", "This wave cannot be restarted. Start a new Survival run."
	}
	if message := g.survivalLineupError(players); message != "" {
		return "not_ready", message
	}
	return "", ""
}

func (r *Room) canRestartSurvivalWave() bool {
	s := r.Game.survivalState()
	if s == nil || r.Match != nil || r.Queue != nil || r.hasAway() {
		return false
	}
	code, _ := r.Game.survivalRestartError(r.Players, r.Game.Generation, s.Wave)
	return code == ""
}

// The maze stays intact, but a fresh generation invalidates predictions, cached
// results and delayed commands from the failed attempt on every connected client.
func (g *Game) restartSurvivalWave(players [maxTanks]*Player) {
	s := g.survivalState()
	g.restoreSurvivalStats()
	g.Generation++
	g.Phase, g.PhaseTime, g.Winner = "countdown", 3, -1
	g.Round, g.Clock = s.Wave, float64(g.settings().TimeLimit)
	g.roundClinched, g.objectiveEnded = false, false
	g.SpawnClock = g.pickupDelay()
	g.events = nil
	g.Bullets, g.Pickups = []*Bullet{}, []*Pickup{}
	g.Tanks, g.Scores = [maxTanks]*Tank{}, [maxTanks]int{}
	s.Status, s.BreakTime = "wave", 0
	for id, p := range players {
		if p == nil {
			continue
		}
		tank := &Tank{ID: id, Name: p.Name, Team: p.Team, Bot: p.Kind == "bot", Difficulty: p.Difficulty, Color: selectedColor(id, p.Team, p.ColorIndex, g.settings()), R: tankRadius, X: cellSize / 2, Y: cellSize / 2}
		g.Tanks[id], g.Scores[id] = tank, s.WavesCleared
		g.bindTankStats(tank, p)
		if participantAvailable(players, id) {
			g.respawnTank(tank)
		}
		p.Ready = false
	}
	g.spawnSurvivalEnemies(players)
	g.clearSurvivalInput(players)
	g.seedPickups()
	g.emit("roundStart", nil, -1, "")
	g.emit("objective", nil, -1, fmt.Sprintf("WAVE %d RESTARTED · %d enemies", s.Wave, s.EnemiesRemaining))
}

func (h *Hub) restartSurvivalWave(c *Client, m clientMessage, now time.Time) {
	r, ok := h.editableHost(c, "restart_wave")
	if !ok {
		return
	}
	fail := func(code, message string) {
		e := roomError(code, message)
		e["action"] = "restart_wave"
		c.enqueue(e)
	}
	// handle normally applies these guards first; keep this operation safe when
	// called directly too. A travelling or queued party cannot alter its match.
	if r.Match != nil || r.Queue != nil || r.hasAway() {
		fail("match_locked", "Only private Survival matches can restart a wave.")
		return
	}
	if code, message := r.Game.survivalRestartError(r.Players, m.Generation, m.Wave); code != "" {
		fail(code, message)
		return
	}
	r.Game.restartSurvivalWave(r.Players)
	r.LastAction = now
	h.broadcastRoom(r)
	for _, p := range r.members() {
		if p.Client != nil {
			h.sendState(p.Client, r)
		}
	}
}
