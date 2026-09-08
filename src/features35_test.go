package main

import (
	"encoding/json"
	"math"
	"math/rand"
	"strings"
	"testing"
	"time"
)

func TestMaps35DefaultAndHuge(t *testing.T) {
	g := newGame(35)
	c, r := g.mapDimensions()
	if c != 12 || r != 10 {
		t.Fatal("default is not 12x10")
	}
	g.Rules.MapSize = "huge"
	c, r = g.mapDimensions()
	if c != 14 || r != 12 {
		t.Fatal("huge is not 14x12")
	}
	h, cs, room := makeRoom(t, 2)
	rules := legacyTeamRules36()
	rules.MapSize = "huge"
	action(t, h, cs[1], map[string]any{"type": "rules", "rules": rules})
	if !hasError(cs[1], "not_host") {
		t.Fatal("guest changed map")
	}
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	if room.Game.Rules.MapSize != "huge" {
		t.Fatal("huge rejected")
	}
}
func TestEight35DistinctSafeSpawnsEveryMap(t *testing.T) {
	for _, size := range []string{"compact", "standard", "large", "huge"} {
		for seed := int64(0); seed < 24; seed++ {
			g := newGame(seed)
			g.Rules.MapSize = size
			g.startMatch(testPlayers(maxTanks))
			seen := map[[2]float64]bool{}
			for _, p := range g.Tanks {
				if p == nil {
					t.Fatal("missing eighth tank")
				}
				key := [2]float64{p.X, p.Y}
				if seen[key] {
					t.Fatal("overlapping spawn")
				}
				seen[key] = true
				x, y := p.X, p.Y
				g.resolveWalls(p)
				if dist(x, y, p.X, p.Y) > .01 {
					t.Fatal("spawn in wall")
				}
			}
		}
	}
}
func TestEight35OneInputStepPerTank(t *testing.T) {
	g := battle(maxTanks)
	ps := testPlayers(maxTanks)
	in := [maxTanks]Input{}
	xs := [maxTanks]float64{}
	for i, p := range g.Tanks {
		xs[i] = p.X
		in[i] = Input{Forward: true, Seq: 17}
		p.Invulnerable = 999
	}
	g.step(tickDT, in, ps)
	for i, p := range g.Tanks {
		if p.Ack != 17 || p.AckSteps != 1 || math.Abs(p.X-xs[i]-128*tickDT) > .001 {
			t.Fatalf("seat%d double/skipped movement: %+v", i, p)
		}
	}
}
func TestEight35NetworkInputTopSeat(t *testing.T) {
	h, cs, r := makeRoom(t, maxTanks)
	readyAll(t, h, cs)
	action(t, h, cs[0], map[string]any{"type": "start"})
	r.Game.Phase = "playing"
	action(t, h, cs[7], map[string]any{"type": "input", "seq": 1, "forward": true, "fire": true})
	if !r.Players[7].Input.Forward || !r.Players[7].Input.Fire {
		t.Fatal("eighth input missing")
	}
	action(t, h, cs[1], map[string]any{"type": "input", "player": 7, "seq": 2, "reverse": true})
	if r.Players[7].Input.Reverse {
		t.Fatal("guest controlled eighth seat")
	}
}
func TestEight35ChatDoesNotOccupyTankSeat(t *testing.T) {
	h, cs, r := makeRoom(t, maxTanks)
	v := viewer33(t, h, r, "Viewer")
	h.chat(v, clientMessage{Text: "Watching eight tanks"}, time.Now())
	if len(r.Chat) != 1 || !r.Chat[0].Spectating || !v.player.Spectating {
		t.Fatal("spectator chat/role")
	}
	for i, p := range r.Players {
		if p != cs[i].player {
			t.Fatal("chat changed roster")
		}
	}
}
func TestChat35SenderAttributionAndRoomIsolation(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	other := fakeClient()
	action(t, h, other, map[string]any{"type": "create", "name": "OTHER"})
	for _, c := range append(cs, other) {
		drain(c)
	}
	action(t, h, cs[1], map[string]any{"type": "chat", "text": "hello 💥 <b>plain</b>", "name": "FORGED", "member": cs[0].player.Member, "spectating": true})
	if len(r.Chat) != 1 || r.Chat[0].Name != "GUEST" || r.Chat[0].Member != cs[1].player.Member || r.Chat[0].Spectating {
		t.Fatal("forged attribution")
	}
	for _, c := range cs {
		ms := drain(c)
		if len(ms) != 1 || ms[0]["type"] != "chat" {
			t.Fatal("room member did not receive chat")
		}
		data, _ := json.Marshal(ms)
		if strings.Contains(string(data), c.player.Token) {
			t.Fatal("credential leak")
		}
	}
	if len(drain(other)) != 0 {
		t.Fatal("other room received chat")
	}
}
func TestChat35UnicodeAndValidation(t *testing.T) {
	for _, bad := range []string{"", " ", "\u200b", "bad\nline", "bad\rline", "a\x00b", "a\u2028b", strings.Repeat("💥", 281), string([]byte{0xff})} {
		h, cs, r := makeRoom(t, 1)
		h.chat(cs[0], clientMessage{Text: bad}, time.Now())
		if len(r.Chat) != 0 || !hasError(cs[0], "bad_chat") {
			t.Fatalf("accepted %q", bad)
		}
	}
	h, cs, r := makeRoom(t, 1)
	h.chat(cs[0], clientMessage{Text: strings.Repeat("💥", 280)}, time.Now())
	if len(r.Chat) != 1 {
		t.Fatal("280 Unicode chars rejected")
	}
}
func TestChat35OnlyCurrentMembership(t *testing.T) {
	h, cs, r := makeRoom(t, 1)
	c := fakeClient()
	h.chat(c, clientMessage{Text: "stranger"}, time.Now())
	if !hasError(c, "not_joined") {
		t.Fatal("outsider chat")
	}
	c.room = r
	c.player = cs[0].player
	h.chat(c, clientMessage{Text: "impersonator"}, time.Now())
	if !hasError(c, "not_joined") || len(r.Chat) != 0 {
		t.Fatal("stale socket impersonation")
	}
}
func TestChat35RateLimitAndRefill(t *testing.T) {
	h, cs, r := makeRoom(t, 1)
	now := time.Now()
	for i := 0; i < 4; i++ {
		h.chat(cs[0], clientMessage{Text: "burst"}, now)
	}
	h.chat(cs[0], clientMessage{Text: "fifth"}, now)
	if len(r.Chat) != 4 || !hasError(cs[0], "chat_rate") {
		t.Fatal("unbounded spam")
	}
	h.chat(cs[0], clientMessage{Text: "refilled"}, now.Add(time.Second))
	if len(r.Chat) != 5 {
		t.Fatal("no refill")
	}
}
func TestChat35HistoryBoundedAcrossMatches(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	now := time.Now()
	for i := 0; i < 85; i++ {
		h.chat(cs[0], clientMessage{Text: "message"}, now.Add(time.Duration(i)*time.Second))
		for _, c := range cs {
			drain(c)
		}
	}
	if len(r.Chat) != chatHistoryLimit || r.Chat[0].ID != 26 || r.Chat[len(r.Chat)-1].ID != 85 {
		t.Fatal("history not bounded/ordered")
	}
	r.Game.startMatch(r.Players)
	if len(r.Chat) != 60 {
		t.Fatal("starting cleared history")
	}
	h.sendChatHistory(cs[1], r)
	ms := drain(cs[1])
	if len(ms) != 1 || len(ms[0]["messages"].([]any)) != 60 {
		t.Fatal("history missing")
	}
	raw, _ := json.Marshal(h.stateMessage(r))
	if strings.Contains(string(raw), "chat_history") || strings.Contains(string(raw), "message\"") {
		t.Fatal("chat in movement snapshot")
	}
}
func TestChat35KickRevokesSendAndHistoryAccess(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	p := cs[1].player
	id := p.ID
	h.kick(cs[0], &id, p.Member, time.Now())
	drain(cs[1])
	h.chat(cs[1], clientMessage{Text: "post kick"}, time.Now())
	if len(r.Chat) != 0 || !hasError(cs[1], "not_joined") {
		t.Fatal("kicked chat accepted")
	}
}
func TestChat35SpectatingKeepsRateBudget(t *testing.T) {
	h, cs, r := makeRoom(t, 1)
	now := time.Now()
	for i := 0; i < 4; i++ {
		h.chat(cs[0], clientMessage{Text: "burst"}, now)
	}
	action(t, h, cs[0], map[string]any{"type": "spectate", "spectating": true})
	h.chat(cs[0], clientMessage{Text: "evade"}, now)
	if len(r.Chat) != 4 || !hasError(cs[0], "chat_rate") {
		t.Fatal("role reset chat limit")
	}
}
func TestChat35AllGamePhases(t *testing.T) {
	h, cs, r := makeRoom(t, 1)
	now := time.Now()
	for i, phase := range []string{"lobby", "countdown", "playing", "roundOver", "matchOver"} {
		r.Game.Phase = phase
		h.chat(cs[0], clientMessage{Text: phase}, now.Add(time.Duration(i)*time.Second))
	}
	if len(r.Chat) != 5 {
		t.Fatal("chat disabled in phase")
	}
}
func TestBroadcast35MatchesIndividualState(t *testing.T) {
	h, cs, r := makeRoom(t, maxTanks)
	r.Game.startMatch(r.Players)
	var reference []byte
	for _, c := range cs {
		drain(c)
		c.mapGeneration = -1
	}
	h.sendState(cs[0], r)
	reference = <-cs[0].send
	cs[0].mapGeneration = -1
	h.broadcastState(r)
	for _, c := range cs {
		raw := <-c.send
		if string(raw) != string(reference) {
			t.Fatal("shared state changed fields")
		}
		if c.mapGeneration != r.Game.Generation {
			t.Fatal("map not acknowledged")
		}
	}
	for _, c := range cs {
		c.updates = make(chan []byte, 1)
	}
	h.broadcastState(r)
	h.broadcastState(r)
	for _, c := range cs {
		if len(c.updates) != 1 || len(c.send) != 0 {
			t.Fatal("coalescing broken")
		}
		var m map[string]any
		_ = json.Unmarshal(<-c.updates, &m)
		if m["world"] != nil {
			t.Fatal("unneeded map resent")
		}
	}
}
func TestSpatial35MatchesBruteForce(t *testing.T) {
	rng := rand.New(rand.NewSource(35))
	for _, size := range []string{"compact", "standard", "large", "huge"} {
		for seed := int64(0); seed < 8; seed++ {
			g := newGame(seed)
			g.Rules.MapSize = size
			g.startMatch(testPlayers(maxTanks))
			for n := 0; n < 600; n++ {
				x, y := rng.Float64()*g.World.Width, rng.Float64()*g.World.Height
				dx, dy := (rng.Float64()-.5)*g.World.Width, (rng.Float64()-.5)*g.World.Height
				if n%2 == 0 {
					dx *= .05
					dy *= .05
				}
				radius := rng.Float64() * 20
				a, b := g.rayWalls(x, y, dx, dy, radius), g.bruteWalls35(x, y, dx, dy, radius)
				if (a == nil) != (b == nil) || a != nil && (math.Abs(a.T-b.T) > 1e-9 || a.NX != b.NX || a.NY != b.NY) {
					t.Fatalf("different collision %s seed%d ray%d: %+v %+v", size, seed, n, a, b)
				}
			}
		}
	}
}
func TestSpatial35RebuildsWithMaze(t *testing.T) {
	g := newGame(35)
	for _, size := range []string{"huge", "compact", "huge"} {
		g.Rules.MapSize = size
		g.startMatch(testPlayers(maxTanks))
		g.wallCandidates(42, 42, 2, 3, 4)
		if g.spatial.cols != g.World.Cols || g.spatial.first != &g.World.Walls[0] {
			t.Fatal("stale maze index")
		}
	}
}
func BenchmarkEightBotsHuge35(b *testing.B) {
	g := newGame(35)
	g.Rules.MapSize = "huge"
	g.Rules.Mode = "koth"
	g.Rules.TimeLimit = 600
	g.Rules.ScoreTarget = 300
	ps := testPlayers(maxTanks)
	for i, p := range ps {
		p.Kind = "bot"
		p.Difficulty = "hard"
		p.Team = 1 + i%2
	}
	g.startMatch(ps)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if g.Phase == "matchOver" {
			g.startMatch(ps)
		}
		g.step(tickDT, [maxTanks]Input{}, ps)
	}
}

