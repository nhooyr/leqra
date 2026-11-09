package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strconv"
	"testing"
	"time"
)

func TestTwoPilotInputBudgets(t *testing.T) {
	h, clients, r := makeRoom(t, 2)
	host, guest := clients[0], clients[1]
	action(t, h, host, map[string]any{"type": "add", "kind": "local"})
	local := r.Players[2]
	if local == nil || local.Kind != "local" {
		t.Fatal("secondary pilot was not added")
	}
	r.Game.startMatch(r.Players)
	now := host.msgWindow.Add(time.Second)
	for seq := 1; seq <= clientMessageLimit; seq++ {
		for _, p := range []*Player{host.player, local} {
			b := fmt.Appendf(nil, `{"type":"input","player":%d,"member":%d,"seq":%d,"forward":true,"fire":%t}`, p.ID, p.Member, seq, seq%2 != 0)
			if err := h.handle(host, b, now); err != nil {
				t.Fatalf("pilot %d lost input %d: %v", p.ID, seq, err)
			}
		}
	}
	for _, p := range []*Player{host.player, local} {
		if p.Input.Seq != clientMessageLimit || !p.Input.Forward || !p.FirePending || p.Input.Fire {
			t.Fatalf("pilot %d lost its last movement or a fire edge: %+v", p.ID, p.Input)
		}
		b := fmt.Appendf(nil, `{"type":"input","player":%d,"seq":%d}`, p.ID, clientMessageLimit+1)
		if err := h.handle(host, b, now); err == nil {
			t.Fatalf("pilot %d was allowed to exceed its input limit", p.ID)
		}
	}
	guest.msgWindow, guest.msgCount = now, clientMessageLimit
	if err := h.handle(guest, fmt.Appendf(nil, `{"type":"input","player":%d}`, local.ID), now); err == nil {
		t.Fatal("an unowned seat ID bypassed the guest's budget")
	}
	for _, p := range []*Player{host.player, local} {
		b := fmt.Appendf(nil, `{"type":"input","player":%d,"seq":%d}`, p.ID, clientMessageLimit+1)
		if err := h.handle(host, b, now.Add(time.Second)); err != nil {
			t.Fatalf("pilot %d budget did not reset: %v", p.ID, err)
		}
	}
}

func TestLobbyActionBudgetExcludesHandshakeAndRecovers(t *testing.T) {
	h, c := newHub(4), fakeClient()
	c.requireVersion = true
	now := time.Now()
	send := func(v any, at time.Time) {
		t.Helper()
		b, ok := encodePacket(v)
		if !ok {
			t.Fatal("failed to encode command")
		}
		if err := h.handle(c, b, at); err != nil {
			t.Fatal(err)
		}
	}
	send(map[string]any{"type": "client_hello", "version": version, "protocol": protocolVersion}, now)
	send(map[string]any{"type": "publish", "roster": []SeatSpec{{Kind: "human", Name: "HOST"}}}, now)
	if c.room == nil || !c.versionOK {
		t.Fatal("host could not publish after the version handshake")
	}
	for i := 1; i < maxTanks; i++ {
		send(map[string]any{"type": "add", "kind": "bot", "difficulty": "normal"}, now)
		if p := c.room.Players[i]; p == nil || p.Kind != "bot" {
			t.Fatalf("room action budget rejected bot %d", i)
		}
	}
	drain(c)
	rename := map[string]any{"type": "rename", "name": "NEW NAME"}
	send(rename, now)
	packets := drain(c)
	if len(packets) != 1 || packets[0]["type"] != "error" || packets[0]["code"] != "action_rate" || packets[0]["action"] != "rename" || c.player.Name != "HOST" {
		t.Fatalf("rate-limited action mutated the room or did not report its rejection: %#v", packets)
	}
	send(map[string]any{"type": "chat", "channel": "opponent", "text": "hello"}, now)
	packets = drain(c)
	if len(packets) != 1 || packets[0]["code"] != "action_rate" || packets[0]["channel"] != "opponent" {
		t.Fatalf("rate-limited chat lost its channel: %#v", packets)
	}
	send(rename, now.Add(time.Second))
	if c.player.Name != "NEW NAME" {
		t.Fatal("rate-limited action could not be retried in the next window")
	}
}

