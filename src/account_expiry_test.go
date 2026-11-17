package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"testing"
	"time"
)

func accountTestClock(r *onlineCallsignRegistry) *time.Time {
	now := time.Now().Truncate(time.Second)
	r.now = func() time.Time { return now }
	return &now
}

func TestAccountExpiryUsesClampedCalendarMonth(t *testing.T) {
	for _, tc := range []struct{ used, expires string }{
		{"2026-01-15T12:34:56Z", "2026-02-15T12:34:56Z"},
		{"2026-01-30T12:34:56Z", "2026-02-28T12:34:56Z"},
		{"2026-01-31T12:34:56Z", "2026-02-28T12:34:56Z"},
		{"2028-01-31T12:34:56Z", "2028-02-29T12:34:56Z"},
		{"2026-02-28T12:34:56Z", "2026-03-28T12:34:56Z"},
		{"2026-03-31T12:34:56Z", "2026-04-30T12:34:56Z"},
		{"2026-12-31T12:34:56Z", "2027-01-31T12:34:56Z"},
		{"2026-03-01T00:30:00+02:00", "2026-03-28T22:30:00Z"},
	} {
		t.Run(tc.used, func(t *testing.T) {
			used, err := time.Parse(time.RFC3339, tc.used)
			if err != nil {
				t.Fatal(err)
			}
			if got := accountExpiry(used).Format(time.RFC3339); got != tc.expires {
				t.Fatalf("expiry = %s, want %s", got, tc.expires)
			}
		})
	}
}

func TestAccountCallsignImmutableAndDifferentAccountStartsZero(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	pair, _, old := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Alpha", IndependentAccounts: true})
	pair.pilot.Score = 37
	commitPublicFixture(t, a.infinite)
	if _, err := a.hub.callsigns.claim(old, []string{"Bravo"}); !errors.Is(err, errCallsignImmutable) {
		t.Fatal("same account renamed", err)
	}
	candidate := freshAccountKey(t)
	w := accountRequest(a, "/api/account/create", fmt.Sprintf(`{"publicToken":%q,"name":"Bravo"}`, candidate))
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	next, _, _ := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Bravo", PublicToken: candidate, IndependentAccounts: true})
	if next.pilot.Score != 0 || next.pilot.ID == pair.pilot.ID {
		t.Fatal("new name inherited score")
	}
	prior, err := a.infinite.accountInfo(old)
	if err != nil || prior.PublicProfile.Score != 37 || prior.Names[0] != "Alpha" {
		t.Fatal(prior, err)
	}
}
func TestAccountExpiryIgnoresPreviewAndExpiresScoreAtDeadline(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	a := accountAppFixture(t, path)
	clock := accountTestClock(a.hub.callsigns)
	*clock = time.Date(2026, time.January, 31, 12, 34, 56, 0, time.UTC)
	pair, c, key := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Alpha", IndependentAccounts: true})
	pair.pilot.Score = 43
	commitPublicFixture(t, a.infinite)
	a.infinite.remove(c)
	start := *clock
	for _, elapsed := range []time.Duration{7 * 24 * time.Hour, 14 * 24 * time.Hour, 28*24*time.Hour - time.Second} {
		*clock = start.Add(elapsed)
		info, err := a.infinite.accountInfo(key)
		if err != nil || info.PublicProfile == nil || info.PublicProfile.Score != 43 {
			t.Fatalf("account lost its score after %s: %+v, %v", elapsed, info, err)
		}
		if !a.hub.callsigns.availability(key, []string{"Alpha"})[0].Available {
			t.Fatal("active name unavailable")
		}
		if a.hub.callsigns.availability("", []string{"Alpha"})[0].Available {
			t.Fatal("active name released early")
		}
	}
	*clock = time.Date(2026, time.February, 28, 12, 34, 56, 0, time.UTC)
	if _, err := a.infinite.accountInfo(key); !errors.Is(err, errOnlineOwnerInvalid) {
		t.Fatal("preview kept account alive", err)
	}
	if !a.hub.callsigns.availability("", []string{"Alpha"})[0].Available {
		t.Fatal("expired name unavailable")
	}
	replacement := freshAccountKey(t)
	if _, err := a.infinite.createAccount(replacement, "Alpha"); err != nil {
		t.Fatal(err)
	}
	next, _, _ := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Alpha", PublicToken: replacement, IndependentAccounts: true})
	if next.pilot.Score != 0 || next.pilot.ID == pair.pilot.ID {
		t.Fatal("expired score resurrected")
	}
	a.infinite.close()
	a = accountAppFixture(t, path)
	if _, err := a.infinite.createAccount(key, "Alpha"); !errors.Is(err, errOnlineOwnerInvalid) {
		t.Fatal("expired key recreated account after restart", err)
	}
}
func TestAccountExplicitSignInRenewsButAvailabilityDoesNot(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	clock := accountTestClock(a.hub.callsigns)
	*clock = time.Date(2026, time.January, 31, 12, 34, 56, 0, time.UTC)
	key := freshAccountKey(t)
	if _, err := a.infinite.createAccount(key, "Alpha"); err != nil {
		t.Fatal(err)
	}
	start := *clock
	*clock = start.Add(27 * 24 * time.Hour)
	w := accountRequest(a, "/api/account", fmt.Sprintf(`{"publicToken":%q,"signIn":true}`, key))
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	*clock = start.Add(28 * 24 * time.Hour)
	if _, err := a.infinite.accountInfo(key); err != nil {
		t.Fatal("explicit sign-in did not renew", err)
	}
	renewedExpiry := time.Date(2026, time.March, 27, 12, 34, 56, 0, time.UTC)
	*clock = renewedExpiry.Add(-time.Second)
	if _, err := a.infinite.accountInfo(key); err != nil {
		t.Fatal("renewed account expired before a full calendar month", err)
	}
	*clock = renewedExpiry
	if _, err := a.infinite.accountInfo(key); !errors.Is(err, errOnlineOwnerInvalid) {
		t.Fatal("background preview renewed", err)
	}
}
func TestAccountConnectedGameplayKeepsIdentityAlive(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	clock := accountTestClock(a.hub.callsigns)
	_, _, key := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Alpha", IndependentAccounts: true})
	*clock = clock.Add(32 * 24 * time.Hour)
	a.infinite.mu.Lock()
	err := a.infinite.expireAccounts()
	a.infinite.mu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := a.infinite.accountInfo(key); err != nil {
		t.Fatal("active game expired", err)
	}
}
func TestAccountCreateRejectsMissingOrExpiredKeyAndIsIdempotent(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	key := freshAccountKey(t)
	for i := 0; i < 2; i++ {
		w := accountRequest(a, "/api/account/create", fmt.Sprintf(`{"publicToken":%q,"name":"Alpha"}`, key))
		var info onlineAccountInfo
		if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &info) != nil || info.TotalNames != 1 {
			t.Fatal(w.Code, w.Body.String())
		}
	}
	w := accountRequest(a, "/api/account/create", fmt.Sprintf(`{"publicToken":%q,"name":"Bravo"}`, key))
	if w.Code != 409 {
		t.Fatal("existing account renamed", w.Code, w.Body.String())
	}
}

