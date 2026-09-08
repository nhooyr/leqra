package main

import "testing"

func TestRejectedSpectatingChangePreservesQueue(t *testing.T) {
	for _, spectating := range []bool{false, true} {
		name, errorCode := "arena full", "no_seat"
		if spectating {
			name, errorCode = "gallery full", "spectators_full"
		}
		t.Run(name, func(t *testing.T) {
			h := newHub(4)
			clients, r := mmRoom(t, h, 1)
			actor := clients[0]
			if !spectating {
				// Bots fill the arena without counting as queued humans.
				for i := 1; i < maxTanks; i++ {
					mmAction(t, h, clients[0], map[string]any{"type": "add", "kind": "bot"})
				}
			}
			viewers := 1
			if spectating {
				viewers = maxSpectators
			}
			for i := 0; i < viewers; i++ {
				viewer := fakeClient()
				h.addClient(viewer)
				mmAction(t, h, viewer, map[string]any{"type": "join", "code": r.Code, "name": "VIEWER", "spectating": true})
				if !spectating {
					actor = viewer
				}
			}
			mmQueue(t, h, clients, "ffa-8")
			queued, member := r.Queue, actor.player
			id, role := member.ID, member.Spectating
			mmAction(t, h, actor, map[string]any{"type": "spectate", "spectating": spectating})
			if !hasError(actor, errorCode) {
				t.Fatal("full destination did not reject role change")
			}
			if member.ID != id || member.Spectating != role {
				t.Fatal("rejected role change moved the member")
			}
			if r.Queue != queued || h.queues[queued.ID] != queued {
				t.Fatal("rejected role change cancelled the existing matchmaking search")
			}
			// Once a slot is available, a successful roster change still
			// invalidates the party's previous matchmaking consent.
			vacancy := 1
			if spectating {
				vacancy = maxTanks
			}
			h.expirePlayer(r, vacancy)
			if r.Queue != queued || h.queues[queued.ID] != queued {
				t.Fatal("vacating an unrelated bot or spectator cancelled the queue")
			}
			mmAction(t, h, actor, map[string]any{"type": "spectate", "spectating": spectating})
			if member.Spectating != spectating || r.Queue != nil || h.queues[queued.ID] != nil {
				t.Fatal("successful role change did not cancel the previous search")
			}
		})
	}
}
