package main

import (
	"bytes"
	"encoding/json"
	"reflect"
	"testing"
	"time"
)

func survivalRoom427(t *testing.T, count int) (*Hub, []*Client, *Room) {
	t.Helper()
	h, clients, r := makeRoom(t, count)
	rules := defaultRules()
	rules.Mode, rules.TeamMode, rules.ScoreTarget = "survival", "teams", 10
	h.setRules(clients[0], clientMessage{Rules: &rules}, time.Now())
	for _, p := range r.Players {
		if p != nil {
			p.Ready = true
		}
	}
	return h, clients, r
}

func clearSurvivalWave427(t *testing.T, r *Room) {
	t.Helper()
	for _, tank := range r.Game.Tanks {
		if tank != nil && tank.SurvivalEnemy {
			tank.Alive = false
		}
	}
	r.Game.stepSurvival(r.Players)
}

func TestSurvival427SingleHumanStartsAndEnemySlotsStayPrivate(t *testing.T) {
	h, clients, r := survivalRoom427(t, 1)
	if !canStart(r) {
		t.Fatal("single connected pilot cannot start survival")
	}
	action(t, h, clients[0], map[string]any{"type": "start"})
	g, s := r.Game, r.Game.survivalState()
	if s == nil || s.Wave != 1 || s.EnemiesRemaining != 2 || g.objectiveMode() || g.Phase != "countdown" {
		t.Fatalf("wrong initial wave: %+v phase=%s", s, g.Phase)
	}
	if participantCount(r.Players) != 1 || len(h.roomMessage(r)["players"].([]map[string]any)) != 1 || len(g.stats.rows) != 1 {
		t.Fatal("generated enemies leaked into roster or statistics")
	}
	for id, tank := range g.Tanks {
		if tank == nil || !tank.SurvivalEnemy {
			continue
		}
		if r.Players[id] != nil || tank.Team != 2 || tank.Difficulty != "easy" || tank.stats != nil {
			t.Fatal("enemy inherited a participant identity")
		}
		for _, other := range g.Tanks {
			if other != nil && other != tank && dist(tank.X, tank.Y, other.X, other.Y) <= tank.R+other.R {
				t.Fatal("wave enemy spawned on another tank")
			}
		}
	}
	if g.Objectives.Flags == nil {
		t.Fatal("survival flags must encode an empty array")
	}
}

func TestSurvival427WaveBreakClearsHazardsRevivesAndKeepsMaze(t *testing.T) {
	_, _, r := survivalRoom427(t, 2)
	g := r.Game
	g.startMatch(r.Players)
	g.Phase = "playing"
	g.Tanks[1].Alive = false
	g.Tanks[1].Power, g.Tanks[1].PowerTime = "grenade", 9
	walls := append([]Wall{}, g.World.Walls...)
	generation := g.Generation
	serial := g.Tanks[0].SpawnSerial
	g.Bullets = []*Bullet{{Owner: 0, Kind: "grenade"}}
	g.Pickups = []*Pickup{{ID: 900, Life: 9}}
	r.Players[0].Input = Input{Seq: 42, Fire: true, Forward: true}
	r.Players[0].FirePending = true
	clearSurvivalWave427(t, r)
	s := g.survivalState()
	if s.Status != "break" || s.BreakTime != 2 || g.Phase != "playing" || len(g.Bullets) != 0 || len(g.Pickups) != 0 || g.Scores[0] != 1 || g.Scores[1] != 1 {
		t.Fatalf("wave did not clear safely: %+v", s)
	}
	if g.fire(g.Tanks[0]) || r.Players[0].Input.Fire || r.Players[0].FirePending || r.Players[0].Input.Seq != 42 {
		t.Fatal("weapon or held input leaked into intermission")
	}
	clock, x := g.Clock, g.Tanks[0].X
	g.step(1, [maxTanks]Input{{Forward: true, Fire: true}}, r.Players)
	if s.BreakTime != 1 || g.Clock != clock || g.Tanks[0].X != x || g.Tanks[1].Alive {
		t.Fatal("intermission moved the simulation or revived too early")
	}
	g.step(1, [maxTanks]Input{}, r.Players)
	if s.Status != "wave" || s.Wave != 2 || g.Round != 2 || !g.Tanks[1].Alive || g.Tanks[1].Power != "" || g.Tanks[0].SpawnSerial <= serial || g.Clock != float64(g.settings().TimeLimit) {
		t.Fatalf("next wave failed to reset squad: %+v", s)
	}
	if generation != g.Generation || !reflect.DeepEqual(walls, g.World.Walls) {
		t.Fatal("wave regenerated the maze")
	}
}

