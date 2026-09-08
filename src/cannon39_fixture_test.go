package main

import (
	"encoding/json"
	"net/http"
)

// Called only by the explicitly enabled, loopback-only TestBrowserFixture.
// _test.go is excluded from both go run . and production executables.
func handleCannon39Fixture(app *App, w http.ResponseWriter, r *http.Request) bool {
	if r.URL.Path != "/_fixture/cannon39" {
		return false
	}
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", 405)
		return true
	}
	var req struct {
		Code   string `json:"code"`
		Shield bool   `json:"shield"`
	}
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, 2048)).Decode(&req) != nil {
		http.Error(w, "bad request", 400)
		return true
	}
	app.hub.mu.Lock()
	defer app.hub.mu.Unlock()
	room := app.hub.rooms[req.Code]
	if room == nil {
		http.NotFound(w, r)
		return true
	}
	g := room.Game
	g.World = World{Cols: 12, Rows: 10, Width: 1008, Height: 840, Walls: []Wall{
		{-4, -4, 1016, 8, "h", 0}, {-4, 836, 1016, 8, "h", 840}, {-4, -4, 8, 848, "v", 0}, {1004, -4, 8, 848, "v", 1008},
		{416, -4, 8, 848, "v", 420}, {668, -4, 8, 848, "v", 672},
	}}
	g.spatial = nil
	g.buildNavigation()
	g.Generation++
	g.Phase = "playing"
	g.PhaseTime = 0
	g.Clock = 600
	g.SpawnClock = 999
	g.Bullets = []*Bullet{}
	g.Pickups = []*Pickup{}
	for id, p := range g.Tanks {
		if p == nil {
			continue
		}
		p.X = 126
		p.Y = 210 + float64(id%4)*168
		p.Angle = 0
		p.Alive = true
		p.Invulnerable = 0
		p.Shield = 0
		p.ScopeTime = 0
		p.SpeedTime = 0
		p.Cooldown = 0
		p.CooldownTotal = 0
		p.VX = 0
		p.VY = 0
		p.Recoil = 0
		p.fireHeld = false
		p.fireBlocked = false
		p.SpawnSerial++
		if id == 2 {
			p.X = 840
			p.Y = 210
			if req.Shield {
				p.Shield = 10
			}
		}
		g.grantPower(p, "cannon")
	}
	// Distinct examples displayed at the bottom of the controlled arena.
	for i, kind := range pickupTypes {
		g.nextPickup++
		g.Pickups = append(g.Pickups, &Pickup{ID: g.nextPickup, Type: kind, X: 84 + float64(i)*100, Y: 755, Life: pickupLifetime(g.World.Cols, g.World.Rows)})
	}
	for _, p := range room.Players {
		if p != nil {
			p.Input = Input{}
			p.FirePending = false
		}
	}
	app.hub.broadcastRoom(room)
	for _, p := range room.members() {
		if p.Client != nil {
			app.hub.sendState(p.Client, room)
		}
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"generation": g.Generation})
	return true
}
