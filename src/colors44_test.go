package main

import (
	"encoding/json"
	"testing"
)

func color44(n int) *int { return &n }

func Test45ColorDefaultsFFAAndTeamAuthority(t *testing.T) {
	r := defaultRules()
	r.TeamColors = []int{7, 6, 5, 4}
	for i := 0; i < maxTanks; i++ {
		if selectedColor(i, 0, nil, r) != tankColors[i] {
			t.Fatal("FFA default")
		}
		for n := 0; n < 8; n++ {
			if selectedColor(i, 0, color44(n), r) != tankColors[n] {
				t.Fatal("FFA paint")
			}
		}
		for team := 1; team <= 4; team++ {
			want := tankColors[r.TeamColors[team-1]]
			if selectedColor(i, team, nil, r) != want {
				t.Fatal("team inherit")
			}
			for n := 0; n < 8; n++ {
				if selectedColor(i, team, color44(n), r) != want {
					t.Fatal("individual paint overrode team")
				}
			}
		}
	}
}

func Test45PaletteValidationAndCloning(t *testing.T) {
	for _, v := range [][]int{{}, {1}, {0, 1, 2}, {0, 1, 2, 3, 4}, {0, 1, 2, 8}, {-1, 0, 1, 2}} {
		r := defaultRules()
		r.TeamColors = v
		if validateRules(r) == nil {
			t.Fatalf("invalid color list %v", v)
		}
	}
	r := defaultRules()
	r.TeamColors = nil
	if validateRules(r) != nil {
		t.Fatal("old preset missing color field")
	}
	r = normalizedRules(r)
	if len(r.TeamColors) != 4 || r.TeamColors[3] != 3 {
		t.Fatal("default migration")
	}
	for _, n := range []int{-9, -2, 8, 100} {
		if validColorIndex(color44(n)) {
			t.Fatal("invalid tank index")
		}
	}
	var m clientMessage
	if json.Unmarshal([]byte(`{"colorIndex":0.5}`), &m) == nil {
		t.Fatal("fractional index accepted")
	}
	r2 := defaultRules()
	out := normalizedRules(r2)
	r2.TeamColors[0] = 7
	if out.TeamColors[0] != 0 {
		t.Fatal("rules slice aliased")
	}
}

func Test45FFASelfPaintAndHostCannotPaintRemoteHuman(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	rules := defaultRules()
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	guest := r.Players[1]
	action(t, h, cs[1], map[string]any{"type": "paint", "target": guest.ID, "member": guest.Member, "colorIndex": 7})
	if guest.ColorIndex == nil || *guest.ColorIndex != 7 {
		t.Fatal("guest could not paint own FFA tank")
	}
	action(t, h, cs[0], map[string]any{"type": "paint", "target": guest.ID, "member": guest.Member, "colorIndex": 3})
	if !hasError(cs[0], "not_owner") || *guest.ColorIndex != 7 {
		t.Fatal("host repainted remote human")
	}
}

func Test45HostCanPaintBotAndOwnerCanPaintLocalP2(t *testing.T) {
	h, cs, r := makeRoom(t, 1)
	rules := defaultRules()
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	zero := 0
	action(t, h, cs[0], map[string]any{"type": "add", "kind": "bot", "name": "BOT", "difficulty": "normal", "team": zero})
	bot := r.Players[1]
	action(t, h, cs[0], map[string]any{"type": "paint", "target": bot.ID, "member": bot.Member, "colorIndex": 6})
	if bot.ColorIndex == nil || *bot.ColorIndex != 6 {
		t.Fatal("host could not paint bot")
	}
	action(t, h, cs[0], map[string]any{"type": "add", "kind": "local", "name": "LOCAL", "team": zero})
	local := r.Players[2]
	action(t, h, cs[0], map[string]any{"type": "paint", "target": local.ID, "member": local.Member, "colorIndex": 5})
	if local.ColorIndex == nil || *local.ColorIndex != 5 {
		t.Fatal("controller could not paint local P2")
	}
}

func Test45TeamsForceTeamPaintAndPaintIsLocked(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	// Give the guest an FFA paint first; switching to Teams must clear it.
	ffa := defaultRules()
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": ffa})
	guest := r.Players[1]
	action(t, h, cs[1], map[string]any{"type": "paint", "target": guest.ID, "member": guest.Member, "colorIndex": 7})
	if guest.ColorIndex == nil {
		t.Fatal("fixture paint missing")
	}
	rules := defaultRules()
	rules.TeamMode = "teams"
	rules.TeamColors = []int{4, 5, 6, 7}
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	if r.Players[0].ColorIndex != nil || r.Players[1].ColorIndex != nil {
		t.Fatal("team format retained individual paint")
	}
	p := r.Players[1]
	action(t, h, cs[1], map[string]any{"type": "paint", "target": p.ID, "member": p.Member, "colorIndex": 7})
	if !hasError(cs[1], "team_color_locked") || p.ColorIndex != nil {
		t.Fatal("team paint changed")
	}
	readyAll(t, h, cs)
	action(t, h, cs[0], map[string]any{"type": "start"})
	if r.Game.Tanks[0].Color != tankColors[4] || r.Game.Tanks[1].Color != tankColors[5] {
		t.Fatal("team colors not authoritative")
	}
}

func Test45PaintValidationStaleAndActiveMatch(t *testing.T) {
	for _, v := range []int{-2, 8, 500} {
		h, cs, r := makeRoom(t, 1)
		rules := defaultRules()
		action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
		p := r.Players[0]
		action(t, h, cs[0], map[string]any{"type": "paint", "target": p.ID, "member": p.Member, "colorIndex": v})
		if !hasError(cs[0], "bad_color") || p.ColorIndex != nil {
			t.Fatal("bad index")
		}
	}
	h, cs, r := makeRoom(t, 1)
	rules := defaultRules()
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	p := r.Players[0]
	action(t, h, cs[0], map[string]any{"type": "paint", "target": p.ID, "member": p.Member + 1, "colorIndex": 1})
	if !hasError(cs[0], "player_missing") {
		t.Fatal("stale target")
	}
	// Configure can no longer be used to bypass owner-aware paint permissions.
	action(t, h, cs[0], map[string]any{"type": "configure", "target": p.ID, "member": p.Member, "colorIndex": 1})
	if !hasError(cs[0], "paint_action") {
		t.Fatal("configure paint bypass")
	}
}

func Test45FinishedReportRetainsPersonalPaint(t *testing.T) {
	g := battle(2)
	tank := g.Tanks[0]
	tank.Color = tankColors[7]
	g.bindTankStats(tank, g.stats.rows[0].participant)
	g.finishMatchStats(0)
	if g.matchReport.Players[0].Color != tankColors[7] {
		t.Fatal("report forgot paint")
	}
	tank.Color = tankColors[2]
	if g.matchReport.Players[0].Color != tankColors[7] {
		t.Fatal("frozen report changed")
	}
}
