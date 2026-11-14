package main

import (
	"database/sql"
	"fmt"
	"math"
	"path/filepath"
	"testing"
	"time"
)

func TestRoomInfinityFiveTierPoolsKeepUniqueNumbersAndReuseScores(t *testing.T) {
	rules := defaultRules()
	rules.InfinityRandomBots = true
	a := newRoomInfiniteArena(rules, nil)
	for i := range maxTanks {
		a.join(fakeClient(), fmt.Sprintf("Human %d", i), time.Unix(0, 0))
	}
	identities := make(map[int]*infinitePilot)
	numbers := make(map[int]int)
	for level, tuning := range infiniteBotTunings {
		a.rules.BotSpawnRates = map[string]float64{tuning.name: 2}
		fillRoamingBots(a)
		if len(roamingBots(a)) != infiniteRoomBotLimit {
			t.Fatal("tier did not fill its active budget", tuning.name, len(roamingBots(a)))
		}
		for _, bot := range roamingBots(a) {
			if bot.botLevel != level || identities[bot.ID] != nil || numbers[bot.ambientNumber] != 0 {
				t.Fatal("new tier changed or duplicated another identity", bot.ID, bot.Name)
			}
			identities[bot.ID], numbers[bot.ambientNumber] = bot, bot.ID
			bot.Score = bot.ID + 10
		}
		a.rules.RandomBots = false
		a.trimRoamingBots()
		a.rules.RandomBots = true
	}
	if len(identities) != infiniteRoomBotLimit*len(infiniteBotTunings) || len(a.inactiveBots) != len(identities) || len(a.rankedLeaders(nil)) != len(identities)+maxTanks {
		t.Fatal("parked five-tier standings lost identities", len(identities), len(a.inactiveBots), len(a.rankedLeaders(nil)))
	}
	lastID := a.nextID
	for _, tuning := range infiniteBotTunings {
		a.rules.BotSpawnRates = map[string]float64{tuning.name: 2}
		fillRoamingBots(a)
		for _, bot := range roamingBots(a) {
			if identities[bot.ID] != bot || bot.Score != bot.ID+10 || bot.Name != fmt.Sprintf("Bot %d", bot.ambientNumber) {
				t.Fatal("matching room tier failed to reuse its permanent identity", bot.ID, bot.Name)
			}
		}
		if a.nextID != lastID || len(roamingBots(a)) != infiniteRoomBotLimit {
			t.Fatal("pool reuse allocated a duplicate identity or exceeded active budget")
		}
		a.rules.RandomBots = false
		a.trimRoamingBots()
		a.rules.RandomBots = true
	}
}

func TestAmbientPoolPreservesDeadContactDeadlineAcrossBudgetChanges(t *testing.T) {
	a, bot, human := dumbInfinityFixture(t)
	bot.Score = 9
	a.eliminatePilot(bot, human.ID, human.Team, human.Name)
	deadline, serial := bot.respawn, bot.Spawn
	a.suspend(human)
	if bot.respawn != deadline || bot.Score != 8 || len(a.inactiveBots) != 1 {
		t.Fatal("early budget parking erased death contact deadline or score")
	}
	if reason := a.resume(fakeClient(), human, 0, time.Unix(1, 0)); reason != "" {
		t.Fatal(reason)
	}
	a.nextBot = a.tick
	a.populate()
	if bot.HP != 0 || bot.Spawn != serial || bot.respawn != deadline {
		t.Fatal("matching opportunity revived a corpse before its contact window ended")
	}
	a.tick, a.nextBot = deadline, deadline
	a.populate()
	if bot.HP == 0 || bot.Spawn != serial+1 || bot.Score != 8 {
		t.Fatal("eligible matching identity did not return after its deadline")
	}
}

