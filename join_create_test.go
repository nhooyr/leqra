package main

import (
	"encoding/json"
	"strings"
	"sync"
	"testing"
	"time"
)

func welcomeMessage(t *testing.T, c *Client) map[string]any {
	t.Helper()
	for _, m := range drain(c) {
		if m["type"] == "welcome" {
			return m
		}
	}
	t.Fatal("missing welcome")
	return nil
}

func TestJoinMissingCreatesRequestedRoomAndHost(t *testing.T) {
	h := newHub(4)
	c := fakeClient()
	action(t, h, c, map[string]any{"type": "join", "code": "ABC234", "name": "  Snow  Fox  "})
	r := h.rooms["ABC234"]
	if r == nil || c.room != r || c.player == nil || r.Host != c.player.ID || r.Host != 0 || connectedPlayers(r) != 1 {
		t.Fatal("fresh join did not create the requested room with its first pilot as host")
	}
	if c.player.Name != "Snow Fox" || c.player.Ready || r.Game.Phase != "lobby" || r.NextMember != 1 {
		t.Fatal("new room bypassed callsign/readiness/lobby setup")
	}
	m := welcomeMessage(t, c)
	if m["created"] != true || m["resumed"] != false || m["room"] != "ABC234" || m["id"] != float64(0) || m["token"] != c.player.Token {
		t.Fatal("incorrect create-on-join welcome", m)
	}
}

func TestJoinCreateNormalizesCodeAndName(t *testing.T) {
	for _, code := range []string{"abc234", "  ABC234  ", "\tAbC234\n"} {
		t.Run(code, func(t *testing.T) {
			h := newHub(4)
			c := fakeClient()
			action(t, h, c, map[string]any{"type": "join", "code": code})
			if len(h.rooms) != 1 || c.room != h.rooms["ABC234"] || c.player.Name != "PILOT" {
				t.Fatal("normalization/default callsign failed")
			}
		})
	}
}

func TestJoinExistingPreservesRoomAndHost(t *testing.T) {
	h := newHub(4)
	host, guest := fakeClient(), fakeClient()
	action(t, h, host, map[string]any{"type": "join", "code": "ABC234", "name": "HOST"})
	r := host.room
	token := host.player.Token
	game := r.Game
	host.player.Ready = true
	r.Game.Scores[0] = 3
	action(t, h, guest, map[string]any{"type": "join", "code": "abc234", "name": "GUEST"})
	if len(h.rooms) != 1 || guest.room != r || r.Host != 0 || r.Game != game || r.Game.Scores[0] != 3 || !host.player.Ready || host.player.Token != token {
		t.Fatal("join replaced or modified an existing host/room")
	}
	if m := welcomeMessage(t, guest); m["created"] != false || m["resumed"] != false {
		t.Fatal("existing-room join reported creation", m)
	}
}

func TestJoinCreateHonorsRoomLimit(t *testing.T) {
	h := newHub(1)
	host, denied, guest := fakeClient(), fakeClient(), fakeClient()
	action(t, h, host, map[string]any{"type": "join", "code": "ABC234"})
	action(t, h, denied, map[string]any{"type": "join", "code": "DEF567"})
	if !hasError(denied, "server_full") || denied.room != nil || len(h.rooms) != 1 || h.rooms["DEF567"] != nil {
		t.Fatal("named creation bypassed capacity or left an orphan")
	}
	action(t, h, denied, map[string]any{"type": "create"})
	if !hasError(denied, "server_full") {
		t.Fatal("random creation bypassed capacity")
	}
	action(t, h, guest, map[string]any{"type": "join", "code": "ABC234"})
	if guest.room != host.room || len(h.rooms) != 1 {
		t.Fatal("room limit wrongly blocked joining an existing room")
	}
}

func TestJoinCreateRejectsInvalidCodesWithoutSideEffects(t *testing.T) {
	for _, code := range []string{"", "  ", "bad\x00name", "bad\nname", "bad\u2028name", strings.Repeat("a", 129), strings.Repeat("💥", 129)} {
		t.Run(code, func(t *testing.T) {
			h := newHub(4)
			c := fakeClient()
			action(t, h, c, map[string]any{"type": "join", "code": code})
			if !hasError(c, "bad_code") || len(h.rooms) != 0 || c.room != nil || c.player != nil {
				t.Fatal("invalid code created a room/seat")
			}
		})
	}
}

