package main

import (
	"encoding/json"
	"math"
	"testing"
	"time"
)

func TestTurretAimKeepsFixedDrivingDirectionAndFiringLine(t *testing.T) {
	g := battle(2)
	p := g.Tanks[0]
	p.X, p.Y, p.Angle = 200, 200, 0
	g.World.Walls = nil
	g.Tanks[1].X, g.Tanks[1].Y = 500, 350
	for i := 0; i < 30; i++ {
		g.control(p, Input{StickX: 1, AimY: -1, TouchAim: true}, tickDT)
	}
	if math.Abs(p.X-264) > 1e-7 || p.Y != 200 || math.Abs(p.Angle+math.Pi/2) > 1e-7 || p.BodyAngle != 0 || !p.IndependentAim {
		t.Fatalf("hull must drive east while turret faces north: %+v", p)
	}
	if !g.fire(p) || len(g.Bullets) != 1 || g.Bullets[0].VY >= 0 || math.Abs(g.Bullets[0].VX) > 1e-7 {
		t.Fatalf("shot must follow the turret: %+v", g.Bullets)
	}
	g.control(p, Input{AimY: -1}, tickDT)
	if math.Abs(p.X-264) > 1e-7 || p.Y != 200 {
		t.Fatal("releasing the joystick did not stop movement")
	}
}

func TestTurretAimKeepsInfiniteDrivingDirectionAndSnapshot(t *testing.T) {
	a := newSeededInfiniteArena(37)
	p := a.join(fakeClient(), "Pilot", time.Unix(0, 0))
	p.X, p.Y, p.Angle = 42, 42, 0
	a.drive(p, Input{StickX: 1, AimY: -1, TouchAim: true})
	if p.X <= 42 || p.Y != 42 || p.Angle != -math.Pi/2 || p.BodyAngle != 0 || !p.IndependentAim {
		t.Fatalf("independent Infinite aiming failed: %+v", p.infiniteTank)
	}
	data, err := json.Marshal(p.wireTank(a.tick))
	if err != nil {
		t.Fatal(err)
	}
	var wire map[string]any
	if err := json.Unmarshal(data, &wire); err != nil {
		t.Fatal(err)
	}
	if wire["independentAim"] != true || wire["angle"].(float64) >= 0 {
		t.Fatalf("missing independent heading in snapshot: %s", data)
	}
}

func TestTurretAimInputPassesThroughRoomProtocol(t *testing.T) {
	h, clients, room := makeRoom(t, 2)
	defer h.close()
	room.Game.startMatch(room.Players)
	room.Game.Phase = "playing"
	p := room.Game.Tanks[0]
	p.X, p.Y, p.Angle = 200, 200, 0
	action(t, h, clients[0], map[string]any{"type": "input", "seq": 1, "stickX": 1, "aimY": -1000})
	input := clients[0].player.Input
	if input.AimY != -1 || input.StickX != 1 {
		t.Fatalf("independent controls were not decoded and bounded: %+v", input)
	}
	room.Game.control(p, input, tickDT)
	if p.Y != 200 || p.X <= 200 || p.Angle != -math.Pi/2 || p.BodyAngle != 0 || !p.IndependentAim {
		t.Fatalf("room input coupled movement to the turret: %+v", p)
	}
}

func TestTurretAimFiresEveryWeaponAlongBarrel(t *testing.T) {
	for _, kind := range []string{"", "rapid", "scatter", "homing", "grenade", "cannon", "laser"} {
		for _, infinity := range []bool{false, true} {
			t.Run(kind+map[bool]string{false: "/fixed", true: "/infinity"}[infinity], func(t *testing.T) {
				check := func(x, y, vx, vy, tankX, tankY float64) {
					t.Helper()
					if vy >= 0 || math.Abs(vx) >= math.Abs(vy)*.25 || y >= tankY {
						t.Fatalf("shot missed the north-facing barrel: x=%v y=%v vx=%v vy=%v", x, y, vx, vy)
					}
					if kind != "scatter" && math.Abs(x-tankX) > 1e-8 {
						t.Fatalf("shot began beside the barrel: x=%v, tank x=%v", x, tankX)
					}
				}
				input := Input{StickX: 1, AimY: -1, Fire: true}
				if infinity {
					a := newSeededInfiniteArena(37)
					p := a.join(fakeClient(), "Pilot", time.Unix(0, 0))
					p.X, p.Y, p.Angle, p.Protected = 42, 42, 0, false
					p.kit.Cooldown, p.kit.Invulnerable, p.kit.SpawnProtected = 0, 0, false
					if kind != "" {
						applyPower(&p.kit, kind, 600, 600)
					}
					a.drive(p, input)
					a.fire(p)
					if p.BodyAngle != 0 || p.Angle != -math.Pi/2 || p.Y != 42 {
						t.Fatal("gun and hull headings became coupled")
					}
					if kind == "laser" {
						for _, effect := range a.effects {
							if effect.Kind == "laser" && len(effect.Points) > 1 {
								first, second := effect.Points[0], effect.Points[1]
								check(first.X, first.Y, second.X-first.X, second.Y-first.Y, p.X, p.Y)
								return
							}
						}
						t.Fatal("laser did not fire")
					}
					if len(a.bullets) == 0 {
						t.Fatal("weapon did not fire")
					}
					for _, b := range a.bullets {
						check(b.X, b.Y, b.VX, b.VY, p.X, p.Y)
					}
					return
				}
				g := battle(2)
				g.World.Walls = nil
				p := g.Tanks[0]
				p.X, p.Y, p.Angle = 200, 200, 0
				g.Tanks[1].X, g.Tanks[1].Y = 500, 350
				if kind != "" {
					g.grantPower(p, kind)
				}
				g.control(p, input, tickDT)
				if p.BodyAngle != 0 || p.Angle != -math.Pi/2 || p.Y != 200 {
					t.Fatal("gun and hull headings became coupled")
				}
				if kind == "laser" {
					for _, event := range g.events {
						if event.Type == "laser" && len(event.Points) > 1 {
							first, second := event.Points[0], event.Points[1]
							check(first.X, first.Y, second.X-first.X, second.Y-first.Y, p.X, p.Y)
							return
						}
					}
					t.Fatal("laser did not fire")
				}
				if len(g.Bullets) == 0 {
					t.Fatal("weapon did not fire")
				}
				for _, b := range g.Bullets {
					check(b.X, b.Y, b.VX, b.VY, p.X, p.Y)
				}
			})
		}
	}
}
