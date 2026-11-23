package main

import (
	"encoding/json"
	"path/filepath"
	"slices"
	"testing"
	"time"
)

func TestPublicInfinityAdminRandomizeColorsPersistsAndBroadcasts(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	s := publicStoreFixture(t, path)
	active, client, token := savedPublicJoin(t, s, infiniteMessage{Name: "ACTIVE", LocalName: "WING"})
	offline, offlineClient, offlineToken := savedPublicJoin(t, s, infiniteMessage{Name: "OFFLINE"})
	active.pilot.Score, active.local.Score, offline.pilot.Score = 5, 4, 50
	active.pilot.ColorIndex, active.local.ColorIndex, offline.pilot.ColorIndex = 0, 1, 6
	var bots []*infinitePilot
	for color := 2; color < len(tankColors); color++ {
		bot := s.public.addPilot("Bot", true, active.pilot.X, active.pilot.Y, 0, 0)
		bot.ambientNumber = color
		bot.publicBotName()
		bot.ColorIndex, bot.Score = color, color
		bots = append(bots, bot)
	}
	parked := bots[len(bots)-1]
	s.public.pilots = slices.DeleteFunc(s.public.pilots, func(p *infinitePilot) bool { return p == parked })
	s.public.inactiveBots = append(s.public.inactiveBots, parked)
	commitPublicFixture(t, s)
	s.remove(offlineClient)
	commitPublicFixture(t, s)
	private := newSeededInfiniteArena(123)
	privatePilot := private.join(fakeClient(), "PRIVATE", time.Now())
	privatePilot.ColorIndex = 4
	s.private[infiniteRoom{generation: 1}] = private
	before := make(map[int]infinitePublicEntry, len(s.public.publicEntries))
	for id, entry := range s.public.publicEntries {
		before[id] = entry
	}
	drain(client)
	count, err := s.RandomizePublicColors()
	if err != nil || count != len(before) {
		t.Fatalf("randomize: count=%d, want %d, error=%v", count, len(before), err)
	}
	for id, old := range before {
		entry := s.public.publicEntries[id]
		if id == offline.pilot.ID {
			if entry.ColorIndex != 0 {
				t.Fatal("offline leaderboard leader did not become blue")
			}
		} else if entry.ColorIndex < 1 || entry.ColorIndex >= len(tankColors) || entry.ColorIndex == old.ColorIndex {
			t.Fatalf("pilot %d did not get a different nonblue color: %d -> %d", id, old.ColorIndex, entry.ColorIndex)
		}
		old.ColorIndex = entry.ColorIndex
		if entry != old {
			t.Fatalf("paint changed identity, score or metadata: got %+v, want %+v", entry, old)
		}
		var stored int
		if err := s.publicDB.QueryRow("SELECT color_index FROM infinity_scores WHERE id=?", id).Scan(&stored); err != nil || stored != entry.ColorIndex {
			t.Fatalf("pilot %d color was not committed: color=%d, error=%v", id, stored, err)
		}
	}
	for _, pilot := range append([]*infinitePilot{active.pilot, active.local}, bots...) {
		if pilot.ColorIndex != s.public.publicEntries[pilot.ID].ColorIndex {
			t.Fatalf("active or parked pilot %d retained old paint", pilot.ID)
		}
	}
	if privatePilot.ColorIndex != 4 {
		t.Fatal("public action changed a private arena")
	}
	var state infiniteSnapshot
	for len(client.send) > 0 {
		var packet infiniteSnapshot
		if err := json.Unmarshal(<-client.send, &packet); err != nil {
			t.Fatal(err)
		}
		if packet.Type == "state" {
			state = packet
		}
	}
	if len(state.Tanks) == 0 || len(state.Leaders) != len(before) || state.Leaders[0].ID != offline.pilot.ID {
		t.Fatalf("missing immediate tank/leaderboard broadcast: %+v", state)
	}
	seenTanks := make(map[int]bool)
	for _, tank := range state.Tanks {
		seenTanks[tank.ID] = true
		if tank.ColorIndex != s.public.publicEntries[tank.ID].ColorIndex {
			t.Fatalf("snapshot kept old paint for tank %d", tank.ID)
		}
	}
	for _, pilot := range s.public.pilots {
		if !seenTanks[pilot.ID] {
			t.Fatalf("immediate snapshot omitted active tank %d", pilot.ID)
		}
	}
	for _, leader := range state.Leaders {
		if leader.ColorIndex != s.public.publicEntries[leader.ID].ColorIndex {
			t.Fatalf("leaderboard kept old paint for pilot %d", leader.ID)
		}
	}
	wantPrimary, wantLocal := active.pilot.ColorIndex, active.local.ColorIndex
	s.close()
	restarted := publicStoreFixture(t, path)
	resumed, _, _ := savedPublicJoin(t, restarted, infiniteMessage{PublicToken: token, Resume: true, ColorIndex: new(int), LocalColorIndex: new(int)})
	if resumed.pilot.ID != active.pilot.ID || resumed.local.ID != active.local.ID || resumed.pilot.ColorIndex != wantPrimary || resumed.local.ColorIndex != wantLocal {
		t.Fatal("restart/reconnect lost randomized primary or co-pilot paint")
	}
	resumedOffline, _, _ := savedPublicJoin(t, restarted, infiniteMessage{PublicToken: offlineToken, Resume: true, ColorIndex: new(int)})
	if resumedOffline.pilot.ID != offline.pilot.ID || resumedOffline.pilot.ColorIndex != 0 || resumedOffline.pilot.Score != 50 {
		t.Fatal("offline leader lost blue paint or score after restart")
	}
	for _, bot := range bots {
		if restarted.public.publicEntries[bot.ID].ColorIndex != bot.ColorIndex {
			t.Fatalf("bot %d lost paint after restart", bot.ID)
		}
	}
}

