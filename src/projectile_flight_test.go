package main

import (
	"encoding/json"
	"math"
	"testing"
	"time"
)

func checkProjectileFlight(t *testing.T, flight *cannonFlight, kind string, endpoint BeamPoint) {
	t.Helper()
	if flight == nil || flight.ID <= 0 || flight.Kind != kind || flight.Radius <= 0 || len(flight.Points) < 2 || len(flight.Points) > 32 || flight.StartTick > flight.EndTick {
		t.Fatalf("missing or invalid authoritative %s flight: %+v", kind, flight)
	}
	previous := math.Inf(-1)
	for _, p := range flight.Points {
		if math.IsNaN(p.X) || math.IsInf(p.X, 0) || math.IsNaN(p.Y) || math.IsInf(p.Y, 0) || math.IsNaN(p.Tick) || math.IsInf(p.Tick, 0) || p.Tick < previous {
			t.Fatal("non-finite or unordered flight point", p)
		}
		previous = p.Tick
	}
	last := flight.Points[len(flight.Points)-1]
	if last.X != endpoint.X || last.Y != endpoint.Y || flight.EndTick != last.Tick || flight.StartTick != flight.Points[0].Tick {
		t.Fatal("flight did not stop exactly at its authoritative contact", flight, endpoint)
	}
	data, err := json.Marshal(flight)
	if err != nil || len(data) > 4096 {
		t.Fatal("flight descriptor is invalid or unbounded", err, len(data))
	}
}

func TestAllBallisticMuzzleHitsPublishOneAuthoritativeFlightWithoutAnotherProjectile(t *testing.T) {
	for _, kind := range []string{"regular", "rapid", "scatter", "homing", "grenade", "cannon"} {
		t.Run(kind, func(t *testing.T) {
			g := battle(2)
			g.Tick = 2
			pilot, target := g.Tanks[0], g.Tanks[1]
			target.X, target.Y = pilot.X+35, pilot.Y
			if kind != "regular" {
				g.grantPower(pilot, kind)
			}
			if !g.fire(pilot) || target.Alive {
				t.Fatal("muzzle fixture did not fire and resolve its authoritative hit")
			}
			found := 0
			for _, event := range g.events {
				if event.Flight == nil {
					continue
				}
				found++
				checkProjectileFlight(t, event.Flight, kind, BeamPoint{event.X, event.Y})
				for _, bullet := range g.Bullets {
					if bullet.ID == event.Flight.ID {
						t.Fatal("an already impacting projectile retained a damaging body")
					}
				}
			}
			if found != 1 || pilot.stats.Eliminations != 1 || target.stats.Deaths != 1 {
				t.Fatal("terminal visual was missing, duplicated, or changed damage", found)
			}
		})
	}
}

func TestCannonBornAndHitBetweenBroadcastsSurvivesRoundEndAsFlight(t *testing.T) {
	g := battle(2)
	pilot, target := g.Tanks[0], g.Tanks[1]
	target.X, target.Y = pilot.X+85, pilot.Y
	g.grantPower(pilot, "cannon")
	var input [maxTanks]Input
	input[0].Fire = true
	g.step(tickDT, input, testPlayers(2))
	g.step(tickDT, [maxTanks]Input{}, testPlayers(2))
	if len(g.Bullets) != 0 || target.Alive || g.Phase != "roundOver" {
		t.Fatal("fixture did not finish its whole flight between state broadcasts")
	}
	var flight *cannonFlight
	for _, event := range g.events {
		if event.Flight != nil {
			flight = event.Flight
			checkProjectileFlight(t, flight, "cannon", BeamPoint{event.X, event.Y})
		}
	}
	if flight == nil || flight.StartTick != 0 || flight.EndTick <= 0 || flight.EndTick > 2 {
		t.Fatal("missing fractional tick bounds on a between-broadcast kill", flight)
	}
}

func TestTerminalFlightKeepsOriginalShotAndLifeIdentity(t *testing.T) {
	g := battle(2)
	g.Tick = 1
	pilot, target := g.Tanks[0], g.Tanks[1]
	target.X, target.Y = pilot.X+85, pilot.Y
	g.grantPower(pilot, "cannon")
	g.fire(pilot)
	b := g.Bullets[0]
	shot, life := b.ShotSerial, b.SpawnSerial
	pilot.ShotSerial, pilot.SpawnSerial = shot+4, life+1
	for i := 0; i < 3 && target.Alive; i++ {
		g.Tick++
		g.updateBullets(tickDT)
	}
	for _, event := range g.events {
		if event.Flight != nil && event.Flight.ID == b.ID {
			if event.ShotSerial != shot || event.SpawnSerial != life || event.Owner != pilot.ID {
				t.Fatal("terminal event borrowed its owner's newer shot/life identity", event)
			}
			return
		}
	}
	t.Fatal("fixture did not create a terminal flight")
}

