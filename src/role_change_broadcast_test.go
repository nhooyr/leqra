package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"testing"
)

func TestRoleChangePreservesReliableIdentityRoomAndStateOrder(t *testing.T) {
	for _, phase := range []string{"lobby", "playing", "matchOver"} {
		t.Run(phase, func(t *testing.T) {
			h, r, now := performanceRoom437(maxSpectators)
			parent, local := r.Players[0], r.Players[1]
			local.Kind, local.Owner, local.Controller, local.Client = "local", parent.ID, parent, nil
			if phase != "lobby" {
				r.Game.startMatch(r.Players)
				r.Game.Phase = phase
				if phase == "matchOver" {
					r.Game.finishMatchStats(parent.ID)
				}
			}
			members := r.members()
			for _, p := range members {
				p.Ready = true
				if p.Client != nil {
					p.Client.mapGeneration = r.Game.Generation
					p.Client.updates <- []byte("obsolete snapshot")
				}
			}
			h.roleChanged(r, now)
			expectedState := h.stateMessage(r)
			if r.Game.Generation > 0 {
				expectedState["world"] = r.Game.World
			}
			state, err := json.Marshal(expectedState)
			if err != nil {
				t.Fatal(err)
			}
			room, err := json.Marshal(h.roomMessage(r))
			if err != nil {
				t.Fatal(err)
			}
			for _, p := range members {
				c := p.Client
				if c == nil {
					continue
				}
				if len(c.send) != 3 || len(c.updates) != 0 {
					t.Fatalf("member %d received %d reliable and %d replaceable packets", p.ID, len(c.send), len(c.updates))
				}
				localID, localMember := -1, uint64(0)
				if p == parent {
					localID, localMember = local.ID, local.Member
				}
				identity, err := json.Marshal(map[string]any{"type": "identity", "id": p.ID, "member": p.Member, "spectating": p.Spectating, "localId": localID, "localMember": localMember})
				if err != nil {
					t.Fatal(err)
				}
				for i, want := range [][]byte{identity, room, state} {
					if got := <-c.send; !bytes.Equal(got, want) {
						t.Fatalf("member %d packet %d changed payload or ordering\ngot: %s\nwant: %s", p.ID, i, got, want)
					}
				}
				if c.mapGeneration != r.Game.Generation {
					t.Fatal("forced map delivery did not update client generation")
				}
			}
		})
	}
}

func BenchmarkRoleChangeBroadcast(b *testing.B) {
	for _, viewers := range []int{0, maxSpectators} {
		b.Run(fmt.Sprintf("viewers_%d", viewers), func(b *testing.B) {
			h, r, now := performanceRoom437(viewers)
			r.Game.startMatch(r.Players)
			members := r.members()
			b.ReportAllocs()
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				h.roleChanged(r, now)
				for _, p := range members {
					for len(p.Client.send) > 0 {
						<-p.Client.send
					}
				}
			}
		})
	}
}
