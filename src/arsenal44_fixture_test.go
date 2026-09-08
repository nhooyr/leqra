package main

import (
	"encoding/json"
	"net/http"
)

// Only the opt-in numeric-loopback test server invokes this. Production binaries
// contain no grant or damage endpoints. All actions still use the actual engine.
func handleArsenal44Fixture(app *App, w http.ResponseWriter, r *http.Request) bool {
	if r.URL.Path != "/_fixture/arsenal44" {
		return false
	}
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", 405)
		return true
	}
	var b struct {
		Code   string `json:"code"`
		Action string `json:"action"`
		Player int    `json:"player"`
		Power  string `json:"power"`
		Count  int    `json:"count"`
	}
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, 2048)).Decode(&b) != nil || b.Player < 0 || b.Player >= maxTanks {
		http.Error(w, "bad request", 400)
		return true
	}
	app.hub.mu.Lock()
	defer app.hub.mu.Unlock()
	room := app.hub.rooms[b.Code]
	if room == nil {
		http.NotFound(w, r)
		return true
	}
	g := room.Game
	t := g.Tanks[b.Player]
	if t == nil {
		http.Error(w, "no tank", 400)
		return true
	}
	switch b.Action {
	case "shield":
		for i := 0; i < min(8, max(1, b.Count)); i++ {
			g.grantPower(t, "shield")
		}
	case "hit":
		t.Invulnerable = 0
		owner := (t.ID + 1) % maxTanks
		for id, other := range g.Tanks {
			if other != nil && id != t.ID {
				owner = id
				break
			}
		}
		g.hurt(t, &Bullet{Owner: owner})
		t.Invulnerable = 600
	case "power":
		g.grantPower(t, b.Power)
	case "clear":
		t.Shield = 0
		t.ShieldCharges = 0
		t.Invulnerable = 0
	}
	app.hub.broadcastState(room)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(app.hub.stateMessage(room))
	return true
}
