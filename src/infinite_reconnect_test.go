package main

import (
	"testing"
	"time"
)

func startInfinityReconnectRoom(t *testing.T, pilots int, local bool) (*infiniteServer, []*Client, *Room) {
	t.Helper()
	h, clients, room := makeRoom(t, pilots)
	room.Game.Rules.Infinity = true
	room.Game.Rules.TeamMode = "ffa"
	if local {
		action(t, h, clients[0], map[string]any{"type": "add", "kind": "local", "name": "WINGMATE"})
	}
	readyAll(t, h, clients[1:])
	action(t, h, clients[0], map[string]any{"type": "start"})
	if !room.infinityActive {
		t.Fatal("room did not start Infinity")
	}
	return newInfiniteServer(h), clients, room
}

func tryInfinityReconnect(t *testing.T, s *infiniteServer, msg infiniteMessage, now time.Time) (infiniteConnection, *Client, string) {
	t.Helper()
	c := fakeClient()
	if !s.admit(c) {
		t.Fatal("could not admit Infinity socket")
	}
	conn, reject := s.join(c, msg, now)
	if reject != "" {
		s.disconnect(c, now)
	}
	return conn, c, reject
}

func TestPrivateInfinityReconnectRetainsBothTanks(t *testing.T) {
	s, clients, room := startInfinityReconnectRoom(t, 1, true)
	now := time.Now()
	join := infiniteMessage{Code: room.Code, Token: clients[0].player.Token}
	pair, original, reject := tryInfinityReconnect(t, s, join, now)
	if reject != "" || pair.local == nil {
		t.Fatalf("could not join both pilots: %q", reject)
	}
	a, p1, p2 := pair.arena, pair.pilot, pair.local
	initial := drain(original)
	if len(initial) != 1 || initial[0]["generation"] != float64(room.infinityGeneration) || initial[0]["resumed"] != nil {
		t.Fatalf("unexpected initial welcome: %v", initial)
	}
	p1.Score, p2.Score = 7, -3
	p1.Ack, p1.AckSteps, p2.Ack, p2.AckSteps = 22, 11, 40, 17
	p1.kit.Power, p1.kit.PowerTime = "laser", 3
	a.setConnectionInput(original, p1, p1, Input{Seq: 23, Forward: true, Fire: true}, false, now)
	a.setConnectionInput(original, p1, p2, Input{Seq: 41, Fire: true}, false, now)
	p2.HP, p2.KilledBy, p2.respawn = 0, "OPPONENT", a.tick+1
	x, y, angle, p2Life := p1.X, p1.Y, p1.Angle, p2.Spawn
	s.disconnect(original, now)
	if a.connected != 0 || a.players != 2 || s.privateCount != 2 || len(s.reservations) != 1 {
		t.Fatal("disconnect discarded seats or left them marked connected")
	}
	s.step(now.Add(time.Millisecond))
	if p1.X != x || p1.Y != y || p1.Angle != angle || p1.kit.Power != "laser" || len(a.bullets) != 0 ||
		p2.HP != 0 || p2.KilledBy != "OPPONENT" || p2.Spawn != p2Life {
		t.Fatal("suspended tanks received stale input, lost their kit, or respawned unattended")
	}
	join.Resume, join.Generation = true, room.infinityGeneration
	// A reservation already occupies its two seats, even at capacity.
	s.privateCount = infinitePrivateCapacity
	resumed, replacement, reject := tryInfinityReconnect(t, s, join, now.Add(time.Second))
	if reject != "" || resumed.pilot != p1 || resumed.local != p2 || resumed.arena != a ||
		p1.Score != 7 || p2.Score != -3 || a.connected != 2 || s.privateCount != infinitePrivateCapacity ||
		p1.Ack != 0 || p1.AckSteps != 0 || p2.Ack != 0 || p2.AckSteps != 0 {
		t.Fatalf("reconnect did not preserve the arena and both pilots or reset input state: %q", reject)
	}
	if got := drain(replacement); len(got) != 1 || got[0]["resumed"] != true || got[0]["id"] != initial[0]["id"] ||
		got[0]["localId"] != initial[0]["localId"] || got[0]["generation"] != initial[0]["generation"] || got[0]["seed"] != initial[0]["seed"] {
		t.Fatalf("resumed welcome changed identity or maze: %v", got)
	}
	if len(s.reservations) != 0 || len(s.connections) != 1 {
		t.Fatal("resumed pair is still reserved or has multiple connections")
	}
	s.step(now.Add(time.Second))
	if p2.HP != infiniteMaxHP || p2.Spawn != p2Life+1 || p2.Score != -3 {
		t.Fatal("returning Player 2 did not resume play with the preserved score")
	}
}

func TestPrivateInfinityReconnectReplacesOnlyStaleSocket(t *testing.T) {
	s, clients, room := startInfinityReconnectRoom(t, 1, true)
	now := time.Now()
	join := infiniteMessage{Code: room.Code, Token: clients[0].player.Token}
	pair, original, reject := tryInfinityReconnect(t, s, join, now)
	if reject != "" || pair.local == nil {
		t.Fatalf("could not join both pilots: %q", reject)
	}
	join.Resume, join.Generation = true, room.infinityGeneration
	heartbeat := now.Add(infiniteResumeIdle)
	pair.arena.setConnectionInput(original, pair.pilot, pair.local, Input{Seq: 18}, false, heartbeat)
	if _, _, reject := tryInfinityReconnect(t, s, join, heartbeat); reject != infiniteSessionActive {
		t.Fatalf("an active Player 2 heartbeat did not protect its socket: %q", reject)
	}
	resumedAt := heartbeat.Add(infiniteResumeIdle)
	fresh := join
	fresh.Resume = false
	if _, _, reject := tryInfinityReconnect(t, s, fresh, resumedAt); reject != infiniteSessionActive {
		t.Fatalf("an ordinary duplicate join replaced a live socket: %q", reject)
	}
	resumed, replacement, reject := tryInfinityReconnect(t, s, join, resumedAt)
	if reject != "" || resumed.pilot != pair.pilot || resumed.local != pair.local {
		t.Fatalf("stale transport blocked a reconnect: %q", reject)
	}
	select {
	case <-original.done:
	default:
		t.Fatal("replaced socket was left open")
	}
	resumed.arena.setConnectionInput(original, resumed.pilot, resumed.local, Input{Seq: 19, Fire: true}, false, resumedAt)
	s.disconnect(original, resumedAt)
	if resumed.local.input.Seq != 0 || resumed.local.firePending || resumed.pilot.client != replacement ||
		len(s.reservations) != 0 || s.privateCount != 2 || resumed.arena.connected != 2 {
		t.Fatal("replaced transport could still control or detach the pair")
	}
}

