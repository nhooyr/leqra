package main

import (
	"bytes"
	"encoding/json"
	"io/fs"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"testing/fstest"
)

func TestPWAWorkerUpdatesAtStableAndLegacyURLs(t *testing.T) {
	h := newApp(4, nil).handler()
	var first string
	for _, path := range []string{"/sw.js", "/assets/v1.0.0/sw.js", "/assets/v" + version + "/sw.js"} {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest("GET", path, nil))
		if w.Code != 200 || w.Header().Get("Cache-Control") != "no-store" || w.Header().Get("Service-Worker-Allowed") != "/" {
			t.Fatalf("worker %s: status=%d headers=%v", path, w.Code, w.Header())
		}
		if !strings.HasPrefix(w.Header().Get("Content-Type"), "text/javascript") || !strings.Contains(w.Body.String(), "self.LEQRA_BUILD = '"+w.Header().Get("X-Leqra-Build")+"'") {
			t.Fatalf("worker %s has no coherent build", path)
		}
		if first == "" {
			first = w.Body.String()
		} else if first != w.Body.String() {
			t.Fatal("legacy worker URL did not receive the current worker")
		}
	}
	for _, path := range []string{"/assets/v1.0/sw.js", "/assets/private/sw.js", "/assets/v1.0.0/game.js"} {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest("GET", path, nil))
		if w.Code != 404 {
			t.Fatalf("unexpected legacy asset access %s: %d", path, w.Code)
		}
	}
}

func TestPWAShellAndMetadataPinEveryAssetToOneBuild(t *testing.T) {
	h := newApp(4, nil).handler()
	metadata := httptest.NewRecorder()
	h.ServeHTTP(metadata, httptest.NewRequest("GET", "/api/build", nil))
	var info struct{ Version, Build string }
	if err := json.Unmarshal(metadata.Body.Bytes(), &info); err != nil {
		t.Fatal(err)
	}
	if metadata.Code != 200 || metadata.Header().Get("Cache-Control") != "no-store" || info.Version != version || !strings.HasPrefix(info.Build, "v"+version+"-") {
		t.Fatalf("invalid build metadata: %s", metadata.Body.String())
	}
	index := httptest.NewRecorder()
	h.ServeHTTP(index, httptest.NewRequest("GET", "/index.html", nil))
	if index.Code != 200 || !strings.Contains(index.Body.String(), `<meta name="leqra-build" content="`+info.Build+`">`) {
		t.Fatalf("index is not pinned to metadata: %d", index.Code)
	}
	links := shellAssetReference.FindAllSubmatch(index.Body.Bytes(), -1)
	if len(links) < 10 {
		t.Fatal("fixture does not cover the real app bundle")
	}
	for _, link := range links {
		u, err := url.Parse(string(link[1]))
		if err != nil || u.Query().Get("build") != info.Build {
			t.Fatalf("unfingerprinted asset %s: %v", link[1], err)
		}
		asset := httptest.NewRecorder()
		h.ServeHTTP(asset, httptest.NewRequest("GET", "/"+u.String(), nil))
		if asset.Code != 200 || asset.Header().Get("X-Leqra-Build") != info.Build {
			t.Fatalf("asset did not match its shell: %s", u)
		}
	}
	conditional := httptest.NewRequest("GET", "/", nil)
	conditional.Header.Set("If-None-Match", index.Header().Get("ETag"))
	w := httptest.NewRecorder()
	h.ServeHTTP(w, conditional)
	if w.Code != 304 {
		t.Fatalf("unchanged shell ETag: %d", w.Code)
	}
}

func TestPWABuildChangesWhenOnlyCSSChanges(t *testing.T) {
	web := fstest.MapFS{}
	err := fs.WalkDir(embeddedWeb, "web", func(path string, entry fs.DirEntry, err error) error {
		if err != nil || entry.IsDir() {
			return err
		}
		data, err := embeddedWeb.ReadFile(path)
		web[path] = &fstest.MapFile{Data: data}
		return err
	})
	if err != nil {
		t.Fatal(err)
	}
	before, err := appBuildID(web)
	if err != nil {
		t.Fatal(err)
	}
	style := "web/" + assetPath + "style.css"
	web[style].Data = append(bytes.Clone(web[style].Data), []byte("\n/* CSS correction in the same release */")...)
	after, err := appBuildID(web)
	if err != nil || before == after {
		t.Fatalf("changed CSS retained a stale build identity: %q %q %v", before, after, err)
	}
	index := web["web/index.html"].Data
	if bytes.Equal(appIndex(index, before), appIndex(index, after)) {
		t.Fatal("same-version correction did not change browser asset URLs")
	}
	again, err := appBuildID(web)
	if err != nil || again != after {
		t.Fatal("identical app builds are not deterministic")
	}
}
