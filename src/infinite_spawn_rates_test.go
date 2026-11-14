package main

import (
	"encoding/json"
	"math"
	"reflect"
	"strings"
	"testing"
	"time"
)

func spawnRateMap(rates map[string]float64) *infinityBotSpawnRates {
	typed := infinityBotSpawnRates(rates)
	return &typed
}

func TestInfinityTierRatesValidateAtomicallyAndCopyIndependentMaps(t *testing.T) {
	rules := defaultRules()
	rules.Infinity, rules.InfinityRandomBots = true, true
	rules.InfinityBotSpawnRates = spawnRateMap(map[string]float64{"dumb": 0, "easy": .125, "normal": .5, "hard": 2, "godlike": 4})
	if err := validateRules(rules); err != nil {
		t.Fatal(err)
	}
	h, clients, room := makeRoom(t, 1)
	action(t, h, clients[0], map[string]any{"type": "rules", "rules": rules})
	before := normalizedRules(room.Game.settings())
	for _, bad := range []map[string]float64{{"evil": 1}, {"Normal": 1}, {"dumb": -1}, {"normal": 4.1}} {
		rules.InfinityBotSpawnRates = spawnRateMap(bad)
		action(t, h, clients[0], map[string]any{"type": "rules", "rules": rules})
		if !reflect.DeepEqual(room.Game.settings(), before) {
			t.Fatal("bad tier partially mutated room rules", bad)
		}
	}
	for _, rate := range []float64{math.NaN(), math.Inf(1), math.Inf(-1)} {
		rules.InfinityBotSpawnRates = spawnRateMap(map[string]float64{"normal": rate})
		if validateRules(rules) == nil {
			t.Fatal("non-finite tier rate accepted", rate)
		}
	}
	source := infinityBotSpawnRates{"normal": 1}
	rules.InfinityBotSpawnRates = &source
	accepted := normalizedRules(rules)
	source["normal"] = 4
	if (*accepted.InfinityBotSpawnRates)["normal"] != 1 {
		t.Fatal("accepted rules alias request map")
	}
	arena := newRoomInfiniteArena(accepted, nil)
	(*accepted.InfinityBotSpawnRates)["normal"] = 3
	if arena.rules.BotSpawnRates["normal"] != 1 {
		t.Fatal("running arena aliases room rules map")
	}
}

func TestInfinityTierRatesMigrateLegacyWithoutLosingOffOrMasterChoices(t *testing.T) {
	rules := defaultRules()
	if got := effectiveInfinityBotSpawnRates(rules); !reflect.DeepEqual(got, map[string]float64{"normal": 2}) {
		t.Fatal("disabled master lost default choice", got)
	}
	rules.InfinityBotDifficulty, rules.InfinityBotSpawnRate, rules.InfinityRandomDifficulty = "hard", 4, true
	if got := effectiveInfinityBotSpawnRates(rules); !reflect.DeepEqual(got, map[string]float64{"dumb": 1, "easy": 1, "normal": 1, "hard": 1}) {
		t.Fatal("legacy random-up-to cadence was multiplied", got)
	}
	rules.InfinityRandomDifficulty = false
	if got := effectiveInfinityBotSpawnRates(rules); !reflect.DeepEqual(got, map[string]float64{"hard": 4}) {
		t.Fatal("legacy fixed tier changed", got)
	}
	rules.InfinityBotSpawnRates = spawnRateMap(map[string]float64{})
	data, err := json.Marshal(normalizedRules(rules))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), `"infinityBotSpawnRates":{}`) {
		t.Fatal("explicit all-Off map vanished", string(data))
	}
	var restored MatchRules
	if err = json.Unmarshal(data, &restored); err != nil {
		t.Fatal(err)
	}
	if restored.InfinityBotSpawnRates == nil || len(effectiveInfinityBotSpawnRates(restored)) != 0 {
		t.Fatal("all-Off remigrated legacy rates")
	}
	rules.InfinityBotSpawnRates = nil
	data, _ = json.Marshal(rules)
	if strings.Contains(string(data), `"infinityBotSpawnRates"`) {
		t.Fatal("missing legacy map gained an explicit empty map")
	}
}

