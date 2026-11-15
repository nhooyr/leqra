package main

import (
	"encoding/json"
	"fmt"
	"math"
	"net/http/httptest"
	"testing"
	"time"
)

func TestInfinityInputSequenceCannotReplayFireOrPauseAnotherAcceptedStep(t *testing.T) {
	for _, local := range []bool{false, true} {
		t.Run(fmt.Sprintf("local%v", local), func(t *testing.T) {
			a := newSeededInfiniteArena(807)
			now := time.Unix(1_800_000_000, 0)
			client := fakeClient()
			primary, secondary := a.joinSeats(client, infiniteSeat{name: "Primary"}, &infiniteSeat{name: "Secondary"}, 0, now)
			a.nextBot, a.nextPickup = math.MaxUint64, math.MaxUint64
			p := primary
			if local {
				p = secondary
			}
			primary.X, primary.Y = 42, 42
			secondary.X, secondary.Y = 1042, 42
			p.Angle, p.Protected, p.kit.Invulnerable, p.kit.SpawnProtected = 0, false, 0, false
			applyPower(&p.kit, "grenade", 15, 8)
			a.setConnectionInput(client, primary, p, Input{Seq: 10, Fire: true, Forward: true}, false, now)
			a.step(now)
			if len(a.bullets) != 1 || p.kit.ShotSerial != 1 || p.firePending {
				t.Fatal("initial accepted edge did not throw one grenade")
			}
			acceptedAt, activeAt := p.inputAt, p.activeAt
			for _, replay := range []struct {
				input  Input
				paused bool
			}{
				{Input{Seq: 9}, false},
				{Input{Seq: 8, Fire: true, Reverse: true}, false},
				{Input{Seq: 10, Fire: true}, true},
			} {
				a.setConnectionInput(client, primary, p, replay.input, replay.paused, now.Add(time.Second))
			}
			if p.input.Seq != 10 || !p.input.Fire || !p.input.Forward || p.input.Reverse || p.paused || p.firePending || p.inputAt != acceptedAt || p.activeAt != activeAt {
				t.Fatal("stale/duplicate packet changed controls, fabricated a press, paused the pilot, or refreshed its activity")
			}
			a.step(now.Add(time.Second / 60))
			if p.Ack != 10 || p.AckSteps != 2 || len(a.bullets) != 1 || a.bullets[0].dead || p.kit.ShotSerial != 1 {
				t.Fatal("a replay rewound acknowledgement or popped the current grenade")
			}
			// The other local channel has its own chronology, even while this
			// controller's primary/secondary has already reached sequence ten.
			other := secondary
			if local {
				other = primary
			}
			a.setConnectionInput(client, primary, other, Input{Seq: 1, Reverse: true}, false, now)
			if other.input.Seq != 1 || !other.input.Reverse {
				t.Fatal("one local seat poisoned the other's sequence")
			}
			a.setConnectionInput(client, primary, p, Input{Seq: 11}, false, now)
			a.setConnectionInput(client, primary, p, Input{Seq: 12, Fire: true}, false, now)
			a.step(now.Add(2 * time.Second / 60))
			if p.Ack != 12 || p.kit.ShotSerial != 1 || len(a.bullets) != 0 {
				t.Fatal("a fresh accepted release/press failed to pop the grenade")
			}
			a.suspend(primary)
			replacement := fakeClient()
			if rejection := a.resume(replacement, primary, 0, now.Add(2*time.Second)); rejection != "" {
				t.Fatal(rejection)
			}
			a.setConnectionInput(replacement, primary, p, Input{Seq: 1, Forward: true}, false, now.Add(2*time.Second))
			if p.input.Seq != 1 || !p.input.Forward {
				t.Fatal("authenticated reconnect did not reset the input chronology")
			}
		})
	}
}

