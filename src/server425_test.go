package main

import (
	"bytes"
	"testing"
)

func TestQueuedRematchWaitsForDisconnectedController(t *testing.T) {
	for _, detached := range []bool{false, true} {
		name := "closed_socket"
		if detached {
			name = "removed_socket"
		}
		t.Run(name, func(t *testing.T) {
			h := newHub(12)
			a, _ := mmRoom(t, h, 1)
			b, _ := mmRoom(t, h, 1)
			mmQueue(t, h, a, "elimination-1")
			mmQueue(t, h, b, "elimination-1")
			mmScan(h)
			battle := a[0].room
			battle.Game.Phase = "matchOver"
			generation := battle.Game.Generation
			member, token := a[0].player.Member, a[0].player.Token
			mmAction(t, h, a[0], map[string]any{"type": "rematch"})
			a[0].stop()
			if detached {
				h.removeClient(a[0])
				if battle.Match.Rematch[member] {
					t.Fatal("disconnect retained a stale rematch vote")
				}
			}
			mmAction(t, h, b[0], map[string]any{"type": "rematch"})
			if battle.Game.Phase != "matchOver" || battle.Game.Generation != generation {
				t.Fatal("rematch started with a disconnected controller")
			}
			if !detached {
				h.removeClient(a[0])
			}
			reconnect := fakeClient()
			h.addClient(reconnect)
			mmAction(t, h, reconnect, map[string]any{"type": "join", "code": battle.Code, "token": token, "name": "RETURNED"})
			if reconnect.room != battle || reconnect.player.Member != member {
				t.Fatal("reconnect lost the reserved match identity")
			}
			if battle.Game.Phase != "matchOver" {
				t.Fatal("reconnect should wait for fresh rematch consent")
			}
			mmAction(t, h, reconnect, map[string]any{"type": "rematch"})
			if battle.Game.Phase != "countdown" || battle.Game.Generation <= generation {
				t.Fatal("connected controllers could not rematch after fresh consent")
			}
		})
	}
}

func TestRoomRenameRoundTripReconnect(t *testing.T) {
	for _, useOldAlias := range []bool{false, true} {
		name := "current_code"
		if useOldAlias {
			name = "intermediate_code"
		}
		t.Run(name, func(t *testing.T) {
			h, cs, r := makeRoom(t, 2)
			original, alias := r.Code, "Temporary room name"
			guest := cs[1].player
			h.removeClient(cs[1])
			mmAction(t, h, cs[0], map[string]any{"type": "rename_room", "code": alias})
			mmAction(t, h, cs[0], map[string]any{"type": "rename_room", "code": original})
			code := original
			if useOldAlias {
				code = alias
			}
			reconnect := fakeClient()
			h.addClient(reconnect)
			mmAction(t, h, reconnect, map[string]any{"type": "join", "code": code, "token": guest.Token, "name": guest.Name})
			if reconnect.room != r || reconnect.player != guest || reconnect.room.Code != original {
				t.Fatal("round-trip rename did not preserve the reconnect identity")
			}
			welcome := false
			for _, packet := range drain(reconnect) {
				if packet["type"] == "welcome" {
					welcome = packet["room"] == original && packet["resumed"] == true
				}
			}
			if !welcome {
				t.Fatal("reconnect welcome did not use the current room code")
			}
		})
	}
}

func TestBroadcastRoomWireParityAndImmutableSnapshots(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	viewer := fakeClient()
	h.addClient(viewer)
	mmAction(t, h, viewer, map[string]any{"type": "join", "code": r.Code, "name": "VIEWER", "spectating": true})
	cs = append(cs, viewer)
	for _, c := range cs {
		drain(c)
	}
	want, ok := encodePacket(h.roomMessage(r))
	if !ok {
		t.Fatal("cannot encode fixture room")
	}
	h.broadcastRoom(r)
	cs[0].player.Name = "CHANGED"
	h.broadcastRoom(r)
	updated, _ := encodePacket(h.roomMessage(r))
	for _, c := range cs {
		if old := <-c.send; !bytes.Equal(old, want) {
			t.Fatal("queued room snapshot changed after a later broadcast")
		}
		if newest := <-c.send; !bytes.Equal(newest, updated) {
			t.Fatal("room broadcast differs from the canonical metadata packet")
		}
	}
}

func BenchmarkBroadcastRoomFullGallery(b *testing.B) {
	h := newHub(1)
	r := &Room{Code: "GALLERY", Host: 0, Game: newGame(1)}
	clients := make([]*Client, 0, maxTanks+maxSpectators)
	for i := 0; i < maxTanks+maxSpectators; i++ {
		c := fakeClient()
		p := &Player{ID: i, Member: uint64(i + 1), Name: "PLAYER", Client: c, Spectating: i >= maxTanks}
		if p.Spectating {
			r.putViewer(p)
		} else {
			r.Players[i] = p
		}
		clients = append(clients, c)
	}
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		h.broadcastRoom(r)
		for _, c := range clients {
			<-c.send
		}
	}
}
