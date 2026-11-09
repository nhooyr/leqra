package main

import (
	"bufio"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestInfiniteShotBounceAndRespawn(t *testing.T) {
	a := newSeededInfiniteArena(16)
	now := time.Now()
	first, second := a.join(fakeClient(), "First", now), a.join(fakeClient(), "Second", now)
	a.nextBot = 1000
	a.tick = 60
	var wall Wall
	for _, candidate := range a.maze.wallsNear(-500, -500, 500, 500) {
		if candidate.Axis == "v" {
			wall = candidate
			break
		}
	}
	if wall.H == 0 {
		t.Fatal("test seed needs a vertical wall")
	}
	y := wall.Y + wall.H/2
	first.X, first.Y, first.Angle, first.Protected = wall.X-30, y, 0, false
	second.X, second.Y, second.Protected = wall.X+wall.W+30, y, false
	for range 40 {
		a.drive(first, Input{Forward: true})
	}
	if first.X > wall.X-tankRadius {
		t.Fatalf("tank moved through wall: x=%f, wall=%+v", first.X, wall)
	}

	bullet := infiniteBullet{Owner: first.ID, X: first.X, Y: y, VX: 282}
	if !a.advanceBullet(&bullet, 60, 0) || bullet.Bounces != 1 || bullet.VX >= 0 {
		t.Fatalf("expected a surviving reflected bullet, got %+v", bullet)
	}
	if first.HP != infiniteMaxHP || second.HP != infiniteMaxHP {
		t.Fatal("shot damaged its owner or a target behind a wall")
	}

	second.X, second.HP = wall.X-48, 1
	bullet = infiniteBullet{Owner: first.ID, X: first.X, Y: y}
	if a.advanceBullet(&bullet, -20, 0) || second.HP != 0 || first.Score != 1 || second.Score != -1 {
		t.Fatal("a lethal hit must consume the projectile, add a point, and deduct a point")
	}
	for range infiniteRespawnTicks - 1 {
		a.step(now)
	}
	if second.HP != 0 {
		t.Fatal("pilot respawned early")
	}
	a.step(now)
	if second.HP != infiniteMaxHP || second.Score != -1 || !second.Protected || a.maze.blocked(second.X, second.Y, tankRadius) {
		t.Fatalf("respawn lost score, protection, or a valid spawn position: %+v", second)
	}
}

func TestInfiniteFireEdgeAndProximitySnapshot(t *testing.T) {
	a := newSeededInfiniteArena(37)
	now := time.Now()
	c := fakeClient()
	p := a.join(c, "Pilot", now)
	other := a.join(fakeClient(), "Distant", now)
	other.X = p.X - infiniteSight*2
	a.nextBot = 1000
	drain(c)
	a.setInput(p, Input{Fire: true}, now)
	a.setInput(p, Input{}, now)
	a.step(now)
	if a.nextBullet != 1 {
		t.Fatal("press and release between ticks lost the shot")
	}
	a.step(now)
	if a.nextBullet != 1 {
		t.Fatal("one fire edge produced more than one shot")
	}
	a.broadcast()
	var packet infiniteSnapshot
	if err := json.Unmarshal(<-c.send, &packet); err != nil {
		t.Fatal(err)
	}
	if packet.Type != "state" || packet.Players != 2 || len(packet.Tanks) != 1 || packet.Tanks[0].ID != p.ID || packet.Leaders == nil {
		t.Fatalf("invalid proximity snapshot: %+v", packet)
	}

	a.remove(p)
	a.remove(other)
	if len(a.pilots)+len(a.bullets) != 0 {
		t.Fatal("empty arena retained match state")
	}
}

func TestInfinitePickupsAndOneHitCombat(t *testing.T) {
	a := newSeededInfiniteArena(37)
	now := time.Now()
	shooter := a.join(fakeClient(), "Shooter", now)
	target := a.join(fakeClient(), "Target", now)
	a.tick = 1
	a.populatePickups()
	if len(a.pickups) == 0 {
		t.Fatal("joining a live arena did not populate nearby pickups")
	}
	target.kit.Invulnerable, target.Protected = 0, false
	a.pickups = []Pickup{{X: target.X, Y: target.Y, Type: "shield", Life: 30}}
	a.collectPickup(target)
	if target.kit.ShieldCharges != 1 || a.pickups[0].Life != 0 {
		t.Fatal("a shield must be collected and removed exactly once")
	}
	a.hurt(target, shooter.ID)
	if target.HP != 1 || target.kit.ShieldCharges != 0 || !target.Protected {
		t.Fatal("shield did not absorb the shot")
	}
	for range 21 {
		a.advanceEquipment(target)
	}
	a.hurt(target, target.ID)
	if target.HP != 1 {
		t.Fatal("a tank damaged itself")
	}
	a.hurt(target, shooter.ID)
	if target.HP != 0 || target.Score != -1 || shooter.Score != 1 {
		t.Fatal("one unshielded hit must kill and adjust both scores")
	}
}

func TestInfiniteLeaderboardRanksTenIncludingBots(t *testing.T) {
	a := newSeededInfiniteArena(51)
	now := time.Now()
	p := a.join(fakeClient(), "Pilot", now)
	bot := a.addPilot("Top bot", true, p.X, p.Y, 3, 6)
	bot.Score, bot.HP = 2, 0
	p.Score = -1
	for range 12 {
		a.addPilot("Other bot", true, p.X, p.Y, 3, 6)
	}
	leaders := a.leaderboard(nil)
	if len(leaders) != 10 || leaders[0].Name != "Top bot" || leaders[0].Score != 2 || !leaders[0].Bot || leaders[9].ID != 11 {
		t.Fatalf("unexpected leaders: %+v", leaders)
	}
	a.pilots = a.pilots[:3]
	leaders = a.leaderboard(leaders)
	if leaders[0].ID != bot.ID || leaders[1].Score != 0 || leaders[2].ID != p.ID || leaders[2].Score != -1 {
		t.Fatalf("leaderboard dropped a respawning bot, zero, or negative score: %+v", leaders)
	}
}

func TestInfiniteWebSocketSharesAnAuthoritativeArena(t *testing.T) {
	app := newApp(4, nil)
	app.infinite.public = newSeededInfiniteArena(99)
	done := make(chan struct{})
	go app.infinite.run(done)
	t.Cleanup(func() {
		close(done)
		app.infinite.close()
	})
	server := httptest.NewServer(app.handler())
	t.Cleanup(server.Close)

	_, bad := dialInfinite(t, server.URL, map[string]string{"type": "join", "version": "outdated"})
	var refusal infiniteMessage
	readInfinitePacket(t, bad, &refusal)
	if refusal.Type != "error" {
		t.Fatalf("outdated client accepted: %+v", refusal)
	}

	type welcome struct {
		Type string `json:"type"`
		ID   int    `json:"id"`
		Seed uint32 `json:"seed"`
	}
	var clients [2]welcome
	for i, name := range []string{"First", "Second"} {
		_, reader := dialInfinite(t, server.URL, map[string]string{"type": "join", "version": version, "name": name})
		w := &clients[i]
		readInfinitePacket(t, reader, w)
		if w.Type != "welcome" || w.Seed != 99 || w.ID == 0 {
			t.Fatalf("invalid welcome: %+v", w)
		}
		var state infiniteSnapshot
		readInfinitePacket(t, reader, &state)
		if state.Type != "state" || state.Players != i+1 {
			t.Fatalf("invalid initial world state: %+v", state)
		}
		for _, client := range clients[:i+1] {
			found := false
			for _, tank := range state.Tanks {
				found = found || tank.ID == client.ID
			}
			if !found {
				t.Fatalf("nearby pilot %d absent from state: %+v", client.ID, state)
			}
		}
	}
	if clients[0].ID == clients[1].ID {
		t.Fatal("two connections acquired the same pilot ID")
	}
}

func dialInfinite(t *testing.T, url string, first map[string]string) (net.Conn, *bufio.Reader) {
	t.Helper()
	host := strings.TrimPrefix(url, "http://")
	c, err := net.Dial("tcp", host)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = c.Close() })
	if err := c.SetDeadline(time.Now().Add(3 * time.Second)); err != nil {
		t.Fatal(err)
	}
	_, err = fmt.Fprintf(c, "GET /ws/infinite HTTP/1.1\r\nHost: %s\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nOrigin: %s\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n", host, url)
	if err != nil {
		t.Fatal(err)
	}
	reader := bufio.NewReader(c)
	response, err := http.ReadResponse(reader, &http.Request{Method: "GET"})
	if err != nil {
		t.Fatal(err)
	}
	if response.StatusCode != http.StatusSwitchingProtocols {
		t.Fatalf("expected WebSocket upgrade, got %s", response.Status)
	}
	message, err := json.Marshal(first)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := c.Write(maskedFrame(1, true, message)); err != nil {
		t.Fatal(err)
	}
	return c, reader
}

