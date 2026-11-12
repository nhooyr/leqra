package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"embed"
	"encoding/json"
	"encoding/xml"
	"errors"
	"flag"
	"fmt"
	"image/png"
	"io/fs"
	"log"
	"net"
	"net/http"
	"net/netip"
	"os"
	"os/signal"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

const (
	version         = "4.49.39"
	protocolVersion = 1
	maxRoomLimit    = 32768
	assetPath       = "assets/v" + version + "/"
	budgetCapacity  = 8192
	budgetWindow    = time.Minute
)

//go:embed web/index.html web/assets
var embeddedWeb embed.FS

var appIconPNGs = [...]string{
	"apple-touch-icon-512.png", "apple-touch-icon.png", "favicon-256.png",
	"icon-1024.png", "icon-192.png", "icon-512.png", "icon-maskable-1024.png", "icon-maskable-512.png",
}

var appShellFiles = [...]string{
	"theme.js", "theme.css", "style.css", "favicon.svg",
	"netcode.js", "game.js", "infinite-maze.js", "infinite.js",
	"pwa.js", "manifest.webmanifest", "sw.js",
}

var shellVersionMarkers = map[string]string{
	"game.js": "const GAME_VERSION='" + version + "';",
	"pwa.js":  "const VERSION = 'v" + version + "';",
	"sw.js":   "const VERSION = 'v" + version + "';",
}

var shellAssetReference = regexp.MustCompile(`[[:space:]](?:src|href)="(assets/[^"]+)"`)
var workerURL = regexp.MustCompile(`^/assets/v[0-9]+\.[0-9]+\.[0-9]+/sw\.js$`)

func appBuildID(web fs.FS) (string, error) {
	h := sha256.New()
	paths := []string{"web/index.html"}
	for _, names := range [][]string{appShellFiles[:], appIconPNGs[:]} {
		for _, name := range names {
			paths = append(paths, "web/"+assetPath+name)
		}
	}
	for _, path := range paths {
		data, err := fs.ReadFile(web, path)
		if err != nil {
			return "", err
		}
		fmt.Fprintf(h, "%s\x00%d\x00", path, len(data))
		_, _ = h.Write(data)
	}
	return fmt.Sprintf("v%s-%x", version, h.Sum(nil)[:8]), nil
}

func appIndex(data []byte, build string) []byte {
	data = shellAssetReference.ReplaceAllFunc(data, func(reference []byte) []byte {
		path := shellAssetReference.FindSubmatch(reference)[1]
		return bytes.Replace(reference, path, []byte(string(path)+"?build="+build), 1)
	})
	meta := []byte(`<meta name="leqra-build" content="` + build + `">` + "\n</head>")
	return bytes.Replace(data, []byte("</head>"), meta, 1)
}

func allowedAsset(name string) bool {
	return slices.Contains(appShellFiles[:], name) || slices.Contains(appIconPNGs[:], name)
}

func checkAppAssets(web fs.FS) error {
	const index = "web/index.html"
	shell, err := fs.ReadFile(web, index)
	if err != nil {
		return fmt.Errorf("required app shell: %w", err)
	}
	if !bytes.Contains(shell, []byte(`<meta name="leqra-version" content="v`+version+`">`)) {
		return fmt.Errorf("%s must declare leqra version v%s", index, version)
	}
	linked := make(map[string]bool)
	for _, match := range shellAssetReference.FindAllSubmatch(shell, -1) {
		path := string(match[1])
		name, current := strings.CutPrefix(path, assetPath)
		if !current || !allowedAsset(name) {
			return fmt.Errorf("%s references unavailable asset %s", index, path)
		}
		linked[name] = true
	}
	for _, name := range appShellFiles {
		path := "web/" + assetPath + name
		data, err := fs.ReadFile(web, path)
		if err != nil {
			return fmt.Errorf("required app asset: %w", err)
		}
		if len(bytes.TrimSpace(data)) == 0 {
			return fmt.Errorf("required app asset %s is empty", path)
		}
		if marker := shellVersionMarkers[name]; marker != "" && !bytes.Contains(data, []byte(marker)) {
			return fmt.Errorf("required app asset %s does not use leqra version v%s", path, version)
		}
		if name == "manifest.webmanifest" {
			if err := checkManifest(data); err != nil {
				return fmt.Errorf("invalid app asset %s: %w", path, err)
			}
		}
		// The PWA script registers the worker. The other shell files are
		// loaded directly from index.html.
		if name != "sw.js" && !linked[name] {
			return fmt.Errorf("%s is missing asset reference %s", index, assetPath+name)
		}
	}
	return checkAppIcons(web)
}

