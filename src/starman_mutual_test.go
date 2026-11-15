package main

import (
	"fmt"
	"testing"
	"time"
)

func TestMutualStarmanContactCommitsBothDeathsAndLivingContactStates(t *testing.T) {
	for _, third := range []bool{false, true} {
		g := battle(3)
		p, q := g.Tanks[0], g.Tanks[1]
		p.X, p.Y, q.X, q.Y = 120, 210, 154, 210
		g.grantPower(p, "starman")
		g.grantPower(q, "starman")
		if third {
			g.Tanks[2].X, g.Tanks[2].Y = 137, 210
		} else {
			g.Tanks[2] = nil
		}
		g.step(tickDT, [maxTanks]Input{}, testPlayers(3))
		if p.Alive || q.Alive || p.KilledBy != q.Name || q.KilledBy != p.Name || p.stats.Eliminations != 1 || q.stats.Eliminations != 1 || p.stats.Deaths != 1 || q.stats.Deaths != 1 {
			t.Fatal("mutual contact did not commit two correctly credited deaths", third)
		}
		if third && !g.Tanks[2].Alive {
			t.Fatal("a dead Starman rammed another overlapping tank")
		}
		contacts := 0
		for _, e := range g.events {
			if e.Type == "hit" && e.Contact != nil {
				contacts++
				if e.Contact.Kind != "starman" || e.Contact.Before.HP != 1 || e.Contact.Before.Invulnerable <= 0 || e.Contact.ProjectileID != 0 {
					t.Fatal("mutual contact metadata captured an already dead victim")
				}
			}
		}
		if contacts != 2 {
			t.Fatal("mutual contact did not publish both causal victim transitions")
		}
	}
}

func TestMutualStarmanContactRespectsWallsTeamsAndDistance(t *testing.T) {
	for _, scenario := range []string{"touching", "outside", "wall", "allies", "friendly fire"} {
		t.Run(scenario, func(t *testing.T) {
			g := ghostArena41()
			p, q := g.Tanks[0], g.Tanks[1]
			p.X, p.Y, q.X, q.Y = 120, 210, 154, 210
			g.grantPower(p, "starman")
			g.grantPower(q, "starman")
			wantDead := scenario == "touching" || scenario == "friendly fire"
			switch scenario {
			case "outside":
				q.X += .01
			case "wall":
				p.X, q.X = 240, 273
			case "allies", "friendly fire":
				p.Team, q.Team, g.Rules.FriendlyFire = 1, 1, scenario == "friendly fire"
			}
			g.step(tickDT, [maxTanks]Input{}, testPlayers(2))
			if p.Alive == wantDead || q.Alive == wantDead {
				t.Fatal("mutual contact bypassed geometry or friendly-fire permissions", p.Alive, q.Alive)
			}
		})
	}
}

func TestMutualStarmanContactDropsBothFlagsAndSchedulesBothRespawns(t *testing.T) {
	g := battle(2)
	p, q := g.Tanks[0], g.Tanks[1]
	g.Rules.Mode, g.Rules.RespawnSeconds = "ctf", 3
	p.Team, q.Team = 1, 2
	p.X, p.Y, q.X, q.Y = 120, 210, 154, 210
	g.Objectives = &ObjectiveState{Mode: "ctf", Flags: []*Flag{{Team: 1, Carrier: q.ID}, {Team: 2, Carrier: p.ID}}}
	g.grantPower(p, "starman")
	g.grantPower(q, "starman")
	g.step(tickDT, [maxTanks]Input{}, testPlayers(2))
	if p.Alive || q.Alive || p.RespawnTime != 3 || q.RespawnTime != 3 {
		t.Fatal("mutual objective contact did not schedule both deaths")
	}
	for _, flag := range g.Objectives.Flags {
		if flag.Carrier != -1 || flag.ReturnIn <= 0 {
			t.Fatal("mutual contact retained one victim's flag")
		}
	}
}