func TestInfinityInputSequencePauseTimeoutAndRespawn(t *testing.T) {
	a := newSeededInfiniteArena(807)
	now := time.Unix(1_800_000_000, 0)
	c := fakeClient()
	p := a.join(c, "Pilot", now)
	a.nextBot, a.nextPickup = math.MaxUint64, math.MaxUint64
	if !a.setConnectionInput(c, p, p, Input{Seq: 1, Forward: true}, false, now) {
		t.Fatal("the first current-client sequence was rejected")
	}
	if !a.setConnectionInput(c, p, p, Input{Seq: 2, Fire: true, Forward: true}, true, now) || !p.paused || p.input.Fire || p.input.Forward || p.firePending {
		t.Fatal("a fresh pause did not neutralize and consume its sequence")
	}
	if !a.setConnectionInput(c, p, p, Input{Seq: 3, Forward: true}, false, now) || p.paused {
		t.Fatal("a fresh unpause did not resume the pilot")
	}
	if a.setConnectionInput(c, p, p, Input{Seq: 2, Fire: true}, true, now.Add(inputTimeout)) || p.inputAt != now || p.paused {
		t.Fatal("a stale pause refreshed the controller timeout")
	}
	x, y := p.X, p.Y
	a.step(now.Add(inputTimeout + time.Millisecond))
	if p.X != x || p.Y != y || p.Ack != 3 {
		t.Fatal("stale replay kept expired movement alive or rewound its acknowledgement")
	}
	p.kit.Invulnerable, p.Protected = 0, false
	a.eliminatePilot(p, p.ID+1, 0, "Opponent")
	serial := p.Spawn
	a.tick = p.respawn - 1
	a.step(now.Add(time.Second))
	if p.HP == 0 || p.Spawn != serial+1 || p.input.Seq != 3 {
		t.Fatal("ordinary respawn changed the current transport chronology")
	}
	if a.setConnectionInput(c, p, p, Input{Seq: 1, Fire: true}, false, now.Add(time.Second)) || !a.setConnectionInput(c, p, p, Input{Seq: 4, Forward: true}, false, now.Add(time.Second)) {
		t.Fatal("respawn accepted an old packet or rejected the next current one")
	}
}

func TestInfinitySocketOrdersBothSeatsAndOnlyAcceptedInputTouchesRoom(t *testing.T) {
	for _, private := range []bool{false, true} {
		t.Run(fmt.Sprintf("private%v", private), func(t *testing.T) {
			app := newApp(8, nil)
			join := map[string]any{"type": "join", "version": version, "name": "Primary", "localName": "Secondary"}
			var room *Room
			if private {
				s, members, r := startInfinityReconnectRoom(t, 1, true)
				app.hub, app.infinite, room = s.hub, s, r
				join = map[string]any{"type": "join", "version": version, "code": r.Code, "token": members[0].player.Token}
			}
			t.Cleanup(app.infinite.close)
			server := httptest.NewServer(app.handler())
			t.Cleanup(server.Close)
			socket, reader := dialInfinite(t, server.URL, join, false)
			var welcome struct {
				Type        string
				ID, LocalID int
			}
			readInfinitePacket(t, reader, &welcome)
			if welcome.Type != "welcome" || welcome.LocalID == 0 {
				t.Fatal("paired socket join failed")
			}
			app.infinite.mu.Lock()
			var pair infiniteConnection
			for _, candidate := range app.infinite.connections {
				if candidate.pilot != nil && candidate.pilot.ID == welcome.ID {
					pair = candidate
					break
				}
			}
			app.infinite.mu.Unlock()
			if pair.pilot == nil || pair.local == nil {
				t.Fatal("paired socket was not indexed")
			}
			initialAt := pair.pilot.inputAt
			oldAction := time.Now().Add(-time.Hour)
			if room != nil {
				app.hub.mu.Lock()
				room.LastAction = oldAction
				app.hub.mu.Unlock()
			}
			send := func(packet any) {
				t.Helper()
				data, err := json.Marshal(packet)
				if err != nil {
					t.Fatal(err)
				}
				if _, err = socket.Write(maskedFrame(1, true, data)); err != nil {
					t.Fatal(err)
				}
			}
			barrier := func(stamp int) {
				t.Helper()
				send(map[string]any{"type": "ping", "t": stamp})
				var packet map[string]any
				readInfinitePacket(t, reader, &packet)
				if packet["type"] != "pong" {
					t.Fatal("input barrier failed", packet["type"])
				}
			}
			for _, local := range []bool{false, true} {
				send(map[string]any{"type": "input", "seq": 0, "local": local, "forward": true, "fire": true})
			}
			barrier(1)
			pair.arena.mu.Lock()
			if pair.pilot.input.Seq != 0 || pair.pilot.input.Forward || pair.pilot.firePending || pair.pilot.inputAt != initialAt || pair.local.input.Forward {
				t.Error("initial stale zero sequence changed a live controller")
			}
			pair.arena.mu.Unlock()
			if room != nil {
				app.hub.mu.Lock()
				if room.LastAction != oldAction {
					t.Error("ignored socket input refreshed private room activity")
				}
				app.hub.mu.Unlock()
			}
			for _, local := range []bool{false, true} {
				send(map[string]any{"type": "input", "seq": 1, "local": local, "forward": true})
				send(map[string]any{"type": "input", "seq": 1, "local": local, "paused": true})
				send(map[string]any{"type": "input", "seq": 0, "local": local, "reverse": true, "fire": true})
			}
			barrier(2)
			pair.arena.mu.Lock()
			for _, seat := range []*infinitePilot{pair.pilot, pair.local} {
				if seat.input.Seq != 1 || !seat.input.Forward || seat.input.Reverse || seat.paused || seat.firePending {
					t.Error("wire replay changed one local seat's accepted controls")
				}
			}
			pair.arena.mu.Unlock()
			if room != nil {
				app.hub.mu.Lock()
				if !room.LastAction.After(oldAction) {
					t.Error("accepted socket input did not refresh private room activity")
				}
				app.hub.mu.Unlock()
			}
		})
	}
}