func TestSurvival427NoRespawnDuringWave(t *testing.T) {
	_, _, r := survivalRoom427(t, 2)
	g := r.Game
	g.startMatch(r.Players)
	g.Phase = "playing"
	g.Tanks[1].Alive, g.Tanks[1].RespawnTime = false, .001
	g.respawnPlayers(5, r.Players)
	if g.Tanks[1].Alive {
		t.Fatal("survival death used objective respawn")
	}
	g.Clock = 1
	g.step(2, [maxTanks]Input{}, r.Players)
	if g.Tanks[1].Alive || g.survivalState().Status != "lost" {
		t.Fatal("timeout did not finish without respawning")
	}
}

func TestSurvival427MutualDestructionAndWipeLose(t *testing.T) {
	for _, clearEnemies := range []bool{false, true} {
		t.Run(map[bool]string{false: "wipe", true: "mutual"}[clearEnemies], func(t *testing.T) {
			_, _, r := survivalRoom427(t, 1)
			g := r.Game
			g.startMatch(r.Players)
			g.Phase = "playing"
			g.Tanks[0].Alive = false
			if clearEnemies {
				clearSurvivalWave427(t, r)
			} else {
				g.stepSurvival(r.Players)
			}
			if g.survivalState().Status != "lost" || g.Phase != "matchOver" || g.Winner != -1 || g.Scores[0] != 0 {
				t.Fatal("wipe incorrectly awarded a survival wave")
			}
		})
	}
}

func TestSurvival427VictoryFreezesOnlySquadStatsAndRematchResets(t *testing.T) {
	_, _, r := survivalRoom427(t, 2)
	g := r.Game
	g.Rules.ScoreTarget = 1
	g.startMatch(r.Players)
	g.Phase = "playing"
	for _, tank := range g.Tanks {
		if tank != nil && tank.SurvivalEnemy {
			tank.Invulnerable = 0
			g.hurt(tank, &Bullet{Owner: 0})
		}
	}
	g.stepSurvival(r.Players)
	if g.Phase != "matchOver" || g.survivalState().Status != "won" || len(g.matchReport.Players) != 2 || g.matchReport.Players[0].Eliminations != 2 {
		t.Fatalf("bad survival victory: %+v", g.matchReport)
	}
	for _, row := range g.matchReport.Players {
		if !row.Winner || row.Score != 1 || row.Team != 1 {
			t.Fatalf("incorrect squad result: %+v", row)
		}
	}
	report := g.matchReport
	wire := append([]byte{}, g.matchReportWire...)
	g.survivalState().WavesCleared = 999
	r.Players[0].Name = "RENAMED"
	if report.Survival.WavesCleared != 1 || !bytes.Equal(wire, g.matchReportWire) {
		t.Fatal("finished run was not frozen")
	}
	g.startMatch(r.Players)
	if g.survivalState().Wave != 1 || g.survivalState().WavesCleared != 0 || g.Scores[0] != 0 || g.matchReport != nil || len(g.stats.rows) != 2 {
		t.Fatal("rematch carried survival state")
	}
}

