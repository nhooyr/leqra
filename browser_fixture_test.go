package main

import (
	"encoding/json"
	"math"
	"net"
	"net/http"
	"os"
	"testing"
	"time"
)

// Opt-in, loopback-only fixture for isolated Chromium environments that cannot
// navigate to local URLs. The browser harness injects the exact shipped assets
// into about:blank. Only this TEST handler supplies its missing HTTP Origin.
// The production server still rejects opaque/missing origins.
func TestBrowserFixture(t *testing.T) {
	if os.Getenv("LEQRA_BROWSER_FIXTURE") != "1" {
		t.Skip("opt-in browser fixture")
	}
	app := newApp(64, nil)
	done := make(chan struct{})
	go app.hub.run(done)
	defer close(done)
	defer app.hub.close()
	handler := app.handler()
	addr := os.Getenv("LEQRA_BROWSER_ADDR")
	if addr == "" {
		addr = "127.0.0.1:8790"
	}
	host, _, err := net.SplitHostPort(addr)
	if err != nil || net.ParseIP(host) == nil || !net.ParseIP(host).IsLoopback() {
		t.Fatal("browser fixture must bind a numeric loopback address")
	}
	srv := &http.Server{Addr: addr, Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if handleArsenal44Fixture(app, w, r) {
			return
		}
		if handleCombat42Fixture(app, w, r) {
			return
		}
		if handlePhase41Fixture(app, w, r) {
			return
		}
		if handleCannon39Fixture(app, w, r) {
			return
		}

		// v3.8 test-only grants preserve the actual maze and controller histories.
		if r.URL.Path == "/_fixture/scope38" && r.Method == http.MethodPost {
			var body struct {
				Code   string `json:"code"`
				Expire bool   `json:"expire"`
			}
			if json.NewDecoder(http.MaxBytesReader(w, r.Body, 2048)).Decode(&body) != nil {
				http.Error(w, "bad request", 400)
				return
			}
			app.hub.mu.Lock()
			defer app.hub.mu.Unlock()
			room := app.hub.rooms[body.Code]
			if room == nil {
				http.NotFound(w, r)
				return
			}
			for _, tank := range room.Game.Tanks {
				if tank != nil {
					room.Game.grantPower(tank, "scope")
					if body.Expire {
						tank.ScopeTime = .02
					}
				}
			}
			w.WriteHeader(http.StatusNoContent)
			return
		}

		if r.URL.Path == "/_fixture/features32" && r.Method == http.MethodPost {
			var b struct {
				Code   string `json:"code"`
				Action string `json:"action"`
				Player int    `json:"player"`
			}
			if json.NewDecoder(http.MaxBytesReader(w, r.Body, 2048)).Decode(&b) != nil || b.Player < 0 || b.Player >= maxTanks {
				http.Error(w, "bad request", 400)
				return
			}
			app.hub.mu.Lock()
			defer app.hub.mu.Unlock()
			room := app.hub.rooms[b.Code]
			if room == nil {
				http.NotFound(w, r)
				return
			}
			g := room.Game
			tank := g.Tanks[b.Player]
			if tank == nil {
				http.Error(w, "no tank", 400)
				return
			}
			for _, t := range g.Tanks {
				if t != nil {
					t.Bot = false
					t.Cooldown = 999
					t.Invulnerable = 0
					t.Shield = 0
					t.X = 42 + float64(t.ID)*84
					t.Y = 42
				}
			}
			for _, p := range room.Players {
				if p != nil {
					p.Input = Input{}
					p.FirePending = false
				}
			}
			switch b.Action {
			case "enemyKill37":
				g.Bullets = nil
				for id, owner := range g.Tanks {
					if owner != nil && g.isOpponent(id, tank) {
						g.hurt(tank, &Bullet{Owner: id})
						break
					}
				}
			case "flagReturn37":
				if g.Objectives == nil || g.Objectives.Mode != "ctf" {
					http.Error(w, "not ctf", 400)
					return
				}
				for _, f := range g.Objectives.Flags {
					if f.Team == tank.Team {
						f.Home = false
						f.Carrier = -1
						f.ReturnIn = 12
						f.X = tank.X
						f.Y = tank.Y
					}
				}
				g.stepObjectives(tickDT, room.Players)
			case "captureWin37":
				if g.Objectives == nil || g.Objectives.Mode != "ctf" {
					http.Error(w, "not ctf", 400)
					return
				}
				for _, f := range g.Objectives.Flags {
					if f.Team == tank.Team {
						resetFlag(f)
						tank.X = f.HomeX
						tank.Y = f.HomeY
					} else {
						f.Home = false
						f.Carrier = tank.ID
					}
				}
				g.stepObjectives(tickDT, room.Players)
			case "tie34":
				g.Scores = [maxTanks]int{2, 2, 2, 2}
				g.Clock = 0
				g.stepObjectives(0, room.Players)
			case "finish34":
				if g.objectiveMode() {
					g.endObjective(b.Player)
				} else {
					g.Scores[b.Player] = g.settings().ScoreTarget
					g.Phase = "playing"
					g.finishRound(b.Player)
					g.PhaseTime = 0
				}
			case "capture":
				if g.Objectives == nil || g.Objectives.Mode != "ctf" {
					http.Error(w, "not ctf", 400)
					return
				}
				for _, f := range g.Objectives.Flags {
					if f.Team == tank.Team {
						resetFlag(f)
						tank.X = f.HomeX
						tank.Y = f.HomeY
					} else {
						f.Home = false
						f.Carrier = tank.ID
						f.X = tank.X
						f.Y = tank.Y
					}
				}
			case "hill", "contested":
				if g.Objectives == nil || g.Objectives.Mode != "koth" {
					http.Error(w, "not hill", 400)
					return
				}
				tank.X = g.Objectives.HillX - 16
				tank.Y = g.Objectives.HillY
				if b.Action == "contested" {
					for _, t := range g.Tanks {
						if t != nil && t.ID != tank.ID && (t.Team == 0 || t.Team != tank.Team) {
							t.X = g.Objectives.HillX + 16
							t.Y = g.Objectives.HillY
							break
						}
					}
				}
			case "kill":
				tank.Alive = true
				g.hurt(tank, &Bullet{Owner: tank.ID})
			case "warning":
				g.Bullets = nil
				owner := -1
				for _, t := range g.Tanks {
					if t != nil && t.ID != tank.ID && g.canDamage(t.ID, tank) {
						owner = t.ID
						break
					}
				}
				if owner >= 0 {
					g.nextBullet++
					g.Bullets = append(g.Bullets, &Bullet{ID: g.nextBullet, Kind: "homing", Owner: owner, Target: tank.ID, X: tank.X + 45, Y: tank.Y, R: 5, VX: -missileSpeed, Life: 5, Age: .2, RangeLeft: 1000, rangeSet: true, Color: "#ff83bd"})
				}
				tank.Cooldown = .7
				tank.CooldownTotal = .85
				tank.Invulnerable = 1
			default:
				http.Error(w, "bad action", 400)
				return
			}
			g.Tick++
			for _, p := range room.Players {
				if p != nil && p.Client != nil {
					app.hub.sendState(p.Client, room)
				}
			}
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{"ok": true, "scores": g.Scores, "objectives": g.Objectives})
			return
		}
		// Test-only deterministic lane for measuring translation, not just turning.
		// This handler is absent from `go run .` and the production executable.
		if r.URL.Path == "/_fixture/powerups" && r.Method == http.MethodPost {
			var body struct {
				MissileScene string `json:"missileScene"`
				Charges      *int   `json:"charges"`
				Code         string `json:"code"`
				Power        string `json:"power"`
				Player       int    `json:"player"`
				Speed        bool   `json:"speed"`
				Shield       bool   `json:"shield"`
				Cover        bool   `json:"cover"`
			}
			if json.NewDecoder(http.MaxBytesReader(w, r.Body, 2048)).Decode(&body) != nil || body.Player < 0 || body.Player >= maxTanks {
				http.Error(w, "bad fixture request", 400)
				return
			}
			app.hub.mu.Lock()
			defer app.hub.mu.Unlock()
			room := app.hub.rooms[body.Code]
			if room == nil {
				http.NotFound(w, r)
				return
			}
			g := room.Game
			g.World = World{Cols: 12, Rows: 8, Width: 1008, Height: 672, Walls: []Wall{{-4, -4, 1016, 8, "h", 0}, {-4, 668, 1016, 8, "h", 672}, {-4, -4, 8, 680, "v", 0}, {1004, -4, 8, 680, "v", 1008}}}
			if body.Cover {
				g.World.Walls = append(g.World.Walls, Wall{330, 100, 8, 300, "v", 334})
			}
			g.Generation++
			g.Phase = "playing"
			g.PhaseTime = 0
			g.Clock = 75
			g.SpawnClock = 999
			g.Bullets = []*Bullet{}
			g.Pickups = []*Pickup{}
			positions := [][2]float64{{130, 252}, {410, 280}, {720, 490}, {870, 170}}
			for id, tank := range g.Tanks {
				if tank != nil {
					tank.X = positions[id][0]
					tank.Y = positions[id][1]
					tank.Angle = 0
					tank.Alive = true
					tank.VX = 0
					tank.VY = 0
					tank.Track = 0
					tank.Power = ""
					tank.PowerTime = 0
					tank.SpeedTime = 0
					tank.Shield = 0
					tank.Invulnerable = 0
					tank.Cooldown = 0
					tank.Charges = 0
					tank.Ack = 0
					tank.AckSteps = 0
					tank.fireHeld = false
					tank.fireBlocked = false
				}
			}
			for _, p := range room.Players {
				if p != nil {
					p.Input = Input{}
					p.FirePending = false
				}
			}
			for i, kind := range pickupTypes {
				g.nextPickup++
				g.Pickups = append(g.Pickups, &Pickup{ID: g.nextPickup, X: 126 + float64(i)*126, Y: 420, Type: kind, Life: pickupLifetime(g.World.Cols, g.World.Rows)})
			}
			if tank := g.Tanks[body.Player]; tank != nil {
				if body.Power == "laser" && g.Tanks[1] != nil {
					g.Tanks[1].Y = tank.Y
				}
				g.grantPower(tank, body.Power)
				if body.Charges != nil && *body.Charges >= 0 && *body.Charges <= 3 {
					tank.Charges = *body.Charges
				}
				if body.Speed {
					g.grantPower(tank, "speed")
				}
				if body.Shield {
					g.grantPower(tank, "shield")
				}
			}
			// v3.1 tank-impact trial; still a test-only handler, never shipped.
			if (body.MissileScene == "grenade-impact" || body.MissileScene == "grenade-shield") && g.Tanks[body.Player] != nil {
				shooter := g.Tanks[body.Player]
				shooter.X, shooter.Y = 110, 210
				for _, other := range g.Tanks {
					if other != nil && other.ID != shooter.ID && g.canDamage(shooter.ID, other) {
						other.X, other.Y = 350, 210
						if body.MissileScene == "grenade-shield" {
							other.Shield = 10
						}
						break
					}
				}
			}
			// v2.8 deterministic missile trials; this handler never ships in the binary.
			if body.MissileScene == "dodge" && g.Tanks[0] != nil && g.Tanks[1] != nil {
				g.Tanks[0].X = 222
				g.Tanks[0].Y = 300
				g.Tanks[1].X = 330
				g.Tanks[1].Y = 300
				g.Tanks[1].Angle = -math.Pi / 2
			}
			if body.MissileScene == "range" {
				for _, tank := range g.Tanks {
					if tank != nil {
						tank.Invulnerable = 20
					}
				}
			}
			app.hub.broadcastRoom(room)
			for _, p := range room.Players {
				if p != nil && p.Client != nil {
					app.hub.sendState(p.Client, room)
				}
			}
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{"ok": true, "generation": g.Generation})
			return
		}
		if r.URL.Path == "/_fixture/lane" && r.Method == http.MethodPost {
			var body struct {
				Code string `json:"code"`
			}
			if json.NewDecoder(http.MaxBytesReader(w, r.Body, 256)).Decode(&body) != nil {
				http.Error(w, "bad request", 400)
				return
			}
			app.hub.mu.Lock()
			defer app.hub.mu.Unlock()
			room := app.hub.rooms[body.Code]
			if room == nil {
				http.NotFound(w, r)
				return
			}
			g := room.Game
			g.World = World{Cols: 20, Rows: 8, Width: 1680, Height: 672, Walls: []Wall{
				{-4, -4, 1688, 8, "h", 0}, {-4, 668, 1688, 8, "h", 672},
				{-4, -4, 8, 680, "v", 0}, {1676, -4, 8, 680, "v", 1680},
			}}
			g.Generation++
			g.Phase = "playing"
			g.PhaseTime = 0
			g.Clock = 75
			g.SpawnClock = 999
			g.Bullets = []*Bullet{}
			g.Pickups = []*Pickup{}
			for id, tank := range g.Tanks {
				if tank != nil {
					tank.X = 100
					tank.Y = 84 + float64(id)*168
					tank.Angle = 0
					tank.Alive = true
					tank.VX = 0
					tank.VY = 0
					tank.Track = 0
				}
			}
			app.hub.broadcastRoom(room)
			for _, p := range room.Players {
				if p != nil && p.Client != nil {
					app.hub.sendState(p.Client, room)
				}
			}
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"ok":true}`))
			return
		}
		if r.URL.Path == "/ws" && r.Header.Get("Origin") == "null" {
			r = r.Clone(r.Context())
			r.Header = r.Header.Clone()
			r.Header.Set("Origin", "http://"+r.Host)
		}
		handler.ServeHTTP(w, r)
	}), ReadHeaderTimeout: 5 * time.Second}
	t.Cleanup(func() { _ = srv.Close() })
	if err := srv.ListenAndServe(); err != http.ErrServerClosed {
		t.Fatal(err)
	}
}
