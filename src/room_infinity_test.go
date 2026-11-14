package main

import (
	"math/rand/v2"
	"testing"
	"time"
)

func TestRoomInfinityLaunchRequiresReadyCombatPilots(t *testing.T) {
	h, clients, r := makeRoom(t, 2)
	host, guest := clients[0], clients[1]
	viewer := fakeClient()
	h.addClient(viewer)
	action(t, h, viewer, map[string]any{"type": "join", "code": r.Code, "name": "VIEWER", "spectating": true})

	rules := r.Game.settings()
	rules.Infinity = true
	rules.MapSize = "compact"
	action(t, h, host, map[string]any{"type": "rules", "rules": rules})
	drain(host)
	drain(guest)
	drain(viewer)
	if got := h.roomWire(r); !got.Rules.Infinity || got.Rules.MapSize != "compact" || got.CanStart || got.InfinityActive {
		t.Fatalf("unexpected room before guests are ready: %+v", got)
	}
	action(t, h, guest, map[string]any{"type": "start"})
	if !hasError(guest, "not_host") {
		t.Fatal("guest was allowed to start Infinity")
	}
	action(t, h, host, map[string]any{"type": "start"})
	if !hasError(host, "not_ready") || r.infinityActive {
		t.Fatal("host started Infinity before the guest readied up")
	}
	action(t, h, guest, map[string]any{"type": "ready", "ready": true})
	if !h.roomWire(r).CanStart {
		t.Fatal("ready combat pilots could not start Infinity")
	}
	action(t, h, host, map[string]any{"type": "start"})
	if r.Game.Phase != "lobby" || !r.infinityActive || h.roomWire(r).CanStart || guest.player.Ready {
		t.Fatal("Infinity launch did not preserve the finite lobby and consume guest readiness")
	}
	for _, client := range clients {
		active, start := false, false
		for _, packet := range drain(client) {
			if packet["type"] == "room" && packet["infinityActive"] == true {
				active = true
			}
			if packet["type"] == "infinity_start" {
				start = active && len(packet) == 1
			}
		}
		if !start {
			t.Fatal("combat pilot did not receive the private launch after room metadata")
		}
	}
	if !receivedType(viewer, "infinity_start") {
		t.Fatal("room spectator did not receive its read-only Infinity launch")
	}
	if _, p, _, _ := h.infiniteMember(r.Code, viewer.player.Token); p != nil {
		t.Fatal("spectator credentials authenticated a private combat pilot")
	}
}

func TestRoomInfinityScoreTargetRequiresAnOpponent(t *testing.T) {
	for _, test := range []struct {
		name       string
		teamMode   string
		target     int
		botTeam    int
		randomBots bool
		canStart   bool
	}{
		{name: "solo score target", target: 5, botTeam: -1},
		{name: "same team", teamMode: "teams", target: 5, botTeam: 1},
		{name: "opposing team", teamMode: "teams", target: 5, botTeam: 2, canStart: true},
		{name: "free-for-all bot", target: 5, canStart: true},
		{name: "random bots", target: 5, botTeam: -1, randomBots: true, canStart: true},
		{name: "endless exploration", botTeam: -1, canStart: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			h, clients, r := makeRoom(t, 1)
			host := clients[0]
			rules := r.Game.settings()
			rules.Infinity, rules.InfinityTarget, rules.InfinityRandomBots = true, test.target, test.randomBots
			rules.TeamMode = "ffa"
			if test.teamMode != "" {
				rules.TeamMode = test.teamMode
			}
			action(t, h, host, map[string]any{"type": "rules", "rules": rules})
			if test.botTeam >= 0 {
				action(t, h, host, map[string]any{"type": "add", "kind": "bot", "name": "OTHER", "team": test.botTeam})
			}
			drain(host)
			packet := h.roomWire(r)
			if packet.CanStart != test.canStart || (packet.StartError == "") != test.canStart {
				t.Fatalf("unexpected start eligibility: can start %v, error %q", packet.CanStart, packet.StartError)
			}
			action(t, h, host, map[string]any{"type": "start"})
			if r.infinityActive != test.canStart || !test.canStart && !hasError(host, "not_ready") {
				t.Fatal("the host could bypass the score target lineup check")
			}
		})
	}
}