func readInfinitePacket(t *testing.T, reader *bufio.Reader, target any) {
	t.Helper()
	var header [2]byte
	if _, err := io.ReadFull(reader, header[:]); err != nil {
		t.Fatal(err)
	}
	if header[0] != 129 {
		t.Fatalf("expected a text frame, got %d", header[0])
	}
	size := int(header[1])
	if size == 126 {
		if _, err := io.ReadFull(reader, header[:]); err != nil {
			t.Fatal(err)
		}
		size = int(binary.BigEndian.Uint16(header[:]))
	}
	packet := make([]byte, size)
	if _, err := io.ReadFull(reader, packet); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(packet, target); err != nil {
		t.Fatalf("decoding %q: %v", packet, err)
	}
}

func TestPublicInfinityReclaimsIdleSeat(t *testing.T) {
	server := newInfiniteServer(newHub(4))
	now := time.Now()
	c := fakeClient()
	if !server.admit(c) {
		t.Fatal("could not open a test Infinity connection")
	}
	conn, reject := server.join(c, infiniteMessage{}, now)
	if reject != "" {
		t.Fatal(reject)
	}
	server.public.setInput(conn.pilot, Input{}, now.Add(4*time.Minute))
	aim := Input{AimOnly: true, StickX: 1}
	aimedAt := now.Add(4*time.Minute + 30*time.Second)
	server.public.setInput(conn.pilot, aim, aimedAt)
	expiry := aimedAt.Add(infinitePublicIdle)
	server.public.spawn(conn.pilot, conn.pilot.X, conn.pilot.Y, 2, 5)
	server.public.setInput(conn.pilot, aim, expiry.Add(-time.Second))
	server.step(expiry.Add(-time.Nanosecond))
	if server.public.players != 1 {
		t.Fatal("pilot was removed before five minutes elapsed from the last active control")
	}
	server.public.setInput(conn.pilot, Input{}, expiry)
	server.step(expiry)
	select {
	case <-c.done:
	default:
		t.Fatal("neutral keepalive or stationary aim retained a public socket")
	}
	if server.public.players != 0 || len(server.connections) != 0 {
		t.Fatal("idle public pilot still occupies admission capacity")
	}
}

