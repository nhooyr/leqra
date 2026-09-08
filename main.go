package main

import (
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

const version = "4.20.0"

//go:embed web/*
var embeddedWeb embed.FS

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
	if len(a.ips) > 4096 {
		for k, v := range a.ips {
			if v.active == 0 && now.Sub(v.window) > time.Minute {
				delete(a.ips, k)
			}
		}
	}
	b := a.ips[ip]
	if b == nil {
		if len(a.ips) > 8192 {
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
	c := &Client{ws: ws, send: make(chan []byte, 12), updates: make(chan []byte, 1), done: make(chan struct{}), mapGeneration: -1, born: time.Now()}
	if !a.hub.addClient(c) {
		ws.writeClose(1013, "Server full")
		ws.close()
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
		_ = json.NewEncoder(w).Encode(map[string]any{"online": true, "protocol": 1, "version": version, "maxPlayers": maxTanks, "chat": true, "chatLimit": chatMaxRunes, "opponentChat": true, "roomRename": true, "spectators": true, "maxSpectators": maxSpectators, "watchLinks": true, "tickRate": 60, "snapshotRate": 30, "inputAckSteps": true, "hostKick": true, "unifiedRooms": true, "localPlayers": 2, "serverBots": true, "teams": true, "matchRules": true, "postMatchStats": true, "matchmaking": true, "queues": queueDefinitions, "presets": true, "objectiveModes": []string{"elimination", "ctf", "koth"}, "powerUps": pickupTypes, "reconnectSeconds": 20})
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" && r.Method != "HEAD" {
			w.WriteHeader(405)
			return
		}
		switch r.URL.Path {
		case "/", "/index.html", "/game.js", "/netcode.js", "/style.css", "/theme.css", "/theme.js", "/favicon.svg":
		default:
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Cache-Control", "no-cache")
		static.ServeHTTP(w, r)
	})
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "same-origin")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' ws: wss:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'")
		mux.ServeHTTP(w, r)
	})
}
func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
func main() {
	port := env("PORT", "8080")
	address := flag.String("addr", env("ADDR", ":"+port), "HTTP listen address")
	roomLimitDefault := 64
	if n, err := strconv.Atoi(env("MAX_ROOMS", "64")); err == nil && n > 0 {
		roomLimitDefault = n
	}
	maxRooms := flag.Int("max-rooms", roomLimitDefault, "Maximum in-memory rooms")
	flag.Parse()
	if *maxRooms < 1 || *maxRooms > 512 {
		log.Fatal("max-rooms must be between 1 and 512")
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
	done := make(chan struct{})
	go app.hub.run(done)
	srv := &http.Server{Addr: *address, Handler: app.handler(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 15 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 8192}
	listener, err := net.Listen("tcp", *address)
	if err != nil {
		log.Fatal(err)
	}
	_, boundPort, _ := net.SplitHostPort(listener.Addr().String())
	fmt.Printf("\nleqra online v%s\nOpen http://localhost:%s\n", version, boundPort)
	if addrs, err := net.InterfaceAddrs(); err == nil {
		for _, a := range addrs {
			if n, ok := a.(*net.IPNet); ok && n.IP.To4() != nil && !n.IP.IsLoopback() {
				fmt.Printf("Same Wi-Fi: http://%s:%s\n", n.IP.String(), boundPort)
			}
		}
	}
	fmt.Print("Start locally, or choose Share Room Online. Invite players or spectators.\nCtrl+C stops the server.\n\n")
	stopped := make(chan os.Signal, 1)
	signal.Notify(stopped, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-stopped
		close(done)
		app.hub.close()
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(ctx)
	}()
	if err := srv.Serve(listener); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
}
