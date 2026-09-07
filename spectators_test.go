package main

import (
	"encoding/json"
	"strings"
	"sync"
	"testing"
	"time"
)

func viewer33(t *testing.T, h *Hub, r *Room, name string) *Client {
	t.Helper()
	c := fakeClient()
	h.addClient(c)
	action(t, h, c, map[string]any{"type": "join", "code": r.Code, "name": name, "spectating": true})
	if c.player == nil || !c.player.Spectating {
		t.Fatalf("viewer rejected: %v", drain(c))
	}
	return c
}
func role33(t *testing.T, h *Hub, c *Client, watch bool) {
	t.Helper()
	action(t, h, c, map[string]any{"type": "spectate", "spectating": watch})
}
func swap33(t *testing.T, h *Hub, c *Client, active, viewer *Player) {
	t.Helper()
	action(t, h, c, map[string]any{"type": "swap", "target": active.ID, "member": active.Member, "spectator": viewer.ID, "spectatorMember": viewer.Member})
}
func TestSpectator33SeparateRosterAndWelcome(t *testing.T) {
	h, cs, r := makeRoom(t, maxTanks)
	v := viewer33(t, h, r, "WATCHER")
	if v.player.ID < 4 || r.freeCombatSeat() != -1 || len(r.Spectators) != 1 {
		t.Fatal("viewer used a combat seat")
	}
	welcome := false
	for _, m := range drain(v) {
		if m["type"] == "welcome" && m["spectating"] == true {
			welcome = true
		}
	}
	if !welcome {
		t.Fatal("role missing from welcome")
	}
	for _, c := range cs {
		seen := false
		for _, m := range drain(c) {
			if m["type"] == "room" && len(m["spectators"].([]any)) == 1 {
				seen = true
			}
		}
		if !seen {
			t.Fatal("viewer not visible to every player")
		}
	}
}
func TestSpectator33CallsignRequired(t *testing.T) {
	h := newHub(4)
	for _, name := range []string{"", "  ", "💥"} {
		c := fakeClient()
		action(t, h, c, map[string]any{"type": "join", "code": "Watch room", "spectating": true, "name": name})
		if c.player != nil || !hasError(c, "bad_name") || len(h.rooms) != 0 {
			t.Fatal("watch bypassed name")
		}
	}
}
func TestSpectator33FullFallbackDuringGame(t *testing.T) {
	h, _, r := makeRoom(t, maxTanks)
	r.Game.startMatch(r.Players)
	v := fakeClient()
	action(t, h, v, map[string]any{"type": "join", "code": r.Code, "name": "FIFTH"})
	if v.player == nil || !v.player.Spectating {
		t.Fatal("full room rejected viewer")
	}
	for _, m := range drain(v) {
		if m["type"] == "welcome" && m["full"] != true {
			t.Fatal("fallback not explained")
		}
	}
	for _, p := range r.Players {
		if p == v.player {
			t.Fatal("fifth tank")
		}
	}
}
func TestSpectator33IgnoresInputAndReady(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	v := viewer33(t, h, r, "WATCHER")
	readyAll(t, h, cs)
	if !canStart(r) {
		t.Fatal("viewer required readiness")
	}
	r.Game.startMatch(r.Players)
	action(t, h, v, map[string]any{"type": "input", "seq": 1, "fire": true, "forward": true})
	if v.player.Input.Fire || v.player.FirePending {
		t.Fatal("viewer can fire")
	}
	action(t, h, v, map[string]any{"type": "input", "seq": 2, "player": 0, "fire": true})
	if !hasError(v, "not_owned") || r.Players[0].Input.Fire {
		t.Fatal("viewer controlled host")
	}
	r.Game.Phase = "lobby"
	action(t, h, v, map[string]any{"type": "ready", "ready": true})
	if v.player.Ready {
		t.Fatal("viewer readied")
	}
}
func TestSpectator33PersistentAcrossRoundsAndRematches(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	v := viewer33(t, h, r, "WATCHER")
	old := v.player
	for i := 0; i < 4; i++ {
		r.Game.startMatch(r.Players)
		r.Game.startRound(r.Players)
		if !old.Spectating || r.member(old.ID) != old {
			t.Fatal("watcher promoted on round start")
		}
		for _, tank := range r.Game.Tanks {
			if tank != nil && tank.ID == old.ID {
				t.Fatal("spectator spawned")
			}
		}
		r.Game.Phase = "matchOver"
		readyAll(t, h, cs)
		if !canStart(r) {
			t.Fatal("viewer blocks rematch")
		}
	}
}
func TestSpectator33ToggleKeepsIdentityAndDropsState(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	p := cs[0].player
	token, member := p.Token, p.Member
	r.Game.startMatch(r.Players)
	r.Game.Phase = "playing"
	r.Game.Bullets = []*Bullet{{ID: 1, Owner: 0}, {ID: 2, Owner: 1, Target: 0}}
	r.Game.Scores[1] = 3
	role33(t, h, cs[0], true)
	if !p.Spectating || p.ID < 4 || r.Host != p.ID || p.Member != member || p.Token != token || r.Game.Tanks[0] != nil || len(r.Game.Bullets) != 1 || r.Game.Bullets[0].Target != -1 {
		t.Fatal("spectating left combat state/changed membership")
	}
	role33(t, h, cs[0], false)
	if p.Spectating || p.ID != 0 || r.Game.Tanks[0].Alive || r.Game.Scores[1] != 3 || r.Game.Generation != 1 {
		t.Fatal("return spawned or reset the match")
	}
	r.Game.startRound(r.Players)
	if !r.Game.Tanks[0].Alive {
		t.Fatal("returning pilot missing next round")
	}
}
func TestSpectator33ToggleFullLeavesViewer(t *testing.T) {
	h, _, r := makeRoom(t, maxTanks)
	v := viewer33(t, h, r, "V")
	id := v.player.ID
	role33(t, h, v, false)
	if !hasError(v, "no_seat") || v.player.ID != id || !v.player.Spectating {
		t.Fatal("full promotion mutated")
	}
}
func TestSpectator33HostCanWatchBotsAndConfigure(t *testing.T) {
	h, cs, r := makeRoom(t, 1)
	for i := 1; i <= 2; i++ {
		action(t, h, cs[0], map[string]any{"type": "add", "kind": "bot", "name": "BOT", "difficulty": "normal", "team": i})
	}
	role33(t, h, cs[0], true)
	if !canStart(r) || r.Host < 4 {
		t.Fatal("spectator-host cannot start bots")
	}
	rules := legacyTeamRules36()
	rules.MapSize = "large"
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	action(t, h, cs[0], map[string]any{"type": "start"})
	if r.Game.Phase != "countdown" || r.Game.World.Cols != 12 {
		t.Fatal("viewer-host controls failed")
	}
}
func TestSpectator33GuestCannotChangeRolesOfOthers(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	v := viewer33(t, h, r, "V")
	action(t, h, v, map[string]any{"type": "spectate", "spectating": true, "target": 0, "member": cs[0].player.Member})
	if !hasError(v, "not_owned") || cs[0].player.Spectating {
		t.Fatal("guest demoted host")
	}
	swap33(t, h, cs[1], cs[0].player, v.player)
	if !hasError(cs[1], "not_host") {
		t.Fatal("guest swapped")
	}
}
func TestSpectator33SwapPreservesSeatSideScoreNoLife(t *testing.T) {
	h, cs, r := makeRoom(t, 3)
	v := viewer33(t, h, r, "V")
	a, b := cs[1].player, v.player
	oldA, oldB := a.ID, b.ID
	tokens := []string{a.Token, b.Token}
	r.Game.startMatch(r.Players)
	r.Game.Phase = "playing"
	r.Game.Scores[oldA] = 3
	r.Game.Tanks[oldA].Power = "laser"
	swap33(t, h, cs[0], a, b)
	if a.ID != oldB || !a.Spectating || b.ID != oldA || b.Spectating || b.Team != a.Team || r.Game.Scores[b.ID] != 3 || r.Game.Tanks[b.ID].Alive || r.Game.Tanks[b.ID].Power != "" || tokens[0] != a.Token || tokens[1] != b.Token || r.Host != cs[0].player.ID {
		t.Fatal("bad swap")
	}
}
func TestSpectator33SwapActiveHostRetainsAuthority(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	v := viewer33(t, h, r, "V")
	host := cs[0].player
	swap33(t, h, cs[0], host, v.player)
	if r.Host != host.ID || !host.Spectating || v.player.ID != 0 {
		t.Fatal("host transferred by swap")
	}
	action(t, h, cs[0], map[string]any{"type": "add", "kind": "bot", "difficulty": "easy", "team": 2})
	if r.Players[2] == nil {
		t.Fatal("host lost editor")
	}
}
func TestSpectator33SwapSpectatorHostRetainsAuthority(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	host := cs[0].player
	role33(t, h, cs[0], true)
	other := cs[1].player
	swap33(t, h, cs[0], other, host)
	if r.Host != host.ID || host.Spectating || !other.Spectating {
		t.Fatal("viewer host lost authority")
	}
}
func TestSpectator33SwapStaleAndCrossRoom(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	v := viewer33(t, h, r, "V")
	a := cs[1].player
	action(t, h, cs[0], map[string]any{"type": "swap", "target": a.ID, "member": a.Member + 100, "spectator": v.player.ID, "spectatorMember": v.player.Member})
	if !hasError(cs[0], "player_missing") || a.Spectating {
		t.Fatal("stale swap applied")
	}
	stranger := fakeClient()
	action(t, h, stranger, map[string]any{"type": "create"})
	swap33(t, h, stranger, a, v.player)
	if !hasError(stranger, "player_missing") {
		t.Fatal("crossroom swap")
	}
}
func TestSpectator33SwapDisconnectedViewerRejected(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	v := viewer33(t, h, r, "V")
	p := v.player
	h.removeClient(v)
	swap33(t, h, cs[0], cs[1].player, p)
	if !hasError(cs[0], "not_connected") || !p.Spectating {
		t.Fatal("promoted disconnected viewer")
	}
}
func TestSpectator33CapacityAndAtomicSwap(t *testing.T) {
	h, cs, r := makeRoom(t, maxTanks)
	var first *Player
	for i := 0; i < maxSpectators; i++ {
		v := viewer33(t, h, r, "V")
		if first == nil {
			first = v.player
		}
	}
	extra := fakeClient()
	action(t, h, extra, map[string]any{"type": "join", "code": r.Code})
	if !hasError(extra, "room_capacity") || extra.room != nil {
		t.Fatal("unbounded room")
	}
	role33(t, h, cs[0], true)
	if !hasError(cs[0], "spectators_full") || cs[0].player.Spectating {
		t.Fatal("partial demotion")
	}
	swap33(t, h, cs[0], cs[1].player, first)
	if len(r.Spectators) != maxSpectators || first.Spectating {
		t.Fatal("full gallery swap failed")
	}
}
func TestSpectator33ReconnectRoleAndHostHandoff(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	v := viewer33(t, h, r, "V")
	p := v.player
	h.removeClient(v)
	c := fakeClient()
	action(t, h, c, map[string]any{"type": "join", "code": r.Code, "token": p.Token, "spectating": false})
	if c.player != p || !p.Spectating || len(r.Spectators) != 1 {
		t.Fatal("resume changed role")
	}
	action(t, h, cs[0], map[string]any{"type": "leave"})
	action(t, h, cs[1], map[string]any{"type": "leave"})
	h.tick(time.Now())
	if h.rooms[r.Code] != r || r.Host != p.ID {
		t.Fatal("viewers did not keep room/host")
	}
}
func TestSpectator33KickRevokesAndClearsViewer(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	v := viewer33(t, h, r, "V")
	p := v.player
	action(t, h, cs[0], kickRequest(p))
	if len(r.Spectators) != 0 || v.room != nil || v.kickedRoom != r.Code {
		t.Fatal("kick failed")
	}
	late := fakeClient()
	action(t, h, late, map[string]any{"type": "join", "code": r.Code, "token": p.Token})
	found := false
	for _, m := range drain(late) {
		found = found || m["type"] == "kicked"
	}
	if !found || late.room != nil {
		t.Fatal("revoked viewer resumed")
	}
}
func TestSpectator33ExpiredViewerCleanup(t *testing.T) {
	h, _, r := makeRoom(t, 1)
	v := viewer33(t, h, r, "V")
	h.removeClient(v)
	h.tick(time.Now().Add(reconnectGrace + time.Second))
	if len(r.Spectators) != 0 {
		t.Fatal("viewer leaked past grace")
	}
}
func TestSpectator33SecondaryControllerCanWatchIndependently(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	action(t, h, cs[0], map[string]any{"type": "add", "kind": "local", "name": "P2", "team": 1})
	p2 := r.Players[2]
	role33(t, h, cs[0], true)
	if p2.Owner != cs[0].player.ID || !participantAvailable(r.Players, 2) {
		t.Fatal("P2 lost controller")
	}
	action(t, h, cs[0], map[string]any{"type": "input", "player": 2, "seq": 1, "fire": true})
	if !p2.Input.Fire {
		t.Fatal("spectator controller cannot operate P2")
	}
	action(t, h, cs[0], map[string]any{"type": "spectate", "target": 2, "member": p2.Member, "spectating": true})
	if !p2.Spectating || r.Players[2] != nil {
		t.Fatal("P2 cannot watch")
	}
	action(t, h, cs[0], map[string]any{"type": "rename_local", "target": p2.ID, "member": p2.Member, "name": "Watcher Two"})
	if p2.Name != "Watcher Two" {
		t.Fatal("P2 viewer naming failed")
	}
	action(t, h, cs[0], map[string]any{"type": "leave"})
	if len(r.Spectators) != 0 {
		t.Fatal("dependent viewer not removed")
	}
}
func TestSpectator33SecondarySwapOwnersStayDistinct(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	action(t, h, cs[0], map[string]any{"type": "add", "kind": "local", "name": "P2", "team": 1})
	v := viewer33(t, h, r, "V")
	p2 := r.Players[2]
	host := cs[0].player
	swap33(t, h, cs[0], host, v.player)
	if p2.Owner != host.ID || p2.Controller != host || !participantAvailable(r.Players, 2) {
		t.Fatal("swap stole local controller")
	}
	action(t, h, v, map[string]any{"type": "input", "player": 2, "seq": 1, "fire": true})
	if !hasError(v, "not_owned") {
		t.Fatal("incoming player stole P2")
	}
}
func TestSpectator33WatchResumeMovesActiveSeat(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	p := cs[1].player
	h.removeClient(cs[1])
	v := fakeClient()
	action(t, h, v, map[string]any{"type": "join", "code": r.Code, "token": p.Token, "name": "New Watcher", "spectating": true})
	if v.player != p || !p.Spectating || p.Name != "New Watcher" || r.Players[1] != nil {
		t.Fatal("explicit watch resume left a tank")
	}
}
func TestSpectator33CTFRoleDropsFlagAndObjectiveReturnWaits(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	r.Game.Rules = legacyTeamRules36()
	r.Game.Rules.Mode = "ctf"
	r.Players[0].Team = 1
	r.Players[1].Team = 2
	r.Game.startMatch(r.Players)
	r.Game.Phase = "playing"
	f := r.Game.Objectives.Flags[1]
	f.Carrier = 0
	f.Home = false
	role33(t, h, cs[0], true)
	if f.Carrier != -1 || f.Home || r.Game.Tanks[0] != nil {
		t.Fatal("spectator kept flag")
	}
	role33(t, h, cs[0], false)
	id := cs[0].player.ID
	if r.Game.Tanks[id].Alive || r.Game.Tanks[id].RespawnTime != 3 {
		t.Fatal("objective return bypassed respawn delay")
	}
}
func TestSpectator33WatchPublishPreservesLocalRoles(t *testing.T) {
	h := newHub(4)
	c := fakeClient()
	roster := []SeatSpec{{Name: "HOST", Kind: "human", Team: 1, Spectating: true}, {Name: "P2", Kind: "local", Team: 1, Spectating: true}, {Name: "R", Kind: "bot", Team: 1, Difficulty: "easy"}, {Name: "V", Kind: "bot", Team: 2, Difficulty: "hard"}}
	action(t, h, c, map[string]any{"type": "publish", "code": "Gallery 🎮", "roster": roster})
	r := c.room
	if r == nil || !c.player.Spectating || len(r.Spectators) != 2 || len(r.members()) != 4 || !canStart(r) {
		t.Fatal("publish lost spectator/bot roster")
	}
	action(t, h, c, map[string]any{"type": "start"})
	if r.Game.Phase != "countdown" || len(r.Spectators) != 2 {
		t.Fatal("spectator host cannot watch imported match")
	}
}
func TestSpectator33RoomStateNoCredentialLeak(t *testing.T) {
	h, _, r := makeRoom(t, 1)
	v := viewer33(t, h, r, "Named viewer")
	data, _ := json.Marshal(h.roomMessage(r))
	if strings.Contains(string(data), v.player.Token) || strings.Contains(string(data), "Controller") {
		t.Fatal("credential/pointer leaked")
	}
	drain(v)
	r.Game.startMatch(r.Players)
	h.sendState(v, r)
	ms := drain(v)
	if len(ms) != 1 || ms[0]["world"] == nil {
		t.Fatal("viewer missing world snapshot")
	}
}
func TestSpectator33ConcurrentLastSeatOnlyOnePromotion(t *testing.T) {
	h, _, r := makeRoom(t, maxTanks-1)
	vs := []*Client{viewer33(t, h, r, "A"), viewer33(t, h, r, "B")}
	var wg sync.WaitGroup
	for _, v := range vs {
		wg.Add(1)
		go func(c *Client) {
			defer wg.Done()
			_ = h.handle(c, []byte(`{"type":"spectate","spectating":false}`), time.Now())
		}(v)
	}
	wg.Wait()
	n := 0
	for _, v := range vs {
		if !v.player.Spectating {
			n++
		}
	}
	if n != 1 || len(r.Spectators) != 1 {
		t.Fatal("racing viewers overbooked seat")
	}
}

