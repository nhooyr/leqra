package main

import (
	"encoding/json"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// Opt-in device fixture. Clients still join, send input, and receive snapshots
// through the real server; this endpoint only arranges a reproducible encounter.
func TestNativeMuzzleDeviceServer(t *testing.T) {
	addr := os.Getenv("LEQRA_MUZZLE_DEVICE_ADDR")
	if addr == "" {
		t.Skip("opt-in native device server")
	}
	app := newApp(32, nil)
	if err := app.infinite.openPublicStore(filepath.Join(t.TempDir(), "devices.sqlite")); err != nil {
		t.Fatal(err)
	}
	done := make(chan struct{})
	go app.hub.run(done)
	go app.infinite.run(done)
	defer close(done)
	defer app.hub.close()
	defer app.infinite.close()
	base := app.handler()
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/_fixture/muzzle" {
			base.ServeHTTP(w, r)
			return
		}
		var request struct {
			Name, Code, Weapon string
			Infinity, Ghost    bool
			Gap                float64
			Serial             int
			Read               bool
		}
		if r.Method != "POST" || json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&request) != nil {
			http.Error(w, "invalid fixture request", http.StatusBadRequest)
			return
		}
		response := map[string]any{}
		if request.Infinity {
			app.infinite.mu.Lock()
			arenas := []*infiniteArena{app.infinite.public}
			for _, arena := range app.infinite.private {
				arenas = append(arenas, arena)
			}
			app.infinite.mu.Unlock()
			for _, arena := range arenas {
				arena.mu.Lock()
				for _, pilot := range arena.pilots {
					if pilot.Name != request.Name || pilot.Bot {
						continue
					}
					if !request.Read {
						walls := arena.maze.wallsNear(pilot.X-252, pilot.Y-252, pilot.X+252, pilot.Y+252)
						for _, wall := range walls {
							if wall.W > 8.01 || wall.H < 50 {
								continue
							}
							pilot.X, pilot.Y, pilot.Angle = wall.X-request.Gap, wall.Y+wall.H/2, 0
							arena.bullets, arena.pickups = nil, nil
							arena.result = nil
							arena.nextPickup, arena.nextBot = arena.tick+36000, arena.tick+36000
							for _, other := range arena.pilots {
								if other != pilot {
									other.X, other.Y = pilot.X+1000, pilot.Y+1000
									other.HP = 1
									other.kit.Cooldown, other.kit.Invulnerable = 600, 600
									other.kit.StarmanTime = 0
									other.Protected = true
								}
							}
							pilot.kit = Tank{ID: pilot.ID, Alive: true, R: tankRadius, Color: tankColors[pilot.ColorIndex]}
							if request.Ghost {
								applyPower(&pilot.kit, "ghost", 600, 600)
							}
							if request.Weapon != "" {
								applyPower(&pilot.kit, request.Weapon, 600, 600)
							}
							pilot.HP, pilot.Protected, pilot.paused = 1, false, false
							pilot.Spawn = request.Serial
							pilot.input, pilot.fireDown, pilot.firePending = Input{}, false, false
							response["wallX"] = wall.X
							break
						}
					}
					response["x"], response["y"], response["angle"] = pilot.X, pilot.Y, pilot.Angle
					response["shots"], response["ghost"], response["input"] = pilot.kit.ShotSerial, pilot.kit.GhostTime, pilot.input
					response["hp"], response["id"], response["serial"] = pilot.HP, pilot.ID, pilot.Spawn
					response["disconnected"], response["paused"] = pilot.disconnected, pilot.paused
					var bullets []infiniteBullet
					for _, bullet := range arena.bullets {
						if bullet.Owner == pilot.ID {
							bullets = append(bullets, bullet)
						}
					}
					response["bullets"] = bullets
				}
				arena.mu.Unlock()
			}
		} else {
			app.hub.mu.Lock()
			if room := app.hub.rooms[request.Code]; room != nil {
				game := room.Game
				for _, pilot := range game.Tanks {
					if pilot == nil || pilot.Name != request.Name {
						continue
					}
					if !request.Read {
						game.World = World{Width: 840, Height: 840, Cols: 10, Rows: 10, Walls: []Wall{{X: 248, Y: 84, W: 8, H: 672}}}
						game.spatial = nil
						game.Generation++
						game.Phase, game.Clock, game.PhaseTime = "playing", 600, 0
						game.Bullets, game.Pickups, game.events = nil, nil, nil
						for _, other := range game.Tanks {
							if other != nil {
								other.X, other.Y, other.Alive, other.Invulnerable, other.Cooldown = 650, 150+float64(other.ID)*100, true, 600, 600
							}
						}
						for _, member := range room.Players {
							if member != nil {
								member.Input, member.FirePending = Input{}, false
								if member.Client != nil {
									member.Client.mapGeneration = 0
								}
							}
						}
						id, name, color := pilot.ID, pilot.Name, pilot.Color
						*pilot = Tank{ID: id, Name: name, Color: color, X: 248 - request.Gap, Y: 420, R: tankRadius, Alive: true, SpawnSerial: request.Serial}
						if request.Ghost {
							game.grantPower(pilot, "ghost")
							pilot.GhostTime = 600
						}
						if request.Weapon != "" {
							game.grantPower(pilot, request.Weapon)
							pilot.PowerTime = 600
						}
						response["wallX"] = 248
					}
					response["x"], response["y"], response["angle"] = pilot.X, pilot.Y, pilot.Angle
					response["shots"], response["ghost"] = pilot.ShotSerial, pilot.GhostTime
					if member := room.Players[pilot.ID]; member != nil {
						response["input"] = member.Input
					}
					var bullets []Bullet
					for _, bullet := range game.Bullets {
						if bullet.Owner == pilot.ID {
							bullets = append(bullets, *bullet)
						}
					}
					response["bullets"] = bullets
				}
			}
			app.hub.mu.Unlock()
		}
		if len(response) == 0 {
			http.Error(w, "pilot not connected", http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(response)
	})
	listener, err := net.Listen("tcp", addr)
	if err != nil {
		t.Fatal(err)
	}
	server := &http.Server{Handler: handler, ReadHeaderTimeout: 5 * time.Second}
	t.Cleanup(func() { _ = server.Close() })
	t.Log("native muzzle device server listening on " + listener.Addr().String())
	if err := server.Serve(listener); err != http.ErrServerClosed {
		t.Fatal(err)
	}
}