func checkManifest(data []byte) error {
	var manifest struct {
		StartURL string `json:"start_url"`
		Scope    string `json:"scope"`
		Icons    []struct{ Src string }
	}
	if err := json.Unmarshal(data, &manifest); err != nil {
		return err
	}
	if manifest.StartURL != "/" || manifest.Scope != "/" || len(manifest.Icons) == 0 {
		return errors.New("the manifest must start at the app root and advertise icons")
	}
	for _, icon := range manifest.Icons {
		if !slices.Contains(appIconPNGs[:], icon.Src) {
			return fmt.Errorf("unavailable icon %q", icon.Src)
		}
	}
	return nil
}

func checkAppIcons(web fs.FS) error {
	dir := "web/" + assetPath
	for _, name := range appIconPNGs {
		path := dir + name
		data, err := fs.ReadFile(web, path)
		if err != nil {
			return fmt.Errorf("required app icon: %w", err)
		}
		if bytes.HasPrefix(data, []byte("version https://git-lfs.github.com/spec/v1")) ||
			bytes.HasPrefix(data, []byte("version https://hawser.github.com/spec/v1")) {
			return fmt.Errorf("embedded app icon %s is a Git LFS pointer. Run git lfs pull and rebuild", path)
		}
		if _, err := png.Decode(bytes.NewReader(data)); err != nil {
			return fmt.Errorf("invalid app icon %s: %w", path, err)
		}
	}
	path := dir + "favicon.svg"
	data, err := fs.ReadFile(web, path)
	if err != nil {
		return fmt.Errorf("required app icon: %w", err)
	}
	var icon struct {
		XMLName xml.Name `xml:"svg"`
	}
	if err := xml.Unmarshal(data, &icon); err != nil {
		return fmt.Errorf("invalid app icon %s: %w", path, err)
	}
	return nil
}

type ipBudget struct {
	active, attempts int
	window           time.Time
}
type App struct {
	hub             *Hub
	infinite        *infiniteServer
	origins         []string
	mu              sync.Mutex
	ips             map[string]*ipBudget
	nextBudgetSweep time.Time
	upgradeMu       sync.RWMutex
	stopping        bool
}

func newApp(maxRooms int, origins []string) *App {
	hub := newHub(maxRooms)
	return &App{hub: hub, infinite: newInfiniteServer(hub), origins: origins, ips: map[string]*ipBudget{}}
}

// Matchmaking and upgrades share one normalized source identity. IPv6 privacy
// addresses on one /64 share a budget, and IPv4-mapped addresses use IPv4.
func connectionSource(remoteAddr string) string {
	host, _, err := net.SplitHostPort(remoteAddr)
	if err != nil {
		host = remoteAddr
	}
	addr, err := netip.ParseAddr(host)
	if err != nil {
		return host
	}
	addr = addr.Unmap()
	if addr.Is6() {
		return netip.PrefixFrom(addr.WithZone(""), 64).Masked().String()
	}
	return addr.String()
}

func (a *App) reserve(ip string, now time.Time) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	// Bounded connection budgets. Forwarded client IP headers are deliberately
	// not trusted; a public reverse proxy should also enforce its own limits.
	b := a.ips[ip]
	if b == nil {
		// Only new sources may need to reclaim capacity. Bound sweep frequency
		// when many of them arrive at once.
		if len(a.ips) > budgetCapacity/2 && !now.Before(a.nextBudgetSweep) {
			a.nextBudgetSweep = now.Add(time.Second)
			for k, v := range a.ips {
				if v.active == 0 && now.Sub(v.window) >= budgetWindow {
					delete(a.ips, k)
				}
			}
		}
		if len(a.ips) >= budgetCapacity {
			return false
		}
		b = &ipBudget{window: now}
		a.ips[ip] = b
	}
	if now.Sub(b.window) >= budgetWindow {
		b.window = now
		b.attempts = 0
	}
	b.attempts++
	if b.active >= 256 || b.attempts > 120 {
		return false
	}
	b.active++
	return true
}
func (a *App) release(ip string) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if b := a.ips[ip]; b != nil {
		b.active--
	}
}
func (a *App) socket(w http.ResponseWriter, r *http.Request) {
	a.serveSocket(w, r, func(c *Client) bool {
		if !a.hub.addClient(c) {
			return false
		}
		c.enqueue(map[string]any{"type": "server_hello", "version": version, "protocol": protocolVersion})
		go c.writeLoop()
		return true
	}, a.hub.readLoop)
}

