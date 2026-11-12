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

func accountAppFixture(t *testing.T, path string) *App {
	t.Helper()
	a := newApp(8, nil)
	if path != "" {
		if err := a.infinite.openPublicStore(path); err != nil {
			t.Fatal(err)
		}
	}
	t.Cleanup(a.infinite.close)
	return a
}

func accountRequest(a *App, path, body string) *httptest.ResponseRecorder {
	r := httptest.NewRequest("POST", "http://leqra.test"+path, strings.NewReader(body))
	r.Header.Set("Origin", "http://leqra.test")
	r.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	a.handler().ServeHTTP(w, r)
	return w
}

func TestOnlineAccountPreviewAuthenticatesWithoutAllocatingOrReplacing(t *testing.T) {
	a := accountAppFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	pair, active, token := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Snow Fox", LocalName: "Wing"})
	pair.pilot.Score, pair.local.Score = 21, -2
	commitPublicFixture(t, a.infinite)
	if _, err := a.hub.callsigns.claim(token, []string{"Previous", "SNOW FOX"}); err != nil {
		t.Fatal(err)
	}
	before := a.infinite.publicProfiles[pair.pilot.publicKey]
	response := accountRequest(a, "/api/account", fmt.Sprintf(`{"publicToken":%q}`, token))
	var info onlineAccountInfo
	if response.Code != 200 || json.Unmarshal(response.Body.Bytes(), &info) != nil {
		t.Fatalf("preview failed: %d %s", response.Code, response.Body.String())
	}
	if strings.Join(info.Names, ",") != "Previous,Snow Fox,Wing" || info.TotalNames != 3 || info.PublicProfile == nil || info.PublicProfile.Name != "Snow Fox" || info.PublicProfile.Score != 21 || info.PublicProfile.LocalName != "Wing" || info.PublicProfile.LocalScore == nil || *info.PublicProfile.LocalScore != -2 {
		t.Fatalf("incorrect authorized preview: %+v", info)
	}
	if response.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("account preview can be cached")
	}
	hash, _ := publicTokenHash(token)
	if strings.Contains(response.Body.String(), token) || strings.Contains(response.Body.String(), hash) || strings.Contains(response.Body.String(), `"id"`) {
		t.Fatal("account preview leaked credential or unrelated identifiers")
	}
	if after := a.infinite.publicProfiles[hash]; after != before || len(a.infinite.publicProfiles) != 1 || a.infinite.public.players != 2 || pair.pilot.client != active || len(drain(active)) != 0 {
		t.Fatal("read-only account preview joined, replaced, or renewed an identity")
	}
	select {
	case <-active.done:
		t.Fatal("checking an imported key disconnected its current device")
	default:
	}
}

func TestOnlineAccountPrivateOnlyAndResetOwnerRemainImportableAcrossRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "data.sqlite")
	a := accountAppFixture(t, path)
	token, err := a.hub.callsigns.claim("", []string{"Private Only"})
	if err != nil {
		t.Fatal(err)
	}
	info, err := a.infinite.accountInfo(token)
	if err != nil || info.PublicProfile != nil || len(info.Names) != 1 || info.Names[0] != "Private Only" {
		t.Fatal("private callsign owner requires a public score profile")
	}
	_, c, _ := savedPublicJoin(t, a.infinite, infiniteMessage{PublicToken: token, Name: "Private Only"})
	a.infinite.remove(c)
	if _, err = a.infinite.ResetPublicLeaderboard(); err != nil {
		t.Fatal(err)
	}
	a.infinite.close()
	a = accountAppFixture(t, path)
	info, err = a.infinite.accountInfo(token)
	if err != nil || info.PublicProfile != nil || len(info.Names) != 1 || info.Names[0] != "Private Only" {
		t.Fatal("leaderboard reset or restart destroyed the account")
	}
}