func TestAccountExpiryRollbackLeavesOwnerAndScoreTogether(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	clock := accountTestClock(a.hub.callsigns)
	pair, c, key := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Alpha", IndependentAccounts: true})
	pair.pilot.Score = 11
	commitPublicFixture(t, a.infinite)
	a.infinite.remove(c)
	if _, err := a.infinite.publicDB.Exec(`CREATE TRIGGER fail_expiry BEFORE DELETE ON online_callsigns BEGIN SELECT RAISE(ABORT,'test failure'); END`); err != nil {
		t.Fatal(err)
	}
	*clock = accountExpiry(*clock)
	if _, err := a.infinite.accountInfo(key); err == nil {
		t.Fatal("expiry failure did not propagate")
	}
	var score int
	if err := a.infinite.publicDB.QueryRow("SELECT score FROM infinity_scores WHERE id=?", pair.pilot.ID).Scan(&score); err != nil || score != 11 {
		t.Fatal("failed expiry partially deleted score", score, err)
	}
	hash, _ := publicTokenHash(key)
	if !a.hub.callsigns.owners[hash] || a.hub.callsigns.expired[hash] {
		t.Fatal("failed expiry partially invalidated owner")
	}
	if _, err := a.infinite.publicDB.Exec("DROP TRIGGER fail_expiry"); err != nil {
		t.Fatal(err)
	}
	if _, err := a.infinite.accountInfo(key); !errors.Is(err, errOnlineOwnerInvalid) {
		t.Fatal("retry failed to expire", err)
	}
}

