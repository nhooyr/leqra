package main

import (
	"path/filepath"
	"testing"
	"time"
)

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
	if err != nil || info.TotalNames != 2 || info.PublicProfile.Score != 41 {
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