func TestOnlineAccountPreviewBoundsHistoricalNamesAndOmitsDisabledLocalSeat(t *testing.T) {
	a := accountAppFixture(t, "")
	pair, _, token := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Primary", LocalName: "Local"})
	var aliases []string
	for i := 0; i < 180; i++ {
		aliases = append(aliases, fmt.Sprintf("Alias %03d", i))
	}
	if _, err := a.hub.callsigns.claim(token, aliases); err != nil {
		t.Fatal(err)
	}
	profile := a.infinite.publicProfiles[pair.pilot.publicKey]
	profile.localEnabled = false
	a.infinite.publicProfiles[profile.hash] = profile
	info, err := a.infinite.accountInfo(token)
	if err != nil || info.TotalNames != 182 || len(info.Names) != 128 || info.Names[0] != "Alias 000" || info.Names[127] != "Alias 127" || info.PublicProfile.LocalName != "" || info.PublicProfile.LocalScore != nil {
		t.Fatal("account preview unbounded, unstable, or restored disabled local seat")
	}
	if len(a.hub.callsigns.claims) != 182 {
		t.Fatal("preview cap released historical aliases")
	}
}

func TestOnlineAccountRejectsForgedKeysAndMalformedRequestsWithoutMutation(t *testing.T) {
	a := accountAppFixture(t, "")
	_, _, victim := savedPublicJoin(t, a.infinite, infiniteMessage{Name: "Victim"})
	unknown, _, _ := newPublicToken()
	for _, tc := range []struct {
		method, origin, content, body string
		status                        int
	}{
		{"GET", "http://leqra.test", "application/json", "", 405},
		{"POST", "https://evil.test", "application/json", fmt.Sprintf(`{"publicToken":%q}`, victim), 403},
		{"POST", "", "application/json", fmt.Sprintf(`{"publicToken":%q}`, victim), 403},
		{"POST", "http://leqra.test", "text/plain", fmt.Sprintf(`{"publicToken":%q}`, victim), 415},
		{"POST", "http://leqra.test", "application/json", `{}`, 401},
		{"POST", "http://leqra.test", "application/json", `{"publicToken":"p_forged"}`, 401},
		{"POST", "http://leqra.test", "application/json", fmt.Sprintf(`{"publicToken":%q}`, unknown), 401},
		{"POST", "http://leqra.test", "application/json", fmt.Sprintf(`{"publicToken":%q,"score":99}`, victim), 400},
		{"POST", "http://leqra.test", "application/json", fmt.Sprintf(`{"publicToken":%q,"name":"Victim"}`, unknown), 400},
		{"POST", "http://leqra.test", "application/json", fmt.Sprintf(`{"publicToken":%q} {}`, victim), 400},
		{"POST", "http://leqra.test", "application/json", fmt.Sprintf(`{"publicToken":%q}`, strings.Repeat("x", 2048)), 400},
	} {
		r := httptest.NewRequest(tc.method, "http://leqra.test/api/account", strings.NewReader(tc.body))
		r.Header.Set("Origin", tc.origin)
		r.Header.Set("Content-Type", tc.content)
		w := httptest.NewRecorder()
		a.handler().ServeHTTP(w, r)
		if w.Code != tc.status {
			t.Fatalf("%s %s =>%d want%d: %s", tc.method, tc.body, w.Code, tc.status, w.Body.String())
		}
		if strings.Contains(w.Body.String(), victim) || strings.Contains(w.Body.String(), unknown) || strings.Contains(w.Body.String(), "Victim") {
			t.Fatal("rejected account request disclosed an identity or bearer")
		}
	}
	if len(a.hub.callsigns.owners) != 1 || len(a.hub.callsigns.claims) != 1 || len(a.infinite.publicProfiles) != 1 {
		t.Fatal("unauthenticated preview allocated claims or profiles")
	}
}

func TestOnlineAccountSharesBoundedSourceBudgetWithoutLeakingActiveSlots(t *testing.T) {
	a := accountAppFixture(t, "")
	token, err := a.hub.callsigns.claim("", []string{"Owner"})
	if err != nil {
		t.Fatal(err)
	}
	body := fmt.Sprintf(`{"publicToken":%q}`, token)
	for i := 0; i < 121; i++ {
		w := accountRequest(a, "/api/account", body)
		want := 200
		if i == 120 {
			want = 429
		}
		if w.Code != want {
			t.Fatalf("check %d =>%d want%d", i, w.Code, want)
		}
	}
	for _, budget := range a.ips {
		if budget.active != 0 {
			t.Fatal("HTTP check leaked a connection-budget slot")
		}
		budget.window = time.Now().Add(-2 * time.Minute)
	}
	if w := accountRequest(a, "/api/account", body); w.Code != 200 {
		t.Fatal("rate budget did not recover next window")
	}
}
