package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"net/http/httptest"
	"strings"
	"testing"
)

type testLeaderboardAdminBackend struct {
	resets, removals int
	pattern          string
	fail             bool
}

func (b *testLeaderboardAdminBackend) AdminLeaderboard() []leaderboardAdminEntry {
	return []leaderboardAdminEntry{{ID: 1, Name: "<script>alert(1)</script>", Score: 17, Connected: true}, {ID: 2, Name: "Test Pilot", Score: 9}, {ID: 3, Name: "bot", Score: 3, Bot: true}}
}
func (b *testLeaderboardAdminBackend) ResetPublicLeaderboard() (int, error) {
	b.resets++
	if b.fail {
		return 0, errors.New("private database path")
	}
	return 3, nil
}
func (b *testLeaderboardAdminBackend) RemovePublicLeaderboard(pattern string) (int, error) {
	b.removals++
	b.pattern = pattern
	return 1, nil
}

func adminTestRequest(a *leaderboardAdmin, method, path, body string, headers map[string]string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, "http://127.0.0.1:8081"+path, strings.NewReader(body))
	r.RemoteAddr = "127.0.0.1:12345"
	for key, value := range headers {
		if key == "Host" {
			r.Host = value
		} else if key == "RemoteAddr" {
			r.RemoteAddr = value
		} else {
			r.Header.Set(key, value)
		}
	}
	w := httptest.NewRecorder()
	a.ServeHTTP(w, r)
	return w
}

func TestLeaderboardAdminProtectsLocalMutations(t *testing.T) {
	b := &testLeaderboardAdminBackend{}
	a, err := newLeaderboardAdmin(b)
	if err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct {
		name, path, body string
		headers          map[string]string
		status           int
	}{
		{"missing csrf", "/api/reset", "{}", nil, 403},
		{"wrong csrf", "/api/reset", "{}", map[string]string{"X-Leqra-Admin-CSRF": "forged"}, 403},
		{"cross origin with csrf", "/api/reset", "{}", map[string]string{"Origin": "https://evil.example", "X-Leqra-Admin-CSRF": a.csrf}, 403},
		{"null origin", "/api/reset", "{}", map[string]string{"Origin": "null", "X-Leqra-Admin-CSRF": a.csrf}, 403},
		{"rebinding", "/api/reset", "{}", map[string]string{"Host": "evil.example:8081", "X-Leqra-Admin-CSRF": a.csrf}, 403},
		{"nonlocal peer", "/api/reset", "{}", map[string]string{"RemoteAddr": "192.0.2.1:12345", "X-Leqra-Admin-CSRF": a.csrf}, 403},
		{"cross site fetch", "/api/reset", "{}", map[string]string{"Sec-Fetch-Site": "cross-site", "X-Leqra-Admin-CSRF": a.csrf}, 403},
		{"form content", "/api/reset", "{}", map[string]string{"Content-Type": "text/plain", "X-Leqra-Admin-CSRF": a.csrf}, 415},
		{"client score", "/api/reset", `{"score":999999}`, map[string]string{"X-Leqra-Admin-CSRF": a.csrf}, 400},
		{"extra object", "/api/reset", `{} {}`, map[string]string{"X-Leqra-Admin-CSRF": a.csrf}, 400},
		{"invalid regex", "/api/remove", `{"pattern":"["}`, map[string]string{"X-Leqra-Admin-CSRF": a.csrf}, 400},
		{"empty regex", "/api/remove", `{"pattern":""}`, map[string]string{"X-Leqra-Admin-CSRF": a.csrf}, 400},
		{"score with pattern", "/api/remove", `{"pattern":"test","score":999}`, map[string]string{"X-Leqra-Admin-CSRF": a.csrf}, 400},
	} {
		t.Run(test.name, func(t *testing.T) {
			headers := map[string]string{"Content-Type": "application/json"}
			for k, v := range test.headers {
				headers[k] = v
			}
			w := adminTestRequest(a, "POST", test.path, test.body, headers)
			if w.Code != test.status {
				t.Fatalf("status %d, want %d: %s", w.Code, test.status, w.Body)
			}
			if b.resets != 0 || b.removals != 0 {
				t.Fatal("rejected request mutated leaderboard")
			}
		})
	}
	for _, method := range []string{"GET", "HEAD", "OPTIONS", "PUT", "DELETE"} {
		w := adminTestRequest(a, method, "/api/reset", "", nil)
		if w.Code != 404 || b.resets != 0 {
			t.Fatalf("%s performed mutation", method)
		}
	}
	for _, path := range []string{"/", "/admin.js", "/api/leaderboard"} {
		w := adminTestRequest(a, "GET", path, "", map[string]string{"Host": "evil.example"})
		if w.Code != 403 || strings.Contains(w.Body.String(), a.csrf) {
			t.Fatal("rebinding could read admin content or CSRF token")
		}
	}
}