func (a *App) serveSocket(w http.ResponseWriter, r *http.Request, admit func(*Client) bool, read func(*Client)) {
	key, err := validateUpgrade(w, r, a.origins)
	if err != nil {
		return
	}
	ip := connectionSource(r.RemoteAddr)
	deflate := acceptsSnapshotDeflate(r.Header.Values("Sec-WebSocket-Extensions"))
	c := a.openSocket(w, key, ip, admit, deflate)
	if c == nil {
		return
	}
	defer a.release(ip)
	read(c)
}

func (a *App) openSocket(w http.ResponseWriter, key, ip string, admit func(*Client) bool, deflate bool) *Client {
	a.upgradeMu.RLock()
	defer a.upgradeMu.RUnlock()
	if a.stopping {
		http.Error(w, "Server shutting down", http.StatusServiceUnavailable)
		return nil
	}
	if !a.reserve(ip, time.Now()) {
		http.Error(w, "Too many connections. Try again shortly.", 429)
		return nil
	}
	ws, err := upgradeWS(w, key, deflate)
	if err != nil {
		a.release(ip)
		return nil
	}
	c := &Client{ws: ws, sourceIP: ip, send: make(chan []byte, 12), updates: make(chan snapshotFrame, 1), done: make(chan struct{}), mapGeneration: -1, born: time.Now(), requireVersion: true}
	if !admit(c) {
		ws.writeClose(1013, "Server full")
		ws.close()
		a.release(ip)
		return nil
	}
	return c
}
func (a *App) handler() http.Handler {
	build, err := appBuildID(embeddedWeb)
	if err != nil {
		panic(err)
	}
	index, err := embeddedWeb.ReadFile("web/index.html")
	if err != nil {
		panic(err)
	}
	index = appIndex(index, build)
	worker, err := embeddedWeb.ReadFile("web/" + assetPath + "sw.js")
	if err != nil {
		panic(err)
	}
	worker = append([]byte("'use strict';\nself.LEQRA_BUILD = '"+build+"';\n"), worker...)
	sub, err := fs.Sub(embeddedWeb, "web")
	if err != nil {
		panic(err)
	}
	static := http.FileServer(http.FS(sub))
	mux := http.NewServeMux()
	mux.HandleFunc("/api/build", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		_ = json.NewEncoder(w).Encode(map[string]string{"version": version, "build": build})
	})
	mux.HandleFunc("/ws", a.socket)
	mux.HandleFunc("/api/infinity", a.infinityStatus)
	mux.HandleFunc("/ws/infinite", a.infiniteSocket)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			w.WriteHeader(405)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"status": "ok", "version": version, "rooms": a.hub.roomCount()})
	})
	mux.HandleFunc("/api/config", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			w.WriteHeader(405)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"online": true, "protocol": protocolVersion, "version": version, "maxPlayers": maxTanks, "chat": true, "chatLimit": chatMaxRunes, "opponentChat": true, "roomRename": true, "spectators": true, "maxSpectators": maxSpectators, "watchLinks": true, "tickRate": 60, "snapshotRate": 30, "inputAckSteps": true, "hostKick": true, "unshareRoom": true, "unifiedRooms": true, "localPlayers": 2, "serverBots": true, "teams": true, "matchRules": true, "postMatchStats": true, "matchmaking": true, "queues": queueDefinitions, "presets": true, "objectiveModes": []string{"elimination", "ctf", "koth", "survival"}, "powerUps": pickupTypes, "reconnectSeconds": 20})
	})
	assetPrefix := "/" + assetPath
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" && r.Method != "HEAD" {
			w.WriteHeader(405)
			return
		}
		w.Header().Set("X-Leqra-Build", build)
		if r.URL.Path == "/sw.js" || workerURL.MatchString(r.URL.Path) {
			w.Header().Set("Content-Type", "text/javascript; charset=utf-8")
			w.Header().Set("Cache-Control", "no-store")
			w.Header().Set("Service-Worker-Allowed", "/")
			http.ServeContent(w, r, "sw.js", time.Time{}, bytes.NewReader(worker))
			return
		}
		if r.URL.Path == "/" || r.URL.Path == "/index.html" {
			w.Header().Set("Cache-Control", "no-cache, must-revalidate")
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			w.Header().Set("ETag", `"`+build+`"`)
			http.ServeContent(w, r, "index.html", time.Time{}, bytes.NewReader(index))
			return
		}
		if !strings.HasPrefix(r.URL.Path, assetPrefix) {
			http.NotFound(w, r)
			return
		}
		name := strings.TrimPrefix(r.URL.Path, assetPrefix)
		if !allowedAsset(name) {
			http.NotFound(w, r)
			return
		}
		if name == "sw.js" {
			w.Header().Set("Service-Worker-Allowed", "/")
		}
		if name == "manifest.webmanifest" {
			w.Header().Set("Content-Type", "application/manifest+json")
		}
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
		static.ServeHTTP(w, r)
	})
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "same-origin")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'self'; worker-src 'self'; manifest-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; media-src 'self' blob:; connect-src 'self' ws: wss:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'")
		mux.ServeHTTP(w, r)
	})
}
func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func (a *App) serve(srv *http.Server, listener net.Listener, stopped <-chan os.Signal) error {
	done := make(chan struct{})
	go a.hub.run(done)
	go a.infinite.run(done)
	serving := make(chan error, 1)
	go func() { serving <- srv.Serve(listener) }()
	select {
	case err := <-serving:
		close(done)
		a.hub.close()
		a.infinite.close()
		return err
	case <-stopped:
	}
	// Finish in-flight upgrades and seal admission before selecting recipients.
	a.upgradeMu.Lock()
	a.stopping = true
	a.upgradeMu.Unlock()
	// Give browsers time to render the terminal notice before closing their
	// hijacked connections, which net/http cannot drain for us.
	if a.hub.notifyShutdown()+a.infinite.notifyShutdown() > 0 {
		time.Sleep(200 * time.Millisecond)
	}
	close(done)
	a.hub.close()
	a.infinite.close()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	// Serve returns as soon as Shutdown closes the listener. Keep main alive
	// until active HTTP handlers finish or the shutdown deadline expires.
	if err := srv.Shutdown(ctx); err != nil {
		return err
	}
	return <-serving
}

