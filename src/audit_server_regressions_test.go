package main

import (
	"testing"
	"time"
)

func TestOnlyLeavingARoomExtendsUnattachedSocketGrace(t *testing.T) {
	for _, attached := range []bool{false, true} {
		name := "never joined"
		if attached {
			name = "left room"
		}
		t.Run(name, func(t *testing.T) {
			h, c := newHub(1), fakeClient()
			born := time.Now()
			c.born = born
			h.addClient(c)
			if attached {
				action(t, h, c, map[string]any{"type": "create", "name": "HOST"})
			}
			leave := []byte(`{"type":"leave"}`)
			leaveAt := born.Add(14 * time.Second)
			if err := h.handle(c, leave, leaveAt); err != nil {
				t.Fatal(err)
			}
			start := born
			if attached {
				start = leaveAt
			}
			if err := h.handle(c, leave, start.Add(14*time.Second)); err != nil {
				t.Fatal(err)
			}
			h.tick(start.Add(14 * time.Second))
			select {
			case <-c.done:
				t.Fatal("socket closed before it could receive its acknowledgement")
			default:
			}
			h.tick(start.Add(16 * time.Second))
			select {
			case <-c.done:
			default:
				t.Fatal("an already-unattached leave extended idle cleanup")
			}
		})
	}
}

func TestResumeAsSpectatorClearsReadinessOnlyOnRoleChange(t *testing.T) {
	h, clients, room := makeRoom(t, 3)
	stable, outgoing := clients[1].player, clients[2]
	ready := map[string]any{"type": "ready", "ready": true}
	action(t, h, clients[1], ready)
	join := map[string]any{"type": "join", "code": room.Code, "name": "NEW PILOT"}
	action(t, h, fakeClient(), join)
	if !stable.Ready {
		t.Fatal("fresh combat join cleared another pilot's readiness")
	}
	token, id := outgoing.player.Token, outgoing.player.ID
	h.removeClient(outgoing)
	join["token"] = token
	resumed := fakeClient()
	action(t, h, resumed, join)
	if resumed.player == nil || !stable.Ready {
		t.Fatal("same-role reconnect cleared another pilot's readiness")
	}
	h.removeClient(resumed)
	stable.Input = Input{Forward: true}
	join["spectating"] = true
	join["name"] = "WATCH PILOT"
	watcher := fakeClient()
	action(t, h, watcher, join)
	if watcher.player == nil || !watcher.player.Spectating || room.Players[id] != nil {
		t.Fatal("existing combat pilot did not resume as a spectator")
	}
	if stable.Ready || !stable.Input.Forward {
		t.Fatal("role change must clear readiness and preserve other pilots' controls")
	}
}

func TestDefenseExpiryPrecedesAttacksInEverySeatOrder(t *testing.T) {
	for _, defense := range []string{"shield", "invulnerability", "starman"} {
		t.Run(defense, func(t *testing.T) {
			for _, tick := range []int{0, 1} {
				for _, remaining := range []float64{.001, .1} {
					g := battle(2)
					g.Tick = tick
					shooter, target := g.Tanks[0], g.Tanks[1]
					g.grantPower(shooter, "laser")
					switch defense {
					case "shield":
						target.Shield, target.ShieldCharges = remaining, 1
					case "invulnerability":
						target.Invulnerable = remaining
					case "starman":
						target.StarmanTime, target.Invulnerable, target.GhostTime = remaining, remaining, remaining
					}
					g.step(tickDT, [maxTanks]Input{0: {Fire: true}}, testPlayers(2))
					if target.Alive != (remaining > tickDT) || shooter.ShotSerial != 1 {
						t.Fatalf("tick %d, remaining %v: alive = %t, shots = %d", tick, remaining, target.Alive, shooter.ShotSerial)
					}
					if defense == "shield" && target.Alive && target.Invulnerable != .35 {
						t.Fatalf("new shield-hit protection shortened by action order: %v", target.Invulnerable)
					}
				}
			}
		})
	}
}
