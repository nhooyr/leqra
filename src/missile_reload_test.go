package main

import (
	"testing"
	"time"
)

func TestMissileReloadsAfterTwentyTwoSimulationTicks(t *testing.T) {
	t.Run("fixed", func(t *testing.T) {
		g := battle(2)
		for _, tank := range g.Tanks {
			if tank != nil {
				tank.Invulnerable = 1000
			}
		}
		p := g.Tanks[0]
		g.grantPower(p, "homing")
		if !g.fire(p) || p.Cooldown != .36 || p.CooldownTotal != .36 {
			t.Fatal("missile did not receive its halved reload")
		}
		var input [maxTanks]Input
		input[0].Fire = true
		for range 21 {
			g.step(tickDT, input, testPlayers(2))
		}
		if p.Charges != 2 || p.ShotSerial != 1 {
			t.Fatal("missile fired before 360ms")
		}
		g.step(tickDT, input, testPlayers(2))
		if p.Charges != 1 || p.ShotSerial != 2 {
			t.Fatal("missile did not fire on the first ready simulation tick")
		}
	})
	t.Run("infinity", func(t *testing.T) {
		a := newSeededInfiniteArena(37)
		p := a.join(fakeClient(), "Pilot", time.Unix(0, 0))
		p.Protected, p.kit.SpawnProtected, p.kit.Invulnerable = false, false, 0
		applyPower(&p.kit, "homing", infinitePowerDuration, infiniteStarDuration)
		a.fire(p)
		if p.kit.Cooldown != .36 || p.kit.CooldownTotal != .36 {
			t.Fatal("Infinity missile did not receive its halved reload")
		}
		for range 21 {
			a.advanceEquipment(p)
			a.fire(p)
		}
		if p.kit.Charges != 2 || p.kit.ShotSerial != 1 {
			t.Fatal("Infinity missile fired before 360ms")
		}
		a.advanceEquipment(p)
		a.fire(p)
		if p.kit.Charges != 1 || p.kit.ShotSerial != 2 {
			t.Fatal("Infinity missile did not fire on the first ready tick")
		}
	})
}