func main() {
	port := env("PORT", "8080")
	address := flag.String("addr", env("ADDR", ":"+port), "HTTP listen address")
	roomLimitDefault := maxRoomLimit
	if value := os.Getenv("MAX_ROOMS"); value != "" {
		// An invalid configured limit must fail validation rather than silently
		// opening the server with the much larger default.
		roomLimitDefault, _ = strconv.Atoi(value)
	}
	maxRooms := flag.Int("max-rooms", roomLimitDefault, "Maximum in-memory rooms")
	checkAssets := flag.Bool("check-assets", false, "Check embedded app shell and assets and exit")
	flag.Parse()
	if err := checkAppAssets(embeddedWeb); err != nil {
		log.Fatal(err)
	}
	if *checkAssets {
		return
	}
	if *maxRooms < 1 || *maxRooms > maxRoomLimit {
		log.Fatalf("MAX_ROOMS or -max-rooms must be between 1 and %d", maxRoomLimit)
	}
	var origins []string
	for _, v := range strings.Split(os.Getenv("ALLOWED_ORIGINS"), ",") {
		if v = strings.TrimRight(strings.TrimSpace(v), "/"); v != "" {
			if strings.Contains(v, "*") {
				log.Fatal("ALLOWED_ORIGINS must contain exact origins, not wildcards")
			}
			origins = append(origins, v)
		}
	}
	app := newApp(*maxRooms, origins)
	srv := &http.Server{Addr: *address, Handler: app.handler(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 15 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 8192}
	listener, err := net.Listen("tcp", *address)
	if err != nil {
		log.Fatal(err)
	}
	stopped := make(chan os.Signal, 1)
	signal.Notify(stopped, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(stopped)
	addrs, _ := net.InterfaceAddrs()
	openURL, lanURLs := startupURLs(listener.Addr().(*net.TCPAddr), addrs, lanHostname)
	fmt.Printf("leqra server v%s\n%s\n", version, openURL)
	for _, lanURL := range lanURLs {
		fmt.Println(lanURL)
	}
	if err := app.serve(srv, listener, stopped); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
}