func TestSpectator33PrimarySwapsWithOwnLocalViewer(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	action(t, h, cs[0], map[string]any{"type": "add", "kind": "local", "name": "P2", "team": 1})
	host, p2 := cs[0].player, r.Players[2]
	action(t, h, cs[0], map[string]any{"type": "spectate", "target": p2.ID, "member": p2.Member, "spectating": true})
	swap33(t, h, cs[0], host, p2)
	if !host.Spectating || p2.Spectating || p2.Owner != host.ID || p2.Controller != host || r.Host != host.ID {
		t.Fatal("own-controller swap lost role or ownership")
	}
	action(t, h, cs[0], map[string]any{"type": "input", "player": p2.ID, "seq": 1, "fire": true, "forward": true})
	if !p2.Input.Fire || !p2.Input.Forward {
		t.Fatal("watching primary cannot drive own swapped-in P2")
	}
	swap33(t, h, cs[0], p2, host)
	if host.Spectating || !p2.Spectating || p2.Owner != host.ID || r.Host != host.ID {
		t.Fatal("reverse swap lost local ownership")
	}
	action(t, h, cs[0], map[string]any{"type": "rename_local", "target": p2.ID, "member": p2.Member, "name": "WATCH TWO"})
	if p2.Name != "WATCH TWO" {
		t.Fatal("owned spectator name editor lost access")
	}
}

func TestSpectator33OtherRoleKeepsUnrelatedInputHistory(t *testing.T) {
	h, cs, r := makeRoom(t, 3)
	r.Game.startMatch(r.Players)
	p := cs[0].player
	p.Input = Input{Seq: 1500, Forward: true, Fire: true}
	p.FirePending = true
	r.Game.Tanks[0].Ack = 1499
	r.Game.Tanks[0].AckSteps = 7
	role33(t, h, cs[1], true)
	if p.Input.Seq != 1500 || !p.Input.Forward || !p.Input.Fire || !p.FirePending || r.Game.Tanks[0].Ack != 1499 || r.Game.Tanks[0].AckSteps != 7 {
		t.Fatal("unrelated controller input/history was reset")
	}
	role33(t, h, cs[1], false)
	if p.Input.Seq != 1500 || !p.Input.Forward {
		t.Fatal("promotion released another controller")
	}
}