func TestSurvival427ProgressionAndBossRespectsAllowedPowerups(t *testing.T) {
	_, _, r := survivalRoom427(t, 1)
	g := r.Game
	g.startMatch(r.Players)
	g.Phase = "playing"
	for wave := 1; wave <= 20; wave++ {
		s := g.survivalState()
		if s.Wave != wave || s.EnemiesRemaining != min(4, 2+(wave-1)/2) || s.Boss != (wave%5 == 0) {
			t.Fatalf("wrong wave progression: %+v", s)
		}
		bosses := 0
		for _, tank := range g.Tanks {
			if tank == nil || !tank.SurvivalEnemy {
				continue
			}
			if tank.SurvivalBoss {
				bosses++
				strength := min(3, wave/5)
				wantSkill := []string{"normal", "hard", "godlike"}[strength-1]
				wantName := []string{"NORMAL BOSS", "FIERCE BOSS", "GODLIKE BOSS"}[strength-1]
				wantSpeed := 0
				if strength >= 2 {
					wantSpeed = 1
				}
				if tank.Name != wantName || tank.Difficulty != wantSkill || tank.ShieldCharges != strength || tank.SpeedStacks != wantSpeed || tank.Power != []string{"homing", "cannon", "laser", "homing"}[wave/5-1] {
					t.Fatalf("wrong boss loadout: %+v", tank)
				}
			} else if tank.Difficulty != []string{"easy", "normal", "hard", "godlike"}[(wave-1)/5] {
				t.Fatal("wrong raider difficulty")
			}
		}
		if (wave%5 == 0 && bosses != 1) || (wave%5 != 0 && bosses != 0) {
			t.Fatal("wrong boss count")
		}
		g.nextSurvivalWave(r.Players)
	}
	for _, weapons := range [][]string{{"laser"}, {"rapid"}, {"shield", "speed"}} {
		g.Rules.Weapons = weapons
		tank := &Tank{}
		g.survivalBossPower(tank, 5)
		if len(weapons) == 1 && weapons[0] == "laser" && tank.Power != "laser" {
			t.Fatal("boss did not use enabled fallback weapon")
		}
		for _, kind := range []string{"shield", "speed", "homing", "cannon", "laser"} {
			enabled := false
			for _, w := range weapons {
				enabled = enabled || w == kind
			}
			if !enabled && ((kind == "shield" && tank.Shield > 0) || (kind == "speed" && tank.SpeedTime > 0) || tank.Power == kind) {
				t.Fatalf("boss granted disabled power-up %s", kind)
			}
		}
	}
	g.Rules.PickupRate = "off"
	tank := &Tank{}
	g.survivalBossPower(tank, 5)
	if tank.Shield > 0 || tank.SpeedTime > 0 || tank.Power != "" {
		t.Fatal("power-up-free rules equipped a boss")
	}
}

func TestSurvival427RulesAndRosterLimitsAreAtomic(t *testing.T) {
	h, clients, r := survivalRoom427(t, 4)
	if !canStart(r) || h.roomMessage(r)["maxPlayers"] != 4 {
		t.Fatal("valid four-player squad rejected")
	}
	h.configureRoom(clients[0], clientMessage{Type: "add", Kind: "bot", Difficulty: "godlike"}, time.Now())
	if !hasError(clients[0], "survival_full") || participantCount(r.Players) != 4 {
		t.Fatal("fifth allied tank was added")
	}
	visitor := fakeClient()
	h.join(visitor, false, r.Code, "FIFTH", "", time.Now())
	if visitor.player == nil || !visitor.player.Spectating {
		t.Fatal("full survival squad join was not a spectator")
	}
	play := false
	h.setSpectating(visitor, clientMessage{Spectating: &play}, time.Now())
	if !hasError(visitor, "survival_full") || !visitor.player.Spectating {
		t.Fatal("promotion bypassed survival capacity")
	}
	team := 2
	target := clients[0].player
	h.configureRoom(clients[0], clientMessage{Type: "configure", Target: &target.ID, Member: target.Member, Team: &team}, time.Now())
	if !hasError(clients[0], "bad_team") || target.Team != 1 {
		t.Fatal("squad player switched to enemy team")
	}
	h2, clients2, r2 := makeRoom(t, 5)
	before := r2.Game.settings()
	rules := before
	rules.Mode, rules.TeamMode = "survival", "teams"
	h2.setRules(clients2[0], clientMessage{Rules: &rules}, time.Now())
	if !hasError(clients2[0], "survival_full") || r2.Game.settings().Mode != before.Mode || participantCount(r2.Players) != 5 {
		t.Fatal("switch silently removed excess participants")
	}
	if validateRules(rules) != nil {
		t.Fatal("valid survival rules rejected")
	}
	rules.TeamMode = "ffa"
	if validateRules(rules) == nil {
		t.Fatal("survival FFA accepted")
	}
	rules.TeamMode, rules.ScoreTarget = "teams", 21
	if validateRules(rules) == nil {
		t.Fatal("unbounded survival wave target accepted")
	}
}

