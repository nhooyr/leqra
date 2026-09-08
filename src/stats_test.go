package main

import (
	"encoding/json"
	"fmt"
	"math"
	"reflect"
	"strings"
	"testing"
)

func statsBattle(mode string, count int) (*Game, [maxTanks]*Player) {
	ps := testPlayers(count)
	for i, p := range ps {
		if p != nil {
			p.Member = uint64(i + 1)
			p.Token = fmt.Sprintf("PRIVATE-TOKEN-%d", i)
		}
	}
	g := newGame(370)
	g.Rules.Mode = mode
	g.Rules.TimeLimit = 600
	g.Rules.PickupRate = "off"
	if mode == "ctf" {
		g.Rules.TeamMode = "teams"
		for i, p := range ps {
			if p != nil {
				p.Team = 1 + i%2
			}
		}
	}
	if mode == "koth" {
		g.Rules.ScoreTarget = 60
	}
	g.startMatch(ps)
	openArena(g)
	g.buildNavigation()
	g.Phase = "playing"
	for i, t := range g.Tanks {
		if t != nil {
			t.X = 60 + float64(i%4)*110
			t.Y = 60 + float64(i/4)*180
			t.Invulnerable = 0
			t.Cooldown = 999
		}
	}
	return g, ps
}
func TestMatchStatsEnemyDeathsAndDuplicateHits(t *testing.T) {
	for _, kind := range []string{"", "homing", "grenade", "laser"} {
		t.Run(kind, func(t *testing.T) {
			g, _ := statsBattle("elimination", 8)
			a, b := g.Tanks[7], g.Tanks[3]
			g.hurt(b, &Bullet{Owner: 7, Kind: kind})
			g.hurt(b, &Bullet{Owner: 7, Kind: kind})
			if a.stats.Eliminations != 1 || b.stats.Deaths != 1 || b.stats.SelfDestructs != 0 {
				t.Fatal(a.stats, b.stats)
			}
		})
	}
}
func TestMatchStatsSelfNotEnemyElimination(t *testing.T) {
	for seat := 0; seat < maxTanks; seat++ {
		t.Run(fmt.Sprint(seat), func(t *testing.T) {
			g, _ := statsBattle("ctf", 8)
			v := g.Tanks[seat]
			v.Bot = seat%2 == 1
			g.hurt(v, &Bullet{Owner: seat, Kind: "grenade"})
			if v.stats.Deaths != 1 || v.stats.SelfDestructs != 1 || v.stats.Eliminations != 0 || v.stats.TeamKills != 0 {
				t.Fatal(v.stats)
			}
		})
	}
}
func TestMatchStatsShieldsAndInvulnerability(t *testing.T) {
	g, _ := statsBattle("elimination", 3)
	a, b := g.Tanks[0], g.Tanks[1]
	b.Shield = 2
	g.hurt(b, &Bullet{Owner: 0})
	g.hurt(b, &Bullet{Owner: 0})
	if !b.Alive || b.stats.Deaths != 0 || a.stats.Eliminations != 0 {
		t.Fatal("shield counted as death")
	}
	b.Invulnerable = 0
	g.hurt(b, &Bullet{Owner: 0})
	if b.stats.Deaths != 1 || a.stats.Eliminations != 1 {
		t.Fatal("unshielded kill not counted")
	}
}
func TestMatchStatsTeamKillsSeparateFromEliminations(t *testing.T) {
	g, ps := statsBattle("elimination", 3)
	ps[0].Team = 1
	ps[1].Team = 1
	g.Tanks[0].Team = 1
	g.Tanks[1].Team = 1
	g.hurt(g.Tanks[1], &Bullet{Owner: 0})
	if g.Tanks[1].stats.Deaths != 0 {
		t.Fatal("friendly immunity ignored")
	}
	g.Rules.FriendlyFire = true
	g.hurt(g.Tanks[1], &Bullet{Owner: 0})
	if g.Tanks[0].stats.TeamKills != 1 || g.Tanks[0].stats.Eliminations != 0 || g.Tanks[1].stats.Deaths != 1 {
		t.Fatal("teamkill misclassified")
	}
}
func TestMatchStatsBlastCreditsAfterShooterDeath(t *testing.T) {
	g, _ := statsBattle("elimination", 3)
	a, b := g.Tanks[0], g.Tanks[1]
	g.Tanks[2].X, g.Tanks[2].Y = 500, 500
	a.X = 160
	a.Y = 160
	b.X = 170
	b.Y = 160
	g.detonate(&Bullet{Owner: 0, X: 160, Y: 160, Kind: "grenade"})
	if a.stats.SelfDestructs != 1 || a.stats.Eliminations != 1 || b.stats.Deaths != 1 {
		t.Fatal("blast ownership lost on shooter death", a.stats, b.stats)
	}
}
func TestMatchStatsPersistThroughRoundsAndRespawns(t *testing.T) {
	g, ps := statsBattle("elimination", 3)
	row := g.Tanks[0].stats
	g.hurt(g.Tanks[1], &Bullet{Owner: 0})
	g.Round++
	g.startRound(ps)
	if g.Tanks[0].stats != row || row.Eliminations != 1 {
		t.Fatal("round reset")
	}
	g.Phase = "playing"
	g.Tanks[0].Invulnerable = 0
	g.hurt(g.Tanks[0], &Bullet{Owner: 0})
	g.respawnTank(g.Tanks[0])
	if g.Tanks[0].stats != row || row.Deaths != 1 {
		t.Fatal("respawn reset")
	}
	g.startMatch(ps)
	if g.Tanks[0].stats == row || g.Tanks[0].stats.Eliminations != 0 || len(g.stats.rows) != 3 {
		t.Fatal("new match not clean")
	}
}
func TestMatchStatsCaptureCreditsActualCarrierIncludingWinningPoint(t *testing.T) {
	g, ps := statsBattle("ctf", 4)
	g.Rules.ScoreTarget = 1
	g.Objectives = &ObjectiveState{Mode: "ctf", Flags: []*Flag{{Team: 1, X: 100, Y: 100, HomeX: 100, HomeY: 100, Home: true, Carrier: -1}, {Team: 2, X: 100, Y: 100, HomeX: 400, HomeY: 300, Home: false, Carrier: 2}}}
	g.Tanks[2].X = 100
	g.Tanks[2].Y = 100
	g.Tanks[0].X = 240
	g.Tanks[0].Y = 100
	g.stepObjectives(tickDT, ps)
	if g.Phase != "matchOver" || g.matchReport == nil || g.matchReport.Players[2].Captures != 1 || g.matchReport.Players[0].Captures != 0 {
		t.Fatal("winning capture omitted or duplicated", g.matchReport)
	}
	if !g.matchReport.Players[0].Winner || !g.matchReport.Players[2].Winner || g.Scores[0] != 1 || g.Scores[2] != 1 {
		t.Fatal("team winners missing")
	}
}
func TestMatchStatsFlagReturnsManualOnly(t *testing.T) {
	g, ps := statsBattle("ctf", 4)
	v := g.Tanks[2]
	v.X = 100
	v.Y = 100
	f := &Flag{Team: 1, HomeX: 42, HomeY: 42, X: 100, Y: 100, Home: false, Carrier: -1, ReturnIn: 12}
	g.Objectives = &ObjectiveState{Mode: "ctf", Flags: []*Flag{f, {Team: 2, HomeX: 420, HomeY: 350, X: 420, Y: 350, Home: true, Carrier: -1}}}
	g.stepObjectives(tickDT, ps)
	g.stepObjectives(tickDT, ps)
	if v.stats.FlagReturns != 1 || g.Tanks[0].stats.FlagReturns != 0 {
		t.Fatal("manual return credit", v.stats)
	}
	f.X = 250
	f.Y = 350
	f.Home = false
	f.ReturnIn = .001
	g.stepObjectives(tickDT, ps)
	if v.stats.FlagReturns != 1 || !f.Home {
		t.Fatal("automatic return credited")
	}
}
func TestMatchStatsHillTimeEachAllyNotMultipliedScore(t *testing.T) {
	g, ps := statsBattle("koth", 4)
	for i := 0; i < 2; i++ {
		ps[i].Team = 1
		g.Tanks[i].Team = 1
	}
	g.Objectives = &ObjectiveState{Mode: "koth", HillX: 210, HillY: 210, Radius: 32, Flags: []*Flag{}}
	g.Tanks[0].X = 200
	g.Tanks[0].Y = 210
	g.Tanks[1].X = 220
	g.Tanks[1].Y = 210
	for i := 0; i < 60; i++ {
		g.stepObjectives(tickDT, ps)
	}
	for i := 0; i < 2; i++ {
		if math.Abs(g.Tanks[i].stats.HillSeconds-1) > 1e-8 || g.Scores[i] != 1 {
			t.Fatal("time or score multiplied", g.Scores, g.Tanks[i].stats)
		}
	}
	g.Tanks[2].X = 210
	g.Tanks[2].Y = 220
	g.stepObjectives(.5, ps)
	if g.Tanks[0].stats.HillSeconds > 1.000001 || g.Tanks[2].stats.HillSeconds != 0 {
		t.Fatal("contested time counted")
	}
	g.Tanks[2].X = 400
	g.Tanks[1].Invulnerable = 1
	g.stepObjectives(.5, ps)
	if math.Abs(g.Tanks[0].stats.HillSeconds-1.5) > 1e-8 || g.Tanks[1].stats.HillSeconds > 1.000001 {
		t.Fatal("spawn protection counted")
	}
}
func TestMatchStatsSuddenDeathPreservesCombatNotObjectives(t *testing.T) {
	g, ps := statsBattle("koth", 2)
	row := g.Tanks[0].stats
	row.HillSeconds = 2
	g.Clock = 0
	g.beginSuddenDeath(ps, false)
	if g.Tanks[0].stats != row {
		t.Fatal("sudden death reset ledger")
	}
	g.recordHillTime(g.Tanks[0], 10)
	g.recordCapture(g.Tanks[0])
	if row.HillSeconds != 2 || row.Captures != 0 {
		t.Fatal("sudden death objectives counted")
	}
	g.Tanks[1].Invulnerable = 0
	g.hurt(g.Tanks[1], &Bullet{Owner: 0})
	g.stepSuddenDeath(ps)
	if g.matchReport == nil || g.matchReport.Players[0].Eliminations != 1 {
		t.Fatal("sudden death kill omitted")
	}
}
func TestMatchStatsLiveTimeExcludesBreaksAndClampsDeadline(t *testing.T) {
	g, ps := statsBattle("koth", 2)
	g.Phase = "countdown"
	g.PhaseTime = 1
	g.step(.5, [maxTanks]Input{}, ps)
	if g.stats.duration != 0 {
		t.Fatal("countdown included")
	}
	g.Phase = "playing"
	g.Clock = .004
	g.Scores[0] = 1
	g.step(tickDT, [maxTanks]Input{}, ps)
	if math.Abs(g.stats.duration-.004) > 1e-10 {
		t.Fatal("live duration overshot", g.stats.duration)
	}
	if g.matchReport == nil {
		t.Fatal("deadline did not freeze")
	}
}
func TestMatchStatsSeatReuseAndReturnStayWithMember(t *testing.T) {
	g, ps := statsBattle("koth", 3)
	r := &Room{Game: g, Players: ps, Spectators: map[int]*Player{}, NextViewerID: maxTanks}
	old := ps[0]
	row := g.Tanks[0].stats
	g.hurt(g.Tanks[1], &Bullet{Owner: 0})
	r.moveMember(old, 8, true)
	if row.Deaths != 0 {
		t.Fatal("spectating counted as death")
	}
	newcomer := &Player{ID: 0, Member: 99, Name: old.Name, Client: &Client{}}
	r.Players[0] = newcomer
	r.initializeSeat(newcomer, -1)
	if g.Tanks[0].stats == row || g.Tanks[0].stats.Eliminations != 0 {
		t.Fatal("seat or duplicate name inherited stats")
	}
	r.moveMember(old, 3, false)
	r.initializeSeat(old, -1)
	if g.Tanks[3].stats != row || row.Eliminations != 1 {
		t.Fatal("return lost personal statistics")
	}
}
func TestMatchStatsEarlierParticipantRetainedNotWinner(t *testing.T) {
	g, ps := statsBattle("koth", 3)
	r := &Room{Game: g, Players: ps, Spectators: map[int]*Player{}}
	g.hurt(g.Tanks[1], &Bullet{Owner: 0})
	old := g.Tanks[0]
	r.clearCombatSeat(0)
	r.Players[0] = nil
	g.Tanks[0] = old // Expiry retains a wreck.
	g.endObjective(2)
	p := g.matchReport.Players[0]
	if p.Active || p.Winner || p.Deaths != 0 || p.Eliminations != 1 {
		t.Fatal("departed participant report", p)
	}
}
func TestMatchStatsSpectatorsNotInventedAsParticipants(t *testing.T) {
	g, ps := statsBattle("koth", 2)
	r := &Room{Game: g, Players: ps, Spectators: map[int]*Player{8: {ID: 8, Name: "WATCHER", Spectating: true}}}
	g.endObjective(0)
	if len(g.matchReport.Players) != 2 {
		t.Fatal("spectator got combat stats")
	}
	if _, ok := newHub(4).stateMessage(r)["matchStats"]; !ok {
		t.Fatal("spectators cannot receive report")
	}
}
func TestMatchStatsSnapshotOnlyAtEndAndNoCredentials(t *testing.T) {
	g, ps := statsBattle("koth", 2)
	r := &Room{Game: g, Players: ps}
	h := newHub(4)
	live := h.stateMessage(r)
	if _, ok := live["matchStats"]; ok {
		t.Fatal("hot snapshot bloated")
	}
	g.hurt(g.Tanks[1], &Bullet{Owner: 0})
	g.endObjective(0)
	raw, _ := json.Marshal(h.stateMessage(r))
	var s map[string]json.RawMessage
	json.Unmarshal(raw, &s)
	var report MatchReport
	if err := json.Unmarshal(s["matchStats"], &report); err != nil || len(report.Players) != 2 {
		t.Fatal("invalid report", err)
	}
	if strings.Contains(string(raw), "PRIVATE-TOKEN") || strings.Contains(string(raw), "participant") || strings.Contains(string(raw), "statsRow") {
		t.Fatal("private state serialized")
	}
	if report.Players[0].Eliminations != 1 {
		t.Fatal("report not authoritative")
	}
}
func TestMatchStatsFrozenAfterRenameRoleAndDamage(t *testing.T) {
	g, ps := statsBattle("koth", 3)
	ps[0].Name = "RENAMED"
	g.hurt(g.Tanks[1], &Bullet{Owner: 0})
	g.endObjective(0)
	before := string(g.matchReportWire)
	snapshot := *g.matchReport
	ps[0].Name = "LATER"
	g.Tanks[0].stats.Eliminations = 999
	g.Phase = "playing"
	g.hurt(g.Tanks[2], &Bullet{Owner: 0})
	g.finishMatchStats(2)
	if before != string(g.matchReportWire) || !reflect.DeepEqual(snapshot, *g.matchReport) || g.matchReport.Players[0].Name != "RENAMED" {
		t.Fatal("finished report mutated")
	}
}
func TestMatchStatsEliminationReportIncludesAllRounds(t *testing.T) {
	g, ps := statsBattle("elimination", 3)
	g.Rules.ScoreTarget = 2
	for n := 0; n < 2; n++ {
		g.Phase = "playing"
		for _, v := range g.Tanks {
			if v != nil {
				v.Invulnerable = 0
			}
		}
		g.hurt(g.Tanks[1], &Bullet{Owner: 0})
		g.hurt(g.Tanks[2], &Bullet{Owner: 0})
		g.finishRound(0)
		g.PhaseTime = 0
		g.step(tickDT, [maxTanks]Input{}, ps)
	}
	if g.matchReport == nil || g.matchReport.Rounds != 2 || g.matchReport.Players[0].Eliminations != 4 || g.matchReport.Players[1].Deaths != 2 {
		t.Fatal("not whole-match results", g.matchReport)
	}
}
func TestMatchStatsBoundedMembershipChurn(t *testing.T) {
	g, _ := statsBattle("koth", 2)
	for i := 0; i < 300; i++ {
		p := &Player{ID: 7, Member: uint64(i + 50), Name: "GUEST"}
		g.bindTankStats(&Tank{ID: 7}, p)
	}
	if len(g.stats.rows) != maxMatchStatParticipants || !g.stats.limited {
		t.Fatal("unbounded stats")
	}
	g.endObjective(0)
	if !g.matchReport.Limited {
		t.Fatal("missing truncation notice")
	}
}

func TestMatchStatsCannotBeForgedByInputs(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	r.Game.startMatch(r.Players)
	r.Game.Phase = "playing"
	action(t, h, cs[0], map[string]any{"type": "input", "seq": 1, "fire": false, "matchStats": map[string]any{"eliminations": 9999}, "captures": 99, "deaths": 0, "winner": 0})
	if r.Game.Tanks[0].stats.Eliminations != 0 || r.Game.Tanks[0].stats.Captures != 0 || r.Game.matchReport != nil {
		t.Fatal("input forged stats")
	}
}
