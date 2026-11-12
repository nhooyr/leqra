package main

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"regexp"
	"strings"
	"time"
)

type leaderboardAdminEntry struct {
	ID        int    `json:"id"`
	Name      string `json:"name"`
	Score     int    `json:"score"`
	Bot       bool   `json:"bot"`
	Connected bool   `json:"connected"`
}

type leaderboardAdminBackend interface {
	AdminLeaderboard() []leaderboardAdminEntry
	ResetPublicLeaderboard() (int, error)
	RemovePublicLeaderboard(string) (int, error)
}

type leaderboardAdmin struct {
	backend leaderboardAdminBackend
	csrf    string
}

type leaderboardAdminListener struct{ server *http.Server }

func (l *leaderboardAdminListener) Close() error {
	if l.server == nil {
		return nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	return l.server.Shutdown(ctx)
}

// The admin handler is deliberately never registered on the game's HTTP server.
// Both the listener and handler reject non-loopback access, including rebinding.
func startLeaderboardAdmin(backend leaderboardAdminBackend, address string) (io.Closer, error) {
	if address == "off" {
		return &leaderboardAdminListener{}, nil
	}
	host, _, err := net.SplitHostPort(address)
	if err != nil || !adminLoopbackHost(host) {
		return nil, fmt.Errorf("LEQRA_ADMIN_ADDR must be a loopback host:port or off")
	}
	listener, err := net.Listen("tcp", address)
	if err != nil {
		return nil, fmt.Errorf("listen for leaderboard admin: %w", err)
	}
	if tcp, ok := listener.Addr().(*net.TCPAddr); !ok || !tcp.IP.IsLoopback() {
		listener.Close()
		return nil, errors.New("leaderboard admin listener must be loopback")
	}
	handler, err := newLeaderboardAdmin(backend)
	if err != nil {
		listener.Close()
		return nil, err
	}
	server := &http.Server{Handler: handler, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 15 * time.Second, IdleTimeout: 30 * time.Second, MaxHeaderBytes: 16 << 10}
	go func() {
		if err := server.Serve(listener); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Printf("leaderboard admin: %v", err)
		}
	}()
	log.Printf("leaderboard admin: http://%s (loopback only)", listener.Addr())
	return &leaderboardAdminListener{server: server}, nil
}

func adminLoopbackHost(host string) bool {
	if strings.EqualFold(host, "localhost") {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

func newLeaderboardAdmin(backend leaderboardAdminBackend) (*leaderboardAdmin, error) {
	var secret [32]byte
	if _, err := rand.Read(secret[:]); err != nil {
		return nil, fmt.Errorf("create admin CSRF secret: %w", err)
	}
	return &leaderboardAdmin{backend: backend, csrf: base64.RawURLEncoding.EncodeToString(secret[:])}, nil
}

func (a *leaderboardAdmin) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("Cross-Origin-Resource-Policy", "same-origin")
	w.Header().Set("Content-Security-Policy", "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")
	remote, _, remoteErr := net.SplitHostPort(r.RemoteAddr)
	host, _, hostErr := net.SplitHostPort(r.Host)
	if hostErr != nil {
		host = r.Host
	}
	if remoteErr != nil || !adminLoopbackHost(remote) || !adminLoopbackHost(host) {
		http.Error(w, "loopback access required", http.StatusForbidden)
		return
	}
	// Browsers supply Origin on cross-origin fetches. Require an exact match
	// when present, and a secret custom header on every mutation even if absent.
	if origin := r.Header.Get("Origin"); origin != "" && origin != "http://"+r.Host {
		http.Error(w, "same-origin access required", http.StatusForbidden)
		return
	}
	if site := r.Header.Get("Sec-Fetch-Site"); site != "" && site != "same-origin" && site != "none" {
		http.Error(w, "same-origin access required", http.StatusForbidden)
		return
	}
	switch {
	case r.Method == http.MethodGet && r.URL.Path == "/":
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		io.WriteString(w, leaderboardAdminHTML)
	case r.Method == http.MethodGet && r.URL.Path == "/admin.css":
		w.Header().Set("Content-Type", "text/css; charset=utf-8")
		io.WriteString(w, leaderboardAdminCSS)
	case r.Method == http.MethodGet && r.URL.Path == "/admin.js":
		w.Header().Set("Content-Type", "text/javascript; charset=utf-8")
		io.WriteString(w, leaderboardAdminJS)
	case r.Method == http.MethodGet && r.URL.Path == "/api/leaderboard":
		a.list(w, r)
	case r.Method == http.MethodPost && (r.URL.Path == "/api/reset" || r.URL.Path == "/api/remove"):
		if subtle.ConstantTimeCompare([]byte(r.Header.Get("X-Leqra-Admin-CSRF")), []byte(a.csrf)) != 1 {
			http.Error(w, "invalid CSRF token", http.StatusForbidden)
			return
		}
		a.mutate(w, r)
	default:
		http.NotFound(w, r)
	}
}

func adminPattern(pattern string) (*regexp.Regexp, error) {
	if len(pattern) > 1024 {
		return nil, errors.New("pattern must be at most 1024 bytes")
	}
	return regexp.Compile(pattern)
}

func (a *leaderboardAdmin) list(w http.ResponseWriter, r *http.Request) {
	pattern := r.URL.Query().Get("pattern")
	match, err := adminPattern(pattern)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	all := a.backend.AdminLeaderboard()
	entries := make([]leaderboardAdminEntry, 0)
	matched, connected := 0, 0
	for _, entry := range all {
		if entry.Connected {
			connected++
		}
		if match.MatchString(entry.Name) {
			matched++
			if len(entries) < 500 {
				entries = append(entries, entry)
			}
		}
	}
	adminJSON(w, map[string]any{"csrfToken": a.csrf, "total": len(all), "connected": connected, "matched": matched, "entries": entries})
}

func (a *leaderboardAdmin) mutate(w http.ResponseWriter, r *http.Request) {
	if strings.Split(r.Header.Get("Content-Type"), ";")[0] != "application/json" {
		http.Error(w, "application/json required", http.StatusUnsupportedMediaType)
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 4096)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	var pattern string
	var err error
	if r.URL.Path == "/api/remove" {
		var request struct {
			Pattern string `json:"pattern"`
		}
		err = decoder.Decode(&request)
		pattern = request.Pattern
		if err == nil && pattern == "" {
			err = errors.New("a nonempty pattern is required; use Reset all to clear everything")
		}
		if err == nil {
			_, err = adminPattern(pattern)
		}
	} else {
		var request struct{}
		err = decoder.Decode(&request)
	}
	if err == nil && decoder.Decode(new(any)) != io.EOF {
		err = errors.New("expected a single JSON object")
	}
	if err != nil {
		http.Error(w, "invalid request: "+err.Error(), http.StatusBadRequest)
		return
	}
	var count int
	if r.URL.Path == "/api/reset" {
		count, err = a.backend.ResetPublicLeaderboard()
	} else {
		count, err = a.backend.RemovePublicLeaderboard(pattern)
	}
	if err != nil {
		log.Printf("leaderboard admin mutation: %v", err)
		http.Error(w, "leaderboard change failed; check server logs", http.StatusInternalServerError)
		return
	}
	adminJSON(w, map[string]any{"affected": count})
}

func adminJSON(w http.ResponseWriter, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	json.NewEncoder(w).Encode(value)
}
