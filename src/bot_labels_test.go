package main

import (
	"database/sql"
	"fmt"
	"path/filepath"
	"testing"
	"time"
)

func TestBotDisplayLabelsKeepExistingDifficultyProtocolKeys(t *testing.T) {
	for _, key := range []string{"dumb", "easy", "normal", "hard", "godlike"} {
		if !validDifficulty(key) {
			t.Fatal("display rename removed a compatible difficulty key", key)
		}
	}
	for _, label := range []string{"Dumb", "Easy", "Medium", "Hard", "Godlike", "medium"} {
		if validDifficulty(label) {
			t.Fatal("display label became an incompatible protocol key", label)
		}
	}
	for _, tc := range []struct {
		wave      int
		key, name string
	}{{5, "normal", "MEDIUM BOSS"}, {10, "hard", "HARD BOSS"}, {15, "godlike", "GODLIKE BOSS"}} {
		if survivalBossDifficulty(tc.wave) != tc.key || survivalBossName(tc.wave) != tc.name {
			t.Fatal("Survival display rename changed its skill progression", tc.wave)
		}
	}
	h, clients, _ := makeRoom(t, 1)
	host := clients[0]
	drain(host)
	action(t, h, host, map[string]any{"type": "add", "kind": "bot", "difficulty": "medium"})
	for _, packet := range drain(host) {
		if packet["type"] == "error" && packet["code"] == "bad_difficulty" {
			if packet["message"] != "Choose Dumb, Easy, Medium, Hard, or Godlike." {
				t.Fatal("difficulty error retained an obsolete display label", packet)
			}
			return
		}
	}
	t.Fatal("invalid display-key submission omitted its actionable error")
}

func TestPublicStoreRenamesNormalBotToMediumWithoutChangingIdentity(t *testing.T) {
	for _, legacy := range []bool{false, true} {
		for _, suffix := range []string{"Normal", "Medium"} {
			t.Run(fmt.Sprintf("legacy=%v/%s", legacy, suffix), func(t *testing.T) {
				path := filepath.Join(t.TempDir(), "data.sqlite")
				s := publicStoreFixture(t, path)
				human, _, token := savedPublicJoin(t, s, infiniteMessage{Name: "Human"})
				human.pilot.Score = 11
				s.public.publicBotLives = 7
				bot := s.public.addPilot("Bot", true, 0, 0, 1, 3)
				bot.ambientNumber, bot.Score = 1024, 17
				s.public.spawn(bot, 0, 0, 1, 3)
				s.public.spawn(bot, 0, 0, 1, 3)
				bot.Name = "Bot 1024 - " + suffix
				id, humanID, serial := bot.ID, human.pilot.ID, bot.Spawn
				seed, nextID, counter := s.public.seed, s.public.nextID, s.public.publicBotLives
				commitPublicFixture(t, s)
				s.close()
				if legacy {
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
					serial = 0
				}
				s = publicStoreFixture(t, path)
				if len(s.public.inactiveBots) != 1 || s.public.seed != seed || s.public.nextID != nextID || s.public.publicBotLives != counter {
					t.Fatal("display migration changed durable arena metadata")
				}
				bot = s.public.inactiveBots[0]
				if bot.ID != id || bot.ambientNumber != 1024 || bot.Score != 17 || bot.Spawn != serial || bot.Name != "Bot 1024 - Medium" || bot.botLevel != infiniteBotLevel("normal") {
					t.Fatal("display migration lost a compatible bot's identity", bot.Name, bot.Spawn)
				}
				var storedName, storedKey string
				var storedScore, storedSerial int
				if err := s.publicDB.QueryRow("SELECT name,difficulty,score,spawn_serial FROM infinity_scores WHERE id=?", id).Scan(&storedName, &storedKey, &storedScore, &storedSerial); err != nil || storedName != bot.Name || storedKey != "normal" || storedScore != 17 || storedSerial != serial {
					t.Fatal("canonical display rename was not durably rewritten", storedName, storedKey, storedScore, storedSerial, err)
				}
				resumed, _, _ := savedPublicJoin(t, s, infiniteMessage{PublicToken: token, Resume: true})
				if resumed.pilot.ID != humanID || resumed.pilot.Score != 11 {
					t.Fatal("bot label migration changed a human profile")
				}
				// The same normal-tier opportunity still reuses this Medium identity.
				s.public.publicBotLives = 23
				s.public.nextBot, s.public.clock = s.public.tick, time.Unix(0, 0)
				s.public.populate()
				if bot.HP == 0 || bot.ID != id || bot.Score != 17 || bot.Spawn != serial+1 || bot.Name != "Bot 1024 - Medium" || bot.wireTank(s.public.tick).Difficulty != "normal" {
					t.Fatal("renamed compatible identity changed spawn tier or score")
				}
			})
		}
	}
}
