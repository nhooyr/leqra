package main

import (
	"fmt"
	"path/filepath"
	"slices"
	"testing"
	"time"
)

func TestPublicPickupAndNonHittingFireDoNotWriteDurableState(t *testing.T) {
	s := publicStoreFixture(t, filepath.Join(t.TempDir(), "data.sqlite"))
	connection, _, _ := savedPublicJoin(t, s, infiniteMessage{Name: "Pilot"})
	a, p := s.public, connection.pilot
	p.X, p.Y, p.Angle = 42, 42, 0
	commitPublicFixture(t, s) // Finish admission metadata before isolating gameplay-only events.
	for _, table := range []string{"infinity_scores", "infinity_meta"} {
		if _, err := s.publicDB.Exec("CREATE TRIGGER deny_" + table + " BEFORE INSERT ON " + table + " BEGIN SELECT RAISE(FAIL,'unexpected gameplay-only write'); END"); err != nil {
			t.Fatal(err)
		}
	}
	for _, kind := range pickupTypes {
		p.kit = Tank{}
		a.pickups = []Pickup{{ID: 1, X: p.X, Y: p.Y, Type: kind, Life: 1}}
		a.collectPickup(p)
		a.bullets = a.bullets[:0]
		a.fire(p)
		if p.Score != 0 || a.pickups[0].Life != 0 {
			t.Fatal("grant/fire fixture changed a score or missed its pickup", kind)
		}
		s.mu.Lock()
		err := s.persistPublicLocked(nil, nil)
		s.mu.Unlock()
		if err != nil {
			t.Fatal("pickup or non-hitting fire attempted a durable write", kind, err)
		}
	}
}

func BenchmarkFixedPickupGrant(b *testing.B) {
	for _, kind := range pickupTypes {
		b.Run(kind, func(b *testing.B) {
			g := battle(2)
			p := g.Tanks[0]
			initial := *p
			g.events = make([]Event, 0, 1)
			b.ReportAllocs()
			b.ResetTimer()
			for range b.N {
				*p = initial
				g.events = g.events[:0]
				g.grantPower(p, kind)
			}
			if len(g.events) != 1 {
				b.Fatal("pickup workload did not emit its grant")
			}
		})
	}
}

// These cases include every power-up's authoritative grant and emitted pickup
// effect. Rendering, audio and disk writes are deliberately measured elsewhere.
func BenchmarkInfinityPickupGrant(b *testing.B) {
	for _, kind := range pickupTypes {
		b.Run(kind, func(b *testing.B) {
			a := newSeededInfiniteArena(503)
			p := a.addPilot("Benchmark", false, 0, 0, 0, 0)
			a.pickups = []Pickup{{ID: 1, X: p.X, Y: p.Y, Type: kind, Life: 1}}
			a.effects = make([]infiniteEffect, 0, 1)
			b.ReportAllocs()
			b.ResetTimer()
			for range b.N {
				p.kit = Tank{}
				a.pickups[0].Life = 1
				a.effects = a.effects[:0]
				a.collectPickup(p)
			}
			if a.pickups[0].Life != 0 || len(a.effects) != 1 {
				b.Fatal("pickup workload did not grant the power-up")
			}
		})
	}
}

// Time complete projectile launch and a close-range tank contact, including
// accurate swept collision, score/death updates and causal contact metadata.
func BenchmarkInfinityFireContact(b *testing.B) {
	for _, kind := range []string{"regular", "rapid", "scatter", "homing", "grenade", "laser", "cannon"} {
		for _, cold := range []bool{false, true} {
			b.Run(fmt.Sprintf("%s/coldMaze_%v", kind, cold), func(b *testing.B) {
				a := newSeededInfiniteArena(503)
				a.rules = &infiniteRules{}
				shooter := a.addPilot("Shooter", false, 0, 0, 0, 0)
				target := a.addPilot("Target", false, 0, 0, 0, 0)
				shooter.X, shooter.Y, shooter.Angle = 42, 42, 0
				target.X, target.Y = 70, 42
				a.effects = make([]infiniteEffect, 0, 16)
				a.projectileEffects = make([]infiniteEffect, 0, 16)
				a.bullets = make([]infiniteBullet, 0, 3)
				b.ReportAllocs()
				b.ResetTimer()
				for range b.N {
					if cold {
						a.maze = newInfiniteMaze(503)
					}
					shooter.kit = Tank{}
					shooter.HP, shooter.Protected = 1, false
					target.kit = Tank{}
					target.HP, target.Protected = 1, false
					a.effects, a.projectileEffects, a.bullets = a.effects[:0], a.projectileEffects[:0], a.bullets[:0]
					if kind != "regular" {
						applyPower(&shooter.kit, kind, infinitePowerDuration, infiniteStarDuration)
					}
					a.fire(shooter)
				}
				if target.HP != 0 {
					b.Fatal("projectile workload did not reach the target", kind)
				}
			})
		}
	}
}

// FULL WAL commits can delay snapshot delivery. Report tails as well as the
// average, retaining the same pilot/bot identity instead of growing the table.
func BenchmarkPublicInfinityDurableEvent(b *testing.B) {
	for _, kind := range []string{"unchanged", "score", "botLifeSerial"} {
		b.Run(kind, func(b *testing.B) {
			s := newInfiniteServer(newHub(4))
			if err := s.openPublicStore(filepath.Join(b.TempDir(), "data.sqlite")); err != nil {
				b.Fatal(err)
			}
			defer s.close()
			s.mu.Lock()
			pilot := s.public.addPilot("Benchmark", false, 0, 0, 0, 0)
			bot := s.public.addPilot("Bot", true, 0, 0, 0, 0)
			bot.ambientNumber = 1
			bot.publicBotName()
			if err := s.persistPublicLocked(nil, nil); err != nil {
				b.Fatal(err)
			}
			s.mu.Unlock()
			samples := make([]time.Duration, 0, b.N)
			b.ReportAllocs()
			b.ResetTimer()
			for range b.N {
				start := time.Now()
				s.mu.Lock()
				switch kind {
				case "score":
					pilot.Score++
				case "botLifeSerial":
					bot.Spawn++
				}
				if err := s.persistPublicLocked(nil, nil); err != nil {
					b.Fatal(err)
				}
				s.mu.Unlock()
				samples = append(samples, time.Since(start))
			}
			b.StopTimer()
			slices.Sort(samples)
			for _, percentile := range []int{50, 95, 99, 100} {
				index := max(0, (len(samples)*percentile+99)/100-1)
				b.ReportMetric(float64(samples[index].Nanoseconds())/1e3, fmt.Sprintf("p%d-us", percentile))
			}
		})
	}
}
