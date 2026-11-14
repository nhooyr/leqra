package main

import (
	"encoding/json"
	"fmt"
	"math"
	"testing"
	"time"
)

func assertContact(t *testing.T, contact *projectileContact, target, life int, kind string, before contactTankState, projectile bool) {
	t.Helper()
	if contact == nil || contact.Target != target || contact.SpawnSerial != life || contact.Kind != kind || contact.Before != before || contact.Tick < 0 || math.IsNaN(contact.Tick) || math.IsInf(contact.Tick, 0) {
		t.Fatalf("missing/mismatched pre-contact identity: %+v, want target %d life %d %s before %+v", contact, target, life, kind, before)
	}
	if (contact.ProjectileID > 0) != projectile {
		t.Fatal("instantaneous/ballistic contact has the wrong projectile identity", contact)
	}
	data, err := json.Marshal(contact)
	if err != nil || len(data) > 1024 {
		t.Fatal("invalid/unbounded contact metadata", err, len(data))
	}
}

func TestAllFixedBallisticsLinkHitAndShieldToExactTerminalContact(t *testing.T) {
	for _, kind := range []string{"regular", "rapid", "scatter", "homing", "grenade", "cannon"} {
		for _, shield := range []bool{false, true} {
			for _, published := range []bool{false, true} {
				for _, boosted := range []bool{false, true} {
					t.Run(fmt.Sprintf("%s/shield_%t/published_%t/starman_%t", kind, shield, published, boosted), func(t *testing.T) {
						g := battle(2)
						g.Tick = 2
						pilot, target := g.Tanks[0], g.Tanks[1]
						target.X, target.Y = pilot.X+35, pilot.Y
						target.VX, target.VY, target.SpawnSerial, target.SpeedTime, target.SpeedStacks, target.GhostTime = 75, -13, 17, 9, 5, 9
						if shield {
							target.Shield, target.ShieldCharges = 9, 3
						}
						if kind != "regular" {
							g.grantPower(pilot, kind)
						}
						if boosted {
							g.grantPower(pilot, "starman")
							pilot.SpeedTime, pilot.SpeedStacks = 9, 5
						}
						if published {
							target.X, target.Y = 450, 350
							g.fire(pilot)
							if len(g.Bullets) == 0 {
								t.Fatal("no published test projectile")
							}
							b := g.Bullets[0]
							b.publishFlight(float64(g.Tick))
							angle := math.Atan2(b.VY, b.VX)
							target.X, target.Y = b.X+(target.R+b.R+.5)*math.Cos(angle), b.Y+(target.R+b.R+.5)*math.Sin(angle)
						}
						before := tankContactBefore(target)
						if published {
							g.Tick++
							g.updateBullets(tickDT)
						} else {
							g.fire(pilot)
						}
						contacts, flights := 0, map[int]*cannonFlight{}
						for _, event := range g.projectileSnapshotEvents(nil) {
							if event.Flight != nil {
								flights[event.Flight.ID] = event.Flight
							}
						}
						for _, event := range g.projectileSnapshotEvents(nil) {
							if event.Contact == nil {
								continue
							}
							contacts++
							assertContact(t, event.Contact, target.ID, target.SpawnSerial, kind, before, true)
							flight := flights[event.Contact.ProjectileID]
							if flight == nil || math.Abs(flight.EndTick-event.Contact.Tick) > 1e-8 || flight.EndTick > float64(g.Tick) {
								t.Fatal("victim transition is not tied to its exact terminal endpoint", event, flight)
							}
							if shield && event.Type != "shield" || !shield && event.Type != "hit" {
								t.Fatal("contact changed the authoritative damage result", event.Type)
							}
						}
						if contacts != 1 || shield && (!target.Alive || target.ShieldCharges != 2) || !shield && target.Alive {
							t.Fatal("visual metadata duplicated/altered damage", contacts, target.Alive, target.ShieldCharges)
						}
					})
				}
			}
		}
	}
}