func TestAccountLegacyActivityMigrationGrantsOneMonthOnce(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	a := accountAppFixture(t, path)
	key := freshAccountKey(t)
	if _, err := a.infinite.createAccount(key, "Alpha"); err != nil {
		t.Fatal(err)
	}
	if _, err := a.infinite.publicDB.Exec("DELETE FROM online_account_activity"); err != nil {
		t.Fatal(err)
	}
	a.infinite.close()
	a = accountAppFixture(t, path)
	hash, _ := publicTokenHash(key)
	used := a.hub.callsigns.lastUsed[hash]
	if used == 0 {
		t.Fatal("legacy account lacks grace timestamp")
	}
	a.infinite.close()
	a = accountAppFixture(t, path)
	if a.hub.callsigns.lastUsed[hash] != used {
		t.Fatal("restart extended grace")
	}
	clock := accountTestClock(a.hub.callsigns)
	*clock = accountExpiry(time.Unix(used, 0)).Add(-time.Second)
	if _, err := a.infinite.accountInfo(key); err != nil {
		t.Fatal("migration grace ended before a full calendar month", err)
	}
	*clock = accountExpiry(time.Unix(used, 0))
	if _, err := a.infinite.accountInfo(key); !errors.Is(err, errOnlineOwnerInvalid) {
		t.Fatal("migration grace never expires", err)
	}
}

func TestAccountDisconnectedPrivateSecondaryDoesNotRenew(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	clock := accountTestClock(a.hub.callsigns)
	h := a.hub
	c := fakeClient()
	local := freshAccountKey(t)
	action(t, h, c, map[string]any{"type": "create", "name": "Alpha", "independentAccounts": true})
	primary := c.player.PublicToken
	action(t, h, c, map[string]any{"type": "add", "kind": "local", "name": "Wing", "localPublicToken": local, "localNewAccount": true, "independentAccounts": true})
	h.removeClient(c)
	*clock = accountExpiry(*clock)
	if _, err := a.infinite.accountInfo(primary); !errors.Is(err, errOnlineOwnerInvalid) {
		t.Fatal("disconnected controller renewed", err)
	}
	if _, err := a.infinite.accountInfo(local); !errors.Is(err, errOnlineOwnerInvalid) {
		t.Fatal("disconnected secondary renewed", err)
	}
}

func TestAccountExpiredPrivateClaimCannotRewriteOldPublicScore(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	clock := accountTestClock(a.hub.callsigns)
	pair, c, key := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Alpha", IndependentAccounts: true})
	pair.pilot.Score = 27
	commitPublicFixture(t, a.infinite)
	a.infinite.remove(c)
	*clock = accountExpiry(*clock)
	// A private claim performs registry expiration before the server's next sweep.
	stranger := fakeClient()
	action(t, a.hub, stranger, map[string]any{"type": "create", "name": "Alpha", "independentAccounts": true})
	if stranger.player == nil {
		t.Fatal("expired callsign was not released")
	}
	a.infinite.mu.Lock()
	err := a.infinite.persistPublicLocked(nil, nil)
	a.infinite.mu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	var count int
	if err := a.infinite.publicDB.QueryRow("SELECT COUNT(*) FROM infinity_scores WHERE id=?", pair.pilot.ID).Scan(&count); err != nil || count != 0 {
		t.Fatal("pending score resurrected deleted identity", count, err)
	}
	if _, err := a.infinite.accountInfo(key); !errors.Is(err, errOnlineOwnerInvalid) {
		t.Fatal("expired key returned", err)
	}
}

func TestAccountRotationCannotReuseAnExpiredBearer(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	clock := accountTestClock(a.hub.callsigns)
	expired := freshAccountKey(t)
	if _, err := a.infinite.createAccount(expired, "Old"); err != nil {
		t.Fatal(err)
	}
	*clock = accountExpiry(*clock)
	if _, err := a.infinite.accountInfo(expired); !errors.Is(err, errOnlineOwnerInvalid) {
		t.Fatal(err)
	}
	current := freshAccountKey(t)
	if _, err := a.infinite.createAccount(current, "Current"); err != nil {
		t.Fatal(err)
	}
	if _, err := a.infinite.rotateAccount(current, expired); !errors.Is(err, errNewAccountKeyInvalid) {
		t.Fatal("expired bearer reused during rotation", err)
	}
}

