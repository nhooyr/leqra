package main

import (
	"encoding/json"
	"math"
)

// Statistics belong to a participant, not a reusable tank seat. They persist
// through rounds, respawns, reconnects and spectator swaps within one match.
// The bounded ledger and frozen wire report never contain session credentials.
const maxMatchStatParticipants = 256

type PlayerMatchStats struct {
	ID            int     `json:"id"`
	Member        uint64  `json:"member"`
	Seat          int     `json:"seat"`
	Name          string  `json:"name"`
	Color         string  `json:"color"`
	Team          int     `json:"team"`
	Score         int     `json:"score"`
	Kind          string  `json:"kind"`
	Eliminations  int     `json:"eliminations"`
	Deaths        int     `json:"deaths"`
	SelfDestructs int     `json:"selfDestructs"`
	TeamKills     int     `json:"teamKills"`
	Captures      int     `json:"captures"`
	FlagReturns   int     `json:"flagReturns"`
	HillSeconds   float64 `json:"hillSeconds"`
	Active        bool    `json:"active"`
	Winner        bool    `json:"winner"`
	MixedTeams    bool    `json:"mixedTeams"`
	participant   *Player
}

type MatchReport struct {
	Mode     string             `json:"mode"`
	Duration float64            `json:"duration"` // Simulated live time; excludes countdowns and round breaks.
	Rounds   int                `json:"rounds"`
	Players  []PlayerMatchStats `json:"players"`
	Limited  bool               `json:"limited"`
}

type matchStatLedger struct {
	rows     []*PlayerMatchStats
	members  map[*Player]*PlayerMatchStats
	duration float64
	limited  bool
}

func (g *Game) resetMatchStats() {
	g.stats = &matchStatLedger{members: make(map[*Player]*PlayerMatchStats)}
	g.matchReport = nil
	g.matchReportWire = nil
}

func (g *Game) bindTankStats(t *Tank, p *Player) {
	if t == nil || p == nil || g.stats == nil || g.matchReport != nil {
		return
	}
	row := g.stats.members[p]
	if row == nil {
		if len(g.stats.rows) >= maxMatchStatParticipants {
			g.stats.limited = true
			return
		}
		kind := p.Kind
		if kind == "" {
			kind = "human"
		}
		row = &PlayerMatchStats{ID: len(g.stats.rows) + 1, Member: p.Member, Seat: t.ID, Name: p.Name, Team: t.Team, Kind: kind, participant: p}
		g.stats.members[p] = row
		g.stats.rows = append(g.stats.rows, row)
	} else if row.Team != t.Team {
		row.MixedTeams = true
	}
	row.Seat, row.Team, row.Name, row.Color = t.ID, t.Team, p.Name, t.Color
	row.Active = true
	t.stats = row
}

func (g *Game) liveStats() bool {
	return g.stats != nil && g.matchReport == nil && g.Phase == "playing"
}

// Call only after damage has passed immunity/shield checks and before clearing
// Alive. Multi-pellet hits and blast re-entry cannot count a dead tank twice.
func (g *Game) recordDeath(t *Tank, owner int) {
	if !g.liveStats() || t == nil || !t.Alive {
		return
	}
	if t.stats != nil {
		t.stats.Deaths++
	}
	if owner == t.ID {
		if t.stats != nil {
			t.stats.SelfDestructs++
		}
		return
	}
	if owner < 0 || owner >= maxTanks {
		return
	}
	shooter := g.Tanks[owner]
	if shooter == nil || shooter.stats == nil {
		return
	}
	if t.Team > 0 && shooter.Team == t.Team {
		shooter.stats.TeamKills++
	} else {
		shooter.stats.Eliminations++
	}
}

func (g *Game) recordCapture(t *Tank) {
	if g.liveStats() && !g.suddenDeath() && t != nil && t.stats != nil {
		t.stats.Captures++
	}
}
func (g *Game) recordFlagReturn(t *Tank) {
	if g.liveStats() && !g.suddenDeath() && t != nil && t.stats != nil {
		t.stats.FlagReturns++
	}
}
func (g *Game) recordHillTime(t *Tank, dt float64) {
	if g.liveStats() && !g.suddenDeath() && dt > 0 && t != nil && t.stats != nil {
		t.stats.HillSeconds += dt
	}
}

// Freeze exactly once, before publishing matchOver. Reports are self-contained;
// later renames, swaps, kicks and state snapshots cannot change a finished game.
func (g *Game) finishMatchStats(winner int) {
	if g.stats == nil || g.matchReport != nil {
		return
	}
	report := &MatchReport{Mode: g.settings().Mode, Duration: math.Round(g.stats.duration*100) / 100, Rounds: g.Round, Players: make([]PlayerMatchStats, 0, len(g.stats.rows)), Limited: g.stats.limited}
	var winning *Tank
	if winner >= 0 && winner < maxTanks {
		winning = g.Tanks[winner]
	}
	for _, row := range g.stats.rows {
		v := *row
		if row.participant != nil {
			v.Name = row.participant.Name
		}
		v.participant = nil
		v.Active = false
		v.HillSeconds = math.Round(v.HillSeconds*100) / 100
		for _, tank := range g.Tanks {
			if row.Active && tank != nil && tank.stats == row {
				v.Active = true
				v.Seat, v.Team = tank.ID, tank.Team
				v.Score = g.Scores[tank.ID]
				v.Winner = winning != nil && sideKey(tank.ID, tank.Team) == sideKey(winning.ID, winning.Team)
				break
			}
		}
		report.Players = append(report.Players, v)
	}
	g.matchReport = report
	// Reuse these immutable encoded bytes in completed-match snapshots. No report
	// is added to playing snapshots or the per-frame tank prediction payload.
	g.matchReportWire, _ = json.Marshal(report)
}