func TestTerminalScatterFlightKeepsItsPelletIdentity(t *testing.T) {
	g := battle(2)
	g.Tick = 1
	pilot, target := g.Tanks[0], g.Tanks[1]
	target.X, target.Y = pilot.X+100*math.Cos(.21), pilot.Y+22
	g.grantPower(pilot, "scatter")
	g.fire(pilot)
	shot, life := pilot.ShotSerial, pilot.SpawnSerial
	pilot.ShotSerial, pilot.SpawnSerial = shot+4, life+1
	for i := 0; i < 20 && target.Alive; i++ {
		g.Tick++
		g.updateBullets(tickDT)
	}
	for _, event := range g.events {
		if event.Flight != nil {
			if event.Flight.Kind != "scatter" || event.Pellet != 2 || event.ShotSerial != shot || event.SpawnSerial != life {
				t.Fatal("terminal scatter event lost the impacting pellet's original identity", event)
			}
			return
		}
	}
	t.Fatal("scatter fixture did not publish its upper pellet impact")
}

func TestPublishedProjectileContactKeepsRecentFlightAndCannonKeepsRimPath(t *testing.T) {
	for _, kind := range []string{"regular", "rapid", "scatter", "homing", "grenade", "cannon"} {
		g := battle(2)
		g.Tick = 2
		pilot, target := g.Tanks[0], g.Tanks[1]
		target.X, target.Y = 450, 350
		if kind != "regular" {
			g.grantPower(pilot, kind)
		}
		g.fire(pilot)
		if len(g.Bullets) == 0 {
			t.Fatal("fixture has no live projectile", kind)
		}
		b := g.Bullets[0]
		b.publishFlight(float64(g.Tick))
		start := BeamPoint{b.X, b.Y}
		target.X, target.Y = b.X+target.R+b.R+1, b.Y
		g.Tick++
		g.updateBullets(tickDT)
		found := false
		for _, event := range g.events {
			if event.Flight != nil {
				found = true
				checkProjectileFlight(t, event.Flight, kind, BeamPoint{event.X, event.Y})
				if kind != "cannon" && (event.Flight.StartTick != 2 || event.Flight.Points[0].X != start.X || event.Flight.Points[0].Y != start.Y) {
					t.Fatal("published contact replayed an old muzzle rather than its recent authoritative segment", kind)
				}
			}
		}
		if !found {
			t.Fatal("published projectile contact omitted its visual endpoint", kind)
		}
	}
	g := battle(2)
	g.Tick = 1
	pilot, target := g.Tanks[0], g.Tanks[1]
	pilot.X, target.X = 250, 100
	g.grantPower(pilot, "cannon")
	g.fire(pilot)
	for i := 0; i < 60 && target.Alive; i++ {
		g.Tick++
		g.updateBullets(tickDT)
	}
	for _, event := range g.events {
		if event.Flight != nil {
			checkProjectileFlight(t, event.Flight, "cannon", BeamPoint{event.X, event.Y})
			if len(event.Flight.Points) < 3 {
				t.Fatal("rim ricochet was reduced to a line through the maze")
			}
			return
		}
	}
	t.Fatal("ricochet impact omitted its flight")
}

func TestInfiniteAllBallisticMuzzleHitsPublishAuthoritativeFlight(t *testing.T) {
	for _, kind := range []string{"regular", "rapid", "scatter", "homing", "grenade", "cannon"} {
		a := newSeededInfiniteArena(37)
		a.tick = 2
		pilot := a.join(fakeClient(), "Pilot", time.Unix(0, 0))
		target := a.join(fakeClient(), "Target", time.Unix(0, 0))
		pilot.X, pilot.Y, pilot.Angle = 42, 42, 0
		pilot.kit.Invulnerable, pilot.kit.SpawnProtected = 0, false
		target.X, target.Y, target.Protected, target.kit.Invulnerable = 77, 42, false, 0
		if kind != "regular" {
			applyPower(&pilot.kit, kind, infinitePowerDuration, infiniteStarDuration)
		}
		a.fire(pilot)
		found := 0
		for _, effect := range a.effects {
			if effect.Flight != nil {
				found++
				checkProjectileFlight(t, effect.Flight, kind, BeamPoint{effect.X, effect.Y})
			}
		}
		if target.HP != 0 || found != 1 || pilot.Score != 1 {
			t.Fatal("Infinity omitted its unseen terminal flight or changed damage", kind, target.HP, found, pilot.Score)
		}
	}
}