func TestAccountExpiryFailureRetainsEarlierQueuedCleanup(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	clock := accountTestClock(a.hub.callsigns)
	*clock = time.Date(2026, time.January, 15, 12, 0, 0, 0, time.UTC)
	first, c, key := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "First", IndependentAccounts: true})
	first.pilot.Score = 17
	commitPublicFixture(t, a.infinite)
	a.infinite.remove(c)
	firstExpiry := accountExpiry(*clock)
	*clock = clock.Add(time.Hour)
	second := freshAccountKey(t)
	if _, err := a.infinite.createAccount(second, "Second"); err != nil {
		t.Fatal(err)
	}
	secondExpiry := accountExpiry(*clock)
	*clock = firstExpiry
	r := a.hub.callsigns
	r.mu.Lock()
	err := r.expireAccountsLocked()
	r.mu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	hash, _ := publicTokenHash(key)
	if !r.expirationPending[hash] {
		t.Fatal("first expiry not queued")
	}
	*clock = secondExpiry
	if _, err := r.db.Exec(`CREATE TRIGGER fail_next_expiry BEFORE DELETE ON online_callsigns BEGIN SELECT RAISE(ABORT,'test failure'); END`); err != nil {
		t.Fatal(err)
	}
	a.infinite.mu.Lock()
	err = a.infinite.expireAccounts()
	a.infinite.mu.Unlock()
	if err == nil || !r.expirationPending[hash] {
		t.Fatal("failed sweep lost earlier pending cleanup", err)
	}
	if _, err := r.db.Exec("DROP TRIGGER fail_next_expiry"); err != nil {
		t.Fatal(err)
	}
	a.infinite.mu.Lock()
	err = a.infinite.expireAccounts()
	a.infinite.mu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	if _, exists := a.infinite.publicProfiles[hash]; exists {
		t.Fatal("retry retained expired score")
	}
}

func TestAccountCannotCreateOrAddSharedCallsigns(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	r := a.hub.callsigns
	if _, err := r.claim("", []string{"Alpha", "Wing"}); !errors.Is(err, errCallsignImmutable) {
		t.Fatal("new shared account accepted", err)
	}
	token, err := r.claim("", []string{"Alpha"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = r.claim(token, []string{"Alpha", "Wing"}); !errors.Is(err, errCallsignImmutable) {
		t.Fatal("existing account gained second callsign", err)
	}
	if len(r.names) != 1 || len(r.claims) != 1 {
		t.Fatal("rejected shared claim mutated registry")
	}
	// Exercise production request dispatch directly, without historical fixture setup.
	client := fakeClient()
	send := func(v any) {
		body, _ := json.Marshal(v)
		if err := a.hub.handle(client, body, time.Now()); err != nil {
			t.Fatal(err)
		}
	}
	send(map[string]any{"type": "create", "name": "Alpha", "publicToken": token})
	send(map[string]any{"type": "add", "kind": "local", "name": "Wing"})
	if roomLocalController(client.room, client.player) != nil || !hasError(client, "callsign_immutable") {
		t.Fatal("old room protocol added a second callsign")
	}
	socket := fakeClient()
	if !a.infinite.admit(socket) {
		t.Fatal("admit")
	}
	_, reject := a.infinite.join(socket, infiniteMessage{Name: "Fresh", LocalName: "Fresh Wing"}, time.Now())
	if reject != errCallsignImmutable.Error() {
		t.Fatal("old public protocol created a shared account", reject)
	}
}

func TestAccountLegacySharedNamesResumeButCannotGrow(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	key, ok := seedLegacyAccountFixture(t, a.hub.callsigns, "", []string{"Alpha", "Wing"})
	if !ok {
		t.Fatal("legacy fixture")
	}
	if _, err := a.hub.callsigns.claim(key, []string{"Alpha", "Wing"}); err != nil {
		t.Fatal("unchanged legacy account cannot resume", err)
	}
	for _, names := range [][]string{{"Alpha", "Other"}, {"Other", "Wing"}, {"Alpha", "Wing", "Third"}} {
		if _, err := a.hub.callsigns.claim(key, names); !errors.Is(err, errCallsignImmutable) {
			t.Fatal("legacy account grew or changed", names, err)
		}
	}
	pair, _, _ := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Alpha", LocalName: "Wing", PublicToken: key})
	if pair.local == nil {
		t.Fatal("legacy paired score missing")
	}
	pair.local.Score = 13
	commitPublicFixture(t, a.infinite)
	upgraded, _, _, _ := independentPair(t, a.infinite, "Alpha", "Wing", key)
	if upgraded.local.Score != 13 || upgraded.local.publicKey == upgraded.pilot.publicKey {
		t.Fatal("legacy split lost score or shared owner")
	}
}