func TestAllInfinityBallisticsLinkHitAndShieldToExactTerminalContact(t *testing.T) {
	for _, kind := range []string{"regular", "rapid", "scatter", "homing", "grenade", "cannon"} {
		for _, shield := range []bool{false, true} {
			for _, published := range []bool{false, true} {
				a := newSeededInfiniteArena(37)
				a.tick = 2
				pilot := a.join(fakeClient(), "Pilot", time.Unix(0, 0))
				target := a.join(fakeClient(), "Target", time.Unix(0, 0))
				pilot.X, pilot.Y, pilot.Angle, pilot.Protected, pilot.kit.Invulnerable, pilot.kit.SpawnProtected = 42, 42, 0, false, 0, false
				target.X, target.Y, target.Protected, target.kit.Invulnerable, target.kit.SpawnProtected = 77, 42, false, 0, false
				target.VX, target.VY, target.Spawn, target.kit.SpeedTime, target.kit.SpeedStacks, target.kit.GhostTime = 75, -13, 17, 9, 5, 9
				if shield {
					target.kit.Shield, target.kit.ShieldCharges = 9, 3
				}
				if kind != "regular" {
					applyPower(&pilot.kit, kind, infinitePowerDuration, infiniteStarDuration)
				}
				if published {
					target.X, target.Y = 500, 500
					a.fire(pilot)
					if len(a.bullets) == 0 {
						t.Fatal("no published Infinity test projectile", kind)
					}
					b := &a.bullets[0]
					b.publishFlight(float64(a.tick))
					angle := math.Atan2(b.VY, b.VX)
					target.X, target.Y = b.X+(tankRadius+b.radius+.5)*math.Cos(angle), b.Y+(tankRadius+b.radius+.5)*math.Sin(angle)
				}
				before := pilotContactBefore(target)
				if published {
					a.tick++
					a.advanceBullets()
				} else {
					a.fire(pilot)
				}
				contacts, flights := 0, map[int]*cannonFlight{}
				for _, effect := range a.projectileSnapshotEffects(nil) {
					if effect.Flight != nil {
						flights[effect.Flight.ID] = effect.Flight
					}
				}
				for _, effect := range a.projectileSnapshotEffects(nil) {
					if effect.Contact == nil {
						continue
					}
					contacts++
					assertContact(t, effect.Contact, target.ID, target.Spawn, kind, before, true)
					flight := flights[effect.Contact.ProjectileID]
					if flight == nil || math.Abs(flight.EndTick-effect.Contact.Tick) > 1e-8 || effect.Tick != a.tick {
						t.Fatal("Infinity victim transition lacks its shared terminal clock", kind, effect, flight)
					}
				}
				if contacts != 1 || shield && (target.HP == 0 || target.kit.ShieldCharges != 2) || !shield && target.HP > 0 {
					t.Fatal("Infinity contact metadata changed damage", kind, contacts, target.HP, target.kit.ShieldCharges)
				}
			}
		}
	}
}

func TestInstantLaserAndStarmanContactsKeepVictimLifeAndBeforeState(t *testing.T) {
	for _, kind := range []string{"laser", "starman"} {
		g := battle(2)
		g.Tick = 10
		pilot, target := g.Tanks[0], g.Tanks[1]
		target.X, target.Y, target.SpawnSerial = pilot.X+35, pilot.Y, 21
		before := tankContactBefore(target)
		if kind == "laser" {
			g.grantPower(pilot, "laser")
			g.fire(pilot)
		} else {
			pilot.StarmanTime = 8
			g.starmanRam(pilot, target)
		}
		if target.Alive {
			t.Fatal("instant fixture did not damage", kind)
		}
		found := false
		for _, event := range g.events {
			if event.Type == "hit" {
				assertContact(t, event.Contact, target.ID, 21, kind, before, false)
				if event.Contact.Tick != 10 {
					t.Fatal("instant contact drifted off its beam/body tick")
				}
				found = true
			}
		}
		if !found {
			t.Fatal("missing instant victim contact", kind)
		}
		a := newSeededInfiniteArena(37)
		a.tick = 10
		shooter := a.join(fakeClient(), "Pilot", time.Unix(0, 0))
		victim := a.join(fakeClient(), "Target", time.Unix(0, 0))
		shooter.X, shooter.Y, shooter.Angle, shooter.Protected, shooter.kit.Invulnerable, shooter.kit.SpawnProtected = 42, 42, 0, false, 0, false
		victim.X, victim.Y, victim.Spawn, victim.Protected, victim.kit.Invulnerable, victim.kit.SpawnProtected = 77, 42, 21, false, 0, false
		before = pilotContactBefore(victim)
		if kind == "laser" {
			a.fireLaser(shooter)
		} else {
			shooter.kit.StarmanTime = 8
			victim.X = 62
			before = pilotContactBefore(victim)
			a.resolveStarmanContacts([]*infinitePilot{shooter, victim})
		}
		found = false
		for _, effect := range a.effects {
			if effect.Kind == "hit" {
				assertContact(t, effect.Contact, victim.ID, 21, kind, before, false)
				if effect.Tick != 10 || effect.Contact.Tick != 10 {
					t.Fatal("Infinity instantaneous effect is not on the global timeline")
				}
				found = true
			}
		}
		if !found || victim.HP != 0 {
			t.Fatal("missing Infinity instantaneous victim contact", kind)
		}
	}
}

