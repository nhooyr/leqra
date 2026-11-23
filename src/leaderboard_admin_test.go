package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"strings"
	"testing"
	"time"
)

type testLeaderboardAdminBackend struct {
	resets, removals, recolors int
	pattern                    string
	fail                       bool
}

func (b *testLeaderboardAdminBackend) AdminLeaderboard() []leaderboardAdminEntry {
	return []leaderboardAdminEntry{{ID: 1, Name: "<script>alert(1)</script>", Score: 17, Connected: true}, {ID: 2, Name: "Test Pilot", Score: 9}, {ID: 3, Name: "bot", Score: 3, Bot: true}}
}
func (b *testLeaderboardAdminBackend) AdminAccounts() []leaderboardAdminAccount { return nil }
func (b *testLeaderboardAdminBackend) RecoverAdminAccount(string, string) error { return nil }
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

func (b *testLeaderboardAdminBackend) RandomizePublicColors() (int, error) {
	b.recolors++
	if b.fail {
		return 0, errors.New("private database path")
	}
	return 3, nil
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

func TestLeaderboardAdminRandomizeColors(t *testing.T) {
	b := &testLeaderboardAdminBackend{}
	a, err := newLeaderboardAdmin(b)
	if err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct {
		name, method, body string
		headers            map[string]string
		status             int
	}{
		{"missing csrf", "POST", "{}", nil, 403},
		{"cross origin", "POST", "{}", map[string]string{"Origin": "https://evil.example"}, 403},
		{"nonlocal peer", "POST", "{}", map[string]string{"RemoteAddr": "192.0.2.1:12345"}, 403},
		{"rebound host", "POST", "{}", map[string]string{"Host": "evil.example"}, 403},
		{"form content", "POST", "{}", map[string]string{"Content-Type": "text/plain"}, 415},
		{"filtered request", "POST", `{"pattern":"test"}`, nil, 400},
		{"client colors", "POST", `{"colors":[0,1]}`, nil, 400},
		{"extra object", "POST", `{} {}`, nil, 400},
		{"malformed JSON", "POST", `{`, nil, 400},
		{"get", "GET", "", nil, 404},
		{"put", "PUT", "{}", nil, 404},
	} {
		t.Run(test.name, func(t *testing.T) {
			headers := map[string]string{"Content-Type": "application/json", "X-Leqra-Admin-CSRF": a.csrf}
			if test.name == "missing csrf" {
				delete(headers, "X-Leqra-Admin-CSRF")
			}
			for key, value := range test.headers {
				headers[key] = value
			}
			response := adminTestRequest(a, test.method, "/api/randomize-colors", test.body, headers)
			if response.Code != test.status || b.recolors != 0 {
				t.Fatalf("rejected request: status=%d recolors=%d body=%s", response.Code, b.recolors, response.Body)
			}
		})
	}
	headers := map[string]string{"Content-Type": "application/json", "X-Leqra-Admin-CSRF": a.csrf}
	response := adminTestRequest(a, "POST", "/api/randomize-colors", `{}`, headers)
	var result struct{ Affected int }
	if response.Code != 200 || json.Unmarshal(response.Body.Bytes(), &result) != nil || result.Affected != 3 || b.recolors != 1 {
		t.Fatalf("randomization failed: status=%d body=%s", response.Code, response.Body)
	}
	b.fail = true
	response = adminTestRequest(a, "POST", "/api/randomize-colors", `{}`, headers)
	if response.Code != 500 || strings.Contains(response.Body.String(), "private database path") {
		t.Fatal("failed color mutation was hidden or exposed internal details")
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
	admin, err := startLeaderboardAdmin(b, "off")
	if err != nil {
		t.Fatal(err)
	}
	if len(admin.urls) != 0 {
		t.Fatalf("disabled admin reported URLs %q", admin.urls)
	}
	admin.Close()
}

func TestLeaderboardAdminAdvertisesBoundAddress(t *testing.T) {
	b := &testLeaderboardAdminBackend{}
	for _, address := range []string{"127.0.0.1:0", "[::1]:0"} {
		admin, err := startLeaderboardAdmin(b, address)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = admin.Close() })
		if len(admin.urls) != 1 {
			t.Fatalf("explicit IP must have one listener: %v", admin.urls)
		}
		adminURL := admin.urls[0]
		if _, ok := admin.server.Handler.(*leaderboardAdmin); !ok {
			t.Fatal("wrong listener handler")
		}
		advertised, err := url.Parse(adminURL)
		host, _, _ := net.SplitHostPort(address)
		if err != nil || advertised.Scheme != "http" || advertised.Hostname() != host || advertised.Port() == "" || advertised.Port() == "0" {
			t.Fatalf("invalid startup URL %q for %q", adminURL, address)
		}
		client := &http.Client{Transport: &http.Transport{DisableKeepAlives: true}, Timeout: time.Second}
		response, err := client.Get(adminURL)
		if err != nil {
			t.Fatalf("GET advertised URL %q: %v", adminURL, err)
		}
		response.Body.Close()
		if response.StatusCode != http.StatusOK {
			t.Fatalf("GET advertised URL %q: status %d", adminURL, response.StatusCode)
		}
		if err := admin.Close(); err != nil {
			t.Fatal(err)
		}
	}
}