func TestDefaultRoomLimit(t *testing.T) {
	if maxRoomLimit != 32768 {
		t.Fatalf("default room limit = %d, want 32768", maxRoomLimit)
	}
	h := newHub(maxRoomLimit)
	// Reserve all but one entry without building 32,767 unrelated simulations.
	reserved := &Room{}
	for i := 1; i < maxRoomLimit; i++ {
		h.rooms[strconv.Itoa(i)] = reserved
	}
	last := fakeClient()
	action(t, h, last, map[string]any{"type": "create"})
	if last.room == nil || len(h.rooms) != maxRoomLimit {
		t.Fatal("the last available room was not created")
	}
	denied := fakeClient()
	action(t, h, denied, map[string]any{"type": "join", "code": "EXTRA ROOM"})
	if !hasError(denied, "server_full") {
		t.Fatal("new rooms can exceed the configured ceiling")
	}
	action(t, h, denied, map[string]any{"type": "join", "code": last.room.Code})
	if denied.room != last.room {
		t.Fatal("an existing room became unjoinable at capacity")
	}
}

func TestFreshCombatJoinKeepsExistingGuestReady(t *testing.T) {
	h, clients, r := makeRoom(t, 2)
	guest := clients[1].player
	action(t, h, clients[1], map[string]any{"type": "ready", "ready": true})
	newcomer := fakeClient()
	action(t, h, newcomer, map[string]any{"type": "join", "code": r.Code, "name": "NEWCOMER"})
	if !guest.Ready || newcomer.player == nil || newcomer.player.Spectating || newcomer.player.Ready || canStart(r) {
		t.Fatal("joining a combat seat changed prior readiness or bypassed the new guest's ready action")
	}
	action(t, h, newcomer, map[string]any{"type": "ready", "ready": true})
	if !canStart(r) {
		t.Fatal("the existing guest must not need to ready up again")
	}
}

func TestShutdownWaitsForActiveHTTPRequest(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	active, release, draining := make(chan struct{}), make(chan struct{}), make(chan struct{})
	srv := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		close(active)
		select {
		case <-release:
			_, _ = io.WriteString(w, "completed")
		case <-ctx.Done():
		}
	})}
	srv.RegisterOnShutdown(func() { close(draining) })
	stopped := make(chan os.Signal, 1)
	defer close(stopped)
	serverResult, requestResult := make(chan error, 1), make(chan error, 1)
	app := newApp(1, nil)
	go func() { serverResult <- app.serve(srv, listener, stopped) }()
	go func() {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, "http://"+listener.Addr().String(), nil)
		if err == nil {
			var res *http.Response
			res, err = http.DefaultClient.Do(req)
			if err == nil {
				defer res.Body.Close()
				var body []byte
				body, err = io.ReadAll(res.Body)
				if err == nil && string(body) != "completed" {
					err = fmt.Errorf("incomplete response: %q", body)
				}
			}
		}
		requestResult <- err
	}()
	select {
	case <-active:
	case <-ctx.Done():
		t.Fatal("request did not start")
	}
	stopped <- os.Interrupt
	select {
	case <-draining:
	case <-ctx.Done():
		t.Fatal("shutdown did not close the listener")
	}
	select {
	case err := <-serverResult:
		t.Fatalf("server exited during an active request: %v", err)
	case <-time.After(25 * time.Millisecond):
	}
	close(release)
	if err := <-requestResult; err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-serverResult:
		if !errors.Is(err, http.ErrServerClosed) {
			t.Fatal(err)
		}
	case <-ctx.Done():
		t.Fatal("server did not exit after the request drained")
	}
}