func TestRoomInfinitySpectatorCanFollowParkedBotWhileWaitingForItsTier(t *testing.T) {
	s, members, room := startInfinityReconnectRoom(t, 1, false)
	now := time.Now()
	connection, _, rejection := tryInfinityReconnect(t, s, infiniteMessage{Code: room.Code, Token: members[0].player.Token}, now)
	if rejection != "" {
		t.Fatal(rejection)
	}
	a := connection.arena
	a.rules.RandomBots, a.rules.BotSpawnRates = true, map[string]float64{"hard": 2}
	a.populate()
	bot := roamingBots(a)[0]
	bot.Score = 42
	serial := bot.Spawn
	for i, p := range a.pilots {
		if p == bot {
			a.parkAmbientBot(i)
			break
		}
	}
	viewer := spectatorRoomClient(t, s, room, "Watching")
	_, c := joinRoomObserver(t, s, room, viewer, now)
	drain(c)
	s.follow(c, bot.ID, now)
	state := readPartySnapshot(t, c)
	if state.TankCount != 2 || state.Following != bot.ID || len(state.Tanks) != 0 || len(state.Bullets) != 0 || len(state.Pickups) != 0 || len(state.Effects) != 0 || len(state.Leaders) != 2 || state.Leaders[0].ID != bot.ID || state.Leaders[0].Score != 42 {
		t.Fatal("parked follow lost its identity, score, or waiting world", state)
	}
	if replies := drain(c); len(replies) != 1 || replies[0]["type"] != "followed" {
		t.Fatal("parked leaderboard identity was not selectable", replies)
	}
	a.nextBot = a.tick
	a.populate()
	a.broadcast()
	state = readPartySnapshot(t, c)
	found := false
	for _, body := range state.Tanks {
		if body.ID == bot.ID && body.Spawn == serial+1 && body.Difficulty == "hard" {
			found = true
		}
	}
	if state.Following != bot.ID || !found || bot.Score != 42 {
		t.Fatal("matching-tier return lost spectator selection or score", state)
	}
}

func TestPublicStoreMigratesLegacyBotTiersWithoutLosingAccountsOrCounters(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	s := publicStoreFixture(t, path)
	human, _, token := savedPublicJoin(t, s, infiniteMessage{Name: "Human"})
	human.pilot.Score = 53
	for i, tier := range []string{"normal", "godlike", "dumb"} {
		bot := s.public.addPilot("Legacy", true, 0, 0, 1, 3)
		bot.botLevel, bot.ambientNumber, bot.Score = infiniteBotLevel(tier), i+1, 20+i
		bot.publicBotName()
		if tier == "normal" {
			bot.Name = "Bot 1 - Normal" // Actual legacy canonical suffix.
		}
		if tier == "dumb" {
			bot.ambientNumber, bot.Name = 0, "Legacy"
		}
	}
	s.public.publicBotLives = 231
	seed, nextID, humanID := s.public.seed, s.public.nextID, human.pilot.ID
	commitPublicFixture(t, s)
	s.close()
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	for _, query := range []string{"ALTER TABLE infinity_scores DROP COLUMN difficulty", "ALTER TABLE infinity_scores DROP COLUMN spawn_serial", "PRAGMA user_version=1"} {
		if _, err = db.Exec(query); err != nil {
			db.Close()
			t.Fatal(err)
		}
	}
	db.Close()
	s = publicStoreFixture(t, path)
	if s.public.seed != seed || s.public.nextID != nextID || s.public.publicBotLives != 231 || len(s.public.inactiveBots) != 3 {
		t.Fatal("legacy migration changed population metadata or identities")
	}
	for i, bot := range s.public.inactiveBots {
		want := []string{"normal", "godlike", "dumb"}[i]
		if infiniteBotTunings[bot.botLevel].name != want || bot.Score != 20+i || bot.HP != 0 || bot.Spawn != 0 || bot.ambientNumber != i+1 {
			t.Fatal("legacy migration lost tier, score, or stable number", bot.ID, bot.Name)
		}
	}
	resumed, _, _ := savedPublicJoin(t, s, infiniteMessage{PublicToken: token, Resume: true})
	if resumed.pilot.ID != humanID || resumed.pilot.Score != 53 {
		t.Fatal("bot schema migration changed an authenticated human profile")
	}
	var version int
	if err = s.publicDB.QueryRow("PRAGMA user_version").Scan(&version); err != nil || version != 2 {
		t.Fatal("bot tier migration did not finish schema v2", version, err)
	}
	s.close()
	s = publicStoreFixture(t, path)
	if len(s.public.inactiveBots) != 3 || s.public.inactiveBots[1].botLevel != infiniteBotLevel("godlike") || s.public.publicBotLives != 231 {
		t.Fatal("migrated identities were not durably rewritten")
	}
}

func TestPublicStoreRetainsBotNumbersBeyondOldActiveLimit(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	s := publicStoreFixture(t, path)
	bot := s.public.addPilot("Bot", true, 0, 0, 1, 3)
	bot.ambientNumber, bot.botLevel, bot.Score = infiniteBotIdentityLimit, infiniteBotLevel("godlike"), 37
	bot.publicBotName()
	id := bot.ID
	commitPublicFixture(t, s)
	s.close()
	s = publicStoreFixture(t, path)
	if len(s.public.inactiveBots) != 1 {
		t.Fatal("large identity number did not restore")
	}
	bot = s.public.inactiveBots[0]
	if bot.ambientNumber != infiniteBotIdentityLimit || bot.Name != "Bot 2560 - Godlike" || bot.ID != id || bot.Score != 37 || bot.botLevel != infiniteBotLevel("godlike") {
		t.Fatal("large numbered identity lost persistence", bot.Name)
	}
	if a := s.public; a.livingPublicGodlikes(nil) != 0 || a.nextBot == math.MaxUint64 {
		t.Fatal("restored parked boss counted toward active population")
	}
}

