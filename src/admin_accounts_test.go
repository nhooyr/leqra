package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

func adminAccountList(t *testing.T, admin *leaderboardAdmin, pattern string) []leaderboardAdminAccount {
	t.Helper()
	response := adminTestRequest(admin, "GET", "/api/leaderboard?pattern="+pattern, "", nil)
	var body struct{ Accounts []leaderboardAdminAccount }
	if response.Code != http.StatusOK || json.Unmarshal(response.Body.Bytes(), &body) != nil {
		t.Fatal("admin account listing failed")
	}
	return body.Accounts
}

func adminRecover(t *testing.T, admin *leaderboardAdmin, id, key string, headers map[string]string) int {
	t.Helper()
	body, err := json.Marshal(map[string]string{"accountId": id, "newPublicToken": key})
	if err != nil {
		t.Fatal(err)
	}
	return adminTestRequest(admin, "POST", "/api/recover-account", string(body), headers).Code
}

func adminRecoveryHeaders(admin *leaderboardAdmin) map[string]string {
	return map[string]string{"Content-Type": "application/json", "X-Leqra-Admin-CSRF": admin.csrf}
}

func TestAdminRecoveryIncludesAccountsWithoutScoresAndSurvivesRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	a := accountAppFixture(t, path)
	old := freshAccountKey(t)
	if _, err := a.infinite.createAccount(old, "Lobby Pilot"); err != nil {
		t.Fatal(err)
	}
	if len(a.infinite.AdminLeaderboard()) != 0 {
		t.Fatal("private-only account unexpectedly has a score")
	}
	admin, err := newLeaderboardAdmin(a.infinite)
	if err != nil {
		t.Fatal(err)
	}
	accounts := adminAccountList(t, admin, "Lobby")
	if len(accounts) != 1 || !slices.Equal(accounts[0].Names, []string{"Lobby Pilot"}) {
		t.Fatal("private-only account missing from recovery list")
	}
	hash, _ := publicTokenHash(old)
	response := adminTestRequest(admin, "GET", "/api/leaderboard", "", nil)
	if strings.Contains(response.Body.String(), old) || strings.Contains(response.Body.String(), hash) {
		t.Fatal("account list exposed a bearer or owner hash")
	}
	if len(adminAccountList(t, admin, "missing")) != 0 {
		t.Fatal("account filter ignored the pattern")
	}
	candidate := freshAccountKey(t)
	if code := adminRecover(t, admin, accounts[0].ID, candidate, adminRecoveryHeaders(admin)); code != 200 {
		t.Fatalf("recovery status %d", code)
	}
	if _, err := a.infinite.accountInfo(old); !errors.Is(err, errOnlineOwnerRevoked) {
		t.Fatal("old key remained usable")
	}
	if code := adminRecover(t, admin, accounts[0].ID, freshAccountKey(t), adminRecoveryHeaders(admin)); code != 404 {
		t.Fatalf("stale account identifier was accepted: %d", code)
	}
	a.infinite.close()
	a = accountAppFixture(t, path)
	info, err := a.infinite.accountInfo(candidate)
	if err != nil || !slices.Equal(info.Names, []string{"Lobby Pilot"}) || info.PublicProfile != nil {
		t.Fatal("recovery did not preserve the account across restart")
	}
	if _, err := a.infinite.accountInfo(old); !errors.Is(err, errOnlineOwnerRevoked) {
		t.Fatal("restart forgot revocation")
	}
}

