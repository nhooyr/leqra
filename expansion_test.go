package main

import (
	"encoding/json"
	"math"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestArbitraryRoomNamesRoundTrip(t *testing.T) {
	names := []string{"a", "000000", "Friday tanks 💥", "🎮 家族の部屋", "café & friends + 50% #1/?=yes", "__proto__", `<img src=x onerror=alert(1)>`, "Adam's \"room\"", strings.Repeat("💥", 128), "family 👩‍👩‍👧‍👧"}
	for _, name := range names {
		t.Run(name, func(t *testing.T) {
			h := newHub(4)
			host, guest := fakeClient(), fakeClient()
			action(t, h, host, map[string]any{"type": "join", "code": name, "name": "HOST"})
			w := welcomeMessage(t, host)
			if host.room == nil || host.room.Code != name || w["room"] != name || w["created"] != true {
				t.Fatalf("room name altered: %v", w)
			}
			action(t, h, guest, map[string]any{"type": "join", "code": name})
			if guest.room != host.room || host.room.Host != host.player.ID || len(h.rooms) != 1 {
				t.Fatal("same arbitrary name did not join existing host")
			}
			msg := h.roomMessage(host.room)
			data, e := json.Marshal(msg)
			if e != nil {
				t.Fatal(e)
			}
			var decoded map[string]any
			if json.Unmarshal(data, &decoded) != nil || decoded["code"] != name {
				t.Fatal("name not preserved over JSON")
			}
		})
	}
}
func TestArbitraryRoomCreationAndCase(t *testing.T) {
	h := newHub(5)
	host, guest, other := fakeClient(), fakeClient(), fakeClient()
	action(t, h, host, map[string]any{"type": "create", "code": "  Friday tanks 💥  "})
	if host.room == nil || host.room.Code != "Friday tanks 💥" {
		t.Fatal("create did not use supplied name")
	}
	action(t, h, guest, map[string]any{"type": "create", "code": "Friday tanks 💥"})
	if host.room != guest.room || host.room.Host != host.player.ID {
		t.Fatal("named Create overwrote host")
	}
	action(t, h, other, map[string]any{"type": "join", "code": "friday tanks 💥"})
	if other.room == host.room || len(h.rooms) != 2 {
		t.Fatal("custom names must preserve case")
	}
	if cleanCode("abc234") != "ABC234" || cleanCode("Aſbcde") != "Aſbcde" {
		t.Fatal("legacy ASCII normalization mismatch")
	}
}
func TestArbitraryRoomLimitsAndControls(t *testing.T) {
	names := []string{"", "  ", "\u200b", strings.Repeat("x", 129), strings.Repeat("💥", 129), "abc\x00x", "abc\nx", "abc\rx", "abc\tx", "a\u0085b", "a\u2028b", "a\u2029b"}
	for _, name := range names {
		t.Run(name, func(t *testing.T) {
			h := newHub(2)
			c := fakeClient()
			action(t, h, c, map[string]any{"type": "join", "code": name})
			if !hasError(c, "bad_code") || len(h.rooms) != 0 || c.room != nil {
				t.Fatal("invalid name allocated room")
			}
		})
	}
	if validCode(string([]byte{0xff})) {
		t.Fatal("invalid UTF8 accepted")
	}
	if cleanCode("\u0085\ufeff room \ufeff\u0085") != "room" {
		t.Fatal("trim parity")
	}
}
func TestArbitraryRoomReconnectAndKickProtection(t *testing.T) {
	h := newHub(3)
	host, guest := fakeClient(), fakeClient()
	code := "A + B & 🛡️"
	action(t, h, host, map[string]any{"type": "join", "code": code})
	action(t, h, guest, map[string]any{"type": "join", "code": code})
	p := guest.player
	h.removeClient(guest)
	resumed := fakeClient()
	action(t, h, resumed, map[string]any{"type": "join", "code": code, "token": p.Token})
	if resumed.player != p || resumed.room != host.room {
		t.Fatal("Unicode resume failed")
	}
	action(t, h, host, map[string]any{"type": "kick", "target": p.ID, "member": p.Member})
	late := fakeClient()
	action(t, h, late, map[string]any{"type": "join", "code": code, "token": p.Token})
	kicked := false
	for _, msg := range drain(late) {
		if msg["type"] == "kicked" {
			kicked = true
		}
	}
	if !kicked || late.room != nil {
		t.Fatal("Unicode name bypassed kick tombstone")
	}
}
func TestConcurrentArbitraryNameCreatesOneHost(t *testing.T) {
	h := newHub(2)
	code := "racing room + 🎮"
	data, _ := json.Marshal(map[string]any{"type": "join", "code": code})
	cs := make([]*Client, 12)
	var wg sync.WaitGroup
	for i := range cs {
		cs[i] = fakeClient()
		wg.Add(1)
		go func(c *Client) { defer wg.Done(); _ = h.handle(c, data, time.Now()) }(cs[i])
	}
	wg.Wait()
	r := h.rooms[code]
	if len(h.rooms) != 1 || r == nil || connectedPlayers(r) != 12 || len(r.Spectators) != 12-maxTanks || r.Host < 0 {
		t.Fatal("concurrent arbitrary creation")
	}
	creators := 0
	for _, c := range cs {
		for _, m := range drain(c) {
			if m["type"] == "welcome" && m["created"] == true {
				creators++
			}
		}
	}
	if creators != 1 {
		t.Fatal("multiple hosts created")
	}
}
func laserEvent(t *testing.T, g *Game) Event {
	t.Helper()
	for i := len(g.events) - 1; i >= 0; i-- {
		if g.events[i].Type == "laser" {
			return g.events[i]
		}
	}
	t.Fatal("beam event missing")
	return Event{}
}
func TestLaserInstantHitFirstTankAndNoSelfDamage(t *testing.T) {
	g := battle(3)
	p := g.Tanks[0]
	g.grantPower(p, "laser")
	if !g.fire(p) || g.Tanks[1].Alive || !g.Tanks[2].Alive || !p.Alive || len(g.Bullets) != 0 {
		t.Fatal("laser must instantly hit first tank only")
	}
	e := laserEvent(t, g)
	if e.Owner != 0 || math.Abs(e.EndX-(g.Tanks[1].X-g.Tanks[1].R-laserRadius)) > 1e-6 || e.EndY != p.Y || e.X != p.X+28 {
		t.Fatalf("beam endpoints %+v", e)
	}
}
func TestLaserWallCoverAndBarrelCannotTunnel(t *testing.T) {
	for _, x := range []float64{90, 129} {
		t.Run(string(rune(x)), func(t *testing.T) {
			g := battle(2)
			p := g.Tanks[0]
			p.X = x
			g.World.Walls = append(g.World.Walls, Wall{150, 100, 8, 220, "v", 154})
			g.grantPower(p, "laser")
			g.fire(p)
			e := laserEvent(t, g)
			if !g.Tanks[1].Alive || len(e.Points) < 3 || e.Points[1].X > 147.00001 || e.Points[2].X >= e.Points[1].X {
				t.Fatalf("laser tunneled through wall: %+v", e)
			}
		})
	}
}
func TestLaserShieldStopsBeamAndInvulnerability(t *testing.T) {
	g := battle(3)
	g.Tanks[1].Shield = 10
	g.grantPower(g.Tanks[0], "laser")
	g.fire(g.Tanks[0])
	if !g.Tanks[1].Alive || g.Tanks[1].Shield != 0 || g.Tanks[1].Invulnerable <= 0 || !g.Tanks[2].Alive {
		t.Fatal("shield did not absorb entire beam")
	}
	g = battle(3)
	g.Tanks[1].Invulnerable = 1
	g.grantPower(g.Tanks[0], "laser")
	g.fire(g.Tanks[0])
	if !g.Tanks[1].Alive || g.Tanks[2].Alive {
		t.Fatal("invulnerability not respected")
	}
}
func TestLaserChargesCooldownAndIndependentBuffs(t *testing.T) {
	g := battle(2)
	p := g.Tanks[0]
	p.Angle = -math.Pi / 2
	g.grantPower(p, "laser")
	g.grantPower(p, "speed")
	g.grantPower(p, "shield")
	if p.Charges != 3 || p.PowerTime != 10 || capacity(p) != 3 {
		t.Fatal("laser loadout")
	}
	g.Bullets = append(g.Bullets, &Bullet{Owner: 0, Life: 2}) // Hitscan is not a live shell slot.
	if !g.fire(p) || g.fire(p) || p.Charges != 2 || p.Cooldown != laserCooldown {
		t.Fatal("cooldown or charges")
	}
	for i := 0; i < 2; i++ {
		p.Cooldown = 0
		if !g.fire(p) {
			t.Fatal("valid laser shot refused")
		}
	}
	if p.Power != "" || p.Charges != 0 || p.PowerTime != 0 || p.SpeedTime != boostDuration || p.Shield != 10 {
		t.Fatal("laser expiry overwrote buffs")
	}
	if g.fireLaser(p) {
		t.Fatal("empty laser allowed")
	}
	g.grantPower(p, "laser")
	p.Alive = false
	p.Cooldown = 0
	if g.fire(p) {
		t.Fatal("dead pilot fired")
	}
}
func TestLaserRangeMissAndEventSerialization(t *testing.T) {
	g := battle(2)
	g.World = World{Cols: 30, Rows: 15, Width: 2520, Height: 1260}
	p := g.Tanks[0]
	g.Tanks[1].X = p.X + g.laserRange() + 100
	g.grantPower(p, "laser")
	g.fire(p)
	e := laserEvent(t, g)
	if !g.Tanks[1].Alive || math.Abs(e.EndX-p.X-g.laserRange()) > 1e-6 {
		t.Fatal("laser unbounded")
	}
	data, _ := json.Marshal(e)
	var msg map[string]any
	json.Unmarshal(data, &msg)
	if msg["type"] != "laser" || msg["endX"] != e.EndX || msg["endY"] != e.EndY {
		t.Fatal("laser endpoints not transmitted")
	}
	for i := 0; i < 100; i++ {
		p.Cooldown = 0
		g.grantPower(p, "laser")
		g.fire(p)
	}
	if len(g.events) > 24 {
		t.Fatal("events not bounded")
	}
}
func TestLaserExpiryAndRoundReset(t *testing.T) {
	g := battle(2)
	p := g.Tanks[0]
	g.grantPower(p, "laser")
	p.PowerTime = tickDT / 2
	g.step(tickDT, [maxTanks]Input{}, testPlayers(2))
	if p.Power != "" {
		t.Fatal("laser timer not expired")
	}
	g.grantPower(p, "laser")
	g.startRound(testPlayers(2))
	if g.Tanks[0].Power != "" {
		t.Fatal("laser survived round")
	}
}
func TestFasterPickupScheduleAndBoundedSupply(t *testing.T) {
	g := newGame(303)
	g.Rules.MapSize = "compact" // Explicitly test the two-start/five-cap tier.
	g.Rules.PickupRate = "fast" // Retained tier; Super fast is now the default.
	ps := testPlayers(2)
	g.startRound(ps)
	if len(g.Pickups) != 2 || g.SpawnClock != 2 {
		t.Fatal("two initial pickups and 2s first delay required")
	}
	g.Phase = "playing"
	g.Pickups = nil
	g.SpawnClock = .001
	g.step(tickDT, [maxTanks]Input{}, ps)
	if len(g.Pickups) != 1 || g.SpawnClock < 2 || g.SpawnClock > 3.5 {
		t.Fatal("faster interval not applied")
	}
	for i := 0; i < 100; i++ {
		g.spawnPower()
	}
	if len(g.Pickups) != 5 {
		t.Fatal("pickup limit should be five")
	}
	for i, p := range g.Pickups {
		for j, q := range g.Pickups {
			if i != j && dist(p.X, p.Y, q.X, q.Y) < cellSize*1.1 {
				t.Fatal("pickups overlap")
			}
		}
	}
}
func TestForgedLaserInputCannotDealDamage(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	r.Game = battle(2)
	action(t, h, cs[0], map[string]any{"type": "input", "seq": 1, "power": "laser", "target": 1, "endX": r.Game.Tanks[1].X, "fire": true})
	if r.Game.Tanks[0].Power != "" || !r.Game.Tanks[1].Alive {
		t.Fatal("client awarded itself a laser")
	}
}
