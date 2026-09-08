package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"
)

func kickRequest(p *Player) map[string]any {
	return map[string]any{"type": "kick", "target": p.ID, "member": p.Member}
}
func receivedType(c *Client, kind string) bool {
	for _, m := range drain(c) {
		if m["type"] == kind {
			return true
		}
	}
	return false
}
func TestKickLobbyDetachesAndNotifies(t *testing.T) {
	h, cs, r := makeRoom(t, 3)
	removed := cs[1].player
	removed.Ready = true
	removed.Input = Input{Forward: true, Fire: true, Seq: 8}
	hostToken := cs[0].player.Token
	for _, c := range cs {
		drain(c)
	}
	action(t, h, cs[0], kickRequest(removed))
	if r.Players[1] != nil || cs[1].room != nil || cs[1].player != nil || removed.Client != nil || removed.Ready || removed.Input != (Input{}) {
		t.Fatal("removed pilot retained state or identity")
	}
	if r.Host != 0 || r.Players[0].Token != hostToken || len(r.Kicked) != 1 {
		t.Fatal("host changed or credential not revoked")
	}
	if !receivedType(cs[1], "kicked") || !receivedType(cs[0], "player_kicked") {
		t.Fatal("missing removal notification/ack")
	}
	if !receivedType(cs[2], "room") {
		t.Fatal("remaining pilot not informed")
	}
}
func TestKickRequiresCurrentHost(t *testing.T) {
	h, cs, r := makeRoom(t, 3)
	p := r.Players[2]
	action(t, h, cs[1], kickRequest(p))
	if !hasError(cs[1], "not_host") || r.Players[2] != p {
		t.Fatal("guest kick allowed")
	}
	c := fakeClient()
	action(t, h, c, kickRequest(p))
	if !hasError(c, "not_joined") || r.Players[2] != p {
		t.Fatal("unjoined kick allowed")
	}
}
func TestKickCannotKickSelf(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	action(t, h, cs[0], kickRequest(r.Players[0]))
	if !hasError(cs[0], "kick_self") || r.Host != 0 || r.Players[0] == nil {
		t.Fatal("self-kick allowed")
	}
}
func TestKickRejectsInvalidTargets(t *testing.T) {
	cases := []map[string]any{
		{"type": "kick"}, {"type": "kick", "target": nil, "member": 2},
		{"type": "kick", "target": -1, "member": 2}, {"type": "kick", "target": maxTanks, "member": 2},
		{"type": "kick", "target": 1}, {"type": "kick", "target": 1, "member": 0},
	}
	for i, m := range cases {
		t.Run(fmt.Sprint(i), func(t *testing.T) {
			h, cs, r := makeRoom(t, 2)
			action(t, h, cs[0], m)
			if !hasError(cs[0], "bad_target") || connectedPlayers(r) != 2 {
				t.Fatal("invalid target accepted")
			}
		})
	}
}
func TestKickRejectsMalformedTargetTypes(t *testing.T) {
	for _, raw := range []string{`{"type":"kick","target":1.5,"member":2}`, `{"type":"kick","target":"1","member":2}`, `{"type":"kick","target":1,"member":-1}`} {
		h, cs, r := makeRoom(t, 2)
		if h.handle(cs[0], []byte(raw), time.Now()) == nil || connectedPlayers(r) != 2 {
			t.Fatal("malformed request accepted")
		}
	}
}
func TestKickStaleConfirmationCannotRemoveReplacement(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	old := r.Players[1]
	request := kickRequest(old)
	action(t, h, cs[1], map[string]any{"type": "leave"})
	replacement := fakeClient()
	action(t, h, replacement, map[string]any{"type": "join", "code": r.Code, "name": "NEW"})
	if replacement.player.ID != old.ID || replacement.player.Member == old.Member {
		t.Fatal("seat incarnation not changed")
	}
	action(t, h, cs[0], request)
	if !hasError(cs[0], "player_missing") || r.Players[1] != replacement.player {
		t.Fatal("stale kick removed new occupant")
	}
}
func TestKickCannotSelectForeignRoom(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	foreign := fakeClient()
	action(t, h, foreign, map[string]any{"type": "create", "name": "OTHER HOST"})
	other := foreign.room
	m := kickRequest(foreign.player)
	m["code"] = other.Code
	m["token"] = foreign.player.Token
	action(t, h, cs[0], m)
	if other.Players[0] != foreign.player || r.Host != 0 || !hasError(cs[0], "kick_self") {
		t.Fatal("foreign room selected by request")
	}
}
func TestKickAfterHostHandoff(t *testing.T) {
	h, cs, r := makeRoom(t, 3)
	old := cs[0].player
	h.removeClient(cs[0])
	if r.Host != 1 {
		t.Fatal("host did not transfer")
	}
	action(t, h, cs[0], kickRequest(r.Players[2]))
	if !hasError(cs[0], "not_joined") {
		t.Fatal("detached old host can kick")
	}
	rejoined := fakeClient()
	action(t, h, rejoined, map[string]any{"type": "join", "code": r.Code, "token": old.Token})
	action(t, h, rejoined, kickRequest(r.Players[2]))
	if !hasError(rejoined, "not_host") {
		t.Fatal("former host regained kick authority")
	}
	action(t, h, cs[1], kickRequest(r.Players[2]))
	if r.Players[2] != nil || r.Host != 1 {
		t.Fatal("new host cannot kick")
	}
}
func TestKickRejectsStaleSocketAfterResume(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	old := cs[0].player
	h.removeClient(cs[0])
	replacement := fakeClient()
	action(t, h, replacement, map[string]any{"type": "join", "code": r.Code, "token": old.Token})
	// Even a stale object which retained pointers does not own the resumed pilot.
	r.Host = 0
	action(t, h, cs[0], kickRequest(r.Players[1]))
	if !hasError(cs[0], "not_joined") || r.Players[1] == nil {
		t.Fatal("stale socket gained resumed host authority")
	}
}
func TestKickDisconnectedSeatRejectsResume(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	p := cs[1].player
	h.removeClient(cs[1])
	action(t, h, cs[0], kickRequest(p))
	c := fakeClient()
	action(t, h, c, map[string]any{"type": "join", "code": r.Code, "token": p.Token})
	if c.player != nil || c.room != nil || !receivedType(c, "kicked") {
		t.Fatal("disconnected kicked seat resumed or became new player")
	}
}
func TestKickTerminalSocketCannotRejoinOrControl(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	p := cs[1].player
	action(t, h, cs[0], kickRequest(p))
	drain(cs[1])
	for _, m := range []map[string]any{{"type": "input", "seq": 100, "fire": true}, {"type": "join", "code": r.Code}, {"type": "create"}} {
		action(t, h, cs[1], m)
		if !receivedType(cs[1], "kicked") || cs[1].room != nil || p.Input != (Input{}) {
			t.Fatal("kicked socket regained authority")
		}
	}
}
func TestKickNewManualJoinAllowed(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	old := cs[1].player
	action(t, h, cs[0], kickRequest(old))
	c := fakeClient()
	action(t, h, c, map[string]any{"type": "join", "code": r.Code, "name": old.Name})
	if c.player == nil || c.player.Token == old.Token || c.player.Member == old.Member {
		t.Fatal("kick became ban or reused revoked identity")
	}
}
func TestKickEveryMatchPhase(t *testing.T) {
	for _, phase := range []string{"countdown", "playing", "roundOver", "matchOver"} {
		t.Run(phase, func(t *testing.T) {
			h, cs, r := makeRoom(t, 3)
			r.Game.startMatch(r.Players)
			r.Game.Phase = phase
			removed := cs[1].player
			r.Game.Tanks[1].VX = 100
			r.Game.Tanks[1].VY = 20
			r.Game.Bullets = []*Bullet{{ID: 1, Owner: 1}, {ID: 2, Owner: 0}, {ID: 3, Owner: 1}, {ID: 4, Owner: 2}}
			r.Game.Scores = [maxTanks]int{2, 1, 3, 0}
			generation := r.Game.Generation
			action(t, h, cs[0], kickRequest(removed))
			if r.Game.Tanks[1].Alive || r.Game.Tanks[1].VX != 0 || r.Game.Tanks[1].VY != 0 || r.Players[1] != nil {
				t.Fatal("tank not eliminated")
			}
			if len(r.Game.Bullets) != 2 || r.Game.Bullets[0].Owner != 0 || r.Game.Bullets[1].Owner != 2 {
				t.Fatal("wrong projectiles removed")
			}
			if r.Game.Generation != generation || r.Game.Phase != phase || r.Game.Scores[0] != 2 || r.Game.Scores[2] != 3 {
				t.Fatal("match or other scores reset")
			}
			// A fresh join cannot inherit a retired tank identity mid-match.
			if phase != "matchOver" {
				c := fakeClient()
				action(t, h, c, map[string]any{"type": "join", "code": r.Code})
				if c.player == nil || c.player.ID == 1 || r.Game.Tanks[c.player.ID].Alive {
					t.Fatal("retired identity reused or late join spawned")
				}
			}
		})
	}
}
func TestKickLastOpponentResolvesRound(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	r.Game.startMatch(r.Players)
	r.Game.Phase = "playing"
	action(t, h, cs[0], kickRequest(cs[1].player))
	h.tick(time.Now())
	if r.Game.Phase != "roundOver" || r.Game.Winner != 0 || r.Game.Scores[0] != 1 {
		t.Fatal("last opponent removal did not end round")
	}
	for i := 0; i < 200; i++ {
		h.tick(time.Now())
	}
	if r.Game.Phase != "lobby" || cs[0].player.Ready {
		t.Fatal("single player not returned to lobby")
	}
}
func TestKickKeepsOtherPlayersReadiness(t *testing.T) {
	h, cs, r := makeRoom(t, 3)
	readyAll(t, h, cs)
	action(t, h, cs[0], kickRequest(cs[2].player))
	if !canStart(r) || !cs[0].player.Ready || !cs[1].player.Ready {
		t.Fatal("kick reset other players' readiness")
	}
}
func TestKickAndRenameKeepMemberStable(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	p := cs[1].player
	member := p.Member
	action(t, h, cs[1], map[string]any{"type": "rename", "name": "RENAMED"})
	if p.Member != member {
		t.Fatal("rename changed seat identity")
	}
	action(t, h, cs[0], kickRequest(p))
	if r.Players[1] != nil {
		t.Fatal("renamed player not removable")
	}
}
func TestKickDoesNotLeakCredentials(t *testing.T) {
	h, cs, _ := makeRoom(t, 3)
	token := cs[1].player.Token
	for _, c := range cs {
		drain(c)
	}
	action(t, h, cs[0], kickRequest(cs[1].player))
	for _, c := range cs {
		for _, m := range drain(c) {
			b, _ := json.Marshal(m)
			if strings.Contains(string(b), token) {
				t.Fatal("kick leaked reconnect credential")
			}
		}
	}
}
func TestKickNoticeLifetimeAndBounds(t *testing.T) {
	now := time.Now()
	r := &Room{}
	for i := 0; i < maxKickNotices+8; i++ {
		r.rememberKick(fmt.Sprint(i), now.Add(time.Duration(i)*time.Millisecond))
	}
	if len(r.Kicked) > maxKickNotices {
		t.Fatal("unbounded tombstones")
	}
	r.rememberKick("latest", now.Add(kickNoticeTTL+2*time.Second))
	if len(r.Kicked) != 1 {
		t.Fatal("expired tombstones not pruned")
	}
	if _, ok := r.Kicked[sha256.Sum256([]byte("latest"))]; !ok {
		t.Fatal("latest notice not retained")
	}
}
func TestKickSimultaneousLeaveIsSafe(t *testing.T) {
	h, cs, r := makeRoom(t, 3)
	p := cs[1].player
	req, _ := json.Marshal(kickRequest(p))
	leave := []byte(`{"type":"leave"}`)
	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		if err := h.handle(cs[0], req, time.Now()); err != nil {
			t.Error(err)
		}
	}()
	go func() {
		defer wg.Done()
		if err := h.handle(cs[1], leave, time.Now()); err != nil {
			t.Error(err)
		}
	}()
	wg.Wait()
	if r.Players[1] != nil || r.Players[0] == nil || r.Players[2] == nil {
		t.Fatal("concurrent removal corrupted roster")
	}
}