func TestAdminRecoveryPreservesIndependentPilotScoresAndDisconnectsOldKey(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	pair, client, primary, old := independentPair(t, a.infinite, "Primary", "Wing", "")
	pair.pilot.Score, pair.local.Score = 31, -7
	commitPublicFixture(t, a.infinite)
	admin, _ := newLeaderboardAdmin(a.infinite)
	accounts := adminAccountList(t, admin, "Wing")
	if len(accounts) != 1 {
		t.Fatal("independent local account missing")
	}
	response := adminTestRequest(admin, "GET", "/api/leaderboard?pattern=Wing", "", nil)
	var listing struct{ Entries []leaderboardAdminEntry }
	if json.Unmarshal(response.Body.Bytes(), &listing) != nil || len(listing.Entries) != 1 || listing.Entries[0].AccountID != accounts[0].ID {
		t.Fatal("leaderboard row was not associated with its owning account")
	}
	candidate := freshAccountKey(t)
	if code := adminRecover(t, admin, accounts[0].ID, candidate, adminRecoveryHeaders(admin)); code != 200 {
		t.Fatalf("recovery status %d", code)
	}
	info, err := a.infinite.accountInfo(candidate)
	if err != nil || info.PublicProfile == nil || info.PublicProfile.Score != -7 || info.PublicProfile.Name != "Wing" {
		t.Fatal("recovery changed the local pilot's identity or score")
	}
	info, err = a.infinite.accountInfo(primary)
	if err != nil || info.PublicProfile == nil || info.PublicProfile.Score != 31 {
		t.Fatal("recovery affected the other account")
	}
	if _, err := a.infinite.accountInfo(old); !errors.Is(err, errOnlineOwnerRevoked) {
		t.Fatal("old local key remained valid")
	}
	notices := drain(client)
	if len(notices) != 1 || notices[0]["code"] != "account_key_revoked" || notices[0]["seat"] != float64(1) || strings.Contains(noticeText(notices), candidate) {
		t.Fatal("old client did not receive a private revocation notice")
	}
}

func noticeText(notices []map[string]any) string {
	data, _ := json.Marshal(notices)
	return string(data)
}

func TestAdminRecoveryRequiresLocalOriginCSRFAndFreshAccount(t *testing.T) {
	a := accountAppFixture(t, "")
	old := freshAccountKey(t)
	if _, err := a.infinite.createAccount(old, "Owner"); err != nil {
		t.Fatal(err)
	}
	admin, _ := newLeaderboardAdmin(a.infinite)
	id := adminAccountList(t, admin, "")[0].ID
	for _, extra := range []map[string]string{
		nil,
		{"X-Leqra-Admin-CSRF": "wrong"},
		{"X-Leqra-Admin-CSRF": admin.csrf, "Origin": "https://evil.example"},
		{"X-Leqra-Admin-CSRF": admin.csrf, "Host": "evil.example"},
		{"X-Leqra-Admin-CSRF": admin.csrf, "RemoteAddr": "192.0.2.1:1234"},
	} {
		headers := map[string]string{"Content-Type": "application/json"}
		for key, value := range extra {
			headers[key] = value
		}
		if code := adminRecover(t, admin, id, freshAccountKey(t), headers); code != 403 {
			t.Fatalf("untrusted recovery status %d", code)
		}
	}
	if code := adminRecover(t, admin, "forged", freshAccountKey(t), adminRecoveryHeaders(admin)); code != 404 {
		t.Fatalf("forged identity status %d", code)
	}
	if code := adminRecover(t, admin, id, "invalid", adminRecoveryHeaders(admin)); code != 400 {
		t.Fatalf("invalid key status %d", code)
	}
	if response := adminTestRequest(admin, "GET", "/api/recover-account", "", nil); response.Code != 404 {
		t.Fatal("GET can recover an account")
	}
	publicResponse := accountRequest(a, "/api/recover-account", "{}")
	var publicResult map[string]any
	_ = json.Unmarshal(publicResponse.Body.Bytes(), &publicResult)
	if publicResult["recovered"] == true {
		t.Fatal("recovery is reachable through the public game server")
	}
	if _, err := a.infinite.accountInfo(old); err != nil {
		t.Fatal("rejected recovery changed the account")
	}
}

func TestAdminRecoveryDatabaseFailureKeepsOldKeyAndScore(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	pair, client, old := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Owner"})
	pair.pilot.Score = 19
	commitPublicFixture(t, a.infinite)
	admin, _ := newLeaderboardAdmin(a.infinite)
	id := adminAccountList(t, admin, "Owner")[0].ID
	if _, err := a.infinite.publicDB.Exec(`CREATE TRIGGER fail_admin_recovery BEFORE DELETE ON online_owners BEGIN SELECT RAISE(ABORT,'test failure'); END`); err != nil {
		t.Fatal(err)
	}
	candidate := freshAccountKey(t)
	if code := adminRecover(t, admin, id, candidate, adminRecoveryHeaders(admin)); code != 503 {
		t.Fatalf("failed recovery status %d", code)
	}
	info, err := a.infinite.accountInfo(old)
	if err != nil || info.PublicProfile.Score != 19 || pair.pilot.client != client {
		t.Fatal("failed recovery changed the original account")
	}
	if _, err := a.infinite.accountInfo(candidate); !errors.Is(err, errOnlineOwnerInvalid) {
		t.Fatal("failed replacement key became valid")
	}
}
