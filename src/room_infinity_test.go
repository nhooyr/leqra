package main

import (
	"testing"
	"time"
)

func TestRoomInfinityLaunchRequiresReadyCombatPilots(t *testing.T) {
	h, clients, r := makeRoom(t, 2)
	host, guest := clients[0], clients[1]
	viewer := fakeClient()
	h.addClient(viewer)
	action(t, h, viewer, map[string]any{"type": "join", "code": r.Code, "name": "VIEWER", "spectating": true})

	rules := r.Game.settings()
	rules.Infinity = true
	rules.MapSize = "compact"
	action(t, h, host, map[string]any{"type": "rules", "rules": rules})
	drain(host)
	drain(guest)
	drain(viewer)
	if got := h.roomWire(r); !got.Rules.Infinity || got.Rules.MapSize != "compact" || got.CanStart || got.InfinityActive {
		t.Fatalf("unexpected room before guests are ready: %+v", got)
	}
	action(t, h, guest, map[string]any{"type": "start"})
	if !hasError(guest, "not_host") {
		t.Fatal("guest was allowed to start Infinity")
	}
	action(t, h, host, map[string]any{"type": "start"})
	if !hasError(host, "not_ready") || r.infinityActive {
		t.Fatal("host started Infinity before the guest readied up")
	}
	action(t, h, guest, map[string]any{"type": "ready", "ready": true})
	if !h.roomWire(r).CanStart {
		t.Fatal("ready combat pilots could not start Infinity")
	}
	action(t, h, host, map[string]any{"type": "start"})
	if r.Game.Phase != "lobby" || !r.infinityActive || h.roomWire(r).CanStart || guest.player.Ready {
		t.Fatal("Infinity launch did not preserve the finite lobby and consume guest readiness")
	}
	for _, client := range clients {
		active, start := false, false
		for _, packet := range drain(client) {
			if packet["type"] == "room" && packet["infinityActive"] == true {
				active = true
			}
			if packet["type"] == "infinity_start" {
				start = active && len(packet) == 1
			}
		}
		if !start {
			t.Fatal("combat pilot did not receive the private launch after room metadata")
		}
	}
	for _, packet := range drain(viewer) {
		if packet["type"] == "infinity_start" {
			t.Fatal("room spectator received a private combat launch")
		}
	}
	if _, p, _, _ := h.infiniteMember(r.Code, viewer.player.Token); p != nil {
		t.Fatal("spectator credentials authenticated a private combat pilot")
	}
}

func TestRoomInfinityAuthorizationFollowsRoomMembershipAndGeneration(t *testing.T) {
	h, clients, r := makeRoom(t, 2)
	host, guest := clients[0], clients[1]
	pilot := guest.player
	code, token := r.Code, pilot.Token
	r.Game.Rules.Infinity = true
	action(t, h, guest, map[string]any{"type": "ready", "ready": true})
	action(t, h, host, map[string]any{"type": "start"})
	room, member, generation, name := h.infiniteMember(code, token)
	if room != r || member != pilot || generation == 0 || name != pilot.Name {
		t.Fatal("active combat pilot could not authenticate")
	}
	for _, invalid := range []struct{ code, token string }{{"other room", token}, {code, ""}, {code, "wrong token"}} {
		if _, member, _, _ := h.infiniteMember(invalid.code, invalid.token); member != nil {
			t.Fatal("invalid room or token was accepted")
		}
	}
	updated := r.LastAction.Add(time.Second)
	if !h.touchInfiniteMember(r, pilot, generation, updated) || r.LastAction != updated {
		t.Fatal("active Infinity gameplay did not keep the room alive")
	}
	action(t, h, host, map[string]any{"type": "rename_room", "code": "Infinity arena room"})
	if _, member, gen, _ := h.infiniteMember(code, token); member != pilot || gen != generation {
		t.Fatal("private Infinity reconnect did not follow a room rename")
	}
	action(t, h, guest, map[string]any{"type": "spectate", "spectating": true})
	if h.validInfiniteMember(r, pilot, generation) {
		t.Fatal("moving to spectators did not revoke combat access")
	}
	action(t, h, host, map[string]any{"type": "lobby"})
	if r.infinityActive || h.validInfiniteMember(r, host.player, generation) {
		t.Fatal("returning to the room did not close the private arena")
	}
	action(t, h, host, map[string]any{"type": "start"})
	if _, _, next, _ := h.infiniteMember(r.Code, host.player.Token); next <= generation || h.validInfiniteMember(r, host.player, generation) {
		t.Fatal("previous Infinity socket could reenter a new generation")
	}
}

func TestRoomInfinityLaunchClearsPriorFiniteMatchResult(t *testing.T) {
	h, clients, r := makeRoom(t, 2)
	host, guest := clients[0], clients[1]
	r.Game.startMatch(r.Players)
	r.Game.Scores[0] = 5
	r.Game.Winner = 0
	r.Game.finishMatchStats(0)
	r.Game.Phase = "matchOver"
	r.Game.Rules.Infinity = true
	action(t, h, guest, map[string]any{"type": "ready", "ready": true})
	action(t, h, host, map[string]any{"type": "start"})
	if !r.infinityActive || h.roomWire(r).Phase != "lobby" {
		t.Fatal("starting Infinity did not replace the finished finite match")
	}
	late := fakeClient()
	h.addClient(late)
	action(t, h, late, map[string]any{"type": "join", "code": r.Code, "name": "MOBILE PILOT"})
	gotLobby := false
	for _, packet := range drain(late) {
		if packet["type"] != "state" {
			continue
		}
		if packet["phase"] != "lobby" || packet["matchStats"] != nil || packet["winner"] != float64(-1) {
			t.Fatalf("late Infinity pilot got a stale finite result: %v", packet)
		}
		gotLobby = true
	}
	if !gotLobby {
		t.Fatal("late Infinity pilot received no lobby state")
	}
}

func TestRoomInfinityDisconnectGraceAndKick(t *testing.T) {
	h, clients, r := makeRoom(t, 2)
	host, guest := clients[0], clients[1]
	pilot := guest.player
	r.Game.Rules.Infinity = true
	action(t, h, guest, map[string]any{"type": "ready", "ready": true})
	action(t, h, host, map[string]any{"type": "start"})
	generation := r.infinityGeneration
	h.removeClient(guest)
	if !h.validInfiniteMember(r, pilot, generation) {
		t.Fatal("a brief room socket interruption revoked Infinity combat access")
	}
	if h.touchInfiniteMember(r, pilot, generation, pilot.DisconnectedAt.Add(reconnectGrace+time.Millisecond)) {
		t.Fatal("a disconnected pilot remained authorized past the room reconnect window")
	}
	action(t, h, host, map[string]any{"type": "kick", "target": pilot.ID, "member": pilot.Member})
	if _, p, _, _ := h.infiniteMember(r.Code, pilot.Token); p != nil || h.validInfiniteMember(r, pilot, generation) {
		t.Fatal("removed pilot retained Infinity combat access")
	}
}
