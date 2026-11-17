package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"image/png"
	"maps"
	"math"
	"net/http/httptest"
	"strings"
	"testing"
	"testing/fstest"
)

func TestIconOutlineFollowsBothTracks(t *testing.T) {
	data, err := embeddedWeb.ReadFile("web/" + assetPath + "icon-1024.png")
	if err != nil {
		t.Fatal(err)
	}
	im, err := png.Decode(bytes.NewReader(data))
	if err != nil {
		t.Fatal(err)
	}
	// Sample just outside each track's long edge.
	for _, y := range []float64{-17.3, 18.3} {
		xPixel := int((32.425 + .85*(31.5+y-32)) * 16)
		yPixel := int(math.Round((31.7 + .85*(42.5-32)) * 16))
		r, g, b, a := im.At(xPixel, yPixel).RGBA()
		if a < 60000 || r < 60000 || g < 60000 || b < 60000 {
			t.Fatalf("track edge y=%g is not outlined in white: %d,%d,%d,%d", y, r, g, b, a)
		}
	}
}

func TestIconTankIsUprightCenteredAndHasTurret(t *testing.T) {
	data, err := embeddedWeb.ReadFile("web/" + assetPath + "favicon.svg")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), `id="tank" transform="translate(31.5 42.5) rotate(-90)"`) || !strings.Contains(string(data), "<circle") || !strings.Contains(string(data), `width="26"`) {
		t.Fatal("vector icon must show an upright, centered tank with its turret")
	}
	for _, name := range []string{"icon-192.png", "icon-512.png", "icon-1024.png", "favicon-256.png"} {
		data, err := embeddedWeb.ReadFile("web/" + assetPath + name)
		if err != nil {
			t.Fatal(err)
		}
		im, err := png.Decode(bytes.NewReader(data))
		if err != nil {
			t.Fatal(err)
		}
		size := im.Bounds().Dx()
		_, _, _, tip := im.At(size*31/64, size*17/64).RGBA()
		_, _, _, right := im.At(size*60/64, size/2).RGBA()
		_, _, _, shadow := im.At(size*51/64, size*44/64).RGBA()
		if shadow != 0 {
			t.Fatalf("%s must not have a shadow protruding beyond the tracks", name)
		}
		if tip < 60000 || right != 0 {
			t.Fatalf("%s must have its turret facing up: tip alpha %d, right alpha %d", name, tip, right)
		}
		left, top, rightEdge, bottom := size, size, -1, -1
		for y := range size {
			laserLeft, laserRight := size, -1
			for x := range size {
				r, g, b, alpha := im.At(x, y).RGBA()
				if alpha > 32767 && r > g+8192 && b > g+8192 {
					if y >= size*2/5 {
						t.Fatalf("%s laser extends below the top of the tracks at (%d,%d)", name, x, y)
					}
					laserLeft, laserRight = min(laserLeft, x), max(laserRight, x)
				}
				if alpha > 32767 {
					left, top = min(left, x), min(top, y)
					rightEdge, bottom = max(rightEdge, x), max(bottom, y)
				}
			}
			if laserRight >= 0 && math.Abs(float64(laserLeft-(size-1-laserRight))) > 2 {
				t.Fatalf("%s laser is not mirrored at row %d: bounds %d-%d", name, y, laserLeft, laserRight)
			}
		}
		if math.Abs(float64(left-(size-1-rightEdge))) > 2 || math.Abs(float64(top-(size-1-bottom))) > 2 {
			t.Fatalf("%s artwork is not centered: bounds (%d,%d)-(%d,%d)", name, left, top, rightEdge, bottom)
		}
		if top < size/10 || size-1-bottom < size/10 {
			t.Fatalf("%s barrel and tracks need balanced padding: top %d, bottom %d", name, top, size-1-bottom)
		}
	}
}

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
		{"missing PNG", "icon-512.png", "", "required app icon"},
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
	for _, name := range []string{"game.js", "pwa.js", "sw.js"} {
		t.Run("stale "+name, func(t *testing.T) {
			files := maps.Clone(web)
			path := dir + name
			files[path] = &fstest.MapFile{Data: bytes.ReplaceAll(web[path].Data, []byte(version), []byte("0.0.0"))}
			if err := checkAppAssets(files); err == nil || !strings.Contains(err.Error(), path) {
				t.Fatalf("preflight = %v, want stale %s error", err, path)
			}
		})
	}
	for _, contents := range []string{
		`{`,
		`{"start_url":"/wrong","scope":"/","icons":[{"src":"icon-192.png"}]}`,
		`{"start_url":"/","scope":"/","icons":[{"src":"missing.png"}]}`,
	} {
		files := maps.Clone(web)
		path := dir + "manifest.webmanifest"
		files[path] = &fstest.MapFile{Data: []byte(contents)}
		if err := checkAppAssets(files); err == nil || !strings.Contains(err.Error(), path) {
			t.Fatalf("preflight = %v for invalid manifest %q", err, contents)
		}
	}
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
			opaque := strings.HasPrefix(name, "apple-touch")
			_, _, _, alpha := im.At(0, 0).RGBA()
			if opaque && alpha != 65535 || !opaque && alpha != 0 {
				t.Fatalf("corner alpha = %d; opaque export = %v", alpha, opaque)
			}
			ink, white := 0, 0
			for y := 0; y < size; y++ {
				for x := 0; x < size; x++ {
					r, g, b, alpha := im.At(x, y).RGBA()
					if opaque && alpha != 65535 {
						t.Fatalf("transparent Apple icon pixel at %d,%d", x, y)
					}
					if !opaque && (x == 0 || y == 0 || x == size-1 || y == size-1) && alpha != 0 {
						t.Fatalf("outlined tank must have a transparent background at %d,%d", x, y)
					}
					if alpha > 0 {
						ink++
					}
					if alpha > 45000 && r*65535/alpha > 55000 && g*65535/alpha > 55000 && b*65535/alpha > 55000 {
						white++
					}
				}
			}
			if ink < size*size/10 {
				t.Fatal("tank artwork is missing or unexpectedly small")
			}
			if white < size*size/1000 {
				t.Fatal("tank must have a visible white outline")
			}
		})
	}

	var manifest struct {
		Icons []struct {
			Src, Sizes, Type, Purpose string
		}
	}
	manifestResponse := get(t, "manifest.webmanifest")
	if got := manifestResponse.Header().Get("Content-Type"); got != "application/manifest+json" {
		t.Fatalf("manifest content type: %q", got)
	}
	if err := json.Unmarshal(manifestResponse.Body.Bytes(), &manifest); err != nil {
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
	if !highResolution["any"] || highResolution["maskable"] {
		t.Fatal("manifest must offer transparent artwork without a maskable background")
	}

	index := httptest.NewRecorder()
	h.ServeHTTP(index, httptest.NewRequest("GET", "/", nil))
	markup := strings.ReplaceAll(index.Body.String(), "?build="+index.Header().Get("X-Leqra-Build"), "")
	brand := fmt.Sprintf(`<div class="brand-mark" aria-hidden="true"><img src="assets/v%s/favicon.svg" width="48" height="48" alt=""></div>`, version)
	if !strings.Contains(markup, brand) {
		t.Fatal("header must use the shared app icon rather than a separate tank drawing")
	}
	for _, link := range []string{
		`favicon-256.png" type="image/png" sizes="256x256"`,
		`favicon.svg" type="image/svg+xml" sizes="any"`,
		`apple-touch-icon.png" sizes="180x180"`,
		`apple-touch-icon-512.png" sizes="512x512"`,
	} {
		if !strings.Contains(markup, link) {
			t.Fatalf("index does not advertise %s", link)
		}
	}
}
