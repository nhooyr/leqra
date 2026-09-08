package main

import (
	"bytes"
	"encoding/json"
	"testing"
	"time"
)

func retryWave433(t *testing.T, h *Hub, c *Client) {
	t.Helper()
	g := c.room.Game
	action(t, h, c, map[string]any{"type": "restart_wave", "generation": g.Generation, "wave": g.survivalState().Wave})
}

func reachSurvivalWave433(t *testing.T, r *Room, wave int) {
	t.Helper()
	g := r.Game
	g.Phase = "playing"
	for g.survivalState().Wave < wave {
		clearSurvivalWave427(t, r)
		if !g.prepareSurvival(4, r.Players) {
			t.Fatal("wave did not advance")
		}
	}
}

func TestSurvival433RetryRestoresBoundaryWithoutRegeneratingMaze(t *testing.T) {
	h, clients, r := survivalRoom427(t, 2)
	g := r.Game
	g.Rules.PickupRate = "off"
	g.startMatch(r.Players)
	g.Phase = "playing"
	g.stats.duration = 9.5
	for _, tank := range g.Tanks {
		if tank != nil && tank.SurvivalEnemy {
			tank.Invulnerable = 0
			g.hurt(tank, &Bullet{Owner: 0})
		}
	}
	g.Tanks[1].Invulnerable = 0
	g.hurt(g.Tanks[1], &Bullet{Owner: 1})
	g.stepSurvival(r.Players)
	g.prepareSurvival(4, r.Players)
	s, cp := g.survivalState(), g.survivalCheckpoint
	if s.Wave != 2 || cp.rows[0].Eliminations != 2 || cp.rows[1].Deaths != 1 {
		t.Fatal("fixture did not capture completed-wave combat statistics")
	}
	world, _ := json.Marshal(g.World)
	walls, navigation, spatial := &g.World.Walls[0], &g.Neighbors[0], g.spatial
	generation := g.Generation
	g.stats.duration = 52
	g.Tanks[0].stats.Eliminations += 11
	g.Tanks[1].stats.Deaths += 4
	g.Tanks[0].Power, g.Tanks[0].PowerTime, g.Tanks[0].MachineRounds = "rapid", 8, 30
	g.Tanks[0].Shield, g.Tanks[0].ShieldCharges = 8, 3
	g.Tanks[0].SpeedTime, g.Tanks[0].SpeedStacks = 8, 3
	g.Tanks[0].ScopeTime, g.Tanks[0].GhostTime = 8, 8
	g.Tanks[0].fireHeld, g.Tanks[0].fireBlocked = true, true
	g.Tanks[0].AI = &BotState{}
	r.Players[0].Input = Input{Seq: 97, Fire: true, Forward: true}
	r.Players[0].FirePending = true
	g.endSurvival(r.Players, false)
	finished := g.matchReport
	finishedWire := append([]byte(nil), g.matchReportWire...)
	g.Bullets = []*Bullet{{Owner: 0, Kind: "grenade"}}
	g.Pickups = []*Pickup{{ID: 900, Life: 8}}
	g.roundClinched, g.objectiveEnded = true, true
	for _, c := range clients {
		drain(c)
		c.mapGeneration = generation
	}
	retryWave433(t, h, clients[0])
	nextWorld, _ := json.Marshal(g.World)
	if !bytes.Equal(world, nextWorld) || walls != &g.World.Walls[0] || navigation != &g.Neighbors[0] || spatial != g.spatial {
		t.Fatal("retry rebuilt the maze or its navigation/collision caches")
	}
	if g.Generation != generation+1 || g.Phase != "countdown" || g.PhaseTime != 2.6 || g.Clock != float64(g.settings().TimeLimit) || g.Winner != -1 || g.Round != 2 || g.roundClinched || g.objectiveEnded {
		t.Fatal("retry did not establish a fresh combat lifecycle")
	}
	if s.Status != "wave" || s.Wave != 2 || s.WavesCleared != 1 || s.EnemiesRemaining != 2 || s.BreakTime != 0 || g.survivalCheckpoint != cp {
		t.Fatal("retry changed the wave or discarded its checkpoint", s)
	}
	if g.matchReport != nil || g.matchReportWire != nil || g.stats.duration != 9.5 || g.stats.rows[0].Eliminations != 2 || g.stats.rows[1].Deaths != 1 || g.stats.rows[1].SelfDestructs != 1 {
		t.Fatal("failed-attempt statistics survived the retry")
	}
	if finished.Duration != 52 || !bytes.Equal(finishedWire, mustJSON433(t, finished)) {
		t.Fatal("retry mutated an already published report")
	}
	if len(g.Bullets) != 0 || len(g.Pickups) != 0 || r.Players[0].Input != (Input{Seq: 97}) || r.Players[0].FirePending {
		t.Fatal("old hazards or held controls survived")
	}
	for id, p := range r.Players {
		if p == nil {
			continue
		}
		tank := g.Tanks[id]
		if !tank.Alive || tank.stats != g.stats.members[p] || tank.stats == &cp.rows[id] || g.Scores[id] != 1 || tank.Power != "" || tank.PowerTime != 0 || tank.MachineRounds != 0 || tank.Shield != 0 || tank.ShieldCharges != 0 || tank.SpeedTime != 0 || tank.SpeedStacks != 0 || tank.ScopeTime != 0 || tank.GhostTime != 0 || tank.AI != nil || tank.fireHeld || tank.fireBlocked {
			t.Fatal("squad did not revive cleanly with its own restored statistics")
		}
	}
	for _, e := range g.events {
		if e.Generation != g.Generation || e.Type == "matchEnd" {
			t.Fatal("stale outcome event survived restart")
		}
	}
	for _, c := range clients {
		states := 0
		for _, m := range drain(c) {
			if m["type"] == "state" {
				states++
				if m["generation"] != float64(g.Generation) || m["phase"] != "countdown" || m["world"] == nil || m["matchReport"] != nil {
					t.Fatal("client did not get reliable fresh lifecycle state", m)
				}
			}
		}
		if states != 1 {
			t.Fatal("every connected client must receive the restarted wave")
		}
	}
	g.step(2.6, [maxTanks]Input{}, r.Players)
	if g.Phase != "playing" || g.stats.duration != 9.5 || g.Clock != float64(g.settings().TimeLimit) {
		t.Fatal("countdown consumed live time or failed to resume")
	}
}

