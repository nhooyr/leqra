package main

import (
	"fmt"
	"testing"
	"time"
)

func TestInfinityGrenadeResolvesEntireWinningBlast(t *testing.T) {
	for _, teams := range []bool{false, true} {
		t.Run(fmt.Sprintf("teams%v", teams), func(t *testing.T) {
			a := newSeededInfiniteArena(37)
			shooter := a.join(fakeClient(), "Grenadier", time.Unix(1_800_000_000, 0))
			shooter.X, shooter.Y = 42, 42
			a.rules = &infiniteRules{Target: 1, TeamNames: defaultTeamNames()}
			if teams {
				a.rules.TeamMode, shooter.Team = "teams", 1
			}
			var victims []*infinitePilot
			for _, x := range []float64{62, 67, 72} {
				p := a.addPilot("Victim", true, x, 42, 1, 0)
				p.X, p.Y, p.Team = x, 42, 2
				p.Protected, p.kit.Invulnerable, p.kit.SpawnProtected = false, 0, false
				victims = append(victims, p)
			}
			b := infiniteBullet{ID: 1, Owner: shooter.ID, ownerTeam: shooter.Team, X: 60, Y: 42, Kind: "grenade", radius: 6, Life: 1}
			a.detonate(&b)
			for _, victim := range victims {
				if victim.HP != 0 || victim.Score != -1 {
					t.Fatal("winning blast stopped before all victims", victim.ID)
				}
			}
			if !b.dead || shooter.Score != 3 || a.result == nil || a.result.Score != 3 {
				t.Fatal("winning result omitted blast victims", shooter.Score, a.result)
			}
			if teams && (a.teamScores[0] != 3 || a.teamScores[1] != -3) {
				t.Fatal("winning blast lost team scores", a.teamScores)
			}
		})
	}
}

func TestInfinityWinningRemoteDetonationResolvesEveryGrenade(t *testing.T) {
	a := newSeededInfiniteArena(37)
	shooter := a.join(fakeClient(), "Grenadier", time.Unix(1_800_000_000, 0))
	shooter.X, shooter.Y = 42, 42
	shooter.Protected, shooter.kit.Invulnerable, shooter.kit.SpawnProtected = false, 0, false
	a.rules = &infiniteRules{Target: 1}
	var victims []*infinitePilot
	for i := range 3 {
		x := 42 + float64(i*6)*cellSize
		victim := a.addPilot("Victim", true, x, 42, 1, 0)
		victim.X, victim.Y = x, 42
		victim.Protected, victim.kit.Invulnerable, victim.kit.SpawnProtected = false, 0, false
		victims = append(victims, victim)
		a.bullets = append(a.bullets, infiniteBullet{ID: i + 1, Owner: shooter.ID, AmmoEpoch: shooter.kit.AmmoEpoch, X: x, Y: 42, Kind: "grenade", radius: 6, Life: 1})
	}
	a.weaponControl(shooter, true, true)
	for i, victim := range victims {
		if victim.HP != 0 || !a.bullets[i].dead {
			t.Fatal("winning remote trigger stopped before its complete bank", i)
		}
	}
	if shooter.Score != 3 || a.result == nil || a.result.Score != 3 {
		t.Fatal("result omitted the remote grenade bank", shooter.Score, a.result)
	}
}

func TestInfinityVolleyWinUsesFinalTeamScore(t *testing.T) {
	for _, weapon := range []string{"laser", "grenade"} {
		t.Run(weapon, func(t *testing.T) {
			a := newSeededInfiniteArena(37)
			shooter := a.join(fakeClient(), "Shooter", time.Unix(1_800_000_000, 0))
			shooter.X, shooter.Y, shooter.Angle, shooter.Team = 42, 42, 0, 1
			shooter.Protected, shooter.kit.Invulnerable, shooter.kit.SpawnProtected = false, 0, false
			a.rules = &infiniteRules{Target: 1, TeamMode: "teams", TeamNames: defaultTeamNames(), FriendlyFire: true}
			for i, team := range []int{2, 1} {
				p := a.addPilot("Target", true, 64, 42, 1, 0)
				p.X, p.Y, p.Team = 62+float64(i)*8, 42, team
				p.Protected, p.kit.Invulnerable, p.kit.SpawnProtected = false, 0, false
			}
			// The allied casualty changes personal score but adds zero net team
			// points. Every victim still resolves before the result is frozen.
			if weapon == "laser" {
				applyPower(&shooter.kit, "laser", 15, 8)
				a.fireLaser(shooter)
			} else {
				a.detonate(&infiniteBullet{Owner: shooter.ID, ownerTeam: 1, X: 60, Y: 42, Kind: "grenade", radius: 6, Life: 1})
			}
			if a.teamScores[0] != 1 || a.result == nil || a.result.Score != 1 || shooter.Score != 2 {
				t.Fatal("volley result did not reflect final friendly-fire scoring", a.teamScores, a.result, shooter.Score)
			}
		})
	}
}

func TestInfinityCompletedResultRejectsLaterRemoteDetonation(t *testing.T) {
	a := newSeededInfiniteArena(37)
	p := a.join(fakeClient(), "Winner", time.Unix(1_800_000_000, 0))
	p.Protected, p.kit.Invulnerable, p.kit.SpawnProtected = false, 0, false
	a.bullets = []infiniteBullet{{ID: 1, Owner: p.ID, AmmoEpoch: p.kit.AmmoEpoch, X: 42, Y: 42, Kind: "grenade", Life: 1}}
	a.result = &infiniteResult{ID: p.ID, Name: p.Name, Score: 1}
	a.weaponControl(p, true, true)
	if a.bullets[0].dead || len(a.effects) != 0 || a.volleyDepth != 0 {
		t.Fatal("a completed match processed a new remote detonation")
	}
}
