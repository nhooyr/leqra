package main

import "testing"

func TestSurvival434BossWaveGrantsEveryAvailableSquadTankAShield(t *testing.T) {
	for _, pickupRate := range []string{"superfast", "off"} {
		t.Run(pickupRate, func(t *testing.T) {
			_, _, r := survivalRoom427(t, 4)
			g := r.Game
			g.Rules.ScoreTarget = 20
			g.Rules.PickupRate = pickupRate
			g.Rules.Weapons = []string{"laser"} // The squad bonus is not a random pickup.
			r.Players[1].Kind, r.Players[1].Owner, r.Players[1].Controller = "local", 0, r.Players[0]
			r.Players[1].Client = nil
			r.Players[2].Kind, r.Players[2].Client = "bot", nil
			r.Players[3].Client = nil
			g.startMatch(r.Players)
			for _, tank := range g.Tanks {
				if tank != nil && !tank.SurvivalEnemy && shieldCount(tank) != 0 {
					t.Fatal("ordinary wave unexpectedly granted a starting shield")
				}
			}
			for _, wave := range []int{5, 10, 15, 20} {
				reachSurvivalWave433(t, r, wave)
				for id := 0; id < 3; id++ {
					tank := g.Tanks[id]
					if !tank.Alive || shieldCount(tank) != 1 || tank.Shield != powerDuration(g.World.Cols, g.World.Rows) {
						t.Fatal("active human, local P2, or bot missed the boss-wave shield", wave, id)
					}
				}
				if tank := g.Tanks[3]; tank == nil || tank.Alive || shieldCount(tank) != 0 {
					t.Fatal("disconnected squad member received active boss-wave protection")
				}
				for _, tank := range g.Tanks {
					if tank != nil && tank.SurvivalEnemy && shieldCount(tank) != 0 {
						t.Fatal("squad bonus leaked to enemies with shield pickups disabled")
					}
				}
			}
		})
	}
}

func TestSurvival434BossWaveRetriesRestoreSquadShields(t *testing.T) {
	h, clients, r := survivalRoom427(t, 2)
	g := r.Game
	g.Rules.MapSize = "huge"
	g.startMatch(r.Players)
	reachSurvivalWave433(t, r, 5)
	for attempt := 0; attempt < 2; attempt++ {
		for _, tank := range g.Tanks {
			if tank != nil && !tank.SurvivalEnemy {
				tank.Shield, tank.ShieldCharges = 0, 0
			}
		}
		if attempt == 1 {
			g.endSurvival(r.Players, false)
		}
		retryWave433(t, h, clients[0])
		for id := 0; id < 2; id++ {
			if shieldCount(g.Tanks[id]) != 1 || g.Tanks[id].Shield != 15 {
				t.Fatal("current/lost boss-wave retry did not restore the full starting shield")
			}
		}
	}
	g.Phase = "playing"
	clearSurvivalWave427(t, r)
	g.prepareSurvival(2, r.Players)
	for id := 0; id < 2; id++ {
		if shieldCount(g.Tanks[id]) != 0 {
			t.Fatal("boss-wave shield leaked into the next ordinary wave")
		}
	}
}

func TestSurvival434BossShieldKeepsStrongerStacksAndExcludesSpectators(t *testing.T) {
	_, _, r := survivalRoom427(t, 4)
	g := r.Game
	g.startMatch(r.Players)
	g.survivalState().Wave = 5
	g.Tanks[0].Shield, g.Tanks[0].ShieldCharges = 7, 3
	g.Tanks[1].Shield, g.Tanks[1].ShieldCharges = 0, 4 // Expired charges cannot replace live protection.
	g.Tanks[2].Alive = false
	viewer := r.Players[3]
	r.moveMember(viewer, r.viewerID(), true)
	g.spawnSurvivalEnemies(r.Players)
	if g.Tanks[0].Shield != 7 || shieldCount(g.Tanks[0]) != 3 {
		t.Fatal("starting bonus replaced or extended a stronger existing shield")
	}
	if shieldCount(g.Tanks[1]) != 1 || g.Tanks[1].Shield != 10 {
		t.Fatal("expired shield charges prevented new boss-wave protection")
	}
	if shieldCount(g.Tanks[2]) != 0 || g.Tanks[2].Alive {
		t.Fatal("shield grant revived a dead tank")
	}
	if r.tankFor(viewer) != nil || participantCount(r.Players) != 3 {
		t.Fatal("spectator received a hidden shielded squad tank")
	}
}

func TestSurvival434SpectatingHostAllBotSquadGetsBossProtection(t *testing.T) {
	h, clients, r := survivalRoom427(t, 1)
	action(t, h, clients[0], map[string]any{"type": "add", "kind": "bot", "difficulty": "normal"})
	action(t, h, clients[0], map[string]any{"type": "spectate", "spectating": true})
	g := r.Game
	g.startMatch(r.Players)
	reachSurvivalWave433(t, r, 5)
	allies := 0
	for _, tank := range g.Tanks {
		if tank != nil && !tank.SurvivalEnemy {
			allies++
			if !tank.Bot || shieldCount(tank) != 1 {
				t.Fatal("all-bot squad missed its starting shield")
			}
		}
	}
	if allies != 1 || r.tankFor(clients[0].player) != nil {
		t.Fatal("spectating host altered the shielded squad")
	}
}
