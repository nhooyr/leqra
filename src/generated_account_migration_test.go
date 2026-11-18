package main

import (
	"path/filepath"
	"testing"
	"time"
)

func TestGeneratedUnusedP2SurvivesSoloTakeoverRestartAndRoomWelcome(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	a := accountAppFixture(t, path)
	primary, local := freshAccountKey(t), freshAccountKey(t)
	names := generateNames(t, a, generationID(24), []callsignGenerationAccount{{Seat: 0, PublicToken: primary}, {Seat: 1, PublicToken: local}})
	first, _, _ := savedPublicJoin(t, a.infinite, infiniteMessage{Name: names[0].Name, PublicToken: primary, IndependentAccounts: true})
	second, _, _ := savedPublicJoin(t, a.infinite, infiniteMessage{PublicToken: primary, Resume: true, IndependentAccounts: true})
	if second.pilot != first.pilot {
		t.Fatal("solo takeover did not preserve its primary identity")
	}
	a.infinite.close()
	a = accountAppFixture(t, path)
	localHash, _ := publicTokenHash(local)
	if !a.hub.callsigns.generatedFresh[localHash] || !a.hub.callsigns.availability(local, []string{names[1].Name})[0].Available {
		t.Fatal("restart lost the unused generated P2's own callsign or registration")
	}
	assertSoloWelcome := func(client *Client) {
		t.Helper()
		welcomed := false
		for _, packet := range drain(client) {
			if packet["type"] == "welcome" {
				welcomed = true
				if _, exists := packet["localPublicToken"]; exists {
					t.Fatal("solo welcome sent a P2 key update without a P2 seat")
				}
			}
		}
		if !welcomed {
			t.Fatal("solo admission omitted its welcome")
		}
	}
	host := fakeClient()
	a.hub.addClient(host)
	action(t, a.hub, host, map[string]any{"type": "publish", "roster": []map[string]any{{"kind": "human", "name": names[0].Name}}, "publicToken": primary, "localPublicToken": local, "localNewAccount": true, "independentAccounts": true})
	if host.room == nil {
		t.Fatal("solo publication failed")
	}
	assertSoloWelcome(host)
	room, seat := host.room, host.player
	a.hub.removeClient(host)
	host = fakeClient()
	a.hub.addClient(host)
	action(t, a.hub, host, map[string]any{"type": "join", "code": room.Code, "token": seat.Token, "publicToken": primary, "localPublicToken": local, "localNewAccount": true, "independentAccounts": true})
	if host.room != room {
		t.Fatal("solo room reconnect failed")
	}
	assertSoloWelcome(host)
	rules := room.Game.settings()
	rules.Infinity, rules.InfinityTarget, rules.InfinityRandomBots = true, 0, false
	action(t, a.hub, host, map[string]any{"type": "rules", "rules": rules})
	action(t, a.hub, host, map[string]any{"type": "start"})
	if !room.infinityActive {
		t.Fatal("solo private Infinity did not start")
	}
	action(t, a.hub, host, map[string]any{"type": "lobby"})
	if room.infinityActive {
		t.Fatal("private Infinity did not end")
	}
	action(t, a.hub, host, map[string]any{"type": "add", "kind": "local", "name": names[1].Name, "localPublicToken": local, "localNewAccount": true, "independentAccounts": true})
	if p := roomLocalController(room, host.player); p == nil || p.PublicToken != local || p.Name != names[1].Name {
		t.Fatal("adding the same generated P2 after solo welcomes failed")
	}
	if a.hub.callsigns.generatedFresh[localHash] {
		t.Fatal("successful P2 admission retained an unused registration marker")
	}
}

func TestGeneratedFreshP2MigratesLegacyScoreAfterRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	a := accountAppFixture(t, path)
	legacy, _, primary := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Primary", LocalName: "Old Wing"})
	legacy.pilot.Score, legacy.local.Score = 7, 41
	id := legacy.local.ID
	commitPublicFixture(t, a.infinite)
	key := freshAccountKey(t)
	name := generateNames(t, a, generationID(20), []callsignGenerationAccount{{Seat: 1, PublicToken: key}})[0].Name
	hash, _ := publicTokenHash(key)
	if !a.hub.callsigns.generatedFresh[hash] {
		t.Fatal("generation lost first-gameplay freshness")
	}
	a.infinite.close()
	a = accountAppFixture(t, path)
	if !a.hub.callsigns.generatedFresh[hash] {
		t.Fatal("restart forgot generated freshness")
	}
	pair, _, _ := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Primary", LocalName: name, PublicToken: primary, LocalPublicToken: key, LocalNewAccount: true, IndependentAccounts: true, UpdateNames: true})
	if pair.local.ID != id || pair.local.Score != 41 || pair.pilot.Score != 7 || pair.local.Name != name {
		t.Fatal("generation registration prevented authorized legacy P2 score split")
	}
	if a.hub.callsigns.generatedFresh[hash] {
		t.Fatal("first gameplay did not consume generated freshness")
	}
	info, err := a.infinite.accountInfo(key)
	if err != nil || info.TotalNames != 1 || info.PublicProfile.Score != 41 {
		t.Fatal("generated P2 lost its own alias or proven legacy alias", info, err)
	}
	var count int
	if err := a.infinite.publicDB.QueryRow("SELECT COUNT(*) FROM online_generated_fresh WHERE token_hash=?", hash).Scan(&count); err != nil || count != 0 {
		t.Fatal("fresh marker consumption was not durable", count, err)
	}
}