// Original exhaustive narrow phase, retained here as a test-only reference.
func (g *Game) bruteWalls35(x, y, dx, dy, r float64) *RayHit {
	var best *RayHit
	nearest := 1.0 + 1e-8
	for _, w := range g.World.Walls {
		minX, maxX, minY, maxY := w.X-r, w.X+w.W+r, w.Y-r, w.Y+w.H+r
		if math.Max(x, x+dx) < minX || math.Min(x, x+dx) > maxX || math.Max(y, y+dy) < minY || math.Min(y, y+dy) > maxY {
			continue
		}
		tx1, tx2, ty1, ty2 := math.Inf(-1), math.Inf(1), math.Inf(-1), math.Inf(1)
		if math.Abs(dx) < 1e-9 {
			if x < minX || x > maxX {
				continue
			}
		} else {
			tx1 = (minX - x) / dx
			tx2 = (maxX - x) / dx
			if tx1 > tx2 {
				tx1, tx2 = tx2, tx1
			}
		}
		if math.Abs(dy) < 1e-9 {
			if y < minY || y > maxY {
				continue
			}
		} else {
			ty1 = (minY - y) / dy
			ty2 = (maxY - y) / dy
			if ty1 > ty2 {
				ty1, ty2 = ty2, ty1
			}
		}
		entry, exit := math.Max(tx1, ty1), math.Min(tx2, ty2)
		if entry > exit || exit < 0 || entry > 1 || entry < -.0001 {
			continue
		}
		hit := math.Max(0, entry)
		nx, ny := 0.0, 0.0
		if math.Abs(tx1-ty1) < 1e-7 {
			nx = 1
			ny = 1
			if dx > 0 {
				nx = -1
			}
			if dy > 0 {
				ny = -1
			}
		} else if tx1 > ty1 {
			nx = 1
			if dx > 0 {
				nx = -1
			}
		} else {
			ny = 1
			if dy > 0 {
				ny = -1
			}
		}
		if hit < nearest-1e-7 {
			nearest = hit
			best = &RayHit{hit, nx, ny}
		} else if best != nil && math.Abs(hit-nearest) < 1e-7 {
			if nx != 0 {
				best.NX = nx
			}
			if ny != 0 {
				best.NY = ny
			}
		}
	}
	return best
}