func TestRoomInfinityDoesNotCountLocalTankOfSpectatingController(t *testing.T) {
	h, clients, r := makeRoom(t, 2)
	host, guest := clients[0], clients[1]
	rules := r.Game.settings()
	rules.Infinity, rules.TeamMode, rules.InfinityTarget = true, "ffa", 5
	action(t, h, host, map[string]any{"type": "rules", "rules": rules})
	action(t, h, host, map[string]any{"type": "add", "kind": "local", "name": "CO-PILOT"})
	action(t, h, host, map[string]any{"type": "spectate", "spectating": true})
	action(t, h, guest, map[string]any{"type": "ready", "ready": true})
	if availableSides(r.Players) != 2 {
		t.Fatal("test fixture needs a spectator-owned tank in the combat roster")
	}
	if got := h.roomWire(r); got.CanStart || got.StartError != infiniteLocalPrimaryRequired {
		t.Fatalf("unavailable local player counted as an Infinity opponent: %+v", got)
	}
}

func TestRoomInfinityAuthorizationFollowsRoomMembershipAndGeneration(t *testing.T) {
	h, clients, r := makeRoom(t, 2)
	host, guest := clients[0], clients[1]
	pilot := guest.player
	code, token := r.Code, pilot.Token
	r.Game.Rules.Infinity = true
	action(t, h, guest, map[string]any{"type": "ready", "ready": true})
	action(t, h, host, map[string]any{"type": "start"})
	room, member, generation, setup := h.infiniteMember(code, token)
	if room != r || member != pilot || generation == 0 || setup.pilot.name != pilot.Name {
		t.Fatal("active combat pilot could not authenticate")
	}
	for _, invalid := range []struct{ code, token string }{{"other room", token}, {code, ""}, {code, "wrong token"}} {
		if _, member, _, _ := h.infiniteMember(invalid.code, invalid.token); member != nil {
			t.Fatal("invalid room or token was accepted")
		}
	}
	updated := r.LastAction.Add(time.Second)
	if !h.touchInfiniteMember(r, pilot, generation, updated) || r.LastAction != updated {
		t.Fatal("active Infinity gameplay did not keep the room alive")
	}
	action(t, h, host, map[string]any{"type": "rename_room", "code": "Infinity arena room"})
	if _, member, gen, _ := h.infiniteMember(code, token); member != pilot || gen != generation {
		t.Fatal("private Infinity reconnect did not follow a room rename")
	}
	action(t, h, guest, map[string]any{"type": "spectate", "spectating": true})
	if h.validInfiniteMember(r, pilot, generation) {
		t.Fatal("moving to spectators did not revoke combat access")
	}
	action(t, h, host, map[string]any{"type": "lobby"})
	if r.infinityActive || h.validInfiniteMember(r, host.player, generation) {
		t.Fatal("returning to the room did not close the private arena")
	}
	action(t, h, host, map[string]any{"type": "start"})
	if _, _, next, _ := h.infiniteMember(r.Code, host.player.Token); next <= generation || h.validInfiniteMember(r, host.player, generation) {
		t.Fatal("previous Infinity socket could reenter a new generation")
	}
}