func TestPublicInfinityPairSelectionResetsControlChronologyWithoutLosingIdentity(t *testing.T) {
	for _, independent := range []bool{false, true} {
		t.Run(fmt.Sprintf("independent%v", independent), func(t *testing.T) {
			s := newInfiniteServer(newHub(4))
			t.Cleanup(s.close)
			pair, old, primaryKey := savedPublicJoin(t, s, infiniteMessage{Name: "Primary", LocalName: "Secondary"})
			localKey := ""
			if independent {
				pair, old, primaryKey, localKey = independentPair(t, s, "Primary", "Secondary", primaryKey)
			}
			now := time.Now()
			a := pair.arena
			id, localID := pair.pilot.ID, pair.local.ID
			if !a.setConnectionInput(old, pair.pilot, pair.pilot, Input{Seq: 53, Forward: true}, false, now) || !a.setConnectionInput(old, pair.pilot, pair.local, Input{Seq: 81, Fire: true}, false, now) {
				t.Fatal("paired controller setup failed")
			}
			solo, current, _ := savedPublicJoin(t, s, infiniteMessage{PublicToken: primaryKey, Name: "Primary", UpdateNames: true, IndependentAccounts: independent})
			if solo.local != nil || solo.pilot.ID != id || !a.setConnectionInput(current, solo.pilot, solo.pilot, Input{Seq: 1, Forward: true}, false, now) {
				t.Fatal("disabling P2 failed to restart the surviving controller's input chronology")
			}
			if a.setConnectionInput(old, pair.pilot, pair.local, Input{Seq: 82, Fire: true}, false, now) {
				t.Fatal("a parked secondary still accepted its old controller")
			}
			restored, replacement, _ := savedPublicJoin(t, s, infiniteMessage{PublicToken: primaryKey, LocalPublicToken: localKey, Name: "Primary", LocalName: "Secondary", UpdateNames: true, IndependentAccounts: independent})
			if restored.pilot.ID != id || restored.local == nil || restored.local.ID != localID {
				t.Fatal("reenabling P2 changed its saved score identity")
			}
			for _, p := range []*infinitePilot{restored.pilot, restored.local} {
				if !a.setConnectionInput(replacement, restored.pilot, p, Input{Seq: 1, Forward: true}, false, now) || a.setConnectionInput(replacement, restored.pilot, p, Input{Seq: 1, Fire: true}, false, now) {
					t.Fatal("a new seat binding rejected its first input or accepted a duplicate")
				}
			}
		})
	}
}
