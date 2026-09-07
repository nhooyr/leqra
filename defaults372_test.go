package main

import (
	"encoding/json"
	"math"
	"testing"
)

func TestDefaults372SuperfastRules(t *testing.T) {
	r := defaultRules()
	if r.PickupRate != "superfast" {
		t.Fatal("new rooms must default to Super fast")
	}
	if err := validateRules(r); err != nil {
		t.Fatal(err)
	}
	b, err := json.Marshal(r)
	if err != nil {
		t.Fatal(err)
	}
	var restored MatchRules
	if err := json.Unmarshal(b, &restored); err != nil {
		t.Fatal(err)
	}
	if restored.PickupRate != "superfast" {
		t.Fatal("new rate lost in serialization")
	}
}

func TestDefaults372SuperfastScheduleAcrossModes(t *testing.T) {
	for _, mode := range []string{"elimination", "ctf", "koth"} {
		t.Run(mode, func(t *testing.T) {
			g := newGame(372)
			g.Rules.MapSize = "compact" // This frequency-only regression uses the five-pickup tier.
			ps := testPlayers(2)
			g.Rules.Mode, g.Rules.TeamMode = mode, "teams"
			ps[0].Team, ps[1].Team = 1, 2
			g.startMatch(ps)
			if len(g.Pickups) != 2 || g.SpawnClock != 1 {
				t.Fatal("expected two starting pickups and 1s initial delay")
			}
			for i := 0; i < 30; i++ {
				g.step(tickDT, [maxTanks]Input{}, ps)
			}
			if g.SpawnClock != 1 || len(g.Pickups) != 2 {
				t.Fatal("countdown must not consume the spawn timer")
			}
			g.Phase = "playing"
			for i := 0; i < 59; i++ {
				g.step(tickDT, [maxTanks]Input{}, ps)
			}
			if len(g.Pickups) != 2 {
				t.Fatal("pickup spawned before first second of live play")
			}
			for i := 0; i < 2; i++ {
				g.step(tickDT, [maxTanks]Input{}, ps)
			}
			if len(g.Pickups) != 3 {
				t.Fatalf("first scheduled pickup missing: %d", len(g.Pickups))
			}
			if g.SpawnClock < 1-tickDT || g.SpawnClock > 2 {
				t.Fatal("next interval not 1–2s")
			}
			low, high := math.Inf(1), 0.0
			for i := 0; i < 128; i++ {
				g.Pickups = nil
				g.SpawnClock = .001
				g.step(tickDT, [maxTanks]Input{}, ps)
				if len(g.Pickups) != 1 || g.SpawnClock < 1 || g.SpawnClock > 2 {
					t.Fatal("Super fast repeated spawn failed")
				}
				low = math.Min(low, g.SpawnClock)
				high = math.Max(high, g.SpawnClock)
			}
			if high-low < .5 {
				t.Fatal("interval should be randomized, not fixed")
			}
		})
	}
}

func TestDefaults372ExistingRatesPreserved(t *testing.T) {
	for _, v := range []struct {
		rate   string
		lo, hi float64
	}{{"superfast", 1, 2}, {"fast", 2, 3.5}, {"normal", 4, 6}, {"slow", 7, 10}} {
		t.Run(v.rate, func(t *testing.T) {
			g := newGame(37)
			g.Rules.PickupRate = v.rate
			if err := validateRules(g.Rules); err != nil {
				t.Fatal(err)
			}
			lo, hi := g.pickupInterval()
			if lo != v.lo || hi != v.hi || g.pickupDelay() != v.lo {
				t.Fatal("rate changed")
			}
			if normalizedRules(g.Rules).PickupRate != v.rate {
				t.Fatal("explicit frequency overwritten")
			}
		})
	}
}

func TestDefaults372BoundedSupplyAndDisabledPickups(t *testing.T) {
	for _, rate := range []string{"superfast", "off"} {
		for _, empty := range []bool{false, true} {
			g := newGame(372)
			g.Rules.MapSize = "compact" // This frequency-only regression uses the five-pickup tier.
			g.Rules.PickupRate = rate
			if empty {
				g.Rules.Weapons = []string{}
			} else {
				g.Rules.Weapons = []string{"shield"}
			}
			ps := testPlayers(2)
			g.startMatch(ps)
			g.Phase = "playing"
			for i := 0; i < 128; i++ {
				g.SpawnClock = .001
				g.step(tickDT, [maxTanks]Input{}, ps)
			}
			want := 5
			if rate == "off" || empty {
				want = 0
			}
			if len(g.Pickups) != want {
				t.Fatalf("rate=%s empty=%v count=%d", rate, empty, len(g.Pickups))
			}
			for _, p := range g.Pickups {
				if p.Type != "shield" {
					t.Fatal("weapon filter ignored")
				}
			}
		}
	}
}

func TestDefaults372NewRoundAndSuddenDeathTimer(t *testing.T) {
	g, ps := objectiveFixture("ctf")
	g.SpawnClock = 99
	g.beginSuddenDeath(ps, false)
	if !g.suddenDeath() || g.SpawnClock != 1 {
		t.Fatal("sudden death must reset to selected rate")
	}
	g.Rules.MapSize = "compact"
	g.startRound(ps)
	if g.SpawnClock != 1 || len(g.Pickups) != 2 {
		t.Fatal("new round must reset to selected rate")
	}
}

func TestDefaults372HostPermissionsAndValidation(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	if r.Game.Rules.PickupRate != "superfast" {
		t.Fatal("online room default differs")
	}
	rules := r.Game.Rules
	rules.PickupRate = "slow"
	action(t, h, cs[1], map[string]any{"type": "rules", "rules": rules})
	if !hasError(cs[1], "not_host") || r.Game.Rules.PickupRate != "superfast" {
		t.Fatal("guest changed frequency")
	}
	for _, rate := range []string{"fast", "superfast", "off", "superfast"} {
		rules.PickupRate = rate
		action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
		if r.Game.Rules.PickupRate != rate {
			t.Fatal("host cannot select " + rate)
		}
	}
	rules.PickupRate = "unbounded"
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	if !hasError(cs[0], "bad_rules") || r.Game.Rules.PickupRate != "superfast" {
		t.Fatal("invalid frequency accepted")
	}
	// Permission tests run without real user think-time; rate limits have separate tests.
	cs[0].actionCount = 0
	readyAll(t, h, cs)
	action(t, h, cs[0], map[string]any{"type": "start"})
	rules.PickupRate = "slow"
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	if !hasError(cs[0], "match_active") || r.Game.Rules.PickupRate != "superfast" {
		t.Fatal("live-match rules changed")
	}
}