func TestRoomInfinityLaunchClearsPriorFiniteMatchResult(t *testing.T) {
	h, clients, r := makeRoom(t, 2)
	host, guest := clients[0], clients[1]
	r.Game.startMatch(r.Players)
	r.Game.Scores[0] = 5
	r.Game.Winner = 0
	r.Game.finishMatchStats(0)
	r.Game.Phase = "matchOver"
	r.Game.Rules.Infinity = true
	action(t, h, guest, map[string]any{"type": "ready", "ready": true})
	action(t, h, host, map[string]any{"type": "start"})
	if !r.infinityActive || h.roomWire(r).Phase != "lobby" {
		t.Fatal("starting Infinity did not replace the finished finite match")
	}
	late := fakeClient()
	h.addClient(late)
	action(t, h, late, map[string]any{"type": "join", "code": r.Code, "name": "MOBILE PILOT"})
	gotLobby := false
	for _, packet := range drain(late) {
		if packet["type"] != "state" {
			continue
		}
		if packet["phase"] != "lobby" || packet["matchStats"] != nil || packet["winner"] != float64(-1) {
			t.Fatalf("late Infinity pilot got a stale finite result: %v", packet)
		}
		gotLobby = true
	}
	if !gotLobby {
		t.Fatal("late Infinity pilot received no lobby state")
	}
}

func TestRoomInfinityDisconnectGraceAndKick(t *testing.T) {
	h, clients, r := makeRoom(t, 2)
	host, guest := clients[0], clients[1]
	pilot := guest.player
	r.Game.Rules.Infinity = true
	action(t, h, guest, map[string]any{"type": "ready", "ready": true})
	action(t, h, host, map[string]any{"type": "start"})
	generation := r.infinityGeneration
	h.removeClient(guest)
	if !h.validInfiniteMember(r, pilot, generation) {
		t.Fatal("a brief room socket interruption revoked Infinity combat access")
	}
	if h.touchInfiniteMember(r, pilot, generation, pilot.DisconnectedAt.Add(reconnectGrace+time.Millisecond)) {
		t.Fatal("a disconnected pilot remained authorized past the room reconnect window")
	}
	action(t, h, host, map[string]any{"type": "kick", "target": pilot.ID, "member": pilot.Member})
	if _, p, _, _ := h.infiniteMember(r.Code, pilot.Token); p != nil || h.validInfiniteMember(r, pilot, generation) {
		t.Fatal("removed pilot retained Infinity combat access")
	}
}

func TestPrivateInfinityAuthenticatesLocalRosterAndKeepsRoomResult(t *testing.T) {
	h, clients, r := makeRoom(t, 2)
	host, guest := clients[0], clients[1]
	rules := r.Game.settings()
	rules.Mode, rules.Infinity, rules.InfinityTarget = "ctf", true, 12
	rules.TeamColors[2] = 7
	action(t, h, host, map[string]any{"type": "rules", "rules": rules})
	action(t, h, host, map[string]any{"type": "add", "kind": "local", "name": "CO-PILOT", "team": 3})
	action(t, h, guest, map[string]any{"type": "ready", "ready": true})
	action(t, h, host, map[string]any{"type": "start"})
	s := newInfiniteServer(h)
	now := time.Now()
	join := func(controller *Player) (infiniteConnection, *Client) {
		t.Helper()
		c := fakeClient()
		if !s.admit(c) {
			t.Fatal("failed to admit socket")
		}
		conn, reject := s.join(c, infiniteMessage{Code: r.Code, Token: controller.Token, Name: "FORGED", LocalName: "FORGED LOCAL"}, now)
		if reject != "" {
			t.Fatal(reject)
		}
		return conn, c
	}
	pair, pairSocket := join(host.player)
	solo, soloSocket := join(guest.player)
	if pair.local == nil || pair.local.Name != "CO-PILOT" || pair.local.Team != 3 || pair.local.ColorIndex != 7 ||
		pair.pilot.Name != host.player.Name || solo.local != nil || solo.arena != pair.arena ||
		pair.arena.rules.Target != 12 || s.privateCount != 3 {
		t.Fatalf("local seat, roster color, or capacity did not match the room: %+v %+v", pair.local, pair.arena.rules)
	}
	winner := infiniteResult{Team: 1, Name: "Team 1", Score: 12}
	pair.arena.result = &winner
	pair.arena.teamScores[0] = 12
	s.remove(pairSocket)
	s.remove(soloSocket)
	if s.privateCount != 0 || pair.arena.players != 0 || pair.arena.maze != nil || len(s.private) != 1 {
		t.Fatal("private score arena was not retained after both controllers left")
	}
	rejoined, socket := join(host.player)
	if rejoined.arena != pair.arena || *rejoined.arena.result != winner || rejoined.arena.teamScores[0] != 12 {
		t.Fatal("rejoining replaced the match instead of retaining it")
	}
	if got := drain(socket); len(got) != 2 || got[1]["type"] != "state" || got[1]["result"] == nil {
		t.Fatalf("rejoining did not receive the final result: %v", got)
	}
	action(t, h, host, map[string]any{"type": "lobby"})
	s.step(now)
	if len(s.private) != 0 || s.privateCount != 0 {
		t.Fatal("ending Infinity did not release the arena")
	}
}

