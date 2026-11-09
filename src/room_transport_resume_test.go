package main

import (
	"encoding/json"
	"net"
	"testing"
	"time"
)

func TestRoomResumeReplacesOnlyStaleAuthenticatedTransport(t *testing.T) {
	h, clients, r := makeRoom(t, 2)
	old := clients[0]
	pilot := old.player
	action(t, h, old, map[string]any{"type": "add", "kind": "local", "name": "WING", "team": pilot.Team})
	action(t, h, clients[1], map[string]any{"type": "ready", "ready": true})
	action(t, h, old, map[string]any{"type": "start"})
	local := r.Players[2]
	if local == nil || local.Kind != "local" || r.Game.Tanks[pilot.ID] == nil || r.Game.Tanks[local.ID] == nil {
		t.Fatal("expected a live room with two local tanks")
	}
	firstTank, secondTank := r.Game.Tanks[pilot.ID], r.Game.Tanks[local.ID]
	r.Game.Scores[pilot.ID], r.Game.Scores[local.ID] = 3, 2
	pilot.Input, local.Input = Input{Seq: 15, Fire: true}, Input{Seq: 16, Fire: true}
	pilot.FirePending, local.FirePending = true, true
	firstTank.Ack, secondTank.Ack = 15, 16
	firstTank.AckSteps, secondTank.AckSteps = 3, 4

	now := time.Now()
	server, peer := net.Pipe()
	defer server.Close()
	defer peer.Close()
	old.ws = &wsConn{conn: server, openedAt: now.Add(-time.Minute)}
	old.ws.lastPeerRead.Store(int64(time.Minute))
	attempt := func(token string, at time.Time) *Client {
		t.Helper()
		c := fakeClient()
		c.requireVersion = true
		h.addClient(c)
		for _, packet := range []map[string]any{
			{"type": "client_hello", "version": version, "protocol": protocolVersion},
			{"type": "join", "code": r.Code, "token": token, "name": "OTHER"},
		} {
			b, err := json.Marshal(packet)
			if err != nil {
				t.Fatal(err)
			}
			if err := h.handle(c, b, at); err != nil {
				t.Fatal(err)
			}
		}
		return c
	}
	liveDuplicate := attempt(pilot.Token, now.Add(roomTransportIdle-time.Millisecond))
	if !hasError(liveDuplicate, "session_active") || pilot.Client != old {
		t.Fatal("duplicate transport displaced a live socket")
	}
	stale := now.Add(roomTransportIdle)
	invalid := attempt("wrong token", stale)
	if !hasError(invalid, "resume_expired") || pilot.Client != old {
		t.Fatal("an invalid token displaced a stale socket")
	}
	resumed := attempt(pilot.Token, stale)
	if resumed.room != r || resumed.player != pilot || pilot.Client != resumed || r.Host != pilot.ID ||
		r.Game.Tanks[pilot.ID] != firstTank || r.Game.Tanks[local.ID] != secondTank || local.Controller != pilot ||
		r.Game.Scores[pilot.ID] != 3 || r.Game.Scores[local.ID] != 2 {
		t.Fatal("replacing a stale transport changed the room, host, tanks, or scores")
	}
	if pilot.Input != (Input{}) || local.Input != (Input{}) || pilot.FirePending || local.FirePending ||
		firstTank.Ack != 0 || secondTank.Ack != 0 || firstTank.AckSteps != 0 || secondTank.AckSteps != 0 {
		t.Fatal("resumed tanks retained stale controls or acknowledgements")
	}
	select {
	case <-old.done:
	default:
		t.Fatal("stale transport remained open")
	}
	welcome, state := false, false
	for _, packet := range drain(resumed) {
		if packet["type"] == "welcome" && packet["resumed"] == true && packet["token"] == pilot.Token {
			welcome = true
		}
		if packet["type"] == "state" {
			state = welcome
		}
	}
	if !state {
		t.Fatal("no resumed welcome preceded state")
	}
	action(t, h, old, map[string]any{"type": "leave"})
	action(t, h, old, map[string]any{"type": "join", "code": "replacement room", "name": "STALE"})
	h.removeClient(old)
	if pilot.Client != resumed || h.rooms["replacement room"] != nil || old.room != nil || old.player != nil {
		t.Fatal("replaced socket could still mutate membership")
	}
}
