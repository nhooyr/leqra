package main

import (
	"encoding/json"
	"math"
	"os"
	"testing"
)

type missileParityCase struct {
	Name     string          `json:"name"`
	World    World           `json:"world"`
	Tanks    [maxTanks]*Tank `json:"tanks"`
	Bullet   Bullet          `json:"bullet"`
	Steps    int             `json:"steps"`
	MoveY    float64         `json:"moveY"`
	Expected Bullet          `json:"expected"`
	Alive    bool            `json:"alive"`
}

func runMissileParity(c missileParityCase) (Bullet, bool) {
	g := newGame(42)
	g.World = c.World
	for id, t := range c.Tanks {
		if t != nil {
			copy := *t
			g.Tanks[id] = &copy
		}
	}
	b := c.Bullet
	b.rangeSet = true
	g.Bullets = []*Bullet{&b}
	for i := 0; i < c.Steps; i++ {
		if c.MoveY != 0 {
			g.moveTank(g.Tanks[1], 0, c.MoveY*tickDT)
		}
		g.updateBullets(tickDT)
	}
	return b, g.Tanks[1].Alive
}
func TestMissileGoClientParityFixtures(t *testing.T) {
	path := "tests/missile-fixtures.json"
	if os.Getenv("LEQRA_WRITE_MISSILE_FIXTURES") == "1" {
		cases := []missileParityCase{}
		for _, name := range []string{"free-flight", "wall", "corner", "dodge", "off-axis", "range-expiry", "wall-near-expiry"} {
			g := battle(2)
			g.World = World{Cols: 12, Rows: 8, Width: 1008, Height: 672, Walls: []Wall{{-4, -4, 1016, 8, "h", 0}, {-4, 668, 1016, 8, "h", 672}, {-4, -4, 8, 680, "v", 0}, {1004, -4, 8, 680, "v", 1008}}}
			g.Tanks[0].Alive = false
			g.Tanks[1].X = 330
			g.Tanks[1].Y = 300
			g.Tanks[1].Invulnerable = 20
			b := missileFor(g, 100, 200, 0)
			steps := 40
			move := 0.0
			switch name {
			case "wall":
				b = missileFor(g, 989, 210, 0)
				steps = 20
			case "corner":
				b = missileFor(g, 984, 648, math.Pi/4)
				steps = 20
			case "dodge":
				b = missileFor(g, 250, 300, 0)
				g.Tanks[1].Invulnerable = 0
				move = -128
				steps = 60
			case "off-axis":
				b = missileFor(g, 180, 220, 0)
				g.Tanks[1].Invulnerable = 0
				g.Tanks[1].Y = 250
				steps = 60
			case "range-expiry":
				b.RangeLeft = 1.25
				steps = 1
			case "wall-near-expiry":
				b = missileFor(g, 998, 210, 0)
				b.RangeLeft = 1.02
				steps = 1
			}
			c := missileParityCase{Name: name, World: g.World, Tanks: g.Tanks, Bullet: *b, Steps: steps, MoveY: move}
			c.Expected, c.Alive = runMissileParity(c)
			cases = append(cases, c)
		}
		data, _ := json.MarshalIndent(cases, "", "  ")
		if err := os.WriteFile(path, append(data, '\n'), 0644); err != nil {
			t.Fatal(err)
		}
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var cases []missileParityCase
	if err = json.Unmarshal(data, &cases); err != nil {
		t.Fatal(err)
	}
	for _, c := range cases {
		t.Run(c.Name, func(t *testing.T) {
			got, alive := runMissileParity(c)
			a, _ := json.Marshal(got)
			b, _ := json.Marshal(c.Expected)
			if string(a) != string(b) || alive != c.Alive {
				t.Fatalf("Go/client reference changed: got %s expected %s", a, b)
			}
		})
	}
}