func TestPrivateInfinitySpawnsOnlyConfiguredBots(t *testing.T) {
	for _, configured := range []bool{false, true} {
		name := "empty roster"
		if configured {
			name = "configured bot"
		}
		t.Run(name, func(t *testing.T) {
			h, clients, r := makeRoom(t, 1)
			host := clients[0]
			rules := r.Game.settings()
			rules.Infinity, rules.TeamMode = true, "teams"
			rules.TeamColors[2] = 7
			action(t, h, host, map[string]any{"type": "rules", "rules": rules})
			if configured {
				action(t, h, host, map[string]any{"type": "add", "kind": "bot", "name": "ROSTER BOT", "team": 3, "difficulty": "hard"})
			}
			action(t, h, host, map[string]any{"type": "start"})
			s := newInfiniteServer(h)
			now := time.Now()
			join := func() (infiniteConnection, *Client) {
				t.Helper()
				c := fakeClient()
				s.admit(c)
				conn, reject := s.join(c, infiniteMessage{Code: r.Code, Token: host.player.Token}, now)
				if reject != "" {
					t.Fatal(reject)
				}
				return conn, c
			}
			conn, socket := join()
			a := conn.arena
			wantPilots := 1
			if configured {
				wantPilots++
				if len(a.pilots) != wantPilots {
					t.Fatalf("expected configured bot at launch, got %d pilots", len(a.pilots))
				}
				bot := a.pilots[1]
				if !bot.Bot || bot.Name != "ROSTER BOT" || bot.Team != 3 || bot.ColorIndex != 7 || bot.botLevel != infiniteBotLevel("hard") {
					t.Fatalf("bot did not use its roster seat: %+v", bot.infiniteTank)
				}
				bot.X, bot.HP, bot.respawn = conn.pilot.X+infiniteSight*2, 0, a.tick+1
				spawn := bot.Spawn
				a.step(now)
				if len(a.pilots) != wantPilots || a.pilots[1] != bot || bot.HP == 0 || bot.Spawn != spawn+1 {
					t.Fatal("distant configured bot did not keep its seat and respawn")
				}
			}
			for i := range 10 {
				a.tick = a.nextBot + uint64(i)
				a.populate()
			}
			if len(a.pilots) != wantPilots {
				t.Fatalf("room spawned an unconfigured bot: got %d pilots, want %d", len(a.pilots), wantPilots)
			}
			s.remove(socket)
			rejoined, socket := join()
			if rejoined.arena != a || len(a.pilots) != wantPilots {
				t.Fatal("reopening an empty room changed its configured bot roster")
			}
			if configured {
				bot := a.pilots[1]
				a.bullets = append(a.bullets, infiniteBullet{Owner: bot.ID, Life: 10})
				action(t, h, host, kickRequest(bot.roomBot))
				s.step(now)
				if len(a.roomBots) != 0 || len(a.pilots) != 1 || len(a.bullets) != 0 {
					t.Fatal("kicked bot kept its seat, tank or in-flight bullets")
				}
				s.remove(socket)
				join()
				if len(a.pilots) != 1 {
					t.Fatal("kicked bot respawned when a pilot rejoined")
				}
			}
		})
	}
}