func (g *Game) bruteResolve35(t *Tank) {
	for pass := 0; pass < 2; pass++ {
		for _, w := range g.World.Walls {
			qx, qy := clamp(t.X, w.X, w.X+w.W), clamp(t.Y, w.Y, w.Y+w.H)
			dx, dy := t.X-qx, t.Y-qy
			ds := dx*dx + dy*dy
			if ds >= t.R*t.R {
				continue
			}
			if ds > .000001 {
				d := math.Sqrt(ds)
				push := t.R - d + .002
				t.X += dx / d * push
				t.Y += dy / d * push
			} else {
				v := []float64{t.X - w.X, w.X + w.W - t.X, t.Y - w.Y, w.Y + w.H - t.Y}
				i := 0
				for n := 1; n < 4; n++ {
					if v[n] < v[i] {
						i = n
					}
				}
				switch i {
				case 0:
					t.X -= v[i] + t.R + .002
				case 1:
					t.X += v[i] + t.R + .002
				case 2:
					t.Y -= v[i] + t.R + .002
				case 3:
					t.Y += v[i] + t.R + .002
				}
			}
		}
	}
}
func TestSpatial35TankResolverMatchesOriginal(t *testing.T) {
	rng := rand.New(rand.NewSource(351))
	for _, size := range []string{"compact", "standard", "large", "huge"} {
		for seed := int64(0); seed < 8; seed++ {
			g := newGame(seed)
			g.Rules.MapSize = size
			g.startMatch(testPlayers(maxTanks))
			for n := 0; n < 1200; n++ {
				a := Tank{X: rng.Float64()*(g.World.Width+100) - 50, Y: rng.Float64()*(g.World.Height+100) - 50, R: 9 + rng.Float64()*15}
				if n%2 == 0 {
					w := g.World.Walls[rng.Intn(len(g.World.Walls))]
					a.X = w.X + w.W*rng.Float64()
					a.Y = w.Y + w.H*rng.Float64()
				}
				b := a
				g.resolveWalls(&a)
				g.bruteResolve35(&b)
				if math.Abs(a.X-b.X) > 1e-8 || math.Abs(a.Y-b.Y) > 1e-8 {
					t.Fatalf("different tank collision %s seed%d case%d: %+v %+v", size, seed, n, a, b)
				}
			}
		}
	}
}
func TestEight35PublishAndPresetFullRoster(t *testing.T) {
	roster := []SeatSpec{{Kind: "human", Name: "HOST", Team: 1}, {Kind: "local", Name: "P2", Team: 1}}
	for i := 2; i < maxTanks; i++ {
		roster = append(roster, SeatSpec{Kind: "bot", Name: "BOT", Team: 1 + i%2, Difficulty: "hard"})
	}
	rules := legacyTeamRules36()
	rules.MapSize = "huge"
	h := newHub(1)
	c := fakeClient()
	action(t, h, c, map[string]any{"type": "publish", "roster": roster, "rules": rules})
	if c.room == nil {
		t.Fatal("eight-seat publish rejected")
	}
	r := c.room
	for _, p := range r.Players {
		if p == nil {
			t.Fatal("full roster lost seat")
		}
	}
	action(t, h, c, map[string]any{"type": "preset", "roster": roster, "rules": rules})
	if !canStart(r) || r.Game.Rules.MapSize != "huge" {
		t.Fatal("eight-seat preset rejected")
	}
	tooMany := append(append([]SeatSpec{}, roster...), SeatSpec{Kind: "bot", Name: "EXTRA", Team: 2, Difficulty: "easy"})
	if validPresetRoster(tooMany) == nil {
		t.Fatal("ninth preset seat accepted")
	}
}
