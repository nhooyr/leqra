package main

import (
	"encoding/json"
	"testing"
	"time"
)

func TestGrenadeDetonationHoldSurvivesInputTimeout(t *testing.T) {
	for _, infinity := range []bool{false, true} {
		t.Run(map[bool]string{false: "fixed", true: "infinity"}[infinity], func(t *testing.T) {
			now := time.Now()
			var tank *Tank
			var send func(uint64, bool)
			var step func()
			if infinity {
				a := newSeededInfiniteArena(513)
				client := fakeClient()
				p := a.join(client, "Pilot", now)
				a.nextBot, a.nextPickup = 1<<60, 1<<60
				p.X, p.Y, p.Angle, p.Protected = 42, 42, 0, false
				p.kit = Tank{}
				tank = &p.kit
				applyPower(tank, "grenade", 15, 8)
				send = func(seq uint64, held bool) {
					a.setConnectionInput(client, p, p, Input{Seq: seq, Fire: held}, false, now)
				}
				step = func() { a.step(now) }
			} else {
				h, room, clients := preparedRoom(t, 2)
				tank = room.Game.Tanks[0]
				tank.Y, room.Game.Tanks[1].Y = 70, 350
				room.Game.grantPower(tank, "grenade")
				send = func(seq uint64, held bool) {
					packet, _ := json.Marshal(map[string]any{"type": "input", "seq": seq, "fire": held})
					if err := h.handle(clients[0], packet, now); err != nil {
						t.Fatal(err)
					}
				}
				step = func() { h.tick(now) }
			}
			send(1, true)
			step()
			send(2, false)
			send(3, true)
			step()
			if tank.ShotSerial != 1 || !tank.fireRelease {
				t.Fatal("fixture did not detonate the first grenade")
			}
			now = now.Add(2*inputTimeout + time.Second)
			step()
			if !tank.fireRelease {
				t.Fatal("synthetic stale-input neutralization released the physical detonation hold")
			}
			send(4, true)
			tank.Cooldown = 0
			step()
			if tank.ShotSerial != 1 {
				t.Fatal("held heartbeat after timeout threw another grenade")
			}
			send(5, false)
			step()
			send(6, true)
			step()
			if tank.ShotSerial != 2 {
				t.Fatal("explicit release and fresh press did not enable the next throw")
			}
		})
	}
}
