package main

import (
	"encoding/json"
	"net/http"
)

// Test-only and invoked only from the existing opt-in loopback fixture.
// No endpoint, grant, or map override is linked into a production build.
func handleCombat42Fixture(app *App, w http.ResponseWriter, r *http.Request) bool {
	if r.URL.Path != "/_fixture/combat42" {
		return false
	}
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", 405)
		return true
	}
	var b struct {
		Code   string `json:"code"`
		Action string `json:"action"`
		Weapon string `json:"weapon"`
		Player int    `json:"player"`
	}
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, 2048)).Decode(&b) != nil {
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
	if b.Action == "win" {
		t := g.Tanks[b.Player]
		if t == nil {
			http.Error(w, "no player", 400)
			return true
		}
		g.Phase = "playing"
		g.Rules.ScoreTarget = 1
		for _, other := range g.Tanks {
			if other != nil && other.ID != t.ID {
				other.Alive = false
			}
		}
		t.Cooldown = .21
		t.CooldownTotal = .34
		t.Recoil = 1
		g.finishRound(t.ID)
	} else {
		g.Generation++
		g.World = World{Cols: 12, Rows: 10, Width: 1008, Height: 840, Walls: []Wall{
			{X: -4, Y: -4, W: 1016, H: 8, Axis: "h"}, {X: -4, Y: 836, W: 1016, H: 8, Axis: "h"},
			{X: -4, Y: -4, W: 8, H: 848, Axis: "v"}, {X: 1004, Y: -4, W: 8, H: 848, Axis: "v"},
		}}
		g.spatial = nil
		g.Bullets = nil
		g.Pickups = nil
		g.events = nil
		g.Phase = "playing"
		g.PhaseTime = 0
		g.Clock = 500
		g.SpawnClock = 999
		g.Objectives = nil
		for id, t := range g.Tanks {
			if t == nil {
				continue
			}
			t.Bot = false
			t.Alive = true
			t.X = 210
			t.Y = 126 + float64(id)*84
			t.Angle = 0
			t.VX = 0
			t.VY = 0
			t.Cooldown = 0
			t.CooldownTotal = 0
			t.ShotSerial = 0
			t.SpawnSerial++
			t.Invulnerable = 600
			t.Shield = 0
			t.SpeedTime = 0
			t.ScopeTime = 0
			t.GhostTime = 0
			t.Power = ""
			t.PowerTime = 0
			t.Charges = 0
			t.Recoil = 0
			t.fireHeld = false
			t.fireBlocked = false
			if b.Weapon != "" {
				g.grantPower(t, b.Weapon)
			}
		}
		for _, p := range room.Players {
			if p != nil {
				p.Input = Input{}
				p.FirePending = false
			}
		}
	}
	app.hub.broadcastState(room)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"ok": true, "generation": g.Generation})
	return true
}
