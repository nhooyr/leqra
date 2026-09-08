package main

import (
	"encoding/json"
	"math"
	"reflect"
	"strings"
	"testing"
)

func TestDefault36FreeForAll(t *testing.T) {
	r := defaultRules()
	if r.TeamMode != "ffa" || r.MapSize != "large" || len(r.TeamNames) != 4 {
		t.Fatal("incorrect defaults", r)
	}
	h := newHub(4)
	c := fakeClient()
	action(t, h, c, map[string]any{"type": "create", "name": "HOST"})
	if c.room.Game.Rules.TeamMode != "ffa" || c.player.Team != 0 {
		t.Fatal("named rooms must also use default FFA")
	}
}
func TestTeamNames36Validation(t *testing.T) {
	cases := []struct {
		name  string
		names []string
		valid bool
	}{
		{"old preset", nil, true}, {"empty list", []string{}, false}, {"ordinary", []string{"Lime", "Coral", "Sky", "Violet"}, true},
		{"Unicode and markup as text", []string{" Équipe 🌟 ", "<b>Fire</b>", "水", strings.Repeat("💥", 24)}, true},
		{"wrong count", []string{"One", "Two"}, false}, {"blank", []string{" ", "Two", "Three", "Four"}, false},
		{"invisible", []string{"\u200d\u200b", "Two", "Three", "Four"}, false},
		{"newline", []string{"bad\nname", "Two", "Three", "Four"}, false},
		{"control", []string{"bad\x00name", "Two", "Three", "Four"}, false},
		{"too long", []string{strings.Repeat("x", 25), "Two", "Three", "Four"}, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			r := defaultRules()
			r.TeamNames = c.names
			if (validateRules(r) == nil) != c.valid {
				t.Fatal("validation", c.names)
			}
		})
	}
}
func TestTeamNames36AtomicHostAuthorityAndSnapshot(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	proposed := defaultRules()
	proposed.TeamMode = "teams"
	proposed.TeamNames = []string{" Alpha ", "Bravo", "Charlie", "Delta"}
	action(t, h, cs[1], map[string]any{"type": "rules", "rules": proposed})
	if !hasError(cs[1], "not_host") || r.Game.settings().TeamNames[0] != "Team 1" {
		t.Fatal("guest renamed teams")
	}
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": proposed})
	if r.Game.Rules.TeamNames[0] != "Alpha" {
		t.Fatal("not normalized")
	}
	old := normalizedRules(r.Game.Rules)
	bad := normalizedRules(proposed)
	bad.TeamNames[3] = "\n"
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": bad})
	if !hasError(cs[0], "bad_rules") || !reflect.DeepEqual(r.Game.Rules, old) {
		t.Fatal("partial update")
	}
	raw, _ := json.Marshal(h.roomMessage(r))
	if !strings.Contains(string(raw), `"teamNames":["Alpha","Bravo","Charlie","Delta"]`) {
		t.Fatal("room lost names")
	}
	r.Game.startMatch(r.Players)
	proposed.TeamNames[0] = "Hacked"
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": proposed})
	if !hasError(cs[0], "match_active") || r.Game.Rules.TeamNames[0] != "Alpha" {
		t.Fatal("live mutation")
	}
}
func TestTeamNames36PresetAndPublish(t *testing.T) {
	h := newHub(4)
	c := fakeClient()
	r := defaultRules()
	r.TeamMode = "teams"
	r.TeamNames = []string{"One", "Two", "Three", "Four"}
	// Explicit legacy zero seats migrate, without reintroducing Independent.
	roster := []SeatSpec{{Name: "HOST", Kind: "human", Team: 0}, {Name: "BOT", Kind: "bot", Difficulty: "normal", Team: 0}}
	action(t, h, c, map[string]any{"type": "publish", "code": "Names 36", "rules": r, "roster": roster})
	if c.room == nil || c.room.Players[0].Team != 1 || c.room.Players[1].Team != 2 || c.room.Game.Rules.TeamNames[0] != "One" {
		t.Fatal("publish migration failed")
	}
	r.TeamNames = []string{"North", "South", "East", "West"}
	action(t, h, c, map[string]any{"type": "preset", "rules": r, "roster": roster})
	if c.room.Game.Rules.TeamNames[3] != "West" || c.room.Players[1].Team != 2 {
		t.Fatal("preset migration failed")
	}
}
func TestTeam36NoIndependentSeatViaConfigureOrAdd(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	action(t, h, cs[0], map[string]any{"type": "configure", "target": 1, "member": r.Players[1].Member, "team": 0})
	if !hasError(cs[0], "bad_team") || r.Players[1].Team != 2 {
		t.Fatal("independent configure accepted")
	}
	action(t, h, cs[0], map[string]any{"type": "add", "kind": "bot", "name": "BOT", "difficulty": "normal", "team": 0})
	if !hasError(cs[0], "bad_team") || r.Players[2] != nil {
		t.Fatal("independent bot accepted")
	}
	r.Game.Rules.TeamMode = "ffa"
	applyFormat(r)
	action(t, h, cs[0], map[string]any{"type": "add", "kind": "bot", "difficulty": "normal", "team": 0})
	if r.Players[2] == nil || r.Players[2].Team != 0 {
		t.Fatal("FFA bot add rejected")
	}
}
func TestFlag36SpawnExclusionSeeded(t *testing.T) {
	for _, size := range []string{"compact", "standard", "large", "huge"} {
		t.Run(size, func(t *testing.T) {
			for seed := int64(0); seed < 30; seed++ {
				g := newGame(seed)
				g.Rules.Mode = "ctf"
				g.Rules.TeamMode = "teams"
				g.Rules.MapSize = size
				ps := testPlayers(8)
				for id, p := range ps {
					p.Team = 1 + id%2
				}
				g.startMatch(ps)
				for round := 0; round < 3; round++ {
					for _, tank := range g.Tanks {
						if round > 0 {
							tank.Alive = false
							g.respawnTank(tank)
						}
						if !tank.Alive || !g.flagSafeSpawn(tank, g.cellAt(tank.X, tank.Y), tank.X, tank.Y) {
							t.Fatalf("spawn on flag seed %d seat %d", seed, tank.ID)
						}
						for _, other := range g.Tanks {
							if other.ID != tank.ID && other.Alive && dist(tank.X, tank.Y, other.X, other.Y) < tank.R+other.R {
								t.Fatalf("overlap seed %d seat %d", seed, tank.ID)
							}
						}
					}
				}
			}
		})
	}
}
func TestFlag36DroppedFlagAlsoExcluded(t *testing.T) {
	g, _ := objectiveFixture("ctf")
	f := g.Objectives.Flags[0]
	f.Home = false
	f.X = f.HomeX + cellSize
	f.Y = f.HomeY
	f.ReturnIn = 12
	for i := 0; i < 10; i++ {
		g.respawnTank(g.Tanks[0])
		if !g.flagSafeSpawn(g.Tanks[0], g.cellAt(g.Tanks[0].X, g.Tanks[0].Y), g.Tanks[0].X, g.Tanks[0].Y) {
			t.Fatal("dropped flag spawn")
		}
	}
}