func TestGeneratedUsedAccountCannotForgeFreshnessOrMergeLegacyScores(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	legacy, _, primary := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Primary", LocalName: "Old Wing"})
	legacy.local.Score = 43
	legacyID := legacy.local.ID
	key := freshAccountKey(t)
	name := generateNames(t, a, generationID(21), []callsignGenerationAccount{{Seat: 1, PublicToken: key}})[0].Name
	other, _, _ := savedPublicJoin(t, a.infinite, infiniteMessage{Name: name, PublicToken: key, IndependentAccounts: true})
	other.pilot.Score = -8
	otherID := other.pilot.ID
	commitPublicFixture(t, a.infinite)
	name = generateNames(t, a, generationID(22), []callsignGenerationAccount{{Seat: 1, PublicToken: key}})[0].Name
	hash, _ := publicTokenHash(key)
	if a.hub.callsigns.generatedFresh[hash] {
		t.Fatal("new alias restored a used/imported account's freshness")
	}
	paired, _, _ := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Primary", LocalName: name, PublicToken: primary, LocalPublicToken: key, LocalNewAccount: true, IndependentAccounts: true, UpdateNames: true})
	if paired.local.ID != otherID || paired.local.Score != -8 || a.infinite.public.publicEntries[legacyID].Score != 43 {
		t.Fatal("client freshness assertion merged an existing account with legacy score")
	}
}

func TestGeneratedFreshnessRotationAndAdmissionRollbackStayAtomic(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	a := accountAppFixture(t, path)
	legacy, _, primary := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Primary", LocalName: "Old Wing"})
	legacy.local.Score = 37
	commitPublicFixture(t, a.infinite)
	old := freshAccountKey(t)
	name := generateNames(t, a, generationID(23), []callsignGenerationAccount{{Seat: 1, PublicToken: old}})[0].Name
	key := freshAccountKey(t)
	if _, err := a.infinite.rotateAccount(old, key); err != nil {
		t.Fatal(err)
	}
	hash, _ := publicTokenHash(key)
	oldHash, _ := publicTokenHash(old)
	if !a.hub.callsigns.generatedFresh[hash] || a.hub.callsigns.generatedFresh[oldHash] {
		t.Fatal("rotation lost or duplicated freshness")
	}
	a.infinite.close()
	a = accountAppFixture(t, path)
	if !a.hub.callsigns.generatedFresh[hash] {
		t.Fatal("rotated freshness did not survive restart")
	}
	if _, err := a.infinite.publicDB.Exec(`CREATE TRIGGER reject_generated_admission BEFORE DELETE ON online_generated_fresh BEGIN SELECT RAISE(ABORT,'test failure'); END`); err != nil {
		t.Fatal(err)
	}
	request := infiniteMessage{Name: "Primary", LocalName: name, PublicToken: primary, LocalPublicToken: key, LocalNewAccount: true, IndependentAccounts: true, UpdateNames: true}
	if _, _, reject := tryInfinityReconnect(t, a.infinite, request, time.Now()); reject == "" {
		t.Fatal("failed marker transaction accepted gameplay")
	}
	if !a.hub.callsigns.generatedFresh[hash] {
		t.Fatal("failed admission consumed in-memory freshness")
	}
	if _, ok := a.infinite.publicProfiles[hash]; ok {
		t.Fatal("failed admission partially moved a score profile")
	}
	if _, err := a.infinite.publicDB.Exec("DROP TRIGGER reject_generated_admission"); err != nil {
		t.Fatal(err)
	}
	pair, _, _ := savedPublicJoin(t, a.infinite, request)
	if pair.local.Score != 37 || a.hub.callsigns.generatedFresh[hash] {
		t.Fatal("retry failed to preserve legacy score or consume freshness")
	}
}
