package main

import "testing"

func TestGodlikeRejectsPiercingShotWithAllyBehindEnemy(t *testing.T) {
	for _, weapon := range []string{"cannon", "laser"} {
		g := battle(3)
		g.Rules.FriendlyFire = true
		owner, enemy, ally := g.Tanks[0], g.Tanks[1], g.Tanks[2]
		owner.X, enemy.X, ally.X = 80, 180, 280
		owner.Team, ally.Team, enemy.Team = 1, 1, 2
		owner.Power = weapon
		if g.godlikeSafeShot(owner, enemy, 0) {
			t.Fatal("piercing shot considered an ally behind the enemy safe", weapon)
		}
		g.Rules.FriendlyFire = false
		if !g.godlikeSafeShot(owner, enemy, 0) {
			t.Fatal("disabled friendly fire blocked a valid piercing shot", weapon)
		}
	}
}
