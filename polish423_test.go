package main

import (
	"encoding/json"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func Test423VersionedPWAAssetsAndCaching(t *testing.T) {
	app := newApp(4, nil)
	h := app.handler()
	index := httptest.NewRecorder()
	h.ServeHTTP(index, httptest.NewRequest("GET", "/", nil))
	if index.Code != 200 || index.Header().Get("Cache-Control") != "no-cache, must-revalidate" {
		t.Fatalf("index cache contract: %d %q", index.Code, index.Header().Get("Cache-Control"))
	}
	explicitIndex := httptest.NewRecorder()
	h.ServeHTTP(explicitIndex, httptest.NewRequest("GET", "/index.html", nil))
	if explicitIndex.Code != 200 || explicitIndex.Header().Get("Location") != "" {
		t.Fatalf("explicit index redirected: %d location=%q", explicitIndex.Code, explicitIndex.Header().Get("Location"))
	}
	body := index.Body.String()
	for _, want := range []string{
		`assets/v4.23.1/game.js`, `assets/v4.23.1/theme.js`, `assets/v4.23.1/manifest.webmanifest`,
		`assets/v4.23.1/pwa.js`, `apple-mobile-web-app-capable`, `apple-touch-icon`,
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("index missing %q", want)
		}
	}
	if strings.Contains(body, `src="game.js"`) || strings.Contains(body, `src="theme.js"`) || strings.Contains(body, `New local room`) {
		t.Fatal("index retained an unversioned asset URL or removed local-room action")
	}
	for _, name := range []string{"game.js", "theme.js", "style.css", "manifest.webmanifest", "sw.js", "icon-192.png", "icon-512.png"} {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest("GET", "/assets/v"+version+"/"+name, nil))
		if w.Code != 200 {
			t.Fatalf("%s: %d", name, w.Code)
		}
		if got := w.Header().Get("Cache-Control"); got != "public, max-age=31536000, immutable" {
			t.Fatalf("%s cache=%q", name, got)
		}
		if name == "sw.js" && w.Header().Get("Service-Worker-Allowed") != "/" {
			t.Fatal("service worker cannot control the app root")
		}
	}
	manifest := httptest.NewRecorder()
	h.ServeHTTP(manifest, httptest.NewRequest("GET", "/assets/v"+version+"/manifest.webmanifest", nil))
	var appManifest struct {
		ID       string `json:"id"`
		StartURL string `json:"start_url"`
		Scope    string `json:"scope"`
		Display  string `json:"display"`
		Icons    []struct {
			Sizes string `json:"sizes"`
		} `json:"icons"`
	}
	if err := json.Unmarshal(manifest.Body.Bytes(), &appManifest); err != nil {
		t.Fatal(err)
	}
	if appManifest.ID != "/" || appManifest.StartURL != "/" || appManifest.Scope != "/" || appManifest.Display != "standalone" || len(appManifest.Icons) < 3 {
		t.Fatalf("PWA manifest contract: %#v", appManifest)
	}
	sw := httptest.NewRecorder()
	h.ServeHTTP(sw, httptest.NewRequest("GET", "/assets/v"+version+"/sw.js", nil))
	for _, want := range []string{"leqra-app-", "v4.23.1", "'/ws'", "'/healthz'", "'/api/'", "caches.match('/')"} {
		if !strings.Contains(sw.Body.String(), want) {
			t.Fatalf("service worker missing %q", want)
		}
	}
	legacy := httptest.NewRecorder()
	h.ServeHTTP(legacy, httptest.NewRequest("GET", "/game.js", nil))
	if legacy.Code != 404 {
		t.Fatalf("legacy asset unexpectedly served: %d", legacy.Code)
	}
}

func Test423RealClientsMustCompleteVersionHandshake(t *testing.T) {
	h := newHub(2)
	c := fakeClient()
	c.requireVersion = true
	h.addClient(c)
	action(t, h, c, map[string]any{"type": "create", "name": "STALE"})
	if !hasError(c, "version_mismatch") || c.room != nil {
		t.Fatal("unversioned client was allowed to create a room")
	}
	action(t, h, c, map[string]any{"type": "client_hello", "version": "4.22.0", "protocol": protocolVersion})
	if !hasError(c, "version_mismatch") || c.versionOK {
		t.Fatal("stale client version was accepted")
	}
	action(t, h, c, map[string]any{"type": "client_hello", "version": version, "protocol": protocolVersion})
	if !c.versionOK {
		t.Fatal("matching client version was not accepted")
	}
	action(t, h, c, map[string]any{"type": "create", "name": "CURRENT"})
	if c.room == nil {
		t.Fatal("version-matched client could not create a room")
	}
}

func Test423ShutdownNoticeQueuesForConnectedClients(t *testing.T) {
	h, cs, _ := makeRoom(t, 3)
	for _, c := range cs {
		drain(c)
	}
	if got := h.notifyShutdown(); got != len(cs) {
		t.Fatalf("notified %d/%d clients", got, len(cs))
	}
	for i, c := range cs {
		packets := drain(c)
		if len(packets) != 1 || packets[0]["type"] != "server_shutdown" || !strings.Contains(packets[0]["message"].(string), "shutting down") {
			t.Fatalf("client %d shutdown packet: %#v", i, packets)
		}
	}
}

func Test423ActivatingTeamsBalancesTanks(t *testing.T) {
	h, cs, r := makeRoom(t, 5)
	r.Game.Rules.TeamMode = "ffa"
	for _, p := range r.Players {
		if p != nil {
			p.Team = 0
		}
	}
	rules := r.Game.settings()
	rules.TeamMode = "teams"
	data, _ := json.Marshal(map[string]any{"type": "rules", "rules": rules})
	if err := h.handle(cs[0], data, time.Now()); err != nil {
		t.Fatal(err)
	}
	counts := [3]int{}
	for _, p := range r.Players {
		if p != nil {
			if p.Team != 1 && p.Team != 2 {
				t.Fatalf("tank assigned to unexpected default team %d", p.Team)
			}
			counts[p.Team]++
		}
	}
	if d := counts[1] - counts[2]; d < -1 || d > 1 {
		t.Fatalf("unbalanced teams: %d vs %d", counts[1], counts[2])
	}
}
