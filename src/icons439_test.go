package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"image/png"
	"maps"
	"net/http/httptest"
	"strings"
	"testing"
	"testing/fstest"
)

func TestCheckAppIconsRejectsInvalidExports(t *testing.T) {
	if err := checkAppIcons(embeddedWeb); err != nil {
		t.Fatalf("checkAppIcons rejected the embedded icons: %v", err)
	}
	dir := "web/assets/v" + version + "/"
	web := fstest.MapFS{}
	for _, name := range append(appIconPNGs[:], "favicon.svg") {
		data, err := embeddedWeb.ReadFile(dir + name)
		if err != nil {
			t.Fatal(err)
		}
		web[dir+name] = &fstest.MapFile{Data: data}
	}
	for _, tc := range []struct{ name, icon, contents, want string }{
		{"missing PNG", "icon-maskable-512.png", "", "required app icon"},
		{"truncated PNG", "favicon-256.png", "\x89PNG\r\n\x1a\n", "invalid app icon"},
		{"Git LFS pointer", "apple-touch-icon.png", "version https://git-lfs.github.com/spec/v1\n", "git lfs pull"},
		{"legacy Git LFS pointer", "icon-192.png", "version https://hawser.github.com/spec/v1\n", "git lfs pull"},
		{"missing SVG", "favicon.svg", "", "required app icon"},
		{"invalid SVG", "favicon.svg", "<html/>", "invalid app icon"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			files := maps.Clone(web)
			path := dir + tc.icon
			if tc.contents == "" {
				delete(files, path)
			} else {
				files[path] = &fstest.MapFile{Data: []byte(tc.contents)}
			}
			if err := checkAppIcons(files); err == nil || !strings.Contains(err.Error(), path) || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("checkAppIcons = %v, want %q and %q", err, path, tc.want)
			}
		})
	}
}

func TestCheckAppAssetsRequiresACompleteMatchingShell(t *testing.T) {
	const index = "web/index.html"
	dir := "web/" + assetPath
	if err := checkAppAssets(embeddedWeb); err != nil {
		t.Fatalf("shipped shell failed preflight: %v", err)
	}
	web := fstest.MapFS{}
	paths := []string{index}
	for _, name := range append(appShellFiles[:], appIconPNGs[:]...) {
		paths = append(paths, dir+name)
	}
	for _, path := range paths {
		data, err := embeddedWeb.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		web[path] = &fstest.MapFile{Data: data}
	}
	for _, path := range []string{index, dir + "game.js", dir + "infinite.js", dir + "sw.js", dir + "style.css", dir + "manifest.webmanifest"} {
		t.Run("missing "+path, func(t *testing.T) {
			files := maps.Clone(web)
			delete(files, path)
			if err := checkAppAssets(files); err == nil || !strings.Contains(err.Error(), path) {
				t.Fatalf("preflight = %v, want error identifying %s", err, path)
			}
		})
	}
	t.Run("empty script", func(t *testing.T) {
		files := maps.Clone(web)
		files[dir+"game.js"] = &fstest.MapFile{Data: []byte(" \n")}
		if err := checkAppAssets(files); err == nil || !strings.Contains(err.Error(), "game.js is empty") {
			t.Fatalf("preflight = %v, want empty game.js error", err)
		}
	})
	for _, tc := range []struct{ name, before, after, want string }{
		{"stale shell", `content="v` + version + `"`, `content="v0.0.0"`, "must declare leqra version"},
		{"stale script", assetPath + "game.js", "assets/v0.0.0/game.js", "references unavailable asset"},
		{"unlinked script", `src="` + assetPath + `game.js"`, "", "is missing asset reference"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			files := maps.Clone(web)
			files[index] = &fstest.MapFile{Data: bytes.Replace(web[index].Data, []byte(tc.before), []byte(tc.after), 1)}
			if err := checkAppAssets(files); err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("preflight = %v, want %q", err, tc.want)
			}
		})
	}
}

