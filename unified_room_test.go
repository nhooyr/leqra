package main

import (
	"encoding/json"
	"math"
	"testing"
	"time"
)

func addSeat(t *testing.T, h *Hub, c *Client, kind, diff string, team int) *Player {
	t.Helper()
	before := c.room.NextMember
	action(t, h, c, map[string]any{"type": "add", "kind": kind, "difficulty": diff, "team": team, "name": "EXTRA"})
	for _, p := range c.room.Players {
		if p != nil && p.Member > before {
			return p
		}
	}
	t.Fatalf("seat not added: %+v", drain(c))
	return nil
}
func configureSeat(t *testing.T, h *Hub, c *Client, p *Player, team int) {
	t.Helper()
	action(t, h, c, map[string]any{"type": "configure", "target": p.ID, "member": p.Member, "team": team})
}
func TestUnifiedPublishPreservesFullConfiguration(t *testing.T) {
	h := newHub(8)
	c := fakeClient()
	action(t, h, c, map[string]any{"type": "publish", "code": "Friends & bots 💥", "roster": []SeatSpec{{Name: "ADAM", Kind: "human", Difficulty: "", Team: 1}, {Name: "LOCAL", Kind: "local", Difficulty: "", Team: 1}, {Name: "RUST", Kind: "bot", Difficulty: "easy", Team: 2}, {Name: "VAPOR", Kind: "bot", Difficulty: "hard", Team: 2}}})
	r := c.room
	if r == nil || r.Host != 0 || r.Code != "Friends & bots 💥" || connectedPlayers(r) != 1 || !canStart(r) {
		t.Fatal("wrong published room")
	}
	for id, p := range r.Players {
		if id >= 4 {
			if p != nil {
				t.Fatal("phantom imported seat")
			}
			continue
		}
		if p == nil || p.ID != id || !participantAvailable(r.Players, id) {
			t.Fatal("import lost seat")
		}
		if id > 0 && (p.Client != nil || p.Token != "") {
			t.Fatal("virtual seat has network identity")
		}
	}
	action(t, h, c, map[string]any{"type": "start"})
	for id, tank := range r.Game.Tanks {
		if id >= 4 {
			if tank != nil {
				t.Fatal("phantom tank")
			}
			continue
		}
		if tank == nil || !tank.Alive || tank.Team != r.Players[id].Team || tank.Bot != (id > 1) {
			t.Fatal("configuration not applied")
		}
	}
}
func TestUnifiedPublishConflictDoesNotMergeOrOverwrite(t *testing.T) {
	h, cs, r := makeRoom(t, 1)
	c := fakeClient()
	action(t, h, c, map[string]any{"type": "publish", "code": r.Code, "roster": []SeatSpec{{Name: "NEW", Kind: "human", Difficulty: "", Team: 1}, {Name: "BOT", Kind: "bot", Difficulty: "hard", Team: 2}}})
	if !hasError(c, "room_exists") || c.room != nil || r.Players[0] != cs[0].player || r.Players[1] != nil {
		t.Fatal("publish replaced existing room")
	}
}
func TestUnifiedPublishValidationAtomic(t *testing.T) {
	cases := []struct {
		roster []SeatSpec
		err    string
	}{
		{nil, "bad_roster"}, {[]SeatSpec{{Name: "B", Kind: "bot", Difficulty: "easy", Team: 0}}, "bad_roster"},
		{[]SeatSpec{{Name: "A", Kind: "human", Difficulty: "", Team: 1}, {Name: "B", Kind: "human", Difficulty: "", Team: 2}}, "bad_roster"},
		{[]SeatSpec{{Name: "A", Kind: "human", Difficulty: "", Team: 1}, {Name: "B", Kind: "bot", Difficulty: "impossible", Team: 2}}, "bad_difficulty"},
		{[]SeatSpec{{Name: "A", Kind: "human", Difficulty: "", Team: 5}}, "bad_team"},
		{[]SeatSpec{{Name: "A", Kind: "human", Difficulty: "", Team: 1}, {Name: "B", Kind: "local", Difficulty: "", Team: 1}, {Name: "C", Kind: "local", Difficulty: "", Team: 2}}, "local_exists"},
	}
	for _, tc := range cases {
		h := newHub(8)
		c := fakeClient()
		action(t, h, c, map[string]any{"type": "publish", "code": "invalid test", "roster": tc.roster})
		if !hasError(c, tc.err) || len(h.rooms) != 0 || c.player != nil {
			t.Fatalf("non-atomic validation: %s", tc.err)
		}
	}
}
func TestUnifiedHostOnlyConfiguration(t *testing.T) {
	for _, kind := range []string{"add", "configure", "lobby"} {
		h, cs, r := makeRoom(t, 2)
		action(t, h, cs[1], map[string]any{"type": kind, "kind": "bot", "difficulty": "hard", "target": 0, "member": r.Players[0].Member, "team": 2})
		if !hasError(cs[1], "not_host") || r.Players[2] != nil || r.Players[0].Team != 1 {
			t.Fatal("guest changed room")
		}
	}
}
func TestUnifiedSeatLimitAndOneLocal(t *testing.T) {
	h, cs, _ := makeRoom(t, 1)
	addSeat(t, h, cs[0], "local", "", 1)
	action(t, h, cs[0], map[string]any{"type": "add", "kind": "local"})
	if !hasError(cs[0], "local_exists") {
		t.Fatal("duplicate local")
	}
	addSeat(t, h, cs[0], "bot", "easy", 2)
	addSeat(t, h, cs[0], "bot", "hard", 2)
	for i := 4; i < maxTanks; i++ {
		cs[0].actionCount = 0
		addSeat(t, h, cs[0], "bot", "normal", 2)
	}
	cs[0].actionCount = 0
	action(t, h, cs[0], map[string]any{"type": "add", "kind": "bot", "difficulty": "normal"})
	if !hasError(cs[0], "room_full") {
		t.Fatal("seat beyond capacity")
	}
}
func TestUnifiedStartNeedsOpposingSidesNotTwoSockets(t *testing.T) {
	h, cs, r := makeRoom(t, 1)
	configureSeat(t, h, cs[0], cs[0].player, 1)
	bot := addSeat(t, h, cs[0], "bot", "normal", 1)
	if canStart(r) {
		t.Fatal("same team can start")
	}
	configureSeat(t, h, cs[0], bot, 2)
	if !canStart(r) {
		t.Fatal("one socket plus enemy bot cannot start")
	}
	action(t, h, cs[0], map[string]any{"type": "start"})
	if r.Game.Phase != "countdown" {
		t.Fatal("host start failed")
	}
}
func TestUnifiedFreeForAllAndGuestReadiness(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	if availableSides(r.Players) != 2 || canStart(r) {
		t.Fatal("FFA or ready incorrect")
	}
	action(t, h, cs[1], map[string]any{"type": "ready", "ready": true})
	if !canStart(r) {
		t.Fatal("host must unnecessarily ready twice")
	}
	configureSeat(t, h, cs[0], cs[1].player, 2)
	if cs[1].player.Ready || canStart(r) {
		t.Fatal("guest consent not reset after configuration")
	}
}
func TestUnifiedConfigureRejectsStaleSeatAndInvalidDifficulty(t *testing.T) {
	h, cs, r := makeRoom(t, 1)
	b := addSeat(t, h, cs[0], "bot", "easy", 2)
	action(t, h, cs[0], map[string]any{"type": "configure", "target": b.ID, "member": b.Member + 1, "team": 4})
	if !hasError(cs[0], "player_missing") || b.Team != 2 {
		t.Fatal("stale configure")
	}
	action(t, h, cs[0], map[string]any{"type": "configure", "target": b.ID, "member": b.Member, "team": 3, "difficulty": "extreme"})
	if !hasError(cs[0], "bad_difficulty") || b.Team != 2 {
		t.Fatal("partial invalid edit")
	}
	action(t, h, cs[0], map[string]any{"type": "configure", "target": b.ID, "member": b.Member, "difficulty": "hard", "name": "SMART", "team": 4})
	if b.Difficulty != "hard" || b.Team != 4 || b.Name != "SMART" || r.Host != 0 {
		t.Fatal("valid bot edit failed")
	}
}
func TestUnifiedLiveRosterEditsBlockedAndReturnClearsCombat(t *testing.T) {
	h, cs, r := makeRoom(t, 1)
	b := addSeat(t, h, cs[0], "bot", "normal", 2)
	r.Game.startMatch(r.Players)
	r.Game.Phase = "playing"
	r.Game.Scores[0] = 3
	action(t, h, cs[0], map[string]any{"type": "configure", "target": b.ID, "member": b.Member, "team": 4})
	if !hasError(cs[0], "match_active") || b.Team != 2 {
		t.Fatal("live team change")
	}
	action(t, h, cs[0], map[string]any{"type": "lobby"})
	if r.Game.Phase != "lobby" || r.Game.Scores[0] != 0 || r.Game.Tanks[0] != nil || len(r.Game.Bullets) != 0 || r.Players[b.ID] != b {
		t.Fatal("return did not reset combat while retaining roster")
	}
}
func TestUnifiedSecondLocalIndependentInputAndFireEdges(t *testing.T) {
	h, cs, r := makeRoom(t, 1)
	p2 := addSeat(t, h, cs[0], "local", "", 2)
	r.Game.startMatch(r.Players)
	action(t, h, cs[0], map[string]any{"type": "input", "seq": 12, "forward": true, "fire": true})
	action(t, h, cs[0], map[string]any{"type": "input", "player": p2.ID, "seq": 1, "right": true, "fire": true})
	action(t, h, cs[0], map[string]any{"type": "input", "player": p2.ID, "seq": 2, "fire": false})
	if !r.Players[0].Input.Forward || r.Players[0].Input.Seq != 12 || p2.Input.Seq != 2 || !p2.FirePending || !r.Players[0].FirePending {
		t.Fatal("controller histories interfere")
	}
}
func TestUnifiedRejectCrossControllerAndBotInput(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	p2 := addSeat(t, h, cs[0], "local", "", 1)
	bot := addSeat(t, h, cs[0], "bot", "easy", 2)
	for _, id := range []int{0, p2.ID, bot.ID, -1, 4} {
		action(t, h, cs[1], map[string]any{"type": "input", "player": id, "seq": 1, "fire": true})
		if !hasError(cs[1], "not_owned") {
			t.Fatal("guest forged controls")
		}
	}
	action(t, h, cs[0], map[string]any{"type": "input", "player": bot.ID, "seq": 1, "fire": true})
	if !hasError(cs[0], "not_owned") || r.Players[bot.ID].Input.Seq != 0 {
		t.Fatal("host forged bot input")
	}
}
func TestUnifiedBothControllersRunThroughHubTick(t *testing.T) {
	h, cs, r := makeRoom(t, 1)
	p2 := addSeat(t, h, cs[0], "local", "", 2)
	r.Game.startMatch(r.Players)
	openArena(r.Game)
	r.Game.Phase = "playing"
	for id, tank := range r.Game.Tanks {
		if tank != nil {
			tank.X = 100
			tank.Y = 100 + float64(id)*168
			tank.Angle = 0
		}
	}
	action(t, h, cs[0], map[string]any{"type": "input", "seq": 1, "forward": true})
	action(t, h, cs[0], map[string]any{"type": "input", "player": p2.ID, "seq": 1, "forward": true})
	for i := 0; i < 12; i++ {
		h.tick(time.Now())
	}
	if math.Abs(r.Game.Tanks[0].X-125.6) > .01 || math.Abs(r.Game.Tanks[p2.ID].X-125.6) > .01 {
		t.Fatal("secondary controls not simulated")
	}
}
func TestUnifiedLocalReconnectAndOwnershipSurviveHostHandoff(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	p2 := addSeat(t, h, cs[0], "local", "", 1)
	owner := cs[0].player
	owner.Input = Input{Seq: 5, Forward: true}
	p2.Input = Input{Seq: 8, Fire: true}
	p2.FirePending = true
	h.removeClient(cs[0])
	if r.Host != 1 || participantAvailable(r.Players, p2.ID) || p2.Input.Fire || p2.FirePending {
		t.Fatal("handoff or local cleanup failed")
	}
	fresh := fakeClient()
	action(t, h, fresh, map[string]any{"type": "join", "code": r.Code, "token": owner.Token})
	if fresh.player != owner || !participantAvailable(r.Players, p2.ID) || p2.Owner != owner.ID || p2.Input.Seq != 0 || r.Host != 1 {
		t.Fatal("resume reassigned or lost local controller")
	}
	action(t, h, cs[1], map[string]any{"type": "input", "player": p2.ID, "seq": 1, "fire": true})
	if !hasError(cs[1], "not_owned") {
		t.Fatal("host stole old host keyboard")
	}
}
func TestUnifiedOwnerRemovalCascadesLocalButNotBots(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	p2 := addSeat(t, h, cs[0], "local", "", 1)
	bot := addSeat(t, h, cs[0], "bot", "hard", 2)
	action(t, h, cs[0], map[string]any{"type": "leave"})
	if r.Players[p2.ID] != nil || r.Players[bot.ID] != bot || r.Host != 1 {
		t.Fatal("owner leave did not remove dependent seat")
	}
	addSeat(t, h, cs[1], "local", "", 2)
}
func TestUnifiedBotOnlyRoomExpires(t *testing.T) {
	h, cs, _ := makeRoom(t, 1)
	addSeat(t, h, cs[0], "bot", "normal", 2)
	h.removeClient(cs[0])
	h.tick(time.Now().Add(21 * time.Second))
	if len(h.rooms) != 0 {
		t.Fatal("bot keeps abandoned room forever")
	}
}
func TestUnifiedTeamDamageRulesAcrossWeapons(t *testing.T) {
	for _, kind := range []string{"normal", "homing", "grenade", "laser"} {
		t.Run(kind, func(t *testing.T) {
			g := battle(3)
			g.Tanks[0].Team = 1
			ally, enemy := g.Tanks[1], g.Tanks[2]
			ally.Team = 1
			enemy.Team = 2
			ally.Shield = 10
			g.hurt(ally, &Bullet{Owner: 0, Kind: kind})
			if !ally.Alive || ally.Shield != 10 {
				t.Fatal("ally damaged or shield consumed")
			}
			g.hurt(enemy, &Bullet{Owner: 0, Kind: kind})
			if enemy.Alive {
				t.Fatal("enemy immune")
			}
			g.hurt(g.Tanks[0], &Bullet{Owner: 0, Kind: kind})
			if g.Tanks[0].Alive {
				t.Fatal("human self damage rule unexpectedly removed")
			}
		})
	}
}
func TestUnifiedFriendlyProjectilesPassThroughTanks(t *testing.T) {
	g := battle(3)
	g.Tanks[0].Team = 1
	g.Tanks[1].Team = 1
	g.Tanks[2].Team = 2
	g.fire(g.Tanks[0])
	for i := 0; i < 100 && g.Tanks[2].Alive; i++ {
		g.updateBullets(tickDT)
	}
	if !g.Tanks[1].Alive || g.Tanks[2].Alive {
		t.Fatal("friendly tank intercepted the shot")
	}
}
func TestUnifiedLaserPassesAllyAndStopsAtEnemy(t *testing.T) {
	g := battle(3)
	g.Tanks[0].Team = 1
	g.Tanks[1].Team = 1
	g.Tanks[2].Team = 2
	g.grantPower(g.Tanks[0], "laser")
	g.fire(g.Tanks[0])
	if !g.Tanks[1].Alive || g.Tanks[2].Alive || !g.Tanks[0].Alive {
		t.Fatal("laser team/owner immunity")
	}
}
func TestUnifiedMissileAcquiresEnemyNotCloserTeammate(t *testing.T) {
	g := battle(3)
	g.Tanks[0].Team = 1
	g.Tanks[1].Team = 1
	g.Tanks[2].Team = 2
	b := missileFor(g, 125, 210, 0)
	g.steerMissile(b, tickDT)
	if b.Target != 2 {
		t.Fatal("seeker locked onto ally")
	}
}
func TestUnifiedTeamScoreIncludesEliminatedTeammate(t *testing.T) {
	ps := testPlayers(4)
	ps[0].Team = 1
	ps[1].Team = 1
	ps[2].Team = 2
	ps[3].Team = 2
	g := newGame(9)
	g.startMatch(ps)
	g.Phase = "playing"
	g.Tanks[0].Alive = false
	g.Tanks[2].Alive = false
	g.Tanks[3].Alive = false
	g.step(tickDT, [maxTanks]Input{}, ps)
	if g.Phase != "roundOver" || g.Winner != 1 || g.Scores != [maxTanks]int{1, 1, 0, 0} {
		t.Fatalf("incorrect team score %+v", g.Scores)
	}
}
func TestUnifiedTwoAlliesCanWinWhileBothAlive(t *testing.T) {
	ps := testPlayers(3)
	ps[0].Team = 1
	ps[1].Team = 1
	ps[2].Team = 2
	g := newGame(8)
	g.startMatch(ps)
	g.Phase = "playing"
	g.Tanks[2].Alive = false
	g.step(tickDT, [maxTanks]Input{}, ps)
	if g.Phase != "roundOver" || g.Scores != [maxTanks]int{1, 1, 0, 0} {
		t.Fatal("waited for allies to kill each other")
	}
}
func TestUnifiedFreeForAllScoresRemainIndividual(t *testing.T) {
	ps := testPlayers(3)
	g := newGame(2)
	g.startMatch(ps)
	g.Phase = "playing"
	g.Tanks[0].Alive = false
	g.Tanks[2].Alive = false
	g.step(tickDT, [maxTanks]Input{}, ps)
	if g.Scores != [maxTanks]int{0, 1, 0, 0} {
		t.Fatal("FFA scores merged")
	}
}
func TestUnifiedBotsHaveIndividualDifficulties(t *testing.T) {
	if tuneBot("easy").speed >= tuneBot("normal").speed || tuneBot("normal").reaction <= tuneBot("hard").reaction || tuneBot("easy").bank || !tuneBot("hard").dodge {
		t.Fatal("difficulty tuning collapsed")
	}
}
func TestUnifiedBotTargetingRespectsAssignedSides(t *testing.T) {
	g := battle(4)
	g.Tanks[1].Bot = true
	g.Tanks[1].Team = 2
	g.Tanks[1].Difficulty = "hard"
	g.Tanks[2].Bot = true
	g.Tanks[2].Team = 2
	g.Tanks[0].Team = 1
	g.Tanks[3].Bot = true
	g.Tanks[3].Team = 3
	g.Tanks[3].X = 215
	g.botControl(g.Tanks[1], tickDT)
	if g.Tanks[1].AI.Target != 3 {
		t.Fatal("enemy bot not eligible")
	}
	g.Tanks[3].Team = 2
	g.botControl(g.Tanks[1], tickDT)
	if g.Tanks[1].AI.Target != 0 {
		t.Fatal("bot targeted teammate")
	}
	g.hurt(g.Tanks[1], &Bullet{Owner: 1})
	if g.Tanks[1].Alive {
		t.Fatal("bot self damage was incorrectly blocked by team protection")
	}
}
func TestUnifiedNavigationConnectedForSeededMazes(t *testing.T) {
	for seed := int64(0); seed < 10; seed++ {
		g := newGame(seed)
		g.makeMaze(9, 8)
		g.buildNavigation()
		seen := map[int]bool{0: true}
		q := []int{0}
		for at := 0; at < len(q); at++ {
			for _, next := range g.Neighbors[q[at]] {
				if !seen[next] {
					seen[next] = true
					q = append(q, next)
				}
			}
		}
		if len(q) != 72 {
			t.Fatalf("seed %d has inaccessible route", seed)
		}
	}
}
func TestUnifiedBotsFightWithoutClientInputs(t *testing.T) {
	for _, difficulty := range []string{"easy", "normal", "hard"} {
		t.Run(difficulty, func(t *testing.T) {
			ps := testPlayers(2)
			ps[0].Team = 1
			ps[1] = &Player{ID: 1, Name: "BOT", Kind: "bot", Difficulty: difficulty, Team: 2}
			g := newGame(7)
			g.startMatch(ps)
			openArena(g)
			g.buildNavigation()
			g.Phase = "playing"
			for id, p := range g.Tanks {
				if p != nil {
					p.X = 100 + float64(id)*280
					p.Y = 210
					p.Invulnerable = 0
					p.Angle = math.Pi
				}
			}
			for i := 0; i < 60*15 && g.Phase == "playing"; i++ {
				g.step(tickDT, [maxTanks]Input{}, ps)
			}
			if g.Phase != "roundOver" || g.Winner != 1 {
				t.Fatalf("bot did not engage stationary opponent: %+v", g.Tanks[1])
			}
		})
	}
}
func TestUnifiedSeededMixedTeamsPowerSimulation(t *testing.T) {
	for seed := int64(1); seed <= 6; seed++ {
		ps := testPlayers(4)
		for id := range ps {
			if ps[id] == nil {
				continue
			}
			ps[id].Team = id/2 + 1
			if id > 0 {
				ps[id].Kind = "bot"
				ps[id].Client = nil
				ps[id].Difficulty = []string{"easy", "normal", "hard"}[id-1]
			}
		}
		g := newGame(seed)
		g.startMatch(ps)
		for step := 0; step < 60*35; step++ {
			if step%120 == 0 {
				for id, tank := range g.Tanks {
					if tank != nil && tank.Alive {
						g.grantPower(tank, pickupTypes[(step/120+id)%len(pickupTypes)])
					}
				}
			}
			g.step(tickDT, [maxTanks]Input{}, ps)
			for _, tank := range g.Tanks {
				if tank != nil && (math.IsNaN(tank.X) || math.IsNaN(tank.Angle) || tank.X < 0 || tank.X > g.World.Width) {
					t.Fatal("nonfinite/out-of-bounds bot")
				}
			}
			if g.Scores[0] != g.Scores[1] || g.Scores[2] != g.Scores[3] {
				t.Fatal("team scoring diverged")
			}
		}
	}
}
func TestUnifiedRoomAndSnapshotExposeOnlyPublicSeatData(t *testing.T) {
	h, cs, r := makeRoom(t, 1)
	addSeat(t, h, cs[0], "bot", "hard", 2)
	r.Game.startMatch(r.Players)
	b, _ := json.Marshal(h.roomMessage(r))
	var m map[string]any
	_ = json.Unmarshal(b, &m)
	rows := m["players"].([]any)
	bot := rows[1].(map[string]any)
	if bot["kind"] != "bot" || bot["difficulty"] != "hard" || bot["connected"] != true || bot["team"] != float64(2) {
		t.Fatal("public roster missing fields")
	}
	if _, ok := bot["token"]; ok {
		t.Fatal("credential leaked")
	}
}