func TestRoomInfinityFullWaitingTierDoesNotAllocateExtraIdentities(t *testing.T) {
	rules := defaultRules()
	rules.InfinityRandomBots = true
	rules.InfinityBotSpawnRates = spawnRateMap(map[string]float64{"hard": 2})
	a := newRoomInfiniteArena(rules, nil)
	a.join(fakeClient(), "Human", time.Unix(0, 0))
	for i := range infiniteRoomBotLimit {
		bot := a.addPilot(fmt.Sprintf("Bot %d", i+1), true, 0, 0, 1, 3)
		bot.botLevel, bot.ambientNumber, bot.Score = infiniteBotLevel("hard"), i+1, -3
		bot.HP, bot.respawn = 0, 60
		a.parkAmbientBot(len(a.pilots) - 1)
	}
	lastID := a.nextID
	a.populate()
	if len(roamingBots(a)) != 0 || len(a.inactiveBots) != infiniteRoomBotLimit || a.nextID != lastID {
		t.Fatal("full waiting tier allocated identities beyond its bound")
	}
	a.tick, a.nextBot = 60, 60
	a.populate()
	if len(roamingBots(a)) != 1 || len(a.inactiveBots) != infiniteRoomBotLimit-1 || a.nextID != lastID || roamingBots(a)[0].Score != -3 {
		t.Fatal("eligible waiting tier failed to reuse an existing scored identity")
	}
}

func TestPublicGodlikeLifeSerialKeepsWarningsFreshAcrossRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	s := publicStoreFixture(t, path)
	_, _, token := savedPublicJoin(t, s, infiniteMessage{Name: "Human"})
	s.public.publicBotLives = 63
	bot := s.public.addPilot("Bot", true, 0, 0, 1, 3)
	bot.ambientNumber, bot.Score = 1, 21
	bot.publicBotName()
	s.public.recordGodlikeSpawn(bot)
	id, serial, counter, seed, nextID := bot.ID, bot.Spawn, s.public.publicBotLives, s.public.seed, s.public.nextID
	seen := map[string]bool{fmt.Sprintf("%d:%d", id, serial): true}
	commitPublicFixture(t, s)
	for restart := range 2 {
		s.close()
		s = publicStoreFixture(t, path)
		if len(s.public.inactiveBots) != 1 {
			t.Fatal("restart lost the Godlike identity")
		}
		bot = s.public.inactiveBots[0]
		if bot.ID != id || bot.Spawn != serial || bot.Score != 21 || bot.Name != "Bot 1 - Godlike" || bot.ambientNumber != 1 || bot.botLevel != infiniteBotLevel("godlike") || bot.HP != 0 || s.public.publicBotLives != counter || s.public.seed != seed || s.public.nextID != nextID {
			t.Fatal("restart lost serial, identity, score, tier, or counters", bot.Name, bot.Spawn)
		}
		_, _, _ = savedPublicJoin(t, s, infiniteMessage{PublicToken: token, Resume: true})
		s.public.publicBotLives = uint64(127 + restart*64)
		s.public.nextBot = s.public.tick
		s.public.populate()
		if bot.HP == 0 || bot.Spawn != serial+1 || len(s.public.godlikeSpawns) != 1 {
			t.Fatal("matching-tier life did not advance the durable serial and warn", bot.Spawn)
		}
		event := s.public.godlikeSpawns[0]
		key := fmt.Sprintf("%d:%d", event.ID, event.Spawn)
		if event.ID != id || event.Spawn != bot.Spawn || seen[key] {
			t.Fatal("reconnecting client's warning dedupe would suppress a new life", key)
		}
		seen[key] = true
		serial, counter, nextID = bot.Spawn, s.public.publicBotLives, s.public.nextID
		commitPublicFixture(t, s)
		var savedSerial int
		if err := s.publicDB.QueryRow("SELECT spawn_serial FROM infinity_scores WHERE id=?", id).Scan(&savedSerial); err != nil || savedSerial != serial {
			t.Fatal("new life serial was not durably committed", savedSerial, serial, err)
		}
	}
}