func TestLeaderboardAdminLocalhostServesBothLoopbacks(t *testing.T) {
	admin, err := startLeaderboardAdmin(&testLeaderboardAdminBackend{}, "localhost:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = admin.Close() })
	if len(admin.urls) != 2 {
		t.Fatalf("localhost must have two listeners: %v", admin.urls)
	}
	advertised, err := url.Parse(admin.urls[0])
	if err != nil {
		t.Fatal(err)
	}
	for index, host := range []string{"127.0.0.1", "::1"} {
		bound, err := url.Parse(admin.urls[index])
		if err != nil || bound.Hostname() != host || bound.Port() != advertised.Port() {
			t.Fatalf("unexpected bound address: %q", admin.urls[index])
		}
	}
	var csrfToken string
	for _, network := range []string{"tcp4", "tcp6"} {
		t.Run(network, func(t *testing.T) {
			transport := &http.Transport{
				DisableKeepAlives: true,
				DialContext: func(ctx context.Context, _, address string) (net.Conn, error) {
					return (&net.Dialer{}).DialContext(ctx, network, address)
				},
			}
			client := &http.Client{Transport: transport, Timeout: time.Second}
			response, err := client.Get("http://" + net.JoinHostPort("localhost", advertised.Port()) + "/api/leaderboard")
			if err != nil {
				t.Fatal(err)
			}
			defer response.Body.Close()
			if response.StatusCode != http.StatusOK {
				t.Fatalf("status %d", response.StatusCode)
			}
			var body struct{ CSRFToken string }
			if err := json.NewDecoder(response.Body).Decode(&body); err != nil || body.CSRFToken == "" {
				t.Fatalf("missing CSRF token: %v", err)
			}
			if csrfToken != "" && csrfToken != body.CSRFToken {
				t.Fatal("listeners do not share the same admin handler")
			}
			csrfToken = body.CSRFToken
		})
	}
	if err := admin.Close(); err != nil {
		t.Fatal(err)
	}
	for _, raw := range admin.urls {
		bound, _ := url.Parse(raw)
		connection, err := net.DialTimeout("tcp", bound.Host, time.Second)
		if err == nil {
			connection.Close()
			t.Fatalf("admin listener %q survived shutdown", raw)
		}
	}
}

func TestLeaderboardAdminLocalhostBindFailureClosesFirstListener(t *testing.T) {
	blocker, err := net.Listen("tcp6", "[::1]:0")
	if err != nil {
		t.Fatal(err)
	}
	defer blocker.Close()
	port := strconv.Itoa(blocker.Addr().(*net.TCPAddr).Port)
	ipv4 := net.JoinHostPort("127.0.0.1", port)
	probe, err := net.Listen("tcp4", ipv4)
	if err != nil {
		t.Fatal(err)
	}
	probe.Close()
	admin, err := startLeaderboardAdmin(&testLeaderboardAdminBackend{}, net.JoinHostPort("localhost", port))
	if err == nil {
		admin.Close()
		t.Fatal("started despite occupied IPv6 port")
	}
	if !strings.Contains(err.Error(), blocker.Addr().String()) {
		t.Fatalf("error does not identify the failed bind: %v", err)
	}
	released, err := net.Listen("tcp4", ipv4)
	if err != nil {
		t.Fatalf("IPv4 listener leaked after IPv6 failure: %v", err)
	}
	released.Close()
}

func TestLeaderboardAdminImmediateCloseReleasesBothListeners(t *testing.T) {
	admin, err := startLeaderboardAdmin(&testLeaderboardAdminBackend{}, "LOCALHOST:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = admin.Close() })
	if len(admin.urls) != 2 {
		t.Fatalf("localhost must have two listeners: %v", admin.urls)
	}
	if err := admin.Close(); err != nil {
		t.Fatal(err)
	}
	for _, raw := range admin.urls {
		bound, _ := url.Parse(raw)
		listener, err := net.Listen("tcp", bound.Host)
		if err != nil {
			t.Fatalf("listener %q remains reserved after Close: %v", raw, err)
		}
		listener.Close()
	}
}
