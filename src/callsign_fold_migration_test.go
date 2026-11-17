package main

import (
	"database/sql"
	"fmt"
	"path/filepath"
	"testing"
)

type foldAccountFixture struct {
	name, token, hash string
	id, score         int
}

func legacyFoldStore(t *testing.T) (string, *sql.DB, []foldAccountFixture) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "accounts.sqlite")
	server := publicStoreFixture(t, path)
	var accounts []foldAccountFixture
	for i, name := range []string{"ΐ Sky", "ΰ Sky", "ﬆ Sky"} {
		pair, _, token := savedPublicJoin(t, server, infiniteMessage{Name: name, IndependentAccounts: true})
		pair.pilot.Score = 11 + i
		hash, _ := publicTokenHash(token)
		accounts = append(accounts, foldAccountFixture{name, token, hash, pair.pilot.ID, pair.pilot.Score})
	}
	commitPublicFixture(t, server)
	server.close()
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	db.SetMaxOpenConns(1)
	t.Cleanup(func() { db.Close() })
	for _, account := range accounts {
		if _, err = db.Exec("UPDATE online_callsigns SET canonical_name=? WHERE owner_hash=?", legacyUnicode17Callsign(account.name), account.hash); err != nil {
			t.Fatal(err)
		}
	}
	return path, db, accounts
}

func TestCallsignFoldMigrationPreservesAccountsAndScores(t *testing.T) {
	path, db, accounts := legacyFoldStore(t)
	if _, err := db.Exec("INSERT INTO online_seat_migrations(new_hash,previous_hash,name) VALUES(?,?,?)", accounts[0].hash, accounts[1].hash, legacyUnicode17Callsign(accounts[0].name)); err != nil {
		t.Fatal(err)
	}
	registry := newOnlineCallsignRegistry()
	if err := registry.open(db); err != nil {
		t.Fatal(err)
	}
	for _, account := range accounts {
		var canonical, display, owner string
		if err := db.QueryRow("SELECT canonical_name,display_name,owner_hash FROM online_callsigns WHERE owner_hash=?", account.hash).Scan(&canonical, &display, &owner); err != nil {
			t.Fatal(err)
		}
		if canonical != canonicalCallsign(account.name) || display != account.name || owner != account.hash {
			t.Fatal("migration changed ownership or spelling", canonical, display, owner)
		}
		if _, err := registry.claim(account.token, []string{account.name}); err != nil {
			t.Fatal("saved credential lost its claim", err)
		}
	}
	if got := registry.seatMigrations[accounts[0].hash].name; got != canonicalCallsign(accounts[0].name) {
		t.Fatal("pending seat migration retained an old canonical key", got)
	}
	db.Close()
	restored := publicStoreFixture(t, path)
	for _, account := range accounts {
		info, err := restored.accountInfo(account.token)
		if err != nil || info.PublicProfile == nil || info.PublicProfile.Score != account.score || info.PublicProfile.Name != account.name {
			t.Fatal("account lost persisted score after restart", info, err)
		}
		profile := restored.publicProfiles[account.hash]
		if profile.primary != account.id {
			t.Fatal("canonical migration replaced the score identity")
		}
	}
}

func TestCallsignFoldMigrationRejectsCollisionsWithoutMerging(t *testing.T) {
	_, db, accounts := legacyFoldStore(t)
	// A mixed or corrupted database must not merge two owners into one name.
	if _, err := db.Exec("UPDATE online_callsigns SET canonical_name=?,display_name=? WHERE owner_hash=?", canonicalCallsign(accounts[0].name), accounts[0].name, accounts[1].hash); err != nil {
		t.Fatal(err)
	}
	if err := newOnlineCallsignRegistry().open(db); err == nil {
		t.Fatal("colliding claims were silently merged")
	}
	var original string
	if err := db.QueryRow("SELECT canonical_name FROM online_callsigns WHERE owner_hash=?", accounts[0].hash).Scan(&original); err != nil {
		t.Fatal(err)
	}
	if original != legacyUnicode17Callsign(accounts[0].name) {
		t.Fatal("failed migration changed a claim")
	}
	var count int
	if err := db.QueryRow("SELECT count(*) FROM online_owners").Scan(&count); err != nil || count != len(accounts) {
		t.Fatal("failed migration removed an owner", count, err)
	}
}

func TestCallsignFoldMigrationRollsBackAllChanges(t *testing.T) {
	_, db, accounts := legacyFoldStore(t)
	if _, err := db.Exec(fmt.Sprintf(`CREATE TRIGGER fail_fold BEFORE UPDATE ON online_callsigns WHEN OLD.owner_hash='%s' BEGIN SELECT RAISE(ABORT,'test failure'); END`, accounts[1].hash)); err != nil {
		t.Fatal(err)
	}
	if err := newOnlineCallsignRegistry().open(db); err == nil {
		t.Fatal("write failure did not propagate")
	}
	for _, account := range accounts {
		var actual string
		if err := db.QueryRow("SELECT canonical_name FROM online_callsigns WHERE owner_hash=?", account.hash).Scan(&actual); err != nil {
			t.Fatal(err)
		}
		if actual != legacyUnicode17Callsign(account.name) {
			t.Fatal("failed transaction partly migrated canonical keys")
		}
	}
	if _, err := db.Exec("DROP TRIGGER fail_fold"); err != nil {
		t.Fatal(err)
	}
	if err := newOnlineCallsignRegistry().open(db); err != nil {
		t.Fatal("migration could not be safely retried", err)
	}
}

func TestCallsignFoldMigrationRejectsUnrecognizedStoredKeys(t *testing.T) {
	_, db, accounts := legacyFoldStore(t)
	if _, err := db.Exec("UPDATE online_callsigns SET canonical_name='unexpected' WHERE owner_hash=?", accounts[0].hash); err != nil {
		t.Fatal(err)
	}
	if err := newOnlineCallsignRegistry().open(db); err == nil {
		t.Fatal("unrecognized key was silently repaired")
	}
}

func TestCallsignFoldKeepsGo123Distinctions(t *testing.T) {
	for _, pair := range [][2]string{{"ΐ", "ΐ"}, {"ΰ", "ΰ"}, {"ﬆ", "ﬅ"}} {
		if canonicalCallsign(pair[0]) == canonicalCallsign(pair[1]) {
			t.Fatalf("Go1.23 distinct accounts merged: %q and %q", pair[0], pair[1])
		}
	}
}
