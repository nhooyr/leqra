package main

import (
	"bytes"
	"context"
	"embed"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io/fs"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

const (
	version         = "4.49.4"
	protocolVersion = 1
	maxRoomLimit    = 32768
)

//go:embed web/index.html web/assets
var embeddedWeb embed.FS

func checkAppIcons(web fs.FS) error {
	dir := "web/assets/v" + version
	entries, err := fs.ReadDir(web, dir)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".png") {
			continue
		}
		path := dir + "/" + entry.Name()
		data, err := fs.ReadFile(web, path)
		if err != nil {
			return err
		}
		if bytes.HasPrefix(data, []byte("version https://git-lfs.github.com/spec/v1")) {
			return fmt.Errorf("embedded app icon %s is a Git LFS pointer. Run git lfs pull and rebuild", path)
		}
	}
	return nil
}

type ipBudget struct {
	active, attempts int
	window           time.Time
}
type App struct {
	hub     *Hub
	origins []string
	mu      sync.Mutex
	ips     map[string]*ipBudget
}

func newApp(maxRooms int, origins []string) *App {
	return &App{hub: newHub(maxRooms), origins: origins, ips: map[string]*ipBudget{}}
}
func (a *App) reserve(ip string, now time.Time) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	// Bounded connection budgets. Forwarded client IP headers are deliberately
	// not trusted; a public reverse proxy should also enforce its own limits.
	b := a.ips[ip]
	if b == nil {
		// Existing addresses already have storage. Only new addresses need to
		// reclaim capacity, avoiding a full-table scan on every retry.
		if len(a.ips) > 4096 {
			for k, v := range a.ips {
				if v.active == 0 && now.Sub(v.window) >= time.Minute {
					delete(a.ips, k)
				}
			}
		}
		if len(a.ips) >= 8192 {
			return false
		}
		b = &ipBudget{window: now}
		a.ips[ip] = b
	}
	if now.Sub(b.window) >= time.Minute {
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
	ip, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		ip = r.RemoteAddr
	}
	if !a.reserve(ip, time.Now()) {
		http.Error(w, "Too many connections. Try again shortly.", 429)
		return
	}
	defer a.release(ip)
	ws, err := upgradeWS(w, r, a.origins)
	if err != nil {
		return
	}
	c := &Client{ws: ws, send: make(chan []byte, 12), updates: make(chan []byte, 1), done: make(chan struct{}), mapGeneration: -1, born: time.Now(), requireVersion: true}
	if !a.hub.addClient(c) {
		ws.writeClose(1013, "Server full")
		ws.close()
		return
	}
	if !c.enqueue(map[string]any{"type": "server_hello", "version": version, "protocol": protocolVersion}) {
		c.stop()
		return
	}
	go c.writeLoop()
	a.hub.readLoop(c)
}
func (a *App) handler() http.Handler {
	sub, err := fs.Sub(embeddedWeb, "web")
	if err != nil {
		panic(err)
	}
	static := http.FileServer(http.FS(sub))
	mux := http.NewServeMux()
	mux.HandleFunc("/ws", a.socket)
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
	assetPrefix := "/assets/v" + version + "/"
	assets := map[string]bool{
		"theme.js": true, "theme.css": true, "style.css": true, "favicon.svg": true,
		"netcode.js": true, "game.js": true, "pwa.js": true, "manifest.webmanifest": true,
		"sw.js": true, "icon-192.png": true, "icon-512.png": true,
		"icon-maskable-512.png": true, "apple-touch-icon.png": true,
		"icon-1024.png": true, "icon-maskable-1024.png": true,
		"favicon-256.png": true, "apple-touch-icon-512.png": true,
	}
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" && r.Method != "HEAD" {
			w.WriteHeader(405)
			return
		}
		if r.URL.Path == "/" || r.URL.Path == "/index.html" {
			w.Header().Set("Cache-Control", "no-cache, must-revalidate")
			if r.URL.Path == "/index.html" {
				// http.FileServer redirects an explicit /index.html to ./; serve the
				// same embedded shell through / instead so PWA precaching has a 200.
				r = r.Clone(r.Context())
				u := *r.URL
				u.Path = "/"
				r.URL = &u
			}
			static.ServeHTTP(w, r)
			return
		}
		if !strings.HasPrefix(r.URL.Path, assetPrefix) {
			http.NotFound(w, r)
			return
		}
		name := strings.TrimPrefix(r.URL.Path, assetPrefix)
		if !assets[name] {
			http.NotFound(w, r)
			return
		}
		if name == "sw.js" {
			w.Header().Set("Service-Worker-Allowed", "/")
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
	serving := make(chan error, 1)
	go func() { serving <- srv.Serve(listener) }()
	select {
	case err := <-serving:
		close(done)
		a.hub.close()
		return err
	case <-stopped:
	}
	// Give browsers time to render the terminal notice before closing their
	// hijacked connections, which net/http cannot drain for us.
	if a.hub.notifyShutdown() > 0 {
		time.Sleep(200 * time.Millisecond)
	}
	close(done)
	a.hub.close()
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
	if n, err := strconv.Atoi(os.Getenv("MAX_ROOMS")); err == nil && n > 0 {
		roomLimitDefault = n
	}
	maxRooms := flag.Int("max-rooms", roomLimitDefault, "Maximum in-memory rooms")
	checkAssets := flag.Bool("check-assets", false, "Check embedded app icons and exit")
	flag.Parse()
	if err := checkAppIcons(embeddedWeb); err != nil {
		log.Fatal(err)
	}
	if *checkAssets {
		return
	}
	if *maxRooms < 1 || *maxRooms > maxRoomLimit {
		log.Fatalf("max-rooms must be between 1 and %d", maxRoomLimit)
	}
	var origins []string
	for _, v := range strings.Split(os.Getenv("ALLOWED_ORIGINS"), ",") {
		if v = strings.TrimSpace(strings.TrimRight(v, "/")); v != "" {
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