func TestPrivateInfinityAuthenticatesAndIsolatesRoomPilots(t *testing.T) {
	h, clients, firstRoom := makeRoom(t, 2)
	otherHost := fakeClient()
	h.addClient(otherHost)
	action(t, h, otherHost, map[string]any{"type": "create", "name": "Other host"})
	otherRoom := otherHost.room
	h.mu.Lock()
	firstRoom.Game.Rules.Infinity = true
	otherRoom.Game.Rules.Infinity = true
	h.startRoomInfinity(firstRoom)
	h.startRoomInfinity(otherRoom)
	h.mu.Unlock()
	server := newInfiniteServer(h)
	now := time.Now()
	join := func(code, token string) (infiniteConnection, *Client, string) {
		t.Helper()
		c := fakeClient()
		if !server.admit(c) {
			t.Fatal("could not open a test Infinity connection")
		}
		m, reject := server.join(c, infiniteMessage{Name: "Forged name", Code: code, Token: token}, now)
		if reject != "" {
			server.remove(c)
		}
		return m, c, reject
	}
	if _, _, reject := join(firstRoom.Code, otherHost.player.Token); reject == "" {
		t.Fatal("cross-room token admitted")
	}
	if _, _, reject := join(firstRoom.Code, ""); reject == "" {
		t.Fatal("private room join without token admitted")
	}
	first, firstSocket, reject := join(firstRoom.Code, clients[0].player.Token)
	if reject != "" || first.pilot.Name != clients[0].player.Name {
		t.Fatalf("authorized pilot rejected or caller name trusted: %s", reject)
	}
	second, _, reject := join(firstRoom.Code, clients[1].player.Token)
	if reject != "" || second.arena != first.arena {
		t.Fatalf("pilots in the same room did not share an arena: %s", reject)
	}
	if _, _, reject := join(firstRoom.Code, clients[1].player.Token); reject == "" {
		t.Fatal("one room member joined twice")
	}
	other, _, reject := join(otherRoom.Code, otherHost.player.Token)
	if reject != "" || other.arena == first.arena {
		t.Fatalf("distinct rooms shared an arena: %s", reject)
	}
	public, _, reject := join("", "")
	if reject != "" || public.arena == first.arena || public.arena == other.arena {
		t.Fatalf("public and private pilots shared an arena: %s", reject)
	}
	first.pilot.Score++
	if other.arena.leaderboard(nil)[0].Score != 0 || public.arena.leaderboard(nil)[0].Score != 0 {
		t.Fatal("private kill leaked to another arena")
	}
	server.step(now.Add(infinitePublicIdle))
	if first.arena.players != 2 || other.arena.players != 1 {
		t.Fatal("public idle timer affected a private arena")
	}
	action(t, h, clients[0], map[string]any{"type": "leave"})
	server.step(now)
	select {
	case <-firstSocket.done:
	default:
		t.Fatal("room departure did not revoke the Infinity socket")
	}
	if first.arena.players > 1 {
		t.Fatal("room departure retained a private pilot")
	}
}