func Test439IconExportsRoutesAndOfflineCache(t *testing.T) {
	h := newApp(4, nil).handler()
	prefix := "/assets/v" + version + "/"
	get := func(t *testing.T, name string) *httptest.ResponseRecorder {
		t.Helper()
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest("GET", prefix+name, nil))
		if w.Code != 200 {
			t.Fatalf("%s: status %d", name, w.Code)
		}
		return w
	}
	sw := get(t, "sw.js").Body.String()
	exports := map[string]int{
		"icon-192.png": 192, "icon-512.png": 512, "icon-1024.png": 1024,
		"icon-maskable-512.png": 512, "icon-maskable-1024.png": 1024,
		"favicon-256.png": 256, "apple-touch-icon.png": 180, "apple-touch-icon-512.png": 512,
	}
	for name, size := range exports {
		t.Run(name, func(t *testing.T) {
			w := get(t, name)
			if got := w.Header().Get("Content-Type"); got != "image/png" {
				t.Fatalf("PNG content type: %q", got)
			}
			if got := w.Header().Get("Cache-Control"); got != "public, max-age=31536000, immutable" {
				t.Fatalf("versioned cache policy: %q", got)
			}
			im, err := png.Decode(bytes.NewReader(w.Body.Bytes()))
			if err != nil {
				t.Fatal(err)
			}
			if im.Bounds().Dx() != size || im.Bounds().Dy() != size {
				t.Fatalf("export dimensions: %v, want %dx%d", im.Bounds(), size, size)
			}
			if !strings.Contains(sw, "BASE + '"+name+"'") {
				t.Fatal("icon is missing from offline precache")
			}
			maskable := strings.Contains(name, "maskable")
			opaque := maskable || strings.HasPrefix(name, "apple-touch")
			_, _, _, alpha := im.At(0, 0).RGBA()
			if opaque && alpha != 65535 || !opaque && alpha != 0 {
				t.Fatalf("corner alpha = %d; opaque export = %v", alpha, opaque)
			}
			if maskable {
				ink := 0
				for y := 0; y < size; y++ {
					for x := 0; x < size; x++ {
						r, g, b, a := im.At(x, y).RGBA()
						if a != 65535 {
							t.Fatalf("transparent maskable pixel at %d,%d", x, y)
						}
						if r > 18*257 {
							t.Fatalf("unexpected light/white raster artifact at %d,%d", x, y)
						}
						if g > 80*257 || b > 80*257 {
							ink++
							dx, dy := (float64(x)+.5)/float64(size)-.5, (float64(y)+.5)/float64(size)-.5
							if dx*dx+dy*dy > .4*.4 {
								t.Fatalf("tank artwork outside maskable safe circle at %d,%d", x, y)
							}
						}
					}
				}
				if ink < size*size/10 {
					t.Fatal("maskable tank artwork is missing or unexpectedly small")
				}
			}
		})
	}

	var manifest struct {
		Icons []struct {
			Src, Sizes, Type, Purpose string
		}
	}
	if err := json.Unmarshal(get(t, "manifest.webmanifest").Body.Bytes(), &manifest); err != nil {
		t.Fatal(err)
	}
	highResolution := map[string]bool{}
	for _, icon := range manifest.Icons {
		size, ok := exports[icon.Src]
		if !ok || icon.Sizes != fmt.Sprintf("%dx%d", size, size) || icon.Type != "image/png" {
			t.Fatalf("manifest icon does not match its export: %+v", icon)
		}
		if size >= 1024 {
			highResolution[icon.Purpose] = true
		}
	}
	if !highResolution["any"] || !highResolution["maskable"] {
		t.Fatal("manifest must offer high-resolution regular and maskable icons")
	}

	index := httptest.NewRecorder()
	h.ServeHTTP(index, httptest.NewRequest("GET", "/", nil))
	for _, link := range []string{
		`favicon-256.png" type="image/png" sizes="256x256"`,
		`favicon.svg" type="image/svg+xml" sizes="any"`,
		`apple-touch-icon.png" sizes="180x180"`,
		`apple-touch-icon-512.png" sizes="512x512"`,
	} {
		if !strings.Contains(index.Body.String(), link) {
			t.Fatalf("index does not advertise %s", link)
		}
	}
}