func TestInfinityTierRatesUseSummedCadenceAndCanonicalWeightedSelection(t *testing.T) {
	rules := defaultRules()
	rules.InfinityRandomBots = true
	rules.InfinityBotSpawnRates = spawnRateMap(map[string]float64{"dumb": .5, "normal": 1.5})
	a := newRoomInfiniteArena(rules, nil)
	counts := make(map[int]int)
	for range 4000 {
		counts[a.chooseRoomBotLevel()]++
	}
	if counts[0] < 900 || counts[0] > 1100 || counts[2] < 2900 || counts[2] > 3100 || len(counts) != 2 {
		t.Fatal("weighted mix did not preserve relative per-tier rates", counts)
	}
	a.join(fakeClient(), "Human", time.Unix(0, 0))
	for range 16 {
		a.tick = a.nextBot
		a.populate()
		if delay := a.nextBot - a.tick; delay < 30 || delay > 60 {
			t.Fatal("sum2 did not preserve legacy total cadence", delay)
		}
	}
	if len(roamingBots(a)) != 16 || a.roamingBotBudget() != 16 {
		t.Fatal("independent tier rates bypassed shared budget")
	}
	rules.InfinityBotSpawnRates = spawnRateMap(map[string]float64{"dumb": 4, "easy": 4, "normal": 4, "hard": 4, "godlike": 4})
	a = newRoomInfiniteArena(rules, nil)
	a.join(fakeClient(), "Human", time.Unix(0, 0))
	a.populate()
	if delay := a.nextBot - a.tick; delay < 3 || delay > 6 {
		t.Fatal("sum20 was clamped to old global cap", delay)
	}
}

func TestInfinityTierRatesSelectNewIdentitiesWithoutRetieringOldOnes(t *testing.T) {
	rules := defaultRules()
	rules.InfinityRandomBots = true
	rules.InfinityBotSpawnRates = spawnRateMap(map[string]float64{"hard": 2})
	member := &Player{ID: 1, Kind: "bot", Difficulty: "godlike"}
	a := newRoomInfiniteArena(rules, []infiniteRoomBot{{member: member, seat: infiniteSeat{name: "Roster"}, difficulty: "godlike"}})
	human := a.join(fakeClient(), "Human", time.Unix(0, 0))
	human.kit.Invulnerable = 1e9
	a.populate()
	ambient, roster := roamingBots(a)[0], a.pilots[1]
	id, name, serial := ambient.ID, ambient.Name, ambient.Spawn
	ambient.Score = 31
	ambient.HP, ambient.respawn = 0, a.tick+1
	roster.HP, roster.respawn = 0, a.tick+1
	a.rules.BotSpawnRates = map[string]float64{"normal": 2}
	a.nextBot, a.nextPickup = math.MaxUint64, math.MaxUint64
	a.step(time.Unix(1, 0))
	if ambient.HP != 0 || ambient.botLevel != infiniteBotLevel("hard") || ambient.ID != id || ambient.Name != name || ambient.Spawn != serial || ambient.Score != 31 {
		t.Fatal("parked identity lost permanent tier or score")
	}
	if roster.HP == 0 || roster.botLevel != infiniteBotLevel("godlike") {
		t.Fatal("authored roster stopped respawning")
	}
	a.nextBot = a.tick
	a.populate()
	if len(roamingBots(a)) != 1 || roamingBots(a)[0] == ambient || roamingBots(a)[0].botLevel != infiniteBotLevel("normal") {
		t.Fatal("Medium opportunity reused Hard identity")
	}
	a.rules.BotSpawnRates = map[string]float64{"hard": 2}
	a.nextBot = a.tick
	a.populate()
	if ambient.HP == 0 || ambient.ID != id || ambient.Score != 31 || ambient.Spawn != serial+1 || ambient.botLevel != infiniteBotLevel("hard") {
		t.Fatal("matching opportunity failed to reuse parked identity")
	}
}

func TestInfinityTierRatesAllOffOrMasterOffTrimOnlyAmbient(t *testing.T) {
	for _, master := range []bool{false, true} {
		rules := defaultRules()
		rules.InfinityRandomBots = master
		rules.InfinityBotSpawnRates = spawnRateMap(map[string]float64{})
		if !master {
			rules.InfinityBotSpawnRates = spawnRateMap(map[string]float64{"normal": 2})
		}
		a := newRoomInfiniteArena(rules, []infiniteRoomBot{{member: &Player{ID: 1, Kind: "bot"}, seat: infiniteSeat{name: "Roster"}, difficulty: "hard"}})
		a.join(fakeClient(), "Human", time.Unix(0, 0))
		a.populate()
		if a.roamingBotBudget() != 0 || len(roamingBots(a)) != 0 || len(a.pilots) != 2 {
			t.Fatal("disabled rates removed roster or spawned ambient")
		}
		if !master && a.rules.BotSpawnRates["normal"] != 2 {
			t.Fatal("master Off discarded per-tier selection")
		}
		a.rules.RandomBots = true
		a.rules.BotSpawnRates = map[string]float64{"normal": 2}
		a.nextBot = a.tick
		a.populate()
		if len(roamingBots(a)) != 1 {
			t.Fatal("enabled tier failed to spawn")
		}
		a.rules.BotSpawnRates = map[string]float64{}
		a.populate()
		if len(roamingBots(a)) != 0 || len(a.pilots) != 2 || len(a.inactiveBots) != 1 {
			t.Fatal("all-Off did not trim ambient alone")
		}
	}
}