func TestPrivateInfinityRevokingOnlyLocalPlayerPreservesPrimary(t *testing.T) {
	for _, timing := range []string{"live kick", "live role change", "reserved role change", "reconnect before sweep"} {
		t.Run(timing, func(t *testing.T) {
			s, clients, room := startInfinityReconnectRoom(t, 1, true)
			host, now := clients[0], time.Now()
			join := infiniteMessage{Code: room.Code, Token: host.player.Token}
			pair, original, reject := tryInfinityReconnect(t, s, join, now)
			if reject != "" || pair.local == nil {
				t.Fatalf("could not join both pilots: %q", reject)
			}
			a, primary, local := pair.arena, pair.pilot, pair.local
			primary.Score = 7
			primary.kit.Power, primary.kit.PowerTime = "laser", 3
			a.bullets = append(a.bullets, infiniteBullet{Owner: local.ID, Life: 10})
			live := timing == "live kick" || timing == "live role change"
			if !live {
				s.disconnect(original, now)
			}
			if timing == "live kick" {
				action(t, s.hub, host, kickRequest(pair.localSeat))
			} else {
				action(t, s.hub, host, map[string]any{"type": "spectate", "target": pair.localSeat.ID, "member": pair.localSeat.Member, "spectating": true})
			}
			now = now.Add(time.Millisecond)
			if timing != "reconnect before sweep" {
				s.step(now)
			}
			if live {
				select {
				case <-original.done:
				default:
					t.Fatal("revoked local controller's original socket is still open")
				}
				s.disconnect(original, now)
			}
			join.Resume, join.Generation = true, room.infinityGeneration
			resumed, replacement, reject := tryInfinityReconnect(t, s, join, now)
			if reject != "" || resumed.arena != a || resumed.pilot != primary || resumed.local != nil || primary.local != nil || primary.Score != 7 || primary.kit.Power != "laser" {
				t.Fatalf("reconnect did not preserve only Player 1 and their score: %q", reject)
			}
			if a.players != 1 || a.connected != 1 || s.privateCount != 1 || len(a.pilots) != 1 || len(a.bullets) != 0 || len(s.reservations) != 0 {
				t.Fatal("revoked local seat or its bullets still occupy the arena")
			}
			if got := drain(replacement); len(got) != 1 || got[0]["resumed"] != true || got[0]["id"] != float64(primary.ID) || got[0]["localId"] != nil {
				t.Fatalf("replacement socket did not receive a solo resumed welcome: %v", got)
			}
			a.setConnectionInput(original, primary, primary, Input{Fire: true}, false, now)
			a.setConnectionInput(replacement, primary, local, Input{Fire: true}, false, now)
			if primary.firePending || local.firePending {
				t.Fatal("revoked transport or seat can still control a tank")
			}
			a.setConnectionInput(replacement, primary, primary, Input{Fire: true}, false, now)
			if !primary.firePending {
				t.Fatal("replacement socket cannot control the surviving primary pilot")
			}
		})
	}
}

func TestPrivateInfinityReconnectRejectsExpiredOrRetiredTank(t *testing.T) {
	for _, how := range []string{"expiry", "leave", "new generation", "kick"} {
		t.Run(how, func(t *testing.T) {
			s, clients, room := startInfinityReconnectRoom(t, 2, false)
			h, host, guest := s.hub, clients[0], clients[1]
			now := time.Now()
			join := infiniteMessage{Code: room.Code, Token: guest.player.Token}
			conn, original, reject := tryInfinityReconnect(t, s, join, now)
			if reject != "" {
				t.Fatal(reject)
			}
			generation := room.infinityGeneration
			switch how {
			case "leave":
				s.remove(original)
			case "expiry":
				s.disconnect(original, now)
				now = now.Add(reconnectGrace + time.Millisecond)
			case "new generation":
				s.disconnect(original, now)
				action(t, h, host, map[string]any{"type": "lobby"})
				readyAll(t, h, clients[1:])
				action(t, h, host, map[string]any{"type": "start"})
			case "kick":
				s.disconnect(original, now)
				action(t, h, host, kickRequest(guest.player))
			}
			s.step(now)
			if len(s.private) != 0 || len(s.reservations) != 0 || s.privateCount != 0 || conn.arena.maze != nil {
				t.Fatal("retired reservation still holds capacity or its arena")
			}
			join.Resume, join.Generation = true, generation
			if _, _, reject := tryInfinityReconnect(t, s, join, now); reject != infiniteResumeExpired {
				t.Fatalf("automatic retry after %s unexpectedly joined a fresh tank: %q", how, reject)
			}
			if len(s.connections) != 0 || s.privateCount != 0 {
				t.Fatal("rejected retry consumed a connection or a seat")
			}
		})
	}
}