func mustJSON433(t *testing.T, v any) []byte {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func TestSurvival433RepeatedLossRetriesDoNotFarmStatsOrKeepResults(t *testing.T) {
	h, clients, r := survivalRoom427(t, 1)
	g := r.Game
	g.Rules.ScoreTarget = 2
	g.startMatch(r.Players)
	reachSurvivalWave433(t, r, 2)
	firstGeneration := g.Generation
	for attempt := 0; attempt < 3; attempt++ {
		g.Phase = "playing"
		g.stats.duration += 12
		g.Tanks[0].Invulnerable = 0
		g.hurt(g.Tanks[0], &Bullet{Owner: 0})
		g.stepSurvival(r.Players)
		if g.matchReport == nil || g.matchReport.Players[0].Deaths != 1 || g.matchReport.Duration != 12 || g.survivalState().Status != "lost" {
			t.Fatal("repeated attempt did not freeze its own independent result")
		}
		retryWave433(t, h, clients[0])
		if g.matchReport != nil || g.stats.duration != 0 || g.Tanks[0].stats.Deaths != 0 || g.Generation != firstGeneration+attempt+1 || g.survivalState().WavesCleared != 1 {
			t.Fatal("retry carried failed-attempt statistics or lost earned progress")
		}
	}
	g.Phase = "playing"
	clearSurvivalWave427(t, r)
	if g.survivalState().Status != "won" || g.matchReport == nil || g.matchReport.Players[0].Score != 2 || g.matchReport.Players[0].Deaths != 0 || !g.matchReport.Players[0].Winner {
		t.Fatal("retried run could not complete with a fresh winning report")
	}
	if code, _ := g.survivalRestartError(r.Players, g.Generation, 2); code != "wave_unavailable" {
		t.Fatal("completed run can be restarted from its final wave")
	}
}

func TestSurvival433RetryRestoresEachBossTierAndGear(t *testing.T) {
	for _, wave := range []int{5, 10, 15} {
		t.Run(survivalBossName(wave), func(t *testing.T) {
			h, clients, r := survivalRoom427(t, 1)
			g := r.Game
			g.Rules.ScoreTarget = 20
			g.startMatch(r.Players)
			reachSurvivalWave433(t, r, wave)
			var initial Tank
			for _, tank := range g.Tanks {
				if tank != nil && tank.SurvivalBoss {
					initial = *tank
					tank.Alive, tank.Power, tank.ShieldCharges = false, "", 0
				}
			}
			g.Clock = 1
			g.stepSurvival(r.Players)
			retryWave433(t, h, clients[0])
			bosses, enemies := 0, 0
			for _, tank := range g.Tanks {
				if tank == nil || !tank.SurvivalEnemy {
					continue
				}
				enemies++
				if !tank.Alive || tank.stats != nil || r.Players[tank.ID] != nil {
					t.Fatal("retry spawned an invalid wave enemy")
				}
				if tank.SurvivalBoss {
					bosses++
					if tank.Name != initial.Name || tank.Difficulty != initial.Difficulty || tank.Power != initial.Power || tank.ShieldCharges != initial.ShieldCharges || tank.SpeedStacks != initial.SpeedStacks {
						t.Fatal("retry changed the boss composition or lost its initial gear")
					}
				} else if tank.Difficulty != survivalDifficulty(wave) {
					t.Fatal("retry changed the regular enemy skill tier")
				}
			}
			if bosses != 1 || enemies != 4 || !g.survivalState().Boss || g.survivalState().Wave != wave || g.survivalState().WavesCleared != wave-1 {
				t.Fatal("retry did not reconstruct the complete boss wave")
			}
		})
	}
}

func TestSurvival433RetryRebindsParticipantIdentityAfterSeatReuse(t *testing.T) {
	h, clients, r := survivalRoom427(t, 2)
	g := r.Game
	g.startMatch(r.Players)
	g.stats.rows[1].Eliminations = 3
	reachSurvivalWave433(t, r, 2)
	old := r.Players[1]
	g.stats.rows[1].Eliminations = 17
	g.endSurvival(r.Players, false)
	r.moveMember(old, r.viewerID(), true)
	replacement := &Player{ID: 1, Member: 900, Name: "REPLACEMENT", Team: 1, Kind: "bot", Difficulty: "hard"}
	r.Players[1] = replacement
	retryWave433(t, h, clients[0])
	if len(g.stats.rows) != 3 || g.stats.members[old].Eliminations != 3 || g.stats.members[old].Active || g.stats.members[replacement].Eliminations != 0 || g.Tanks[1].stats != g.stats.members[replacement] || g.Tanks[1].Name != "REPLACEMENT" || g.Tanks[1].Difficulty != "hard" || g.Scores[1] != 1 {
		t.Fatal("replacement inherited departed participant statistics or lost squad progress")
	}
	g.Phase = "playing"
	g.stats.members[replacement].Eliminations = 4
	g.endSurvival(r.Players, false)
	retryWave433(t, h, clients[0])
	if len(g.stats.rows) != 3 || g.stats.members[replacement].Eliminations != 0 || g.stats.members[old].Eliminations != 3 {
		t.Fatal("repeated retry changed the identity checkpoint")
	}
}

func TestSurvival433SpectatingHostCanRetryAllBotSquad(t *testing.T) {
	h, clients, r := survivalRoom427(t, 1)
	action(t, h, clients[0], map[string]any{"type": "add", "kind": "bot", "difficulty": "godlike"})
	action(t, h, clients[0], map[string]any{"type": "spectate", "spectating": true})
	g := r.Game
	g.startMatch(r.Players)
	g.Phase = "playing"
	for _, tank := range g.Tanks {
		if tank != nil && !tank.SurvivalEnemy {
			tank.Alive = false
		}
	}
	g.stepSurvival(r.Players)
	retryWave433(t, h, clients[0])
	allies := 0
	for _, tank := range g.Tanks {
		if tank != nil && !tank.SurvivalEnemy {
			allies++
			if !tank.Alive || !tank.Bot || tank.Name == clients[0].player.Name {
				t.Fatal("spectating host acquired a hidden combat seat")
			}
		}
	}
	if g.Phase != "countdown" || allies != 1 || len(g.stats.rows) != 1 {
		t.Fatal("bot-only squad could not retry")
	}
}

func TestSurvival433RetryDoesNotReviveDisconnectedMembers(t *testing.T) {
	h, clients, r := survivalRoom427(t, 2)
	g := r.Game
	g.startMatch(r.Players)
	r.Players[1].Client = nil
	g.Phase = "playing"
	retryWave433(t, h, clients[0])
	if !g.Tanks[0].Alive || g.Tanks[1] == nil || g.Tanks[1].Alive || g.Tanks[1].RespawnTime != 0 {
		t.Fatal("retry revived a disconnected squad member")
	}
}

func TestSurvival433RetryRejectsUnavailableOrStaleStates(t *testing.T) {
	for _, scenario := range []string{"lobby", "break", "won", "mode", "generation", "wave", "missing_generation", "missing_wave", "checkpoint", "empty", "disconnected", "team", "capacity"} {
		t.Run(scenario, func(t *testing.T) {
			h, clients, r := survivalRoom427(t, 1)
			g := r.Game
			g.startMatch(r.Players)
			g.Phase = "playing"
			generation, wave := g.Generation, g.survivalState().Wave
			code := "wave_unavailable"
			switch scenario {
			case "lobby":
				g.Phase = "lobby"
			case "break":
				clearSurvivalWave427(t, r)
			case "won":
				g.endSurvival(r.Players, true)
			case "mode":
				g.Rules.Mode = "elimination"
			case "generation":
				generation++
				code = "stale_wave"
			case "wave":
				wave++
				code = "stale_wave"
			case "missing_generation":
				generation = 0
				code = "stale_wave"
			case "missing_wave":
				wave = 0
				code = "stale_wave"
			case "checkpoint":
				g.survivalCheckpoint = nil
			case "empty":
				r.moveMember(clients[0].player, r.viewerID(), true)
				code = "not_ready"
			case "disconnected":
				r.Players[1] = &Player{ID: 1, Team: 1, Name: "OFFLINE"}
				r.moveMember(clients[0].player, r.viewerID(), true)
				code = "not_ready"
			case "team":
				r.Players[0].Team = 2
				code = "not_ready"
			case "capacity":
				for id := 1; id < 5; id++ {
					r.Players[id] = &Player{ID: id, Team: 1, Kind: "bot"}
				}
				code = "not_ready"
			}
			before := mustJSON433(t, h.stateMessage(r))
			drain(clients[0])
			action(t, h, clients[0], map[string]any{"type": "restart_wave", "generation": generation, "wave": wave})
			if !bytes.Equal(before, mustJSON433(t, h.stateMessage(r))) {
				t.Fatal("rejected retry mutated game state")
			}
			messages := drain(clients[0])
			if len(messages) != 1 || messages[0]["code"] != code || messages[0]["action"] != "restart_wave" {
				t.Fatal("retry rejection did not identify the pending action", messages)
			}
		})
	}
}

func TestSurvival433RetryRejectsDuplicateAndPriorWaveRequests(t *testing.T) {
	h, clients, r := survivalRoom427(t, 1)
	g := r.Game
	g.startMatch(r.Players)
	request := map[string]any{"type": "restart_wave", "generation": g.Generation, "wave": 1}
	action(t, h, clients[0], request)
	generation := g.Generation
	action(t, h, clients[0], request)
	if !hasError(clients[0], "stale_wave") || g.Generation != generation {
		t.Fatal("duplicate restart reset the wave twice")
	}
	request["generation"] = generation
	reachSurvivalWave433(t, r, 2)
	action(t, h, clients[0], request)
	if !hasError(clients[0], "stale_wave") || g.Generation != generation || g.survivalState().Wave != 2 {
		t.Fatal("delayed previous-wave request reset the current wave")
	}
}

func TestSurvival433RetryRequiresAuthenticatedPrivateHost(t *testing.T) {
	for _, scenario := range []string{"guest", "foreign_socket", "not_joined", "matchmaking", "queue", "away", "version", "rate"} {
		t.Run(scenario, func(t *testing.T) {
			h, clients, r := survivalRoom427(t, 2)
			g := r.Game
			g.startMatch(r.Players)
			c, code := clients[0], "not_host"
			switch scenario {
			case "guest":
				c = clients[1]
			case "foreign_socket":
				c = fakeClient()
				c.room, c.player = r, clients[0].player
				code = "not_joined"
			case "not_joined":
				c = fakeClient()
				code = "not_joined"
			case "matchmaking":
				r.Match = &QueueMatch{}
				code = "match_locked"
			case "queue":
				r.Queue = &QueueTicket{}
				code = "queue_locked"
			case "away":
				r.Players[1].Away = &MatchTravel{Battle: &Room{Code: "AWAY"}}
				code = "party_away"
			case "version":
				c.requireVersion, c.versionOK = true, false
				code = "version_mismatch"
			case "rate":
				c.msgWindow, c.actionCount = time.Now(), 8
			}
			before, generation := mustJSON433(t, h.stateMessage(r)), g.Generation
			drain(c)
			b := mustJSON433(t, map[string]any{"type": "restart_wave", "generation": generation, "wave": 1})
			err := h.handle(c, b, time.Now())
			if scenario == "rate" {
				if err == nil || err.Error() != "Action rate exceeded" {
					t.Fatal("restart did not honor action rate limit", err)
				}
			} else {
				if err != nil || !hasError(c, code) {
					t.Fatal("restart bypassed authenticated host, queue, or version guard", code, err)
				}
			}
			if g.Generation != generation || !bytes.Equal(before, mustJSON433(t, h.stateMessage(r))) {
				t.Fatal("unauthorized restart changed match state")
			}
		})
	}
}

func TestSurvival433NextWaveRefreshesCheckpointAndNewMatchClearsIt(t *testing.T) {
	h, clients, r := survivalRoom427(t, 1)
	g := r.Game
	g.startMatch(r.Players)
	first := g.survivalCheckpoint
	g.stats.rows[0].Eliminations = 2
	g.stats.duration = 7
	reachSurvivalWave433(t, r, 2)
	second := g.survivalCheckpoint
	if first == second || first.wave != 1 || second.wave != 2 || second.duration != 7 || first.rows[0].Eliminations != 0 || second.rows[0].Eliminations != 2 {
		t.Fatal("wave boundary checkpoint aliases live or previous-wave statistics")
	}
	retryWave433(t, h, clients[0])
	g.stats.rows[0].Eliminations = 4
	g.stats.duration = 16
	reachSurvivalWave433(t, r, 3)
	if g.survivalCheckpoint.wave != 3 || g.survivalCheckpoint.duration != 16 || g.survivalCheckpoint.rows[0].Eliminations != 4 || second.rows[0].Eliminations != 2 {
		t.Fatal("successful retried wave did not advance the immutable checkpoint")
	}
	g.startMatch(r.Players)
	if g.survivalCheckpoint.wave != 1 || g.survivalCheckpoint.duration != 0 || g.survivalCheckpoint.rows[0].Eliminations != 0 {
		t.Fatal("new Survival run inherited a previous checkpoint")
	}
	g.Rules.Mode = "elimination"
	g.startMatch(r.Players)
	if g.survivalCheckpoint != nil {
		t.Fatal("non-Survival match retained restart state")
	}
}

func TestSurvival433SetupChangesInvalidateLostWaveCheckpoint(t *testing.T) {
	for _, scenario := range []string{"map", "mode", "target", "weapons", "lobby", "preset", "same_rules", "invalid_rules"} {
		t.Run(scenario, func(t *testing.T) {
			h, clients, r := survivalRoom427(t, 1)
			g := r.Game
			g.startMatch(r.Players)
			g.endSurvival(r.Players, false)
			checkpoint := g.survivalCheckpoint
			originalRules := g.settings()
			rules := originalRules
			switch scenario {
			case "map":
				rules.MapSize = "compact"
			case "mode":
				rules.Mode = "elimination"
			case "target":
				rules.ScoreTarget = 15
			case "weapons":
				rules.Weapons = []string{"laser"}
			case "invalid_rules":
				rules.Mode = "unknown"
			}
			switch scenario {
			case "lobby":
				action(t, h, clients[0], map[string]any{"type": "lobby"})
			case "preset":
				action(t, h, clients[0], map[string]any{"type": "preset", "rules": rules, "roster": []SeatSpec{{Name: "HOST", Kind: "human", Team: 1}}})
			default:
				action(t, h, clients[0], map[string]any{"type": "rules", "rules": rules})
			}
			if scenario == "same_rules" || scenario == "invalid_rules" {
				if g.survivalCheckpoint != checkpoint {
					t.Fatal("unchanged or rejected rules discarded a valid restart")
				}
				retryWave433(t, h, clients[0])
				if g.Phase != "countdown" {
					t.Fatal("unchanged settings prevented retry")
				}
				return
			}
			if g.survivalCheckpoint != nil {
				t.Fatal("setup changed but retained a stale Survival checkpoint")
			}
			// Returning to the old settings must not resurrect a checkpoint whose
			// maze, enemies, time limit, or mode may no longer match the setup.
			action(t, h, clients[0], map[string]any{"type": "rules", "rules": originalRules})
			drain(clients[0])
			action(t, h, clients[0], map[string]any{"type": "restart_wave", "generation": g.Generation, "wave": 1})
			if !hasError(clients[0], "wave_unavailable") || g.Phase == "countdown" {
				t.Fatal("stale results reopened after restoring earlier setup values")
			}
		})
	}
}

func TestSurvival433RestartCapabilityFollowsWaveTransitionsAndSetup(t *testing.T) {
	h, clients, r := survivalRoom427(t, 1)
	g, c := r.Game, clients[0]
	if h.roomMessage(r)["canRestartWave"] != false {
		t.Fatal("lobby advertised a Survival retry")
	}
	g.startMatch(r.Players)
	if h.roomMessage(r)["canRestartWave"] != true {
		t.Fatal("countdown did not advertise its restart capability")
	}
	checkRoom := func(want bool) {
		t.Helper()
		count := 0
		for _, message := range drain(c) {
			if message["type"] == "room" {
				count++
				if message["canRestartWave"] != want {
					t.Fatal("room advertised a stale restart capability", message["canRestartWave"])
				}
			}
		}
		if count != 1 {
			t.Fatal("wave transition should publish room metadata exactly once", count)
		}
	}
	g.Phase = "playing"
	for _, tank := range g.Tanks {
		if tank != nil && tank.SurvivalEnemy {
			tank.Alive = false
		}
	}
	drain(c)
	h.tick(time.Now())
	checkRoom(false)
	if g.survivalState().Status != "break" {
		t.Fatal("fixture did not enter intermission")
	}
	g.survivalState().BreakTime = tickDT / 2
	h.tick(time.Now())
	checkRoom(true)
	if g.survivalState().Wave != 2 {
		t.Fatal("fixture did not begin the next wave")
	}
	g.Tanks[0].Alive = false
	h.tick(time.Now())
	checkRoom(true)
	if g.survivalState().Status != "lost" {
		t.Fatal("fixture did not lose")
	}
	rules := g.settings()
	rules.TimeLimit = 120
	h.setRules(c, clientMessage{Rules: &rules}, time.Now())
	checkRoom(false)
}
