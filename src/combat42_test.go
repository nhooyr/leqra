package main

import (
	"encoding/json"
	"math"
	"testing"
)

func combat42Game() (*Game, *Tank) {
	g := newGame(42)
	g.makeMaze(12, 10)
	g.Phase = "playing"
	g.Generation = 2
	g.Tick = 60
	t := &Tank{ID: 7, Name: "P2", Alive: true, X: 210, Y: 210, R: tankRadius, SpawnSerial: 3, Color: tankColors[7]}
	g.Tanks[7] = t
	return g, t
}
func Test42AcceptedVolleyIdentity(t *testing.T) {
	for _, power := range []string{"", "rapid", "scatter", "homing", "grenade", "cannon", "laser"} {
		t.Run(power, func(tst *testing.T) {
			g, t := combat42Game()
			if power != "" {
				g.grantPower(t, power)
			}
			g.events = nil
			if !g.fire(t) || t.ShotSerial != 1 {
				tst.Fatal("accepted shot needs identity")
			}
			if g.fire(t) || t.ShotSerial != 1 {
				tst.Fatal("rejected cooldown must not consume identity")
			}
			for i, b := range g.Bullets {
				if b.ShotSerial != 1 || b.SpawnSerial != 3 || b.Pellet != i || b.Owner != 7 {
					tst.Fatalf("bad projectile identity %+v", b)
				}
			}
			count := 0
			for _, e := range g.events {
				if e.Type == "shot" {
					count++
					if e.ShotSerial != 1 || e.SpawnSerial != 3 || e.Tick != 60 {
						tst.Fatal(e)
					}
				}
			}
			if count != 1 {
				tst.Fatal("one event per volley")
			}
		})
	}
}
func Test42FrozenCooldownAndScoresAfterRound(t *testing.T) {
	g, tank := combat42Game()
	g.fire(tank)
	g.finishRound(7)
	before, points := tank.Cooldown, g.Scores
	for n := 0; n < 60; n++ {
		g.step(tickDT, [maxTanks]Input{}, [maxTanks]*Player{})
	}
	if tank.Cooldown != before || g.Scores != points {
		t.Fatal("round result advanced weapon or scoring")
	}
}
func Test42ShotMetadataSurvivesSnapshotWithoutClientAuthority(t *testing.T) {
	g, tank := combat42Game()
	g.fire(tank)
	r := &Room{Game: g}
	h := &Hub{}
	wire, e := json.Marshal(h.stateMessage(r))
	if e != nil {
		t.Fatal(e)
	}
	var packet struct {
		Tanks   []Tank   `json:"tanks"`
		Bullets []Bullet `json:"bullets"`
	}
	if json.Unmarshal(wire, &packet) != nil {
		t.Fatal("wire")
	}
	if len(packet.Bullets) != 1 || packet.Tanks[0].ShotSerial != 1 || packet.Bullets[0].ShotSerial != 1 {
		t.Fatal(string(wire))
	}
	var in Input
	if json.Unmarshal([]byte(`{"seq":12,"fire":true,"shotSerial":1000,"cooldown":0,"damage":999}`), &in) != nil {
		t.Fatal("input")
	}
	if in.Seq != 12 || !in.Fire || tank.ShotSerial != 1 {
		t.Fatal("client cannot grant a shot")
	}
}
func Test42TimingMetadataDoesNotChangeProjectileTuning(t *testing.T) {
	g, tank := combat42Game()
	g.grantPower(tank, "cannon")
	g.fire(tank)
	b := g.Bullets[0]
	if b.R != 14 || math.Abs(math.Hypot(b.VX, b.VY)-1128) > 1e-9 || b.Life != 5.3 {
		t.Fatal("cannon changed")
	}
}