func TestSurvival427BotsCanStartButUnavailableSquadsCannot(t *testing.T) {
	h, clients, r := survivalRoom427(t, 1)
	h.configureRoom(clients[0], clientMessage{Type: "add", Kind: "bot", Difficulty: "godlike"}, time.Now())
	spectate := true
	h.setSpectating(clients[0], clientMessage{Spectating: &spectate}, time.Now())
	if !clients[0].player.Spectating || !canStart(r) || r.Game.lineupError(r.Players) != "" {
		t.Fatal("spectating host cannot start a bot-only squad")
	}
	var empty [maxTanks]*Player
	if r.Game.lineupError(empty) == "" {
		t.Fatal("empty survival squad can start")
	}
	empty[0] = &Player{ID: 0, Kind: "human", Team: 1}
	if r.Game.lineupError(empty) == "" {
		t.Fatal("disconnected-only survival squad can start")
	}
	action(t, h, clients[0], map[string]any{"type": "start"})
	if r.Game.Phase != "countdown" || r.Game.survivalState() == nil {
		t.Fatal("bot-only start did not launch")
	}
}

func TestSurvival427JoinAndSwapCannotOverwriteWaveEnemies(t *testing.T) {
	h, clients, r := survivalRoom427(t, 1)
	g := r.Game
	g.startMatch(r.Players)
	g.Phase = "playing"
	before := g.Tanks
	visitor := fakeClient()
	h.join(visitor, false, r.Code, "VISITOR", "", time.Now())
	if visitor.player == nil || !visitor.player.Spectating || before != g.Tanks {
		t.Fatal("active-run join claimed a combat slot")
	}
	play := false
	h.setSpectating(visitor, clientMessage{Spectating: &play}, time.Now())
	if !hasError(visitor, "survival_active") || before != g.Tanks {
		t.Fatal("mid-wave promotion mutated combat")
	}
	a, v := clients[0].player, visitor.player
	h.swapSpectator(clients[0], clientMessage{Target: &a.ID, Member: a.Member, Spectator: &v.ID, SpectatorMember: v.Member}, time.Now())
	if !hasError(clients[0], "survival_active") || before != g.Tanks {
		t.Fatal("mid-wave swap bought an extra life")
	}
	for id, tank := range g.Tanks {
		if tank == nil || !tank.SurvivalEnemy {
			continue
		}
		action(t, h, clients[0], map[string]any{"type": "input", "player": id, "seq": 1, "forward": true, "fire": true})
		if !hasError(clients[0], "not_owned") || r.Players[id] != nil {
			t.Fatal("client took control of a wave enemy")
		}
		break
	}
}

func TestSurvival427DepartureKeepsBotsRunningAndReconnectWaitsForWave(t *testing.T) {
	h, clients, r := survivalRoom427(t, 2)
	h.configureRoom(clients[0], clientMessage{Type: "add", Kind: "bot", Difficulty: "normal"}, time.Now())
	g := r.Game
	g.startMatch(r.Players)
	g.Phase = "playing"
	h.removeClient(clients[1])
	g.prepareSurvival(tickDT, r.Players)
	if g.Tanks[1].Alive || g.Phase == "matchOver" {
		t.Fatal("disconnect did not retire only departed life")
	}
	resumed := fakeClient()
	h.join(resumed, false, r.Code, "IGNORED", r.Players[1].Token, time.Now())
	if resumed.player != r.Players[1] || g.Tanks[1].Alive {
		t.Fatal("reconnect granted an immediate life")
	}
	clearSurvivalWave427(t, r)
	g.prepareSurvival(2, r.Players)
	if !g.Tanks[1].Alive {
		t.Fatal("reconnected squadmate was not revived for next wave")
	}
	h.removeClient(clients[0])
	h.removeClient(resumed)
	g.step(tickDT, [maxTanks]Input{}, r.Players)
	if g.survivalState().Status != "wave" || g.Phase != "playing" {
		t.Fatal("departing humans ended a live bot squad's run")
	}
	for _, tank := range g.Tanks {
		if tank != nil && !tank.SurvivalEnemy {
			tank.Alive = false
		}
	}
	g.stepSurvival(r.Players)
	if g.survivalState().Status != "lost" {
		t.Fatal("wiped bot squad did not lose")
	}
}