func TestGrenadeVictimsShareOneTerminalFlightAndKeepIndependentLifeSnapshots(t *testing.T) {
	g := battle(4)
	g.Tick = 10
	for id, target := range g.Tanks {
		if target != nil {
			target.SpawnSerial, target.VX, target.VY = id+20, 12, -3
		}
	}
	g.Tanks[1].Shield, g.Tanks[1].ShieldCharges = 9, 3
	before := map[int]contactTankState{}
	for id, target := range g.Tanks {
		if target != nil {
			before[id] = tankContactBefore(target)
		}
	}
	b := &Bullet{ID: 99, Owner: 0, Kind: "grenade", R: 6, X: 200, Y: 210, Age: 1, Life: 9, Color: tankColors[0]}
	b.beginFlight(b.X, b.Y, 9)
	b.X, b.flightAge = 240, 1.01
	g.detonate(b)
	flights, contacts := 0, 0
	for _, event := range g.projectileSnapshotEvents(nil) {
		if event.Flight != nil {
			flights++
		}
		if event.Contact != nil {
			contacts++
			c := event.Contact
			assertContact(t, c, event.Player, event.Player+20, "grenade", before[event.Player], true)
			if c.ProjectileID != 99 || math.Abs(c.Tick-b.flight.EndTick) > 1e-9 || c.Target == b.Owner {
				t.Fatal("grenade victims did not share the single blast contact", c)
			}
		}
	}
	if flights != 1 || contacts != 3 || !g.Tanks[0].Alive || !g.Tanks[1].Alive || g.Tanks[2].Alive || g.Tanks[3].Alive {
		t.Fatal("contact metadata duplicated blast damage or damaged the owner", flights, contacts)
	}
	g.Tanks[2].SpawnSerial++
	g.Tanks[2].X += 100
	for _, event := range g.projectileSnapshotEvents(nil) {
		if event.Contact != nil && event.Contact.Target == 2 && (event.Contact.SpawnSerial != 22 || event.Contact.Before != before[2]) {
			t.Fatal("a later life mutated the old victim's contact snapshot")
		}
	}
}

func TestInfinityGrenadeVictimsShareOneTerminalFlight(t *testing.T) {
	a := newSeededInfiniteArena(37)
	a.tick = 10
	var pilots []*infinitePilot
	before := map[int]contactTankState{}
	for i := range 4 {
		p := a.join(fakeClient(), fmt.Sprintf("Pilot%d", i), time.Unix(0, 0))
		p.X, p.Y, p.VX, p.VY, p.Spawn = 42+float64(i*8), 42, 12, -3, p.ID+20
		p.Protected, p.kit.Invulnerable, p.kit.SpawnProtected = false, 0, false
		if i == 1 {
			p.kit.Shield, p.kit.ShieldCharges = 9, 3
		}
		pilots = append(pilots, p)
		before[p.ID] = pilotContactBefore(p)
	}
	b := &infiniteBullet{ID: 99, Owner: pilots[0].ID, Kind: "grenade", X: 70, Y: 42, radius: 6, age: 1, Life: 9}
	b.beginFlight(b.X, b.Y, 9)
	b.X, b.flightAge = 72, 1.01
	a.detonate(b)
	flights, contacts := 0, 0
	for _, effect := range a.projectileSnapshotEffects(nil) {
		if effect.Flight != nil {
			flights++
		}
		if effect.Contact != nil {
			contacts++
			c := effect.Contact
			assertContact(t, c, c.Target, c.Target+20, "grenade", before[c.Target], true)
			if c.ProjectileID != 99 || math.Abs(c.Tick-b.flight.EndTick) > 1e-9 || c.Target == b.Owner {
				t.Fatal("Infinity grenade victims did not share the single blast contact", c)
			}
		}
	}
	if flights != 1 || contacts != 3 || pilots[0].HP == 0 || pilots[1].HP == 0 || pilots[2].HP > 0 || pilots[3].HP > 0 {
		t.Fatal("Infinity contact metadata duplicated blast damage or damaged the owner", flights, contacts)
	}
}

func TestInfinityEveryHittingStarmanLaserPublishesBeamBeforeVictimContact(t *testing.T) {
	for _, shield := range []bool{false, true} {
		a := newSeededInfiniteArena(37)
		a.tick = 10
		p := a.join(fakeClient(), "Pilot", time.Unix(0, 0))
		target := a.join(fakeClient(), "Target", time.Unix(0, 0))
		p.X, p.Y, p.Angle, p.kit.StarmanTime, p.kit.ShotSerial = 42, 42, 0, 9, 1
		p.Protected, p.kit.Invulnerable, p.kit.SpawnProtected = false, 0, false
		target.X, target.Y, target.Protected, target.kit.Invulnerable, target.kit.SpawnProtected = 77, 42, false, 0, false
		if shield {
			target.kit.Shield, target.kit.ShieldCharges = 9, 3
		}
		a.fireLaser(p) // Second volley normally skips the cosmetic one-in-four beam.
		beamID, contactID := 0, 0
		for _, effect := range a.projectileSnapshotEffects(nil) {
			if effect.Kind == "laser" && len(effect.Points) >= 2 && effect.Tick == a.tick {
				beamID = effect.ID
			}
			if effect.Contact != nil && effect.Contact.Kind == "laser" && effect.Contact.Target == target.ID {
				contactID = effect.ID
			}
		}
		if beamID == 0 || contactID <= beamID || p.kit.ShotSerial != 2 {
			t.Fatal("a damaging Star laser volley lost its causative visible beam", shield, beamID, contactID)
		}
	}
}