func TestLeaderboardAdminPreviewAndActions(t *testing.T) {
	b := &testLeaderboardAdminBackend{}
	a, _ := newLeaderboardAdmin(b)
	w := adminTestRequest(a, "GET", "/api/leaderboard?pattern=%28%3Fi%29test", "", nil)
	var got struct {
		CSRFToken                 string `json:"csrfToken"`
		Total, Connected, Matched int
		Entries                   []leaderboardAdminEntry
	}
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if w.Code != 200 || got.Total != 3 || got.Connected != 1 || got.Matched != 1 || len(got.Entries) != 1 || got.Entries[0].Name != "Test Pilot" || got.CSRFToken != a.csrf {
		t.Fatalf("unexpected preview: %+v", got)
	}
	for key, value := range map[string]string{"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"} {
		if w.Header().Get(key) != value {
			t.Fatalf("missing %s", key)
		}
	}
	if !strings.Contains(w.Header().Get("Content-Security-Policy"), "frame-ancestors 'none'") {
		t.Fatal("admin UI may be framed")
	}
	headers := map[string]string{"Content-Type": "application/json", "X-Leqra-Admin-CSRF": a.csrf, "Origin": "http://127.0.0.1:8081"}
	w = adminTestRequest(a, "POST", "/api/remove", `{"pattern":"(?i)test"}`, headers)
	if w.Code != 200 || b.removals != 1 || b.pattern != "(?i)test" {
		t.Fatalf("remove failed: %s", w.Body)
	}
	w = adminTestRequest(a, "POST", "/api/reset", `{}`, headers)
	if w.Code != 200 || b.resets != 1 {
		t.Fatalf("reset failed: %s", w.Body)
	}
	b.fail = true
	w = adminTestRequest(a, "POST", "/api/reset", `{}`, headers)
	if w.Code != 500 || bytes.Contains(w.Body.Bytes(), []byte("private database path")) {
		t.Fatal("database error was exposed or swallowed")
	}
}

func TestLeaderboardAdminRefusesPublicListener(t *testing.T) {
	b := &testLeaderboardAdminBackend{}
	for _, address := range []string{":8081", "0.0.0.0:8081", "[::]:8081", "192.0.2.1:8081", "example.com:8081"} {
		if closer, err := startLeaderboardAdmin(b, address); err == nil {
			closer.Close()
			t.Fatalf("accepted public address %q", address)
		}
	}
	closer, err := startLeaderboardAdmin(b, "off")
	if err != nil {
		t.Fatal(err)
	}
	closer.Close()
	for _, address := range []string{"127.0.0.1:0", "[::1]:0"} {
		closer, err := startLeaderboardAdmin(b, address)
		if err != nil {
			t.Fatal(err)
		}
		server := closer.(*leaderboardAdminListener).server
		if _, ok := server.Handler.(*leaderboardAdmin); !ok {
			t.Fatal("wrong listener handler")
		}
		if err := closer.Close(); err != nil {
			t.Fatal(err)
		}
	}
}
