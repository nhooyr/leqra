package main

import (
	"bytes"
	"encoding/json"
	"math"
	"net/http/httptest"
	"os"
	"regexp"
	"testing"
	"time"
)

func TestHeldInputAcknowledgementSteps(t *testing.T) {
	g := newGame(1)
	g.makeMaze(9, 8)
	tank := &Tank{X: 42, Y: 42, R: 17, Alive: true}
	for n := uint32(1); n <= 4; n++ {
		g.control(tank, Input{Seq: 9, Right: true}, tickDT)
		if tank.Ack != 9 || tank.AckSteps != n {
			t.Fatalf("ack=%d steps=%d, want 9/%d", tank.Ack, tank.AckSteps, n)
		}
	}
	g.control(tank, Input{Seq: 10, Left: true}, tickDT)
	if tank.Ack != 10 || tank.AckSteps != 1 {
		t.Fatal("new held command did not reset step count")
	}
}
func TestExpiredControlsPreserveAcknowledgementTimeline(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	r.Game.startMatch(r.Players)
	r.Game.Phase = "playing"
	action(t, h, cs[0], map[string]any{"type": "input", "seq": 41, "right": true})
	now := time.Now()
	h.tick(now)
	a := r.Game.Tanks[0].Angle
	h.tick(now.Add(inputTimeout + time.Second))
	tank := r.Game.Tanks[0]
	if tank.Angle != a {
		t.Fatal("expired input still turns tank")
	}
	if tank.Ack != 41 || tank.AckSteps != 2 {
		t.Fatalf("neutral timeout lost ack chronology: %d/%d", tank.Ack, tank.AckSteps)
	}
}
func TestResumeResetsAcknowledgementTimeline(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	r.Game.startMatch(r.Players)
	tank := r.Game.Tanks[1]
	tank.Ack = 123
	tank.AckSteps = 15
	token := cs[1].player.Token
	h.removeClient(cs[1])
	c := fakeClient()
	action(t, h, c, map[string]any{"type": "join", "code": r.Code, "token": token})
	if tank.Ack != 0 || tank.AckSteps != 0 {
		t.Fatal("reconnect inherited old connection ack")
	}
}
func TestSnapshotRateThirtyHz(t *testing.T) {
	h, cs, _ := makeRoom(t, 2)
	for _, c := range cs {
		drain(c)
	}
	now := time.Now()
	for i := 0; i < 60; i++ {
		h.tick(now.Add(time.Duration(i) * time.Second / 60))
	}
	n := 0
	for _, msg := range drain(cs[0]) {
		if msg["type"] == "state" {
			n++
		}
	}
	if n != 30 {
		t.Fatalf("60 server ticks produced %d snapshots, want 30", n)
	}
}
func TestSnapshotQueueCoalescesWithoutLosingMaze(t *testing.T) {
	h, _, r := makeRoom(t, 2)
	r.Game.startMatch(r.Players)
	c := fakeClient()
	c.updates = make(chan []byte, 1)
	h.sendState(c, r)
	if len(c.send) != 1 || len(c.updates) != 0 {
		t.Fatal("first maze must be reliable")
	}
	var initial map[string]any
	_ = json.Unmarshal(<-c.send, &initial)
	if initial["world"] == nil {
		t.Fatal("first snapshot lost maze")
	}
	for i := 0; i < 50; i++ {
		r.Game.Tick++
		h.sendState(c, r)
	}
	if len(c.updates) != 1 {
		t.Fatal("stale snapshots accumulated")
	}
	var latest map[string]any
	_ = json.Unmarshal(<-c.updates, &latest)
	if int(latest["tick"].(float64)) != r.Game.Tick {
		t.Fatal("queue did not retain newest tick")
	}
	h.sendState(c, r) // Pending old-generation update must be invalidated.
	r.Game.startRound(r.Players)
	h.sendState(c, r)
	if len(c.updates) != 0 || len(c.send) != 1 {
		t.Fatal("generation transition retained obsolete snapshot")
	}
	_ = json.Unmarshal(<-c.send, &latest)
	if latest["world"] == nil || int(latest["generation"].(float64)) != r.Game.Generation {
		t.Fatal("new maze not reliable")
	}
}
func TestPredictionMetadataCannotChangeServerMovementBudget(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	r.Game.startMatch(r.Players)
	r.Game.Phase = "playing"
	tank := r.Game.Tanks[0]
	start := tank.Angle
	now := time.Now()
	// 60 input messages in a second remain within the valid client budget.
	for i := 1; i <= 60; i++ {
		action(t, h, cs[0], map[string]any{"type": "input", "seq": i, "right": true, "ackSteps": 999999, "x": -9999, "dt": 999})
	}
	h.tick(now)
	if math.Abs(delta(start, tank.Angle)-3.65*tickDT) > 1e-8 {
		t.Fatal("input flood/client timing changed simulation speed")
	}
	if tank.Ack != 60 || tank.AckSteps != 1 {
		t.Fatal("ack counted messages, not server steps")
	}
}
func TestClientServerMovementParity(t *testing.T) {
	var fixtures []struct {
		Name     string `json:"name"`
		World    World  `json:"world"`
		Initial  Tank   `json:"initial"`
		Segments []struct {
			Steps int   `json:"steps"`
			Input Input `json:"input"`
		} `json:"segments"`
		Expected struct{ X, Y, Angle float64 } `json:"expected"`
	}
	data, err := os.ReadFile("tests/movement-fixtures.json")
	if err != nil {
		t.Fatal(err)
	}
	if err = json.Unmarshal(data, &fixtures); err != nil {
		t.Fatal(err)
	}
	for _, fixture := range fixtures {
		t.Run(fixture.Name, func(t *testing.T) {
			g := newGame(1)
			g.World = fixture.World
			tank := fixture.Initial
			for _, segment := range fixture.Segments {
				for i := 0; i < segment.Steps; i++ {
					g.control(&tank, segment.Input, tickDT)
				}
			}
			if math.Abs(tank.X-fixture.Expected.X) > 1e-7 || math.Abs(tank.Y-fixture.Expected.Y) > 1e-7 || math.Abs(delta(tank.Angle, fixture.Expected.Angle)) > 1e-7 {
				t.Fatalf("Go/client movement diverged: (%f,%f,%f) vs %+v", tank.X, tank.Y, tank.Angle, fixture.Expected)
			}
		})
	}
}

// Verify the production route allowlist, not just embedded files / injected JS.
func TestProductionServesEveryGameScript(t *testing.T) {
	app := newApp(2, nil)
	defer app.hub.close()
	handler := app.handler()
	html, err := embeddedWeb.ReadFile("web/index.html")
	if err != nil {
		t.Fatal(err)
	}
	scripts := regexp.MustCompile(`<script src="([^"]+)"`).FindAllSubmatch(html, -1)
	if len(scripts) != 3 {
		t.Fatalf("expected theme, netcode and game scripts, got %d", len(scripts))
	}
	for _, m := range scripts {
		name := string(m[1])
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, httptest.NewRequest("GET", "/"+name, nil))
		expected, err := embeddedWeb.ReadFile("web/" + name)
		if err != nil {
			t.Fatal(err)
		}
		if rec.Code != 200 || !bytes.Equal(rec.Body.Bytes(), expected) {
			t.Fatalf("script %s not served correctly: %d", name, rec.Code)
		}
	}
	for _, path := range []string{"/_fixture/lane", "/_fixture/powerups"} {
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, httptest.NewRequest("POST", path, nil))
		if rec.Code != 404 && rec.Code != 405 {
			t.Fatalf("production server exposed test fixture: %s", path)
		}
	}
}