func TestPrivateInfinityRandomBotsKeepConfiguredRosterAndUseRoomDifficulty(t *testing.T) {
	for _, tc := range []struct {
		name   string
		random bool
	}{{"fixed", false}, {"random up to maximum", true}} {
		t.Run(tc.name, func(t *testing.T) {
			h, clients, r := makeRoom(t, 1)
			host := clients[0]
			rules := r.Game.settings()
			rules.Infinity, rules.TeamMode = true, "teams"
			rules.InfinityRandomBots, rules.InfinityBotDifficulty, rules.InfinityRandomDifficulty = true, "hard", tc.random
			action(t, h, host, map[string]any{"type": "rules", "rules": rules})
			action(t, h, host, map[string]any{"type": "add", "kind": "bot", "name": "ALLY", "team": 1, "difficulty": "godlike"})
			action(t, h, host, map[string]any{"type": "start"})
			s := newInfiniteServer(h)
			c := fakeClient()
			s.admit(c)
			conn, reject := s.join(c, infiniteMessage{Code: r.Code, Token: host.player.Token}, time.Now())
			if reject != "" {
				t.Fatal(reject)
			}
			a := conn.arena
			a.random = rand.New(rand.NewPCG(17, 1))
			roster := a.pilots[1]
			if roster.Name != "ALLY" || roster.Team != 1 || roster.botLevel != infiniteBotLevel("godlike") {
				t.Fatal("roster bot inherited the ambient bot configuration")
			}
			far := conn.pilot.X + infiniteSight*2
			roster.X = far
			maxLevel := infiniteBotLevel("hard")
			var seen uint64
			for i := range 24 {
				a.tick = a.nextBot
				a.populate()
				if len(a.pilots) != 2+min(i+1, 8) || a.pilots[1] != roster || roster.X != far {
					t.Fatal("spawn cycle did not preserve the configured roster and roaming budget")
				}
				for _, bot := range a.pilots[2:] {
					if !bot.Bot || bot.roomBot != nil || bot.Team < 1 || bot.Team > 2 || bot.botLevel > maxLevel || !tc.random && bot.botLevel != maxLevel {
						t.Fatalf("roaming bot ignored the room setup: team %d, level %d", bot.Team, bot.botLevel)
					}
					seen |= 1 << bot.botLevel
					bot.X = far
				}
			}
			if tc.random && seen != (1<<(maxLevel+1))-1 {
				t.Fatalf("seeded spawn sequence did not use all selected levels: %b", seen)
			}
		})
	}
}

func TestInfinityBotDifficultyRulesAcceptLegacyDefaults(t *testing.T) {
	rules := defaultRules()
	if rules.InfinityRandomBots || rules.InfinityRandomDifficulty || rules.InfinityBotDifficulty != "normal" {
		t.Fatal("unexpected default Infinity bot settings")
	}
	for _, level := range []string{"", "easy", "normal", "hard", "godlike"} {
		rules.InfinityBotDifficulty = level
		if err := validateRules(rules); err != nil {
			t.Fatalf("rejected valid Infinity difficulty %q: %v", level, err)
		}
	}
	rules.InfinityBotDifficulty = ""
	if normalizedRules(rules).InfinityBotDifficulty != "normal" {
		t.Fatal("legacy rules did not default to Normal difficulty")
	}
	rules.InfinityBotDifficulty = "impossible"
	if validateRules(rules) == nil {
		t.Fatal("accepted an invalid Infinity bot difficulty")
	}
}

func TestInfinityRulesValidateTargetAndOverrideLegacyModeTeams(t *testing.T) {
	rules := defaultRules()
	rules.Mode, rules.Infinity = "survival", true
	for _, target := range []int{0, 1, 999} {
		rules.InfinityTarget = target
		if err := validateRules(rules); err != nil || activeTeamCount(normalizedRules(rules)) != 0 {
			t.Fatalf("legacy mode did not accept Infinity FFA and target %d: %v", target, err)
		}
	}
	for _, target := range []int{-1, 1000} {
		rules.InfinityTarget = target
		if err := validateRules(rules); err == nil {
			t.Fatalf("invalid target accepted: %d", target)
		}
	}
}