func TestSurvival427SnapshotAndWireCopiesAreImmutable(t *testing.T) {
	h, _, r := survivalRoom427(t, 1)
	r.Game.startMatch(r.Players)
	message := h.stateMessage(r)
	wire := h.stateWire(r)
	b1, err := json.Marshal(message)
	if err != nil {
		t.Fatal(err)
	}
	b2, err := json.Marshal(wire)
	if err != nil || !bytes.Equal(b1, b2) {
		t.Fatalf("snapshot encoder parity failed: %v", err)
	}
	r.Game.survivalState().Wave = 19
	if message["objectives"].(*ObjectiveState).Survival.Wave != 1 {
		t.Fatal("wave state aliases previously built snapshot")
	}
	for _, tank := range message["tanks"].([]Tank) {
		if tank.SurvivalEnemy && (!tank.Bot || tank.Team != 2 || tank.ID >= maxTanks) {
			t.Fatal("bad enemy wire identity")
		}
	}
}

func TestSurvival427PublishAndPresetRejectExcessBeforeMutation(t *testing.T) {
	rules := defaultRules()
	rules.Mode, rules.TeamMode, rules.ScoreTarget = "survival", "teams", 10
	roster := []SeatSpec{{Kind: "human", Name: "HOST", Team: 1}}
	for i := 0; i < 4; i++ {
		roster = append(roster, SeatSpec{Kind: "bot", Name: "ALLY", Difficulty: "godlike", Team: 1})
	}
	h := newHub(4)
	c := fakeClient()
	h.publishRoom(c, clientMessage{Code: "SURVIVAL LIMIT", Rules: &rules, Roster: roster}, time.Now())
	if !hasError(c, "survival_full") || c.room != nil || len(h.rooms) != 0 {
		t.Fatal("oversized publish partially created a room")
	}
	h, clients, r := makeRoom(t, 1)
	before := r.Players
	h.applyPreset(clients[0], clientMessage{Rules: &rules, Roster: roster}, time.Now())
	if !hasError(clients[0], "survival_full") || before != r.Players || r.Game.survivalMode() {
		t.Fatal("oversized preset partially replaced the roster")
	}
	h.applyPreset(clients[0], clientMessage{Rules: &rules, Roster: roster[:4]}, time.Now())
	if !r.Game.survivalMode() || participantCount(r.Players) != 4 || !canStart(r) {
		t.Fatal("valid survival preset failed to load")
	}
}

func TestSurvival427SpectatingLastHumanKeepsBotsWithoutEnemyOwnership(t *testing.T) {
	h, clients, r := survivalRoom427(t, 1)
	h.configureRoom(clients[0], clientMessage{Type: "add", Kind: "bot", Difficulty: "godlike"}, time.Now())
	r.Game.startMatch(r.Players)
	r.Game.Phase = "playing"
	spectate := true
	h.setSpectating(clients[0], clientMessage{Spectating: &spectate}, time.Now())
	r.Game.step(tickDT, [maxTanks]Input{}, r.Players)
	if !clients[0].player.Spectating || r.Game.survivalState().Status != "wave" || r.Game.Phase != "playing" {
		t.Fatal("last human spectating stopped a live bot squad")
	}
	for _, p := range r.Players {
		if p != nil && p.Kind != "bot" {
			t.Fatal("spectator retained a hidden human seat")
		}
	}
}

func TestSurvival427BossSimulationAcrossEveryMap(t *testing.T) {
	for _, size := range []string{"compact", "standard", "large", "huge", "giant", "ultrawide"} {
		t.Run(size, func(t *testing.T) {
			_, _, r := survivalRoom427(t, 4)
			g := r.Game
			g.Rules.MapSize = size
			for id := 1; id < 4; id++ {
				r.Players[id].Kind, r.Players[id].Difficulty = "bot", "godlike"
			}
			g.startMatch(r.Players)
			g.Phase = "playing"
			g.survivalState().Wave = 4
			g.nextSurvivalWave(r.Players)
			for i := 0; i < 180 && g.Phase == "playing"; i++ {
				g.step(tickDT, [maxTanks]Input{}, r.Players)
			}
			for id, tank := range g.Tanks {
				if tank == nil {
					continue
				}
				if tank.ID != id || tank.X < tank.R || tank.Y < tank.R || tank.X > g.World.Width-tank.R || tank.Y > g.World.Height-tank.R {
					t.Fatalf("survival bot left the physical arena: %+v", tank)
				}
				if tank.SurvivalEnemy && r.Players[id] != nil {
					t.Fatal("simulation created an enemy room participant")
				}
			}
		})
	}
}