func TestPublicInfinityAdminRandomizeColorsChoosesRankedLeader(t *testing.T) {
	for _, test := range []struct {
		name    string
		entries []infinitePublicEntry
		leader  int
	}{
		{"bot leader", []infinitePublicEntry{{infiniteLeader: infiniteLeader{ID: 1, Score: 4, ColorIndex: 3}, listed: true}, {infiniteLeader: infiniteLeader{ID: 2, Score: 8, ColorIndex: 5, Bot: true}, listed: true}}, 2},
		{"tied score uses lower id", []infinitePublicEntry{{infiniteLeader: infiniteLeader{ID: 7, Score: 8, ColorIndex: 2}, listed: true}, {infiniteLeader: infiniteLeader{ID: 2, Score: 8, ColorIndex: 7}, listed: true}}, 2},
		{"hidden score is not leader", []infinitePublicEntry{{infiniteLeader: infiniteLeader{ID: 1, Score: 99, ColorIndex: 0}}, {infiniteLeader: infiniteLeader{ID: 2, Score: -4, ColorIndex: 2}, listed: true}}, 2},
		{"no listed leader", []infinitePublicEntry{{infiniteLeader: infiniteLeader{ID: 1, ColorIndex: 0}}}, 0},
		{"empty", nil, 0},
	} {
		t.Run(test.name, func(t *testing.T) {
			s := newInfiniteServer(newHub(2))
			t.Cleanup(s.close)
			for _, entry := range test.entries {
				s.public.publicEntries[entry.ID] = entry
			}
			count, err := s.RandomizePublicColors()
			if err != nil || count != len(test.entries) {
				t.Fatalf("randomize: %d %v", count, err)
			}
			for _, old := range test.entries {
				color := s.public.publicEntries[old.ID].ColorIndex
				if old.ID == test.leader {
					if color != 0 {
						t.Fatal("ranked leader did not become blue")
					}
				} else if color < 1 || color >= len(tankColors) || color == old.ColorIndex {
					t.Fatalf("nonleader retained paint or became blue: %d -> %d", old.ColorIndex, color)
				}
			}
		})
	}
}

func TestPublicInfinityAdminRandomizeColorsDatabaseFailureIsAtomic(t *testing.T) {
	s := publicStoreFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	pair, client, _ := savedPublicJoin(t, s, infiniteMessage{Name: "PRIMARY", LocalName: "LOCAL"})
	pair.pilot.ColorIndex, pair.local.ColorIndex = 4, 5
	commitPublicFixture(t, s)
	drain(client)
	before := make(map[int]infinitePublicEntry, len(s.public.publicEntries))
	for id, entry := range s.public.publicEntries {
		before[id] = entry
	}
	for _, statement := range []string{
		`CREATE TABLE paint_updates (count INTEGER NOT NULL)`,
		`INSERT INTO paint_updates VALUES(0)`,
		`CREATE TRIGGER reject_admin_paint BEFORE UPDATE OF color_index ON infinity_scores BEGIN UPDATE paint_updates SET count=count+1; SELECT CASE WHEN (SELECT count FROM paint_updates)=2 THEN RAISE(ABORT,'paint rejected') END; END`,
	} {
		if _, err := s.publicDB.Exec(statement); err != nil {
			t.Fatal(err)
		}
	}
	if count, err := s.RandomizePublicColors(); err == nil || count != 0 {
		t.Fatalf("database failure was ignored: count=%d, error=%v", count, err)
	}
	for id, old := range before {
		if s.public.publicEntries[id] != old {
			t.Fatal("database failure changed cached paint")
		}
		var stored int
		if err := s.publicDB.QueryRow("SELECT color_index FROM infinity_scores WHERE id=?", id).Scan(&stored); err != nil || stored != old.ColorIndex {
			t.Fatalf("database failure partially committed paint: %d %v", stored, err)
		}
	}
	if pair.pilot.ColorIndex != 4 || pair.local.ColorIndex != 5 || len(client.send) != 0 {
		t.Fatal("database failure changed live paint or broadcast uncommitted state")
	}
	s.close()
	if count, err := s.RandomizePublicColors(); err == nil || count != 0 {
		t.Fatalf("closed server accepted recoloring: count=%d, error=%v", count, err)
	}
}
