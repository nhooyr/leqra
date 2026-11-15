package main

import (
	"fmt"
	"math"
	"testing"
)

func TestGhostExpiryHitboxResolvesBeforeEveryAttackOrder(t *testing.T) {
	for _, mode := range []string{"elimination", "ctf", "koth", "survival"} {
		for _, initialTick := range []int{0, 1} {
			for _, right := range []bool{false, true} {
				t.Run(fmt.Sprintf("%s/tick%d/right%v", mode, initialTick, right), func(t *testing.T) {
					g := ghostArena41()
					players := testPlayers(2)
					shooter, target := g.Tanks[0], g.Tanks[1]
					g.Rules.Mode = mode
					shooter.Team, target.Team = 1, 2
					g.initObjectives()
					g.Tick = initialTick
					shooter.X, shooter.Y, shooter.Angle = 150, 210, 0
					target.X, target.Y = 253, 210
					wantX := 273.01
					if right {
						shooter.X, shooter.Angle = 350, math.Pi
						target.X, wantX = 251, 230.99
					}
					if mode == "survival" {
						target.SurvivalEnemy = true
						players[1] = nil
					}
					shooter.Invulnerable, target.Invulnerable = 0, 0
					shooter.SpawnProtected, target.SpawnProtected = false, false
					target.GhostTime = tickDT / 2
					epoch, spawn := target.AmmoEpoch, target.SpawnSerial
					g.grantPower(shooter, "laser")
					g.step(tickDT, [maxTanks]Input{{Fire: true}}, players)
					if !target.Alive || target.GhostTime != 0 || math.Abs(target.X-wantX) > 1e-6 || target.Y != 210 {
						t.Fatalf("expired Ghost was attacked before safe solidification: alive=%v x=%v y=%v ghost=%v", target.Alive, target.X, target.Y, target.GhostTime)
					}
					if target.VX != 0 || target.VY != 0 || target.Track != 0 || target.AmmoEpoch != epoch+1 || target.SpawnSerial != spawn || shooter.ShotSerial != 1 {
						t.Fatal("expiry counted a snap as driving, refilled twice, respawned, or prevented the legal laser")
					}
				})
			}
		}
	}
}
