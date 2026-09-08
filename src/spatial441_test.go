package main

import (
	"math"
	"math/rand"
	"slices"
	"testing"
)

type spatialQuery441 struct{ x, y, dx, dy, r float64 }

func spatialFixture441(kind string, size ...string) (*Game, []spatialQuery441) {
	g := newGame(441)
	g.Rules.MapSize = "ultrawide"
	if len(size) > 0 {
		g.Rules.MapSize = size[0]
	}
	g.startMatch(testPlayers(maxTanks))
	rng := rand.New(rand.NewSource(441))
	queries := make([]spatialQuery441, 4096)
	for i := range queries {
		q := spatialQuery441{x: 10 + rng.Float64()*(g.World.Width-20), y: 10 + rng.Float64()*(g.World.Height-20)}
		switch kind {
		case "movement":
			q.dx = (rng.Float64() - .5) * 10
			q.dy = (rng.Float64() - .5) * 10
			q.r = 17
		case "aiming":
			q.dx = (rng.Float64() - .5) * 840
			q.dy = (rng.Float64() - .5) * 840
			q.r = 3.5
		default:
			a := rng.Float64() * math.Pi * 2
			q.dx = math.Cos(a) * (g.World.Width + g.World.Height)
			q.dy = math.Sin(a) * (g.World.Width + g.World.Height)
			q.r = 3
		}
		queries[i] = q
	}
	g.wallCandidates(42, 42, 1, 1, 3)
	return g, queries
}

var spatialSink441 float64

func BenchmarkSpatial441(b *testing.B) {
	for _, kind := range []string{"movement", "aiming", "laser"} {
		b.Run(kind, func(b *testing.B) {
			for _, operation := range []string{"candidates", "ray"} {
				b.Run(operation, func(b *testing.B) {
					g, qs := spatialFixture441(kind)
					b.ReportAllocs()
					b.ResetTimer()
					for n := 0; n < b.N; n++ {
						q := qs[n%len(qs)]
						if operation == "candidates" {
							spatialSink441 = float64(len(g.wallCandidates(q.x, q.y, q.dx, q.dy, q.r)))
						} else {
							h, ok := g.rayWallsHit(q.x, q.y, q.dx, q.dy, q.r)
							if ok {
								spatialSink441 = h.T + h.NX + h.NY
							}
						}
					}
				})
			}
		})
	}
}

func expectedCandidates441(g *Game, q spatialQuery441) []int {
	cols, rows := g.World.Cols, g.World.Rows
	x0 := int(clamp(math.Floor((math.Min(q.x, q.x+q.dx)-q.r)/cellSize), 0, float64(cols-1)))
	x1 := int(clamp(math.Floor((math.Max(q.x, q.x+q.dx)+q.r)/cellSize), 0, float64(cols-1)))
	y0 := int(clamp(math.Floor((math.Min(q.y, q.y+q.dy)-q.r)/cellSize), 0, float64(rows-1)))
	y1 := int(clamp(math.Floor((math.Max(q.y, q.y+q.dy)+q.r)/cellSize), 0, float64(rows-1)))
	all := len(g.World.Walls) < 24 || (x1-x0+1)*(y1-y0+1) > cols*rows/3
	var expected []int
	// Independent interval-overlap oracle, filtering original wall order without
	// cell-bin gathering, sorting, stamps, or bit operations.
	for i, w := range g.World.Walls {
		wx0 := int(clamp(math.Floor(w.X/cellSize), 0, float64(cols-1)))
		wx1 := int(clamp(math.Floor((w.X+w.W)/cellSize), 0, float64(cols-1)))
		wy0 := int(clamp(math.Floor(w.Y/cellSize), 0, float64(rows-1)))
		wy1 := int(clamp(math.Floor((w.Y+w.H)/cellSize), 0, float64(rows-1)))
		if all || wx0 <= x1 && wx1 >= x0 && wy0 <= y1 && wy1 >= y0 {
			expected = append(expected, i)
		}
	}
	return expected
}
func TestSpatial441CandidatesPreserveOrderedMembership(t *testing.T) {
	for _, size := range []string{"compact", "standard", "large", "huge", "giant", "ultrawide"} {
		for _, kind := range []string{"movement", "aiming", "laser"} {
			g, qs := spatialFixture441(kind, size)
			for n, q := range qs[:512] {
				got := g.wallCandidates(q.x, q.y, q.dx, q.dy, q.r)
				want := expectedCandidates441(g, q)
				if !slices.Equal(got, want) {
					t.Fatalf("%s %s query%d: %v != %v", size, kind, n, got, want)
				}
			}
		}
	}
}
func TestSpatial441ExactRayParityIncludingGiantAndUltrawide(t *testing.T) {
	for _, size := range []string{"compact", "large", "giant", "ultrawide"} {
		for _, kind := range []string{"movement", "aiming", "laser"} {
			g, qs := spatialFixture441(kind, size)
			for n, q := range qs[:512] {
				got, ok := g.rayWallsHit(q.x, q.y, q.dx, q.dy, q.r)
				want := g.bruteWalls35(q.x, q.y, q.dx, q.dy, q.r)
				if ok != (want != nil) || ok && got != *want {
					t.Fatalf("%s %s query%d: %+v/%v != %+v", size, kind, n, got, ok, want)
				}
			}
		}
	}
}
func TestSpatial441MaskBoundariesClearingAndInvalidation(t *testing.T) {
	g := newGame(441)
	g.World = World{Cols: 24, Rows: 14, Width: 24 * 84, Height: 14 * 84}
	for i := 0; i < 193; i++ {
		g.World.Walls = append(g.World.Walls, Wall{X: 84 + float64(i%3)*84, Y: 84 + float64(i/32)*84, W: 92, H: 92})
	}
	q := spatialQuery441{x: 80, y: 80, dx: 280, dy: 570, r: 3}
	check := func() {
		t.Helper()
		if got, want := g.wallCandidates(q.x, q.y, q.dx, q.dy, q.r), expectedCandidates441(g, q); !slices.Equal(got, want) {
			t.Fatalf("stale, duplicate or misordered candidates: %v != %v", got, want)
		}
	}
	check()
	if len(g.wallCandidates(q.x, q.y, q.dx, q.dy, q.r)) != 193 {
		t.Fatal("high-bit candidates omitted")
	}
	for n := 0; n < 10; n++ {
		check()
		if got := g.wallCandidates(1200, 900, 100, 100, 3); len(got) != 0 {
			t.Fatalf("previous bits survived an empty query: %v", got)
		}
	}
	g.World.Walls = append([]Wall(nil), g.World.Walls...)
	g.World.Walls[63].X = 1700
	check()
	g.World.Walls = append(g.World.Walls, Wall{X: 84, Y: 84, W: 8, H: 92})
	check()
	g.World.Cols = 12
	g.World.Width = 12 * 84
	check()
	if g.spatial.cols != 12 || g.spatial.count != 194 {
		t.Fatal("dimensions/count failed to invalidate spatial index")
	}
}

func TestSpatial441SingleCellCandidatesRemainStableAcrossQueries(t *testing.T) {
	g, _ := spatialFixture441("movement")
	original := g.wallCandidates(42, 42, 1, 1, 0)
	want := append([]int(nil), original...)
	g.wallCandidates(80, 80, 280, 400, 3)
	if !slices.Equal(original, want) {
		t.Fatal("another query overwrote the cached single-cell wall order")
	}
	again := g.wallCandidates(43, 43, 1, 1, 0)
	if len(again) > 0 && &again[0] != &original[0] {
		t.Fatal("unchanged single-cell sweep rebuilt its candidate list")
	}
}
