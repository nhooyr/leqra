package main

import (
	"net/http/httptest"
	"strings"
	"testing"
)

func Test45DarkAppearanceAssetsAreServedSameOrigin(t *testing.T) {
	app := newApp(4, nil)
	for _, path := range []string{"/assets/v" + version + "/theme.js", "/assets/v" + version + "/theme.css"} {
		w := httptest.NewRecorder()
		app.handler().ServeHTTP(w, httptest.NewRequest("GET", path, nil))
		if w.Code != 200 || w.Body.Len() < 100 {
			t.Fatalf("missing appearance asset %s", path)
		}
		if w.Header().Get("Cache-Control") != "public, max-age=31536000, immutable" {
			t.Fatal("versioned appearance asset is not immutable-cacheable")
		}
	}
}
func Test45LightThemeAndSystemThemeCodeRemoved(t *testing.T) {
	app := newApp(4, nil)
	w := httptest.NewRecorder()
	app.handler().ServeHTTP(w, httptest.NewRequest("GET", "/", nil))
	html := w.Body.String()
	if !strings.Contains(html, `content="dark"`) {
		t.Fatal("document does not declare dark-only color scheme")
	}
	for _, path := range []string{"/assets/v" + version + "/theme.js", "/assets/v" + version + "/theme.css", "/assets/v" + version + "/game.js"} {
		w := httptest.NewRecorder()
		app.handler().ServeHTTP(w, httptest.NewRequest("GET", path, nil))
		body := strings.ToLower(w.Body.String())
		for _, bad := range []string{"prefers-color-scheme", "neon purple", "themeMode", "data-theme=\"light\""} {
			if strings.Contains(body, strings.ToLower(bad)) {
				t.Fatalf("%s still contains removed light-theme path %q", path, bad)
			}
		}
	}
}
func Test45ThemeBootstrapPrecedesStyles(t *testing.T) {
	app := newApp(4, nil)
	w := httptest.NewRecorder()
	app.handler().ServeHTTP(w, httptest.NewRequest("GET", "/", nil))
	html := w.Body.String()
	boot := strings.Index(html, `<script src="assets/v`+version+`/theme.js"></script>`)
	css := strings.Index(html, `rel="stylesheet"`)
	if boot < 0 || css < 0 || boot > css {
		t.Fatal("dark palette must initialize before styles")
	}
}
