package main

import (
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestPublicBotMixHasFourNormalAndOneGodlikeOpportunityPer64Lives(t *testing.T) {
	a := newSeededInfiniteArena(37)
	a.connected = 1
	bot := a.addPilot("Bot", true, 0, 0, 1, 3)
	bot.ambientNumber = 7
	a.publicBotLives = 0
	counts := make(map[string]int)
	for life := 1; life <= 128; life++ {
		bot.HP = 0
		bot.botLevel = a.chooseAmbientBotLevel()
		bot.publicBotName()
		level := infiniteBotTunings[bot.botLevel].name
		counts[level]++
		want := "dumb"
		if life%64 == 0 {
			want = "godlike"
		} else if life%16 == 8 {
			want = "normal"
		}
		if level != want || a.publicBotLives != uint64(life) {
			t.Fatalf("life %d: got %s, want %s", life, level, want)
		}
		title := map[string]string{"dumb": "Dumb", "normal": "Normal", "godlike": "Godlike"}[want]
		if bot.Name != "Bot 7 - "+title || !reservedCallsign(bot.Name) {
			t.Fatal("public bot name lost its tier or reserved namespace", bot.Name)
		}
	}
	if counts["normal"] != 8 || counts["godlike"] != 2 || counts["dumb"] != 118 {
		t.Fatal("public encounter ratios changed", counts)
	}
}

func TestPublicNormalEncountersHaveNoSpecialCapWarningOrGodlikeCompetition(t *testing.T) {
	a := newSeededInfiniteArena(37)
	a.connected = 1
	a.publicBotLives = 63
	boss := a.addPilot("Bot", true, 0, 0, 1, 3)
	boss.ambientNumber = 1
	boss.publicBotName()
	a.recordGodlikeSpawn(boss)
	for i := range 8 {
		a.publicBotLives = uint64(7 + i*16)
		p := a.addPilot("Bot", true, 0, 0, 1, 3)
		p.ambientNumber = i + 2
		p.publicBotName()
		a.recordGodlikeSpawn(p)
		if infiniteBotTunings[p.botLevel].name != "normal" || p.Name != fmt.Sprintf("Bot %d - Normal", i+2) {
			t.Fatal("normal opportunity was capped by another normal or Godlike", p.Name)
		}
	}
	a.enforcePublicGodlikeLimit()
	if len(a.godlikeSpawns) != 1 || a.godlikeSpawns[0].ID != boss.ID {
		t.Fatal("normal encounters emitted a special warning or changed the Godlike notice", a.godlikeSpawns)
	}
	for _, p := range a.pilots[1:] {
		if infiniteBotTunings[p.botLevel].name != "normal" {
			t.Fatal("Godlike cap enforcement changed a normal bot")
		}
	}
	a.publicBotLives = 127
	p := a.addPilot("Bot", true, 0, 0, 1, 3)
	p.ambientNumber = 10
	p.publicBotName()
	if infiniteBotTunings[p.botLevel].name != "dumb" || p.Name != "Bot 10 - Dumb" || a.livingPublicGodlikes(nil) != 1 {
		t.Fatal("normal encounters altered capped Godlike fallback")
	}
}

func TestInfinityLeaderboardsCarryActualBotDifficultyAndNeverHumanDifficulty(t *testing.T) {
	for _, private := range []bool{false, true} {
		a := newSeededInfiniteArena(37)
		if private {
			a = newRoomInfiniteArena(defaultRules(), nil)
		}
		human := a.join(fakeClient(), "Human - Godlike", time.Unix(0, 0))
		human.Difficulty = "godlike"
		want := make(map[int]string)
		for _, tier := range []string{"dumb", "easy", "normal", "hard", "godlike"} {
			p := a.addPilot("Bot Rust", true, 0, 0, 1, 3)
			p.botLevel = infiniteBotLevel(tier)
			want[p.ID] = tier
		}
		for _, leader := range a.rankedLeaders(nil) {
			if leader.Difficulty != want[leader.ID] {
				t.Fatalf("private=%t: leaderboard tier mismatch: %+v", private, leader)
			}
			data, err := json.Marshal(leader)
			if err != nil {
				t.Fatal(err)
			}
			if leader.ID == human.ID && strings.Contains(string(data), `"difficulty"`) {
				t.Fatal("human callsign fabricated a bot difficulty", string(data))
			}
		}
	}
}

func TestPublicStatusCarriesBotDifficultyWithoutAllocatingAPlayer(t *testing.T) {
	app := newApp(4, nil)
	for i, tier := range []string{"dumb", "normal", "godlike"} {
		p := app.infinite.public.addPilot("Bot", true, 0, 0, 1, 3)
		p.botLevel = infiniteBotLevel(tier)
		p.ambientNumber = i + 1
		p.publicBotName()
		p.Score = 3 - i
	}
	commitPublicFixture(t, app.infinite)
	response := httptest.NewRecorder()
	app.infinityStatus(response, httptest.NewRequest("GET", "/api/infinity", nil))
	var status struct {
		Players int
		Leaders []infiniteStatusLeader
	}
	if err := json.Unmarshal(response.Body.Bytes(), &status); err != nil {
		t.Fatal(err)
	}
	if status.Players != 0 || len(status.Leaders) != 3 {
		t.Fatal("status changed population or lost rows", status)
	}
	for i, tier := range []string{"dumb", "normal", "godlike"} {
		if status.Leaders[i].Difficulty != tier {
			t.Fatal("status omitted authoritative bot tier", status.Leaders)
		}
	}
}

func TestRestoredNormalBotLeaderKeepsItsTierAndPreservedScore(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	s := publicStoreFixture(t, path)
	s.public.publicBotLives = 7
	bot := s.public.addPilot("Bot", true, 0, 0, 1, 3)
	bot.ambientNumber = 1
	bot.publicBotName()
	bot.Score = 42
	commitPublicFixture(t, s)
	id := bot.ID
	if got := s.public.leaderboard(nil)[0]; got.Difficulty != "normal" || got.Name != "Bot 1 - Normal" {
		t.Fatal("durable normal leaderboard tier missing", got)
	}
	s.close()
	s = publicStoreFixture(t, path)
	defer s.close()
	leader := s.public.leaderboard(nil)[0]
	if leader.ID != id || leader.Score != 42 || leader.Name != "Bot 1 - Normal" || leader.Difficulty != "normal" || s.public.publicBotLives != 8 {
		t.Fatal("restart lost score, cadence, or permanent normal identity", leader)
	}
}

func TestLongCanonicalGodlikeBotNameSurvivesPublicStoreRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	s := publicStoreFixture(t, path)
	_, _, _ = savedPublicJoin(t, s, infiniteMessage{Name: "Human"})
	s.public.publicBotLives = 63
	bot := s.public.addPilot("Bot", true, 0, 0, 1, 3)
	bot.ambientNumber = 128
	bot.publicBotName()
	bot.Score = 23
	if bot.Name != "Bot 128 - Godlike" || len(bot.Name) <= 16 {
		t.Fatal("fixture does not exercise the human callsign length boundary", bot.Name)
	}
	commitPublicFixture(t, s)
	id := bot.ID
	s.close()
	s = publicStoreFixture(t, path)
	defer s.close()
	var restored *infinitePilot
	for _, p := range s.public.inactiveBots {
		if p.ID == id {
			restored = p
		}
	}
	if restored == nil || restored.Name != "Bot 128 - Godlike" || restored.Score != 23 {
		t.Fatal("long canonical bot label broke durable score restoration", restored)
	}
}

func TestSavedPublicNameExceptionOnlyAllowsCanonicalAmbientBotLabels(t *testing.T) {
	for _, tc := range []struct {
		name    string
		bot     bool
		ambient int
		valid   bool
	}{
		{"Bot 128 - Godlike", true, 128, true},
		{"Bot 512 - Godlike", true, 512, true},
		{"Bot 128 - Godlike", false, 128, false},
		{"Bot 128 - Godlike", true, 129, false},
		{"Bot 999 - Godlike", true, 999, true},
		{"Bot 2560 - Godlike", true, 2560, true},
		{"Bot 2561 - Godlike", true, 2561, false},
		{"Bot 128 - Whatever", true, 128, false},
		{"ABCDEFGHIJKLMNOPQ", false, 0, false},
		{"ABCDEFGHIJKLMNOP", false, 0, true},
	} {
		entry := infinitePublicEntry{infiniteLeader: infiniteLeader{Name: tc.name, Bot: tc.bot}, ambient: tc.ambient}
		if got := validSavedPublicName(entry); got != tc.valid {
			t.Fatalf("name=%q bot=%v ambient=%d: got %v", tc.name, tc.bot, tc.ambient, got)
		}
	}
}