func TestInfiniteMutualStarmanContactHasAtomicScoresAndNoTransientTargetWinner(t *testing.T) {
	for _, teams := range []bool{false, true} {
		for _, order := range []uint64{0, 1} {
			t.Run(fmt.Sprintf("teams%v/order%d", teams, order), func(t *testing.T) {
				a := newSeededInfiniteArena(37)
				a.rules = &infiniteRules{Target: 1, TeamNames: []string{"Amber", "Azure"}}
				if teams {
					a.rules.TeamMode = "teams"
				}
				now := time.Unix(1_800_000_000, 0)
				p, q := a.join(fakeClient(), "First", now), a.join(fakeClient(), "Second", now)
				p.X, p.Y, q.X, q.Y = 24, 42, 58, 42
				if teams {
					p.Team, q.Team = 1, 2
				}
				applyPower(&p.kit, "starman", 15, 8)
				applyPower(&q.kit, "starman", 15, 8)
				p.Protected, q.Protected = true, true
				a.tick = order
				third := a.join(fakeClient(), "Third", now)
				third.X, third.Y, third.Protected = 41, 42, false
				a.resolveStarmanContacts([]*infinitePilot{p, q, third})
				if p.HP != 0 || q.HP != 0 || third.HP == 0 || p.Score != 0 || q.Score != 0 || p.KilledBy != q.Name || q.KilledBy != p.Name || a.result != nil || a.teamScores != [4]int{} {
					t.Fatal("mutual Infinity contact was partial, chained through a dead actor, or ended on a transient score", p.Score, q.Score, a.result)
				}
				if p.respawn != a.tick+infiniteRespawnTicks || q.respawn != a.tick+infiniteRespawnTicks {
					t.Fatal("mutual Infinity victims did not retain their normal respawn schedule")
				}
				contacts := 0
				for _, e := range a.effects {
					if e.Kind == "hit" && e.Contact != nil {
						contacts++
						if e.Contact.Before.HP != 1 || e.Contact.Kind != "starman" {
							t.Fatal("mutual Infinity contact captured a dead before-state")
						}
					}
				}
				if contacts != 2 {
					t.Fatal("mutual Infinity contact did not publish both victim transitions")
				}
				a.resolveStarmanContacts([]*infinitePilot{p, q, third})
				if p.Score != 0 || q.Score != 0 || len(a.effects) != 2 {
					t.Fatal("dead mutual contact scored a second time")
				}
			})
		}
	}
}

func TestInfiniteMutualStarmanContactRespectsWallsTeamsAndDistance(t *testing.T) {
	for _, scenario := range []string{"touching", "outside", "wall", "embedded", "allies", "friendly fire"} {
		t.Run(scenario, func(t *testing.T) {
			a, p, q, wall := wallLaunchInfinityArena()
			p.X, p.Y, q.X, q.Y = wall.X-60, wall.Y+wall.H/2, wall.X-26, wall.Y+wall.H/2
			applyPower(&p.kit, "starman", 15, 8)
			applyPower(&q.kit, "starman", 15, 8)
			wantDead := scenario == "touching" || scenario == "friendly fire"
			switch scenario {
			case "outside":
				q.X += .01
			case "wall", "embedded":
				p.X, q.X = wall.X-1, wall.X+wall.W+tankRadius
				if scenario == "embedded" {
					p.X = wall.X + wall.W/2
				}
			case "allies", "friendly fire":
				p.Team, q.Team = 1, 1
				a.rules = &infiniteRules{FriendlyFire: scenario == "friendly fire"}
			}
			a.resolveStarmanContacts([]*infinitePilot{p, q})
			if (p.HP == 0) != wantDead || (q.HP == 0) != wantDead {
				t.Fatal("mutual Infinity contact bypassed geometry or friendly-fire permissions", p.HP, q.HP)
			}
		})
	}
}
