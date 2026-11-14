package main

import (
	"testing"
	"time"
)

func TestShotgunReloadsAfterSeventeenSimulationTicks(t *testing.T) {
	t.Run("fixed", func(t *testing.T) {
		g := battle(2)
		for _, tank := range g.Tanks {
			if tank != nil {
				tank.Invulnerable = 1000
			}
		}
		p := g.Tanks[0]
		g.grantPower(p, "scatter")
		if !g.fire(p) || p.Cooldown != .27 || p.CooldownTotal != .27 {
			t.Fatal("shotgun did not receive its halved reload")
		}
		var input [maxTanks]Input
		input[0].Fire = true
		for range 16 {
			g.step(tickDT, input, testPlayers(2))
		}
		if p.Charges != 4 || p.ShotSerial != 1 {
			t.Fatal("shotgun fired before 270ms")
		}
		g.step(tickDT, input, testPlayers(2))
		if p.Charges != 3 || p.ShotSerial != 2 {
			t.Fatal("shotgun did not fire on the first ready simulation tick")
		}
	})
	t.Run("infinity", func(t *testing.T) {
		a := newSeededInfiniteArena(37)
		p := a.join(fakeClient(), "Pilot", time.Unix(0, 0))
		p.Protected, p.kit.SpawnProtected, p.kit.Invulnerable = false, false, 0
		applyPower(&p.kit, "scatter", infinitePowerDuration, infiniteStarDuration)
		a.fire(p)
		if p.kit.Cooldown != .27 || p.kit.CooldownTotal != .27 {
			t.Fatal("Infinity shotgun did not receive its halved reload")
		}
		for range 16 {
			a.advanceEquipment(p)
			a.fire(p)
		}
		if p.kit.Charges != 4 || p.kit.ShotSerial != 1 {
			t.Fatal("Infinity shotgun fired before 270ms")
		}
		a.advanceEquipment(p)
		a.fire(p)
		if p.kit.Charges != 3 || p.kit.ShotSerial != 2 {
			t.Fatal("Infinity shotgun did not fire on the first ready tick")
		}
	})
}
