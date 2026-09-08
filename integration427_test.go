package main

import "testing"

func TestIntegration427HugeSurvivalBossUsesExtendedPowerDuration(t *testing.T) {
	_, _, r := survivalRoom427(t, 1)
	g := r.Game
	g.Rules.MapSize = "huge"
	g.startMatch(r.Players)
	g.Phase = "playing"
	g.survivalState().Wave = 4
	g.nextSurvivalWave(r.Players)
	for _, tank := range g.Tanks {
		if tank == nil || !tank.SurvivalBoss {
			continue
		}
		if tank.Power != "homing" || tank.PowerTime != 15 || tank.Shield != 15 || tank.SpeedTime != 15 || tank.ShieldCharges != 3 || tank.SpeedStacks != 1 {
			t.Fatalf("Huge boss did not receive the extended power-up duration: %+v", tank)
		}
		return
	}
	t.Fatal("wave five has no Godlike boss")
}

func TestIntegration427MachineBudgetPausesDuringBreakAndResetsOnRevival(t *testing.T) {
	_, _, r := survivalRoom427(t, 2)
	g := r.Game
	g.startMatch(r.Players)
	g.Phase = "playing"
	tank := g.Tanks[0]
	g.grantPower(tank, "rapid")
	tank.MachineRounds = 30
	clearSurvivalWave427(t, r)
	if g.survivalState().Status != "break" {
		t.Fatal("wave did not enter intermission")
	}
	g.weaponControl(tank, true, true)
	if g.fire(tank) {
		t.Fatal("machine gun fired during intermission")
	}
	g.step(2, [maxTanks]Input{{Fire: true, FirePressed: true}}, r.Players)
	if tank.MachineRounds != 30 || tank.Power != "rapid" || len(g.Bullets) != 0 {
		t.Fatal("intermission consumed machine ammunition or advanced weapons")
	}
	tank.Alive = false
	g.step(2, [maxTanks]Input{}, r.Players)
	if !tank.Alive || tank.Power != "" || tank.MachineRounds != 0 || g.survivalState().Status != "wave" {
		t.Fatal("wave revival did not reset the machine gun budget")
	}
}

func TestIntegration427GodlikeValuesReplacementForNearlyEmptyMachineGun(t *testing.T) {
	tank := &Tank{Power: "rapid", PowerTime: 15, Charges: 5, MachineRounds: 180}
	if value := godlikePickupValue(tank, "rapid"); value != 0 {
		t.Fatalf("Godlike abandoned a full machine gun for an identical pickup: %v", value)
	}
	tank.MachineRounds = 30
	if value := godlikePickupValue(tank, "rapid"); value <= 0 {
		t.Fatalf("Godlike ignored a fresh gun with only half a second of ammunition left: %v", value)
	}
}

func TestIntegration427BossIndicatorClearsWhileOtherRaidersRemain(t *testing.T) {
	_, _, r := survivalRoom427(t, 1)
	g := r.Game
	g.startMatch(r.Players)
	g.Phase = "playing"
	g.survivalState().Wave = 4
	g.nextSurvivalWave(r.Players)
	var boss *Tank
	for _, tank := range g.Tanks {
		if tank != nil && tank.SurvivalBoss {
			boss = tank
			break
		}
	}
	if boss == nil || !g.survivalState().Boss {
		t.Fatal("boss wave missing its live boss indicator")
	}
	boss.Shield, boss.Invulnerable = 0, 0
	g.hurt(boss, &Bullet{Owner: 0})
	g.stepSurvival(r.Players)
	s := g.survivalState()
	if boss.Alive || s.Boss || s.EnemiesRemaining != 3 || s.Status != "wave" {
		t.Fatalf("dead boss still advertised or wave ended prematurely: %+v", s)
	}
}

func TestIntegration427EnemyReusingDepartedSeatCannotInheritScore(t *testing.T) {
	h, _, r := survivalRoom427(t, 2)
	g := r.Game
	g.startMatch(r.Players)
	g.Phase = "playing"
	g.Scores[1] = 4
	h.expirePlayer(r, 1)
	g.nextSurvivalWave(r.Players)
	if r.Players[1] != nil || g.Tanks[1] == nil || !g.Tanks[1].SurvivalEnemy || g.Scores[1] != 0 {
		t.Fatal("generated enemy inherited a departed squadmate's score or identity")
	}
}

func TestIntegration427SurvivorLeavingDuringBreakStillRevivesConnectedSquadmate(t *testing.T) {
	h, _, r := survivalRoom427(t, 2)
	g := r.Game
	g.startMatch(r.Players)
	g.Phase = "playing"
	g.Tanks[0].Alive = false
	clearSurvivalWave427(t, r)
	h.expirePlayer(r, 1)
	g.step(2, [maxTanks]Input{}, r.Players)
	if g.Phase != "playing" || g.survivalState().Status != "break" || g.Tanks[0].Alive {
		t.Fatal("last survivor leaving cancelled an already-earned squad revival")
	}
	g.step(2, [maxTanks]Input{}, r.Players)
	if g.Phase != "playing" || g.survivalState().Wave != 2 || g.survivalState().Status != "wave" || !g.Tanks[0].Alive {
		t.Fatal("connected squadmate did not revive for the next wave")
	}
}