func TestInfinityTinyPositiveTierRatesSaturateFutureWaveWithoutOverflow(t *testing.T) {
	for _, rate := range []float64{1e-300, math.SmallestNonzeroFloat64} {
		rules := defaultRules()
		rules.InfinityRandomBots = true
		rules.InfinityBotSpawnRates = spawnRateMap(map[string]float64{"normal": rate})
		if err := validateRules(rules); err != nil {
			t.Fatal("valid finite tiny rate rejected", err)
		}
		a := newRoomInfiniteArena(rules, nil)
		a.join(fakeClient(), "Human", time.Unix(0, 0))
		a.populate()
		if a.nextBot != math.MaxUint64 || len(roamingBots(a)) != 1 {
			t.Fatal("tiny rate wrapped into an immediate next wave", a.nextBot)
		}
		a.tick++
		a.populate()
		if len(roamingBots(a)) != 1 {
			t.Fatal("tiny rate repeatedly spawned")
		}
	}
}

func TestInfinityTierRatesAllOffCannotPretendToSupplyAScoreTargetOpponent(t *testing.T) {
	h, clients, room := makeRoom(t, 1)
	rules := room.Game.settings()
	rules.Infinity = true
	rules.InfinityTarget = 5
	rules.InfinityRandomBots = true
	rules.InfinityBotSpawnRates = spawnRateMap(map[string]float64{})
	action(t, h, clients[0], map[string]any{"type": "rules", "rules": rules})
	if h.roomWire(room).CanStart {
		t.Fatal("all-Off mix pretended to supply an opposing tank")
	}
	action(t, h, clients[0], map[string]any{"type": "start"})
	if room.infinityActive {
		t.Fatal("solo target run started without an opponent")
	}
	rules.InfinityBotSpawnRates = spawnRateMap(map[string]float64{"normal": .5})
	action(t, h, clients[0], map[string]any{"type": "rules", "rules": rules})
	if !h.roomWire(room).CanStart {
		t.Fatal("enabled tier did not supply a score-target opponent")
	}
}

func TestInfinityTierRatesDisabledTierCannotReenterFromALivingBudgetPool(t *testing.T) {
	rules := defaultRules()
	rules.InfinityRandomBots = true
	rules.InfinityBotSpawnRates = spawnRateMap(map[string]float64{"hard": 2})
	a := newRoomInfiniteArena(rules, nil)
	human := a.join(fakeClient(), "Human", time.Unix(0, 0))
	a.populate()
	bot := roamingBots(a)[0]
	bot.Score = 17
	id := bot.ID
	a.suspend(human)
	a.rules.BotSpawnRates = map[string]float64{"easy": 2}
	if reason := a.resume(fakeClient(), human, 0, time.Unix(1, 0)); reason != "" {
		t.Fatal(reason)
	}
	a.nextBot = a.tick
	a.populate()
	if bot.HP != 0 || bot.ID != id || bot.Score != 17 || bot.botLevel != infiniteBotLevel("hard") || len(roamingBots(a)) != 1 || roamingBots(a)[0] == bot || roamingBots(a)[0].botLevel != infiniteBotLevel("easy") {
		t.Fatal("living pool reintroduced a disabled tier or lost the identity")
	}
}

func TestInfinityTierRateJSONRequiresNumbersAndKeepsWholeMapNullLegacy(t *testing.T) {
	h, clients, room := makeRoom(t, 1)
	original := normalizedRules(room.Game.settings())
	data, _ := json.Marshal(original)
	var rules map[string]json.RawMessage
	if err := json.Unmarshal(data, &rules); err != nil {
		t.Fatal(err)
	}
	for _, value := range []string{`{"normal":null}`, `{"normal":"2"}`, `{"normal":true}`, `{"normal":[]}`, `{"normal":{}}`} {
		rules["infinityBotSpawnRates"] = json.RawMessage(value)
		packet, _ := json.Marshal(map[string]any{"type": "rules", "rules": rules})
		if err := h.handle(clients[0], packet, time.Now()); err == nil {
			t.Fatal("nonnumeric tier JSON was accepted", value)
		}
		if !reflect.DeepEqual(room.Game.settings(), original) {
			t.Fatal("rejected tier JSON changed room rules", value)
		}
	}
	rules["infinityBotSpawnRates"] = json.RawMessage(`null`)
	packet, _ := json.Marshal(map[string]any{"type": "rules", "rules": rules})
	if err := h.handle(clients[0], packet, time.Now()); err != nil || room.Game.Rules.InfinityBotSpawnRates != nil {
		t.Fatal("whole-map null stopped being a legacy omission", err)
	}
	var typed = infinityBotSpawnRates{"normal": 2}
	if err := json.Unmarshal([]byte(`{"dumb":1,"normal":null}`), &typed); err == nil || len(typed) != 1 || typed["normal"] != 2 {
		t.Fatal("typed map decode was not atomic", typed, err)
	}
}