func TestJoinFullDoesNotRecreateRoom(t *testing.T) {
	h, cs, r := makeRoom(t, maxTanks)
	game := r.Game
	token := cs[0].player.Token
	extra := fakeClient()
	action(t, h, extra, map[string]any{"type": "join", "code": r.Code})
	if (extra.player == nil || !extra.player.Spectating) || len(h.rooms) != 1 || h.rooms[r.Code] != r || r.Game != game || r.Host != 0 || cs[0].player.Token != token || extra.room != r {
		t.Fatal("full room was overwritten or a fifth pilot accepted")
	}
}

func TestConcurrentJoinMissingCreatesOneHost(t *testing.T) {
	h := newHub(4)
	const count = 24
	cs := make([]*Client, count)
	errors := make([]error, count)
	data := []byte(`{"type":"join","code":"ABC234","name":"RACER"}`)
	start := make(chan struct{})
	var wg sync.WaitGroup
	for i := range cs {
		cs[i] = fakeClient()
		wg.Add(1)
		go func(i int) { defer wg.Done(); <-start; errors[i] = h.handle(cs[i], data, time.Now()) }(i)
	}
	close(start)
	wg.Wait()
	r := h.rooms["ABC234"]
	if len(h.rooms) != 1 || r == nil || connectedPlayers(r) != maxTanks+maxSpectators || len(r.Spectators) != maxSpectators || r.Host != 0 {
		t.Fatal("concurrent join did not create one full room/host")
	}
	created, joined, rejected := 0, 0, 0
	tokens := map[string]bool{}
	for i, c := range cs {
		if errors[i] != nil {
			t.Fatal(errors[i])
		}
		for _, m := range drain(c) {
			switch m["type"] {
			case "welcome":
				joined++
				if m["created"] == true {
					created++
					if m["id"] != float64(r.Host) {
						t.Fatal("creator is not host")
					}
				}
				token := m["token"].(string)
				if tokens[token] {
					t.Fatal("duplicate credentials")
				}
				tokens[token] = true
			case "error":
				if m["code"] != "room_capacity" {
					t.Fatal(m)
				}
				rejected++
			}
		}
		if c.room != nil && c.room != r {
			t.Fatal("two room instances created for one code")
		}
	}
	if created != 1 || joined != maxTanks+maxSpectators || rejected != count-maxTanks-maxSpectators {
		t.Fatalf("created=%d joined=%d rejected=%d", created, joined, rejected)
	}
}

func TestConcurrentNamedCreatesRespectServerCapacity(t *testing.T) {
	h := newHub(2)
	codes := []string{"ABC234", "DEF567", "GHJ789", "KLM234", "NPQ567", "RST789"}
	cs := make([]*Client, len(codes))
	errs := make([]error, len(codes))
	var wg sync.WaitGroup
	start := make(chan struct{})
	for i, code := range codes {
		cs[i] = fakeClient()
		data, _ := json.Marshal(map[string]any{"type": "join", "code": code})
		wg.Add(1)
		go func(i int, b []byte) { defer wg.Done(); <-start; errs[i] = h.handle(cs[i], b, time.Now()) }(i, data)
	}
	close(start)
	wg.Wait()
	if len(h.rooms) != 2 {
		t.Fatal("concurrent named creations exceeded capacity")
	}
	joined := 0
	for i, c := range cs {
		if errs[i] != nil {
			t.Fatal(errs[i])
		}
		if c.room != nil {
			joined++
			if c.room.Host != c.player.ID {
				t.Fatal("new pilot is not host")
			}
		} else if !hasError(c, "server_full") {
			t.Fatal("wrong capacity error")
		}
	}
	if joined != 2 {
		t.Fatal("incorrect creation count")
	}
}

