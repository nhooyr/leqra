package main

import (
	"encoding/json"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestUnshareRoomHostOnlyAndDetachesRemotePlayers(t *testing.T) {
	h, cs, r := makeRoom(t, 3)
	code := r.Code
	// Keep a bot in the authoritative room too; unshare should not need to kick
	// server-owned seats individually because the whole online room disappears.
	r.NextMember++
	r.Players[3] = &Player{ID: 3, Member: r.NextMember, Name: "BOT", Kind: "bot", Difficulty: "normal"}

	bad, _ := json.Marshal(map[string]any{"type": "unshare"})
	if err := h.handle(cs[1], bad, time.Now()); err != nil {
		t.Fatal(err)
	}
	if h.rooms[code] == nil {
		t.Fatal("guest was able to unshare room")
	}

	if err := h.handle(cs[0], bad, time.Now()); err != nil {
		t.Fatal(err)
	}
	if h.rooms[code] != nil {
		t.Fatal("online room still published after unshare")
	}
	for i, c := range cs {
		if c.room != nil || c.player != nil {
			t.Fatalf("client %d still attached", i)
		}
	}
}

func TestUnshareRejectedDuringActiveMatch(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	r.Game.Phase = "playing"
	req, _ := json.Marshal(map[string]any{"type": "unshare"})
	if err := h.handle(cs[0], req, time.Now()); err != nil {
		t.Fatal(err)
	}
	if h.rooms[r.Code] == nil {
		t.Fatal("active room was unshared")
	}
}

func TestGhostTankOverlapCannotPushThroughWall(t *testing.T) {
	g := &Game{
		Phase:      "playing",
		Clock:      60,
		SpawnClock: 999,
		World: World{Cols: 12, Rows: 10, Width: 1008, Height: 840, Walls: []Wall{
			{-4, -4, 1016, 8, "h", 0}, {-4, 836, 1016, 8, "h", 840},
			{-4, -4, 8, 848, "v", 0}, {1004, -4, 8, 848, "v", 1008},
			{248, -4, 8, 848, "v", 252},
		}},
	}
	// The normal tank is a legal radius away from the wall. The ghost's center is
	// still on the far side but its radius overlaps the normal tank through the wall.
	g.Tanks[0] = &Tank{ID: 0, X: 242, Y: 420, R: tankRadius, Alive: true, GhostTime: 5}
	g.Tanks[1] = &Tank{ID: 1, X: 273, Y: 420, R: tankRadius, Alive: true}
	var players [maxTanks]*Player
	players[0] = &Player{ID: 0, Member: 1, Name: "GHOST"}
	players[1] = &Player{ID: 1, Member: 2, Name: "OTHER"}
	beforeA, beforeB := g.Tanks[0].X, g.Tanks[1].X
	g.step(tickDT, [maxTanks]Input{}, players)
	if g.Tanks[0].X != beforeA || g.Tanks[1].X != beforeB {
		t.Fatalf("tank overlap force crossed wall: ghost %.3f->%.3f other %.3f->%.3f", beforeA, g.Tanks[0].X, beforeB, g.Tanks[1].X)
	}
}

func TestSafariFallbackMediaAllowedByCSP(t *testing.T) {
	rr := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "http://example.test/", nil)
	newApp(8, nil).handler().ServeHTTP(rr, req)
	csp := rr.Header().Get("Content-Security-Policy")
	if !strings.Contains(csp, "media-src 'self' blob:") {
		t.Fatalf("Safari blob-audio fallback blocked by CSP: %q", csp)
	}
}
