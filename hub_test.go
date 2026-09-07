package main

import (
	"encoding/json"
	"math"
	"strings"
	"testing"
	"time"
)

func fakeClient() *Client {
	return &Client{send: make(chan []byte, 4096), done: make(chan struct{}), mapGeneration: -1, born: time.Now()}
}
func action(t *testing.T, h *Hub, c *Client, v any) {
	t.Helper()
	b, _ := json.Marshal(v)
	if err := h.handle(c, b, time.Now()); err != nil {
		t.Fatal(err)
	}
}
func makeRoom(t *testing.T, n int) (*Hub, []*Client, *Room) {
	t.Helper()
	h := newHub(4)
	cs := []*Client{}
	for i := 0; i < n; i++ {
		c := fakeClient()
		h.addClient(c)
		cs = append(cs, c)
		if i == 0 {
			action(t, h, c, map[string]any{"type": "create", "name": "HOST"})
			c.room.Game.Rules.TeamMode = "teams" // Explicit historical fixture, not a production default.
			c.player.Team = 1
		} else {
			action(t, h, c, map[string]any{"type": "join", "code": cs[0].room.Code, "name": "GUEST"})
		}
	}
	return h, cs, cs[0].room
}
func drain(c *Client) []map[string]any {
	var out []map[string]any
	for len(c.send) > 0 {
		var v map[string]any
		_ = json.Unmarshal(<-c.send, &v)
		out = append(out, v)
	}
	return out
}
func hasError(c *Client, code string) bool {
	for _, m := range drain(c) {
		if m["type"] == "error" && m["code"] == code {
			return true
		}
	}
	return false
}
func readyAll(t *testing.T, h *Hub, cs []*Client) {
	for _, c := range cs {
		action(t, h, c, map[string]any{"type": "ready", "ready": true})
	}
}
func TestRoomCodeAndTokens(t *testing.T) {
	h, cs, r := makeRoom(t, 4)
	_ = h
	if !validCode(r.Code) || len(r.Code) != 6 {
		t.Fatal("invalid room code")
	}
	tokens := map[string]bool{}
	for _, c := range cs {
		token := c.player.Token
		if len(token) < 40 || tokens[token] {
			t.Fatal("unsafe or duplicate token")
		}
		tokens[token] = true
	}
	for _, m := range drain(cs[0]) {
		if m["type"] != "welcome" {
			b, _ := json.Marshal(m)
			for token := range tokens {
				if strings.Contains(string(b), token) {
					t.Fatal("token leaked in broadcast")
				}
			}
		}
	}
}
func TestJoinLimitAndInvalidRoom(t *testing.T) {
	h, cs, r := makeRoom(t, maxTanks)
	extra := fakeClient()
	action(t, h, extra, map[string]any{"type": "join", "code": r.Code})
	if extra.player == nil || !extra.player.Spectating || len(r.Spectators) != 1 {
		t.Fatal("fifth visitor did not become a spectator")
	}
	extra = fakeClient()
	action(t, h, extra, map[string]any{"type": "join", "code": "bad\x00code"})
	if !hasError(extra, "bad_code") {
		t.Fatal("invalid code accepted")
	}
	action(t, h, cs[0], map[string]any{"type": "create"})
	if !hasError(cs[0], "already_joined") {
		t.Fatal("double join")
	}
}
func TestOnlyReadyHostCanStart(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	action(t, h, cs[0], map[string]any{"type": "start"})
	if !hasError(cs[0], "not_ready") {
		t.Fatal("unready match start")
	}
	readyAll(t, h, cs)
	action(t, h, cs[1], map[string]any{"type": "start"})
	if !hasError(cs[1], "not_host") {
		t.Fatal("guest started match")
	}
	action(t, h, cs[0], map[string]any{"type": "start"})
	if r.Game.Phase != "countdown" {
		t.Fatal("ready match did not start")
	}
}
func TestReconnectPreservesPilotAndScore(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	p := cs[1].player
	r.Game.Scores[1] = 3
	h.removeClient(cs[1])
	c := fakeClient()
	action(t, h, c, map[string]any{"type": "join", "code": r.Code, "token": p.Token})
	if c.player != p || p.ID != 1 || r.Game.Scores[1] != 3 || p.Client != c {
		t.Fatal("session not resumed")
	}
}
func TestActiveSessionCannotBeStolen(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	c := fakeClient()
	action(t, h, c, map[string]any{"type": "join", "code": r.Code, "token": cs[0].player.Token})
	if !hasError(c, "session_active") || c.player != nil {
		t.Fatal("active pilot replaced")
	}
}
func TestExpiredReconnectRejected(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	p := cs[1].player
	h.removeClient(cs[1])
	p.DisconnectedAt = time.Now().Add(-21 * time.Second)
	c := fakeClient()
	action(t, h, c, map[string]any{"type": "join", "code": r.Code, "token": p.Token})
	if !hasError(c, "resume_expired") {
		t.Fatal("expired token accepted")
	}
	if c.player != nil {
		t.Fatal("silently created replacement pilot")
	}
}
func TestHostTransferAndRoomCleanup(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	h.removeClient(cs[0])
	if r.Host != 1 {
		t.Fatal("host did not transfer")
	}
	h.removeClient(cs[1])
	future := time.Now().Add(21 * time.Second)
	h.tick(future)
	if len(h.rooms) != 0 {
		t.Fatal("empty room retained")
	}
}
func TestForgedStateIgnoredAndControlsClamped(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	r.Game.startMatch(r.Players)
	r.Game.Phase = "playing"
	p := cs[0].player
	tank := r.Game.Tanks[0]
	x := tank.X
	action(t, h, cs[0], map[string]any{"type": "input", "seq": 1, "stickX": 9999, "stickY": 9999, "x": 100000, "score": 999, "speed": 100000, "owner": 1})
	if math.Hypot(p.Input.StickX, p.Input.StickY) > 1.00001 {
		t.Fatal("unbounded analog input")
	}
	if tank.X != x || r.Game.Scores[0] != 0 {
		t.Fatal("client forged authoritative state")
	}
	action(t, h, cs[0], map[string]any{"type": "input", "seq": 1, "fire": true})
	if p.Input.Fire {
		t.Fatal("duplicate sequence accepted")
	}
}
func TestStaleInputIsNeutral(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	r.Game.startMatch(r.Players)
	openArena(r.Game)
	r.Game.Phase = "playing"
	tank := r.Game.Tanks[0]
	tank.X = 90
	tank.Y = 210
	tank.Angle = 0
	cs[0].player.Input = Input{Seq: 1, Forward: true, Fire: true}
	cs[0].player.InputAt = time.Now().Add(-time.Second)
	x := tank.X
	h.tick(time.Now())
	if tank.X != x || len(r.Game.Bullets) != 0 {
		t.Fatal("stale movement/fire continued")
	}
}
func TestRoomsIsolated(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	other := fakeClient()
	action(t, h, other, map[string]any{"type": "create", "name": "OTHER"})
	if r == other.room {
		t.Fatal("shared room")
	}
	drain(other)
	readyAll(t, h, cs)
	action(t, h, cs[0], map[string]any{"type": "start"})
	for _, msg := range drain(other) {
		if msg["type"] == "state" {
			t.Fatal("room state leaked")
		}
	}
	if other.room.Game.Phase != "lobby" {
		t.Fatal("other room started")
	}
}
func TestMalformedAndFloodedInputRejected(t *testing.T) {
	h, cs, _ := makeRoom(t, 1)
	c := cs[0]
	if err := h.handle(c, []byte(`{"type":"input","seq":2,"stickX":1e999}`), time.Now()); err == nil {
		t.Fatal("invalid JSON float accepted")
	}
	c.msgCount = 100
	c.msgWindow = time.Now()
	if err := h.handle(c, []byte(`{"type":"input","seq":3}`), time.Now()); err == nil {
		t.Fatal("message flood allowed")
	}
}
func TestNamesAreBoundedAndSafe(t *testing.T) {
	for _, s := range []string{"<img src=x onerror=alert(1)>", "\u202e\n\t", strings.Repeat("Å", 100)} {
		name := cleanName(s)
		if len([]rune(name)) > 16 || strings.ContainsAny(name, "<>\n\r\u202e") {
			t.Fatalf("unsafe name: %q", name)
		}
	}
}
func TestServerRoomLimit(t *testing.T) {
	h := newHub(1)
	c := fakeClient()
	action(t, h, c, map[string]any{"type": "create"})
	other := fakeClient()
	action(t, h, other, map[string]any{"type": "create"})
	if !hasError(other, "server_full") {
		t.Fatal("room cap ignored")
	}
}
func TestLateJoinWaitsForNextRound(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	r.Game.startMatch(r.Players)
	r.Game.Phase = "playing"
	c := fakeClient()
	action(t, h, c, map[string]any{"type": "join", "code": r.Code})
	if c.player == nil || r.Game.Tanks[c.player.ID].Alive {
		t.Fatal("midround player spawned")
	}
	if cs[0].room != r {
		t.Fatal("existing players changed")
	}
	r.Game.startRound(r.Players)
	if !r.Game.Tanks[c.player.ID].Alive {
		t.Fatal("late join missing next round")
	}
}
func TestLatestSnapshotIncludesNewMaze(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	r.Game.startMatch(r.Players)
	drain(cs[0])
	h.sendState(cs[0], r)
	ms := drain(cs[0])
	if ms[0]["world"] == nil {
		t.Fatal("initial maze missing")
	}
	h.sendState(cs[0], r)
	ms = drain(cs[0])
	if ms[0]["world"] != nil {
		t.Fatal("maze resent every tick")
	}
	r.Game.startRound(r.Players)
	h.sendState(cs[0], r)
	ms = drain(cs[0])
	if ms[0]["world"] == nil {
		t.Fatal("new round maze missing")
	}
}

func TestNewPilotCannotInheritDepartedCombatIdentity(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	readyAll(t, h, cs)
	action(t, h, cs[0], map[string]any{"type": "start"})
	r.Game.Scores[0] = 3
	action(t, h, cs[0], map[string]any{"type": "leave"})
	extra := fakeClient()
	action(t, h, extra, map[string]any{"type": "join", "code": r.Code, "name": "NEW"})
	if extra.player == nil || extra.player.ID != 2 {
		t.Fatal("new pilot reused an old match identity")
	}
	if r.Game.Scores[0] != 3 || r.Game.Tanks[0].Alive {
		t.Fatal("departed pilot's historical score changed")
	}
}

// Versioned regression fixtures request the former Teams format explicitly.
func legacyTeamRules36() MatchRules { r := defaultRules(); r.TeamMode = "teams"; return r }