// These audit cases also run against the untouched v3.5 sources to demonstrate
// the deadline bug, rather than inferring it from a visual symptom.
func TestAudit36NoPostBuzzerCTFCapture(t *testing.T) {
	g, ps := objectiveFixture("ctf")
	tank := g.Tanks[0]
	own, enemy := g.Objectives.Flags[0], g.Objectives.Flags[1]
	tank.X, tank.Y = own.HomeX, own.HomeY
	enemy.Home = false
	enemy.Carrier = 0
	enemy.X, enemy.Y = tank.X, tank.Y
	g.Clock = 0
	g.step(tickDT, [maxTanks]Input{}, ps)
	if g.Scores[0] != 0 || !g.suddenDeath() {
		t.Fatalf("late capture changed tied result: phase=%s scores=%v", g.Phase, g.Scores)
	}
}
func TestAudit36PartialFinalHillTick(t *testing.T) {
	g, ps := objectiveFixture("koth")
	tank := g.Tanks[0]
	tank.X, tank.Y = g.Objectives.HillX, g.Objectives.HillY
	g.Objectives.Owner = sideKey(tank.ID, tank.Team)
	g.Objectives.Hold = .99
	g.Clock = .001
	g.step(tickDT, [maxTanks]Input{}, ps)
	if g.Scores[0] != 0 || !g.suddenDeath() {
		t.Fatalf("extra time awarded late hill point: phase=%s scores=%v", g.Phase, g.Scores)
	}
}
func TestAudit36PointsFrozenAfterMatch(t *testing.T) {
	g, _ := objectiveFixture("koth")
	g.endObjective(1)
	before := g.Scores
	g.addObjectivePoint(0)
	if g.Scores != before {
		t.Fatal("post-result point mutation")
	}
}
func TestAudit36GrenadeDeathAndShieldAreSingleEvents(t *testing.T) {
	for _, shield := range []bool{false, true} {
		g := battle(2)
		a, b := g.Tanks[0], g.Tanks[1]
		a.X, a.Y = 100, 100
		b.X, b.Y = 350, 250
		if shield {
			a.Shield = 3
		}
		grenade := &Bullet{Owner: 1, Kind: "grenade", X: a.X, Y: a.Y}
		g.detonate(grenade)
		g.detonate(grenade)
		if a.Alive != shield || a.Shield != 0 {
			t.Fatal("double blast/shield damage")
		}
		events := 0
		for _, e := range g.events {
			if e.Type == "blast" {
				events++
			}
		}
		if events != 1 {
			t.Fatal("duplicate blast events")
		}
	}
}
func TestAudit36TeamRoundPointOnlyOnceIncludingDeadHighSeat(t *testing.T) {
	g := battle(8)
	for _, tank := range g.Tanks {
		tank.Team = 2
		tank.Alive = false
	}
	g.Tanks[0].Team = 1
	g.Tanks[7].Team = 1
	g.Tanks[7].Alive = true
	g.finishRound(7)
	g.finishRound(7)
	if g.Scores[0] != 1 || g.Scores[7] != 1 || g.Scores[1] != 0 {
		t.Fatal("team point not exactly once", g.Scores)
	}
}
func TestAudit36AllDestroyedNoSlotOrderWinner(t *testing.T) {
	g := battle(8)
	for _, tank := range g.Tanks {
		tank.Alive = false
	}
	g.step(tickDT, [maxTanks]Input{}, testPlayers(8))
	if g.Winner != -1 || g.Scores != ([maxTanks]int{}) {
		t.Fatal("mutual destruction assigned arbitrary winner")
	}
}
func TestAudit36PartialTickMotionStopsAtDeadline(t *testing.T) {
	g, ps := objectiveFixture("koth")
	t0 := g.Tanks[0]
	t0.Angle = 0
	start := t0.X
	g.Scores[0] = 1
	g.Scores[2] = 1
	g.Clock = .002
	var inputs [maxTanks]Input
	inputs[0] = Input{Forward: true, Seq: 1}
	g.step(tickDT, inputs, ps)
	if math.Abs(t0.X-start-128*.002) > 1e-6 {
		t.Fatal("movement beyond deadline", t0.X-start)
	}
}
