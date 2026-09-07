package main

import (
	"encoding/json"
	"math"
	"testing"
	"time"
)

func objectiveFixture(mode string) (*Game, [maxTanks]*Player) {
	ps := [maxTanks]*Player{{ID: 0, Name: "A", Team: 1, Client: fakeClient()}, {ID: 1, Name: "B", Team: 2, Client: fakeClient()}, {ID: 2, Name: "ALLY", Team: 1, Client: fakeClient()}}
	g := newGame(32)
	g.Rules.Mode = mode
	g.Rules.TeamMode = "teams"
	g.Rules.ScoreTarget = 3
	g.Rules.TimeLimit = 180
	g.startMatch(ps)
	// Open, bounded fixture only. Production maps retain their generated walls.
	g.World.Walls = []Wall{{-4, -4, g.World.Width + 8, 8, "h", 0}, {-4, g.World.Height - 4, g.World.Width + 8, 8, "h", g.World.Height}, {-4, -4, 8, g.World.Height + 8, "v", 0}, {g.World.Width - 4, -4, 8, g.World.Height + 8, "v", g.World.Width}}
	g.buildNavigation()
	g.Phase = "playing"
	g.PhaseTime = 0
	g.Pickups = nil
	g.SpawnClock = 999
	for _, t := range g.Tanks {
		if t != nil {
			t.Invulnerable = 0
			t.X = 250 + float64(t.ID)*100
			t.Y = 250
			t.Cooldown = 999
		}
	}
	return g, ps
}
func TestRules32Validation(t *testing.T) {
	mutations := []struct {
		name string
		mut  func(*MatchRules)
	}{
		{"mode", func(r *MatchRules) { r.Mode = "hack" }}, {"format", func(r *MatchRules) { r.TeamMode = "mixed" }}, {"ctf ffa", func(r *MatchRules) { r.Mode = "ctf"; r.TeamMode = "ffa" }}, {"map", func(r *MatchRules) { r.MapSize = "enormous" }},
		{"low score", func(r *MatchRules) { r.ScoreTarget = 0 }}, {"high score", func(r *MatchRules) { r.ScoreTarget = 21 }}, {"hill score", func(r *MatchRules) { r.Mode = "koth"; r.ScoreTarget = 301 }},
		{"short timer", func(r *MatchRules) { r.TimeLimit = 29 }}, {"long timer", func(r *MatchRules) { r.TimeLimit = 601 }}, {"short respawn", func(r *MatchRules) { r.RespawnSeconds = 0 }}, {"long respawn", func(r *MatchRules) { r.RespawnSeconds = 11 }},
		{"frequency", func(r *MatchRules) { r.PickupRate = "flood" }}, {"unknown weapon", func(r *MatchRules) { r.Weapons = []string{"cheat"} }}, {"duplicate", func(r *MatchRules) { r.Weapons = []string{"laser", "laser"} }},
	}
	for _, tc := range mutations {
		t.Run(tc.name, func(t *testing.T) {
			r := legacyTeamRules36()
			tc.mut(&r)
			if validateRules(r) == nil {
				t.Fatal("accepted invalid rules")
			}
		})
	}
	for _, mode := range []string{"elimination", "ctf", "koth"} {
		r := legacyTeamRules36()
		r.Mode = mode
		r.TeamMode = "teams"
		r.Weapons = []string{}
		if e := validateRules(r); e != nil {
			t.Fatal(e)
		}
	}
}
func TestRules32GuestCannotChange(t *testing.T) {
	for _, kind := range []string{"rules", "preset"} {
		h, cs, r := makeRoom(t, 2)
		rules := legacyTeamRules36()
		rules.TeamMode = "ffa"
		action(t, h, cs[1], map[string]any{"type": kind, "rules": rules, "roster": []SeatSpec{{Name: "A", Kind: "human", Difficulty: "", Team: 0}}})
		if !hasError(cs[1], "not_host") || r.Game.Rules.TeamMode == "ffa" {
			t.Fatal("guest changed host rules")
		}
	}
}
func TestRules32FFAForcesAndLocksTeams(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	rules := legacyTeamRules36()
	rules.TeamMode = "ffa"
	r.Players[1].Ready = true
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	for _, p := range r.Players {
		if p != nil && (p.Team != 0 || p.Ready) {
			t.Fatal("format/readiness not enforced")
		}
	}
	action(t, h, cs[0], map[string]any{"type": "configure", "target": 1, "member": r.Players[1].Member, "team": 2})
	if !hasError(cs[0], "teams_locked") || r.Players[1].Team != 0 {
		t.Fatal("FFA changed via roster")
	}
	action(t, h, cs[0], map[string]any{"type": "add", "kind": "bot", "difficulty": "hard", "team": 3})
	if !hasError(cs[0], "teams_locked") || r.Players[2] != nil {
		t.Fatal("FFA bypass via bot")
	}
	guest := fakeClient()
	action(t, h, guest, map[string]any{"type": "join", "code": r.Code, "name": "new"})
	if guest.player.Team != 0 {
		t.Fatal("join bypassed FFA")
	}
}
func TestRules32ReturnToTeams(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	rules := legacyTeamRules36()
	rules.TeamMode = "ffa"
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	rules.TeamMode = "teams"
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	if r.Players[0].Team != 1 || r.Players[1].Team != 2 {
		t.Fatal("no team defaults")
	}
}
func TestRules32ImmutableDuringMatch(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	r.Game.startMatch(r.Players)
	rules := legacyTeamRules36()
	rules.ScoreTarget = 17
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	if !hasError(cs[0], "match_active") || r.Game.Rules.ScoreTarget == 17 {
		t.Fatal("live rules changed")
	}
}
func TestRules32HostHandoff(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	h.removeClient(cs[0])
	rules := legacyTeamRules36()
	rules.ScoreTarget = 8
	action(t, h, cs[1], map[string]any{"type": "rules", "rules": rules})
	if r.Game.Rules.ScoreTarget != 8 {
		t.Fatal("new host cannot configure")
	}
}
func TestRules32RejectAtomically(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	rules := legacyTeamRules36()
	rules.ScoreTarget = 99
	rules.TeamMode = "ffa"
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	if !hasError(cs[0], "bad_rules") || r.Game.Rules.TeamMode == "ffa" || r.Players[0].Team != 1 {
		t.Fatal("partial invalid rule update")
	}
}
func TestRules32SnapshotAndRoom(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	rules := legacyTeamRules36()
	rules.Mode = "koth"
	rules.ScoreTarget = 60
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	rm := h.roomMessage(r)
	if rm["rules"].(MatchRules).Mode != "koth" {
		t.Fatal("rules absent from roster")
	}
	r.Game.startMatch(r.Players)
	h.sendState(cs[0], r)
	select {
	case raw := <-cs[0].updates:
		var m map[string]any
		_ = json.Unmarshal(raw, &m)
		if m["objectives"] == nil || m["rules"] == nil {
			t.Fatal("objectives absent from state")
		}
	default: // First map snapshots are reliable.
		found := false
		for len(cs[0].send) > 0 {
			raw := <-cs[0].send
			var m map[string]any
			_ = json.Unmarshal(raw, &m)
			if m["type"] == "state" && m["objectives"] != nil {
				found = true
			}
		}
		if !found {
			t.Fatal("no objective snapshot")
		}
	}
}
func TestRules32MapSizes(t *testing.T) {
	for _, size := range []string{"compact", "standard", "large"} {
		g := newGame(11)
		g.Rules.MapSize = size
		ps := [maxTanks]*Player{{ID: 0, Client: fakeClient()}, {ID: 1, Client: fakeClient()}}
		g.startMatch(ps)
		c, r := g.mapDimensions()
		if g.World.Cols != c || g.World.Rows != r {
			t.Fatal("wrong dimensions")
		}
		for _, x := range g.Tanks {
			if x != nil && (x.X < 0 || x.X > g.World.Width || x.Y < 0 || x.Y > g.World.Height) {
				t.Fatal("spawn outside map")
			}
		}
		if len(g.Neighbors) != c*r {
			t.Fatal("missing navigation")
		}
	}
}
func TestRules32PickupOffAndFilter(t *testing.T) {
	g := newGame(1)
	g.makeMaze(9, 8)
	g.Rules.PickupRate = "off"
	g.spawnPower()
	if len(g.Pickups) > 0 {
		t.Fatal("off spawned")
	}
	g.Rules.PickupRate = "fast"
	g.Rules.Weapons = []string{}
	g.spawnPower()
	if len(g.Pickups) > 0 {
		t.Fatal("empty spawned")
	}
	g.Rules.Weapons = []string{"laser"}
	for i := 0; i < 40; i++ {
		g.Pickups = nil
		g.spawnPower()
		if len(g.Pickups) == 0 || g.Pickups[0].Type != "laser" {
			t.Fatal("filter failed")
		}
	}
}
func TestRules32PickupIntervals(t *testing.T) {
	for _, v := range []struct {
		name   string
		lo, hi float64
	}{{"superfast", 1, 2}, {"fast", 2, 3.5}, {"normal", 4, 6}, {"slow", 7, 10}} {
		g := newGame(1)
		g.Rules.PickupRate = v.name
		lo, hi := g.pickupInterval()
		if lo != v.lo || hi != v.hi || g.pickupDelay() != v.lo {
			t.Fatal("interval mismatch")
		}
	}
}
func TestRules32ScoreTarget(t *testing.T) {
	g := newGame(1)
	g.Rules.ScoreTarget = 2
	ps := [maxTanks]*Player{{ID: 0, Team: 1, Client: fakeClient()}, {ID: 1, Team: 2, Client: fakeClient()}}
	g.startMatch(ps)
	g.Scores[0] = 1
	g.Phase = "playing"
	g.finishRound(0)
	g.PhaseTime = 0
	g.step(tickDT, [maxTanks]Input{}, ps)
	if g.Phase != "matchOver" || g.Scores[0] != 2 {
		t.Fatal("score target ignored")
	}
}
func TestRules32ConfiguredClock(t *testing.T) {
	g := newGame(1)
	g.Rules.TimeLimit = 240
	g.startMatch([maxTanks]*Player{})
	if g.Clock != 240 {
		t.Fatal("clock not configured")
	}
}
func TestRules32CTFStartValidation(t *testing.T) {
	g, ps := objectiveFixture("ctf")
	if g.lineupError(ps) != "" {
		t.Fatal("valid teams blocked")
	}
	ps[2].Team = 3
	if g.lineupError(ps) == "" {
		t.Fatal("third team accepted")
	}
	ps[2].Team = 0
	if g.lineupError(ps) == "" {
		t.Fatal("unassigned CTF accepted")
	}
}
func TestObjective32StealAndCapture(t *testing.T) {
	g, ps := objectiveFixture("ctf")
	t0 := g.Tanks[0]
	own, enemy := g.Objectives.Flags[0], g.Objectives.Flags[1]
	t0.X = enemy.X
	t0.Y = enemy.Y
	g.stepObjectives(tickDT, ps)
	if enemy.Carrier != 0 || enemy.Home {
		t.Fatal("flag not stolen")
	}
	t0.X = own.HomeX
	t0.Y = own.HomeY
	g.stepObjectives(tickDT, ps)
	if g.Scores[0] != 1 || g.Scores[2] != 1 || !enemy.Home || g.Phase != "playing" {
		t.Fatal("capture/team scoring failed")
	}
}
func TestObjective32OwnFlagMustBeHome(t *testing.T) {
	g, ps := objectiveFixture("ctf")
	own, enemy := g.Objectives.Flags[0], g.Objectives.Flags[1]
	own.Home = false
	own.X = 500
	own.Y = 500
	own.ReturnIn = 10
	enemy.Carrier = 0
	enemy.Home = false
	t0 := g.Tanks[0]
	t0.X = own.HomeX
	t0.Y = own.HomeY
	g.stepObjectives(.01, ps)
	if g.Scores[0] != 0 || enemy.Carrier != 0 {
		t.Fatal("capture without own flag")
	}
}
func TestObjective32FriendlyReturn(t *testing.T) {
	g, ps := objectiveFixture("ctf")
	f := g.Objectives.Flags[0]
	f.Home = false
	f.X = 350
	f.Y = 400
	f.ReturnIn = 10
	g.Tanks[2].X = f.X
	g.Tanks[2].Y = f.Y
	g.stepObjectives(.01, ps)
	if !f.Home || g.Scores[2] != 0 {
		t.Fatal("friendly flag not returned")
	}
}
func TestObjective32FlagAutoReturn(t *testing.T) {
	g, ps := objectiveFixture("ctf")
	f := g.Objectives.Flags[0]
	f.Home = false
	f.ReturnIn = .02
	f.X = 600
	f.Y = 600
	g.stepObjectives(.03, ps)
	if !f.Home || f.X != f.HomeX {
		t.Fatal("flag not auto returned")
	}
}
func TestObjective32DeathDropsFlag(t *testing.T) {
	g, _ := objectiveFixture("ctf")
	f := g.Objectives.Flags[1]
	f.Home = false
	f.Carrier = 0
	g.hurt(g.Tanks[0], &Bullet{Owner: 1})
	if f.Carrier != -1 || f.Home || f.ReturnIn != 12 || g.Tanks[0].RespawnTime != 3 {
		t.Fatal("death/drop state wrong")
	}
}
func TestObjective32KickDropsFlag(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	r.Game.Rules.Mode = "ctf"
	r.Game.startMatch(r.Players)
	f := r.Game.Objectives.Flags[0]
	f.Home = false
	f.Carrier = 1
	h.kick(cs[0], intPtr32(1), r.Players[1].Member, time.Now())
	if f.Carrier != -1 {
		t.Fatal("kick left a ghost carrier")
	}
}
func intPtr32(v int) *int { return &v }
func TestObjective32SpawnProtectionNoCapture(t *testing.T) {
	g, ps := objectiveFixture("ctf")
	f := g.Objectives.Flags[1]
	g.Tanks[0].X = f.X
	g.Tanks[0].Y = f.Y
	g.Tanks[0].Invulnerable = 1
	g.stepObjectives(.1, ps)
	if f.Carrier != -1 {
		t.Fatal("protected pilot picked flag")
	}
}
func TestObjective32CaptureEndsWithoutBonus(t *testing.T) {
	g, ps := objectiveFixture("ctf")
	g.Rules.ScoreTarget = 1
	own, enemy := g.Objectives.Flags[0], g.Objectives.Flags[1]
	enemy.Carrier = 0
	enemy.Home = false
	g.Tanks[0].X = own.X
	g.Tanks[0].Y = own.Y
	g.stepObjectives(.01, ps)
	if g.Phase != "matchOver" || g.Winner != 0 || g.Scores[0] != 1 || g.Scores[2] != 1 {
		t.Fatal("bad objective ending/bonus")
	}
}
func TestObjective32HillOnePointPerSecond(t *testing.T) {
	g, ps := objectiveFixture("koth")
	o := g.Objectives
	g.Tanks[0].X = o.HillX
	g.Tanks[0].Y = o.HillY
	g.stepObjectives(.6, ps)
	if g.Scores[0] != 0 {
		t.Fatal("early hill score")
	}
	g.stepObjectives(.4, ps)
	if g.Scores[0] != 1 || g.Scores[2] != 1 || math.Abs(o.Hold) > 1e-7 {
		t.Fatal("hill/team score")
	}
}
func TestObjective32HillContested(t *testing.T) {
	g, ps := objectiveFixture("koth")
	o := g.Objectives
	for i := 0; i < 2; i++ {
		g.Tanks[i].X = o.HillX
		g.Tanks[i].Y = o.HillY
	}
	g.stepObjectives(2, ps)
	if !o.Contested || g.Scores[0] != 0 || g.Scores[1] != 0 || o.Owner != 0 {
		t.Fatal("contested scored")
	}
}
func TestObjective32HillAlliesDontContest(t *testing.T) {
	g, ps := objectiveFixture("koth")
	o := g.Objectives
	for _, i := range []int{0, 2} {
		g.Tanks[i].X = o.HillX
		g.Tanks[i].Y = o.HillY
	}
	g.stepObjectives(1, ps)
	if o.Contested || g.Scores[0] != 1 || g.Scores[2] != 1 {
		t.Fatal("allies contested or double counted")
	}
}
func TestObjective32HillFFAContest(t *testing.T) {
	g, ps := objectiveFixture("koth")
	o := g.Objectives
	for i := 0; i < 2; i++ {
		g.Tanks[i].Team = 0
		ps[i].Team = 0
		g.Tanks[i].X = o.HillX
		g.Tanks[i].Y = o.HillY
	}
	g.stepObjectives(1, ps)
	if !o.Contested {
		t.Fatal("FFA treated as team")
	}
}
func TestObjective32HillProtectionAndWalls(t *testing.T) {
	g, ps := objectiveFixture("koth")
	o := g.Objectives
	g.Tanks[0].X = o.HillX
	g.Tanks[0].Y = o.HillY
	g.Tanks[0].Invulnerable = .5
	g.stepObjectives(1, ps)
	if g.Scores[0] != 0 {
		t.Fatal("protected scored")
	}
	g.Tanks[0].Invulnerable = 0
	g.Tanks[0].X = o.HillX + 25
	g.World.Walls = append(g.World.Walls, Wall{o.HillX + 12, o.HillY - 50, 8, 100, "v", o.HillX + 16})
	g.stepObjectives(1, ps)
	if g.Scores[0] != 0 {
		t.Fatal("scored across wall")
	}
}
func TestObjective32HillOwnershipResetsProgress(t *testing.T) {
	g, ps := objectiveFixture("koth")
	o := g.Objectives
	g.Tanks[0].X = o.HillX
	g.Tanks[0].Y = o.HillY
	g.stepObjectives(.8, ps)
	g.Tanks[0].X = 100
	g.Tanks[1].X = o.HillX
	g.Tanks[1].Y = o.HillY
	g.stepObjectives(.3, ps)
	if g.Scores[1] != 0 || math.Abs(o.Hold-.3) > .001 {
		t.Fatal("stole partial point")
	}
}
func TestObjective32TimedLeaderAndTie(t *testing.T) {
	for _, tie := range []bool{true, false} {
		g, ps := objectiveFixture("koth")
		g.Clock = 0
		if !tie {
			g.Scores[0] = 2
			g.Scores[2] = 2
		}
		g.stepObjectives(.01, ps)
		if tie {
			if g.Phase != "playing" || !g.suddenDeath() {
				t.Fatal("tied objective must enter sudden death")
			}
		} else if g.Phase != "matchOver" || g.Winner != 0 {
			t.Fatal("unique timed leader should win")
		}
	}
}
func TestObjective32RespawnResetsPowers(t *testing.T) {
	g, ps := objectiveFixture("ctf")
	t0 := g.Tanks[0]
	g.grantPower(t0, "grenade")
	t0.SpeedTime = 4
	g.hurt(t0, &Bullet{Owner: 1})
	g.respawnPlayers(2.9, ps)
	if t0.Alive {
		t.Fatal("early respawn")
	}
	old := t0.SpawnSerial
	g.respawnPlayers(.11, ps)
	if !t0.Alive || t0.Power != "" || t0.SpeedTime != 0 || t0.SpawnSerial != old+1 || t0.Invulnerable <= 0 {
		t.Fatal("respawn state")
	}
}
func TestObjective32DisconnectedCannotRespawn(t *testing.T) {
	g, ps := objectiveFixture("ctf")
	g.Tanks[0].Alive = false
	g.Tanks[0].RespawnTime = 0
	ps[0].Client = nil
	g.respawnPlayers(5, ps)
	if g.Tanks[0].Alive {
		t.Fatal("disconnected respawned")
	}
}
func TestObjective32DeadTeamsDontEndMatch(t *testing.T) {
	g, ps := objectiveFixture("ctf")
	for _, x := range g.Tanks {
		if x != nil {
			x.Alive = false
			x.RespawnTime = 3
		}
	}
	g.stepObjectives(.1, ps)
	if g.Phase != "playing" {
		t.Fatal("all dead prematurely ended objective")
	}
}
func TestObjective32RespawnAvoidsOccupiedBase(t *testing.T) {
	g, _ := objectiveFixture("ctf")
	own := g.Objectives.Flags[0]
	g.Tanks[2].X = own.HomeX
	g.Tanks[2].Y = own.HomeY
	g.respawnTank(g.Tanks[0])
	if dist(g.Tanks[0].X, g.Tanks[0].Y, g.Tanks[2].X, g.Tanks[2].Y) < tankRadius*2 {
		t.Fatal("respawn overlapped ally")
	}
}
func TestObjective32BotGoals(t *testing.T) {
	g, _ := objectiveFixture("ctf")
	t0 := g.Tanks[0]
	own, enemy := g.Objectives.Flags[0], g.Objectives.Flags[1]
	x, y, ok := g.objectiveGoal(t0)
	if !ok || x != enemy.X || y != enemy.Y {
		t.Fatal("bot not pursuing flag")
	}
	enemy.Carrier = 0
	enemy.Home = false
	x, y, _ = g.objectiveGoal(t0)
	if x != own.HomeX || y != own.HomeY {
		t.Fatal("carrier not returning")
	}
	own.Home = false
	own.ReturnIn = 10
	own.X = 400
	own.Y = 400
	x, y, _ = g.objectiveGoal(t0)
	if x != 400 || y != 400 {
		t.Fatal("not returning own flag")
	}
	g, _ = objectiveFixture("koth")
	x, y, ok = g.objectiveGoal(g.Tanks[0])
	if !ok || x != g.Objectives.HillX || y != g.Objectives.HillY {
		t.Fatal("not pursuing hill")
	}
}
func TestObjective32BotMovesWithoutAliveEnemy(t *testing.T) {
	g, _ := objectiveFixture("koth")
	t0 := g.Tanks[0]
	t0.Bot = true
	t0.Difficulty = "normal"
	for id, tank := range g.Tanks {
		if id != 0 && tank != nil {
			tank.Alive = false
		}
	}
	x, y := t0.X, t0.Y
	for i := 0; i < 120; i++ {
		g.Tick++
		g.botControl(t0, tickDT)
	}
	if dist(x, y, t0.X, t0.Y) < 30 {
		t.Fatal("bot stopped chasing objective when no enemy alive")
	}
}
func TestPreset32AtomicAndPreservesHost(t *testing.T) {
	h, cs, r := makeRoom(t, 1)
	token, member := r.Players[0].Token, r.Players[0].Member
	rules := legacyTeamRules36()
	rules.Mode = "ctf"
	roster := []SeatSpec{{Name: "Captain", Kind: "human", Difficulty: "", Team: 1}, {Name: "NOVA", Kind: "local", Difficulty: "", Team: 1}, {Name: "RUST", Kind: "bot", Difficulty: "hard", Team: 2}}
	action(t, h, cs[0], map[string]any{"type": "preset", "rules": rules, "roster": roster})
	if r.Players[0].Token != token || r.Players[0].Member != member || r.Players[1].Owner != 0 || r.Players[2].Difficulty != "hard" || r.Game.Rules.Mode != "ctf" {
		t.Fatal("preset failed or reset host identity")
	}
}
func TestPreset32CannotReplaceGuest(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	member := r.Players[1].Member
	action(t, h, cs[0], map[string]any{"type": "preset", "rules": legacyTeamRules36(), "roster": []SeatSpec{{Name: "A", Kind: "human", Difficulty: "", Team: 1}}})
	if !hasError(cs[0], "guests_present") || r.Players[1].Member != member {
		t.Fatal("replaced guest")
	}
	h.removeClient(cs[1])
	action(t, h, cs[0], map[string]any{"type": "preset", "rules": legacyTeamRules36(), "roster": []SeatSpec{{Name: "A", Kind: "human", Difficulty: "", Team: 1}}})
	if !hasError(cs[0], "guests_present") {
		t.Fatal("replaced reconnecting guest")
	}
}
func TestPreset32RejectInvalidBeforeMutation(t *testing.T) {
	h, cs, r := makeRoom(t, 1)
	rules := legacyTeamRules36()
	roster := []SeatSpec{{Name: "A", Kind: "human", Difficulty: "", Team: 1}, {Name: "B", Kind: "human", Difficulty: "", Team: 2}}
	action(t, h, cs[0], map[string]any{"type": "preset", "rules": rules, "roster": roster})
	if !hasError(cs[0], "bad_roster") || r.Players[0].Name == "A" {
		t.Fatal("invalid preset partly applied")
	}
}
func TestPreset32PublishImportsRules(t *testing.T) {
	h := newHub(3)
	c := fakeClient()
	rules := legacyTeamRules36()
	rules.TeamMode = "ffa"
	rules.MapSize = "large"
	action(t, h, c, map[string]any{"type": "publish", "code": "Capture & Hill", "rules": rules, "roster": []SeatSpec{{Name: "A", Kind: "human", Difficulty: "", Team: 1}, {Name: "B", Kind: "bot", Difficulty: "easy", Team: 2}}})
	if c.room == nil || c.room.Game.Rules.MapSize != "large" || c.room.Players[0].Team != 0 || c.room.Players[1].Team != 0 {
		t.Fatal("publish lost rules/FFA")
	}
}
func TestPreset32PublishInvalidRulesNoRoom(t *testing.T) {
	h := newHub(3)
	c := fakeClient()
	rules := legacyTeamRules36()
	rules.TimeLimit = -1
	action(t, h, c, map[string]any{"type": "publish", "code": "invalid", "rules": rules, "roster": []SeatSpec{{Name: "A", Kind: "human", Difficulty: "", Team: 1}}})
	if c.room != nil || len(h.rooms) != 0 || !hasError(c, "bad_rules") {
		t.Fatal("invalid publish allocated room")
	}
}
func TestFeedback32CooldownSerialized(t *testing.T) {
	g, _ := objectiveFixture("ctf")
	t0 := g.Tanks[0]
	t0.Cooldown = 0
	t0.Power = "laser"
	t0.Charges = 3
	g.fire(t0)
	if t0.CooldownTotal != laserCooldown {
		t.Fatal("laser cooldown denominator missing")
	}
	raw, _ := json.Marshal(t0)
	var obj map[string]any
	_ = json.Unmarshal(raw, &obj)
	if obj["cooldownTotal"] != laserCooldown {
		t.Fatal("cooldown not sent")
	}
}
func TestObjective32SeededBotMatches(t *testing.T) {
	for _, mode := range []string{"ctf", "koth"} {
		for seed := int64(1); seed <= 3; seed++ {
			g := newGame(seed)
			// Preserve the original regression map; default-size coverage is in v3.5 tests.
			g.Rules.MapSize = "standard"
			g.Rules.Mode = mode
			g.Rules.TimeLimit = 180
			g.Rules.ScoreTarget = 3
			if mode == "koth" {
				g.Rules.ScoreTarget = 30
			}
			ps := [maxTanks]*Player{{ID: 0, Kind: "bot", Team: 1, Difficulty: "hard", Name: "A"}, {ID: 1, Kind: "bot", Team: 2, Difficulty: "hard", Name: "B"}, {ID: 2, Kind: "bot", Team: 1, Difficulty: "normal", Name: "C"}, {ID: 3, Kind: "bot", Team: 2, Difficulty: "normal", Name: "D"}}
			g.startMatch(ps)
			for i := 0; i < 30000 && g.Phase != "matchOver"; i++ {
				g.step(tickDT, [maxTanks]Input{}, ps)
			}
			sum := 0
			for _, s := range g.Scores {
				sum += s
			}
			t.Logf("%s seed%d scores=%v phase=%s", mode, seed, g.Scores, g.Phase)
			if sum == 0 {
				t.Fatal("bots never scored the objective")
			}
			if g.Phase != "matchOver" {
				t.Fatal("objective match and sudden death did not terminate")
			}
		}
	}
}
func TestObjective32LateJoinExistingTeamsAndRespawn(t *testing.T) {
	h, _, r := makeRoom(t, 2)
	r.Players[0].Team = 3
	r.Players[1].Team = 4
	r.Game.Rules.Mode = "ctf"
	r.Game.Rules.RespawnSeconds = 2
	r.Game.startMatch(r.Players)
	r.Game.Phase = "playing"
	r.Game.Scores[0] = 2
	c := fakeClient()
	action(t, h, c, map[string]any{"type": "join", "code": r.Code, "name": "late"})
	if c.player == nil || c.player.Team != 3 {
		t.Fatal("join created a third side")
	}
	id := c.player.ID
	tk := r.Game.Tanks[id]
	if tk.Team != 3 || tk.Alive || tk.RespawnTime != 2 || r.Game.Scores[id] != 2 {
		t.Fatal("join lost team, score, or spawn delay")
	}
	r.Game.respawnPlayers(1, r.Players)
	if tk.Alive {
		t.Fatal("spawned early")
	}
	r.Game.respawnPlayers(1.1, r.Players)
	if !tk.Alive || tk.Invulnerable <= 0 || tk.Color != participantColor(id, 3) {
		t.Fatal("late player never respawned correctly")
	}
}
func TestObjective32FreshTeammateCannotResetTeamScore(t *testing.T) {
	g, _ := objectiveFixture("koth")
	g.Rules.ScoreTarget = 10
	g.Scores[0] = 4
	g.Scores[2] = 0
	g.addObjectivePoint(2)
	if g.Scores[0] != 5 || g.Scores[2] != 5 {
		t.Fatal("fresh teammate reset shared score")
	}
}
