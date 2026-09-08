package main

import (
	"encoding/json"
	"fmt"
	"testing"
)

func TestFriendlyFire34RulesDefaultsAndSerialization(t *testing.T) {
	r := legacyTeamRules36()
	if r.FriendlyFire {
		t.Fatal("must default off")
	}
	raw, _ := json.Marshal(r)
	var got map[string]any
	_ = json.Unmarshal(raw, &got)
	if got["friendlyFire"] != false {
		t.Fatal("default not explicit in wire rules")
	}
	if json.Unmarshal([]byte(`{"friendlyFire":"off"}`), &r) == nil {
		t.Fatal("string accepted as boolean")
	}
	r.FriendlyFire = true
	if validateRules(r) != nil {
		t.Fatal("valid friendly fire rejected")
	}
}
func TestFriendlyFire34EverySeatOwnDamage(t *testing.T) {
	for _, ff := range []bool{false, true} {
		for _, bot := range []bool{false, true} {
			for id := 0; id < maxTanks; id++ {
				t.Run(fmt.Sprintf("ff%v-bot%v-seat%d", ff, bot, id), func(t *testing.T) {
					g := battle(maxTanks)
					g.Rules.FriendlyFire = ff
					for _, p := range g.Tanks {
						p.Team = 2
					}
					p := g.Tanks[id]
					p.Bot = bot
					if !g.canDamage(id, p) {
						t.Fatal("own damage incorrectly gated by team or bot")
					}
					g.hurt(p, &Bullet{Owner: id})
					if p.Alive {
						t.Fatal("own shot survived")
					}
				})
			}
		}
	}
}
func TestFriendlyFire34AlliesAndShields(t *testing.T) {
	for _, ff := range []bool{false, true} {
		for a := 0; a < maxTanks; a++ {
			for b := 0; b < maxTanks; b++ {
				if a == b {
					continue
				}
				t.Run(fmt.Sprintf("ff%v-%d-%d", ff, a, b), func(t *testing.T) {
					g := battle(maxTanks)
					g.Rules.FriendlyFire = ff
					for _, p := range g.Tanks {
						p.Team = 2
					}
					target := g.Tanks[b]
					target.Shield = 5
					g.hurt(target, &Bullet{Owner: a})
					if !target.Alive || (target.Shield == 0) != ff {
						t.Fatal("wrong teammate shield handling")
					}
					target.Invulnerable = 0
					g.hurt(target, &Bullet{Owner: a})
					if target.Alive == ff {
						t.Fatal("wrong teammate damage")
					}
				})
			}
		}
	}
}
func TestFriendlyFire34ActualWeapons(t *testing.T) {
	for _, kind := range []string{"", "homing", "grenade", "laser"} {
		for _, ff := range []bool{false, true} {
			t.Run(fmt.Sprintf("%s-ff%v", kind, ff), func(t *testing.T) {
				g := battle(2)
				g.Rules.FriendlyFire = ff
				g.Tanks[0].Team = 2
				g.Tanks[1].Team = 2
				if kind == "laser" {
					g.grantPower(g.Tanks[0], "laser")
					g.fire(g.Tanks[0])
				} else if kind == "grenade" {
					g.detonate(&Bullet{Kind: "grenade", Owner: 0, X: g.Tanks[1].X, Y: g.Tanks[1].Y, R: 6, Life: 3})
				} else {
					g.Bullets = []*Bullet{{Kind: kind, ID: 1, Owner: 0, X: 170, Y: 210, VX: 235, R: 4, Age: 1, Life: 5, RangeLeft: 700, rangeSet: true, Target: -1}}
					g.updateBullets(.025)
				}
				if g.Tanks[1].Alive == ff {
					t.Fatalf("teammate alive %v", g.Tanks[1].Alive)
				}
			})
		}
	}
}
func TestFriendlyFire34OwnReturningShellAllSeats(t *testing.T) {
	for id := 0; id < maxTanks; id++ {
		g := battle(maxTanks)
		p := g.Tanks[id]
		for _, v := range g.Tanks {
			v.Team = 2
		}
		g.Bullets = []*Bullet{{Owner: id, X: p.X + 22, Y: p.Y, VX: -282, R: 3.5, Life: 2, Age: .8}}
		g.updateBullets(.02)
		if p.Alive {
			t.Fatalf("seat %d immune", id)
		}
	}
}
func TestFriendlyFire34BotsAndMissilesNeverHuntAllies(t *testing.T) {
	g := battle(3)
	g.Rules.FriendlyFire = true
	g.Tanks[0].Team = 1
	g.Tanks[1].Team = 1
	g.Tanks[2].Team = 2
	g.Tanks[0].Bot = true
	g.Tanks[0].Difficulty = "hard"
	g.botControl(g.Tanks[0], tickDT)
	if g.Tanks[0].AI.Target != 2 {
		t.Fatal("bot hunted ally")
	}
	b := &Bullet{Owner: 0, X: 110, Y: 210, VX: 235, R: 4, Age: 1, Life: 5, Target: -1}
	g.steerMissile(b, tickDT)
	if b.Target != 2 {
		t.Fatalf("missile hunted %d", b.Target)
	}
}
func TestFriendlyFire34HostAuthorityAndPreservation(t *testing.T) {
	h, cs, r := makeRoom(t, 2)
	rules := legacyTeamRules36()
	rules.FriendlyFire = true
	action(t, h, cs[1], map[string]any{"type": "rules", "rules": rules})
	if !hasError(cs[1], "not_host") || r.Game.Rules.FriendlyFire {
		t.Fatal("guest set friendly fire")
	}
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	if !r.Game.Rules.FriendlyFire {
		t.Fatal("host setting lost")
	}
	r.Game.startMatch(r.Players)
	if !r.Game.settings().FriendlyFire {
		t.Fatal("start reset setting")
	}
	rules.FriendlyFire = false
	action(t, h, cs[0], map[string]any{"type": "rules", "rules": rules})
	if !hasError(cs[0], "match_active") || !r.Game.Rules.FriendlyFire {
		t.Fatal("mid-match change accepted")
	}
}
func TestSuddenDeath34TiedClockBothModes(t *testing.T) {
	for _, mode := range []string{"ctf", "koth"} {
		t.Run(mode, func(t *testing.T) {
			g, ps := objectiveFixture(mode)
			g.Scores = [maxTanks]int{1, 1, 1, 0}
			g.Tanks[2].Alive = false
			g.Tanks[2].RespawnTime = 5
			g.Clock = 0
			generation := g.Generation
			g.stepObjectives(.01, ps)
			if g.Phase != "playing" || !g.suddenDeath() || g.Generation != generation || g.PhaseTime != 0 {
				t.Fatal("wrong final-life transition")
			}
			for _, p := range g.Tanks {
				if p != nil && (!p.Alive || p.Invulnerable <= 0 || !p.suddenLife) {
					t.Fatal("missing final life")
				}
			}
			if g.Scores != [maxTanks]int{1, 1, 1, 0} {
				t.Fatal("objective points changed")
			}
		})
	}
}
func TestSuddenDeath34UnequalClockEndsNormally(t *testing.T) {
	for _, mode := range []string{"ctf", "koth"} {
		g, ps := objectiveFixture(mode)
		g.Scores = [maxTanks]int{2, 1, 2, 0}
		g.Clock = 0
		g.stepObjectives(.01, ps)
		if g.Phase != "matchOver" || g.suddenDeath() || g.Winner != 0 {
			t.Fatal("unequal score did not end normally")
		}
	}
}
func TestSuddenDeath34NoRespawnsOrScoring(t *testing.T) {
	for _, mode := range []string{"ctf", "koth"} {
		g, ps := objectiveFixture(mode)
		g.beginSuddenDeath(ps, false)
		p := g.Tanks[2]
		p.Invulnerable = 0
		g.hurt(p, &Bullet{Owner: 2})
		g.respawnPlayers(99, ps)
		if p.Alive || p.RespawnTime > 0 {
			t.Fatal("extra life")
		}
		g.addObjectivePoint(0)
		if g.Scores != [maxTanks]int{} {
			t.Fatal("objective score progressed")
		}
		if _, _, ok := g.objectiveGoal(g.Tanks[0]); ok {
			t.Fatal("bots still pursue objectives")
		}
		g.stepSuddenDeath(ps)
		if g.Phase != "playing" {
			t.Fatal("teammate death prematurely ended match")
		}
	}
}
func TestSuddenDeath34LastSideWinsWithoutBonusPoints(t *testing.T) {
	g, ps := objectiveFixture("ctf")
	g.Scores = [maxTanks]int{1, 1, 1, 0}
	g.beginSuddenDeath(ps, false)
	g.Tanks[0].Alive = false
	g.Tanks[2].Alive = false
	g.stepSuddenDeath(ps)
	if g.Phase != "matchOver" || g.Winner != 1 || g.Scores != [maxTanks]int{1, 1, 1, 0} {
		t.Fatal("wrong survival winner or added points")
	}
}
func TestSuddenDeath34FFAAndTeammateSurvival(t *testing.T) {
	g, ps := objectiveFixture("koth")
	g.Rules.TeamMode = "ffa"
	for _, p := range ps {
		if p != nil {
			p.Team = 0
		}
	}
	for _, p := range g.Tanks {
		if p != nil {
			p.Team = 0
		}
	}
	g.beginSuddenDeath(ps, false)
	g.Tanks[0].Alive = false
	g.stepSuddenDeath(ps)
	if g.Phase != "playing" {
		t.Fatal("two opponents still live")
	}
	g.Tanks[1].Alive = false
	g.stepSuddenDeath(ps)
	if g.Winner != 2 || g.Phase != "matchOver" {
		t.Fatal("FFA survivor did not win")
	}
}
func TestSuddenDeath34MutualDestructionReplays(t *testing.T) {
	g, ps := objectiveFixture("koth")
	g.beginSuddenDeath(ps, false)
	serial := g.Tanks[0].SpawnSerial
	for _, v := range g.Tanks {
		if v != nil {
			v.Alive = false
		}
	}
	g.stepSuddenDeath(ps)
	if g.Phase != "playing" || g.Objectives.Showdown != 2 || !g.Tanks[0].Alive || g.Tanks[0].SpawnSerial <= serial {
		t.Fatal("mutual destruction did not reset final lives")
	}
}
func TestSuddenDeath34LateJoinCannotGainLife(t *testing.T) {
	g, ps := objectiveFixture("ctf")
	g.beginSuddenDeath(ps, false)
	ps[3] = &Player{ID: 3, Client: fakeClient(), Team: 2}
	g.Tanks[3] = &Tank{ID: 3, Team: 2, R: tankRadius, RespawnTime: 1}
	g.respawnPlayers(99, ps)
	if g.Tanks[3].Alive {
		t.Fatal("late arrival respawned")
	}
	g.Tanks[1].Alive = false
	g.stepSuddenDeath(ps)
	if g.Phase != "matchOver" || g.Tanks[g.Winner].Team != 1 {
		t.Fatal("late arrival prevented survival win")
	}
}
func TestSuddenDeath34ReplacementExcludedFromReplay(t *testing.T) {
	g, ps := objectiveFixture("ctf")
	g.beginSuddenDeath(ps, false)
	g.Tanks[2] = &Tank{ID: 2, Team: 1, R: tankRadius}
	g.Tanks[0].Alive = false
	g.Tanks[1].Alive = false
	g.stepSuddenDeath(ps)
	if g.Tanks[2].Alive || !g.Tanks[0].Alive || !g.Tanks[1].Alive {
		t.Fatal("replacement gained sudden-death life")
	}
}
func TestSuddenDeath34SnapshotAndNewMatch(t *testing.T) {
	g, ps := objectiveFixture("ctf")
	g.beginSuddenDeath(ps, false)
	raw, _ := json.Marshal(g.Objectives)
	var obj map[string]any
	_ = json.Unmarshal(raw, &obj)
	if obj["suddenDeath"] != true || obj["showdown"] != float64(1) {
		t.Fatal("state not serialized")
	}
	g.startMatch(ps)
	if g.suddenDeath() {
		t.Fatal("new match retained tiebreaker")
	}
	for _, p := range g.Tanks {
		if p != nil && p.suddenLife {
			t.Fatal("eligibility leaked")
		}
	}
}
func TestSuddenDeath34EmptyRoomDoesNotLoop(t *testing.T) {
	g, ps := objectiveFixture("ctf")
	g.beginSuddenDeath(ps, false)
	for i := range ps {
		ps[i] = nil
	}
	g.stepSuddenDeath(ps)
	if g.Phase != "matchOver" || g.Winner != -1 {
		t.Fatal("abandoned room did not terminate")
	}
}
