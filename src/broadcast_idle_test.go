package main

import (
	"bytes"
	"encoding/json"
	"testing"
	"time"
)

func TestBroadcastStateWithoutRecipientsDoesNotAllocate(t *testing.T) {
	for _, closed := range []bool{false, true} {
		name := "disconnected"
		if closed {
			name = "closed"
		}
		t.Run(name, func(t *testing.T) {
			h, r, _ := performanceRoom437(maxSpectators)
			r.Game.startMatch(r.Players)
			for _, p := range r.members() {
				if closed {
					p.Client.stop()
				} else {
					p.Client = nil
				}
			}
			// Empty seats and bots also provide no recipients.
			r.Players[1] = nil
			r.Players[2] = &Player{ID: 2, Kind: "bot"}
			if got := testing.AllocsPerRun(100, func() { h.broadcastState(r) }); got != 0 {
				t.Fatalf("recipient-free broadcast allocated %g times", got)
			}
		})
	}
}

func TestBroadcastStateReconnectAfterRecipientFreeBroadcast(t *testing.T) {
	for _, spectating := range []bool{false, true} {
		name := "pilot"
		if spectating {
			name = "spectator"
		}
		t.Run(name, func(t *testing.T) {
			h, clients, r := makeRoom(t, 2)
			original := clients[0]
			if spectating {
				original = fakeClient()
				h.join(original, false, r.Code, "VIEWER", "", time.Now(), true)
				clients = append(clients, original)
			}
			r.Game.startMatch(r.Players)
			token := original.player.Token
			for _, c := range clients {
				h.removeClient(c)
				drain(c)
			}
			h.broadcastState(r)
			// Reconnect must still receive the complete maze.
			next := fakeClient()
			h.join(next, false, r.Code, "VIEWER", token, time.Now(), spectating)
			if next.room != r || next.player.Spectating != spectating {
				t.Fatal("reconnect failed")
			}
			canonical := h.stateMessage(r)
			canonical["world"] = r.Game.World
			want, err := json.Marshal(canonical)
			if err != nil {
				t.Fatal(err)
			}
			found := false
			for len(next.send) > 0 {
				raw := <-next.send
				var kind struct {
					Type string `json:"type"`
				}
				if err := json.Unmarshal(raw, &kind); err != nil {
					t.Fatal(err)
				}
				if kind.Type == "state" {
					found = true
					if !bytes.Equal(raw, want) {
						t.Fatal("reconnect changed the complete state payload")
					}
				}
			}
			if !found || next.mapGeneration != r.Game.Generation {
				t.Fatal("reconnect omitted its maze")
			}
			// The reconnect is the room's only live socket, including spectator-only rooms.
			next.updates = make(chan []byte, 1)
			h.broadcastState(r)
			if len(next.updates) != 1 {
				t.Fatal("reconnected controller did not receive subsequent broadcasts")
			}
		})
	}
}

func BenchmarkBroadcastStateWithoutRecipients(b *testing.B) {
	for _, closed := range []bool{false, true} {
		name := "disconnected"
		if closed {
			name = "closed"
		}
		b.Run(name, func(b *testing.B) {
			h, r, _ := performanceRoom437(maxSpectators)
			r.Game.startMatch(r.Players)
			for _, p := range r.members() {
				if closed {
					p.Client.stop()
				} else {
					p.Client = nil
				}
			}
			b.ReportAllocs()
			b.ResetTimer()
			for n := 0; n < b.N; n++ {
				h.broadcastState(r)
			}
		})
	}
}