func TestMissingRoomResumeNeverCreatesRoom(t *testing.T) {
	h := newHub(4)
	c := fakeClient()
	action(t, h, c, map[string]any{"type": "join", "code": "ABC234", "token": "old-credential"})
	if !hasError(c, "room_missing") || len(h.rooms) != 0 || c.room != nil {
		t.Fatal("background resume resurrected a missing room")
	}
	// A deliberate fresh join is separate and is allowed with the exact same code.
	action(t, h, c, map[string]any{"type": "join", "code": "ABC234", "name": "NEW HOST"})
	if c.room == nil || c.room.Host != c.player.ID || c.player.Token == "old-credential" {
		t.Fatal("explicit fresh join did not create a new host")
	}
	other := fakeClient()
	action(t, h, other, map[string]any{"type": "join", "code": "ABC234", "token": "old-credential"})
	if !hasError(other, "resume_expired") || connectedPlayers(c.room) != 1 || c.room.Host != c.player.ID {
		t.Fatal("old credential captured a newly created room")
	}
}

func TestNamedRoomReconnectKeepsHostAndIdentity(t *testing.T) {
	h := newHub(4)
	c := fakeClient()
	action(t, h, c, map[string]any{"type": "join", "code": "ABC234"})
	p := c.player
	r := c.room
	h.removeClient(c)
	resumed := fakeClient()
	action(t, h, resumed, map[string]any{"type": "join", "code": "ABC234", "token": p.Token})
	if resumed.room != r || resumed.player != p || r.Host != p.ID {
		t.Fatal("named room did not reconnect the same host")
	}
	m := welcomeMessage(t, resumed)
	if m["created"] != false || m["resumed"] != true {
		t.Fatal("reconnection treated as new creation", m)
	}
}

func TestExpiredNamedRoomCanBeRecreated(t *testing.T) {
	h := newHub(4)
	old := fakeClient()
	action(t, h, old, map[string]any{"type": "join", "code": "ABC234"})
	oldRoom := old.room
	oldToken := old.player.Token
	h.removeClient(old)
	h.tick(time.Now().Add(reconnectGrace + time.Second))
	if h.rooms["ABC234"] != nil {
		t.Fatal("old room not cleaned up")
	}
	fresh := fakeClient()
	action(t, h, fresh, map[string]any{"type": "join", "code": "ABC234", "name": "NEW HOST"})
	if fresh.room == nil || fresh.room == oldRoom || fresh.room.Host != 0 || fresh.player.Token == oldToken || fresh.room.Game.Phase != "lobby" {
		t.Fatal("recreated room did not reset identity/state")
	}
}

func TestNamedHostHasNormalRoomControls(t *testing.T) {
	h := newHub(4)
	host, guest := fakeClient(), fakeClient()
	action(t, h, host, map[string]any{"type": "join", "code": "ABC234"})
	r := host.room
	action(t, h, host, map[string]any{"type": "rename", "name": "CAPTAIN"})
	action(t, h, host, map[string]any{"type": "ready", "ready": true})
	action(t, h, host, map[string]any{"type": "start"})
	if !hasError(host, "not_ready") {
		t.Fatal("single host could start match")
	}
	action(t, h, guest, map[string]any{"type": "join", "code": "ABC234"})
	action(t, h, guest, map[string]any{"type": "ready", "ready": true})
	action(t, h, guest, map[string]any{"type": "start"})
	if !hasError(guest, "not_host") {
		t.Fatal("guest can start")
	}
	action(t, h, host, map[string]any{"type": "start"})
	if r.Game.Phase != "countdown" || host.player.Name != "CAPTAIN" {
		t.Fatal("host start/rename failed")
	}
	action(t, h, host, map[string]any{"type": "kick", "target": guest.player.ID, "member": guest.player.Member})
	if guest.room != nil || connectedPlayers(r) != 1 || r.Host != 0 {
		t.Fatal("new host kick controls failed")
	}
}

func TestNamedRoomJoinDoesNotMoveAlreadyJoinedPilot(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	c := cs[0]
	action(t, h, c, map[string]any{"type": "join", "code": "ABC234"})
	if !hasError(c, "already_joined") || c.room != r || len(h.rooms) != 1 || r.Host != 0 {
		t.Fatal("join changed current membership or created an extra room")
	}
}

func TestRandomRoomCreateStillReportsCreation(t *testing.T) {
	h := newHub(4)
	c := fakeClient()
	action(t, h, c, map[string]any{"type": "create", "code": "000000"})
	if c.room == nil || !validCode(c.room.Code) || c.room.Host != 0 {
		t.Fatal("random create regressed")
	}
	if m := welcomeMessage(t, c); m["created"] != true {
		t.Fatal("random creation not identified", m)
	}
}
