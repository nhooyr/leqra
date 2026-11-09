package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"slices"
	"testing"
)

func TestInfiniteMazeParity(t *testing.T) {
	data, err := os.ReadFile("tests/fixtures/infinite-maze.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixtures []struct {
		Seed   uint32
		Bounds [4]float64
		Count  int
		SHA256 string
	}
	if err := json.Unmarshal(data, &fixtures); err != nil {
		t.Fatal(err)
	}
	for _, fixture := range fixtures {
		m, b := newInfiniteMaze(fixture.Seed), fixture.Bounds
		walls := m.wallsNear(b[0], b[1], b[2], b[3])
		if len(walls) != fixture.Count {
			t.Fatalf("seed %d and bounds %v: got %d walls, want %d", fixture.Seed, b, len(walls), fixture.Count)
		}
		if walls == nil {
			walls = []Wall{}
		}
		encoded, err := json.Marshal(walls)
		if err != nil {
			t.Fatal(err)
		}
		if hash := fmt.Sprintf("%x", sha256.Sum256(encoded)); hash != fixture.SHA256 {
			t.Errorf("seed %d and bounds %v: Go wall hash %s differs from browser wall hash %s", fixture.Seed, b, hash, fixture.SHA256)
		}
	}
}

func TestInfiniteMazeChunkConnectivity(t *testing.T) {
	const cells = infiniteChunkCells
	for seed := uint32(0); seed < 10; seed++ {
		for y := -2; y <= 2; y++ {
			for x := -2; x <= 2; x++ {
				chunk := makeInfiniteChunk(seed, infiniteChunkCoord{x, y})
				seen := [cells * cells]bool{true}
				queue := []int{0}
				reach := func(i int) {
					if !seen[i] {
						seen[i] = true
						queue = append(queue, i)
					}
				}
				for head := 0; head < len(queue); head++ {
					i := queue[head]
					col, row := i%cells, i/cells
					if row > 0 && chunk[i]&infiniteNorth == 0 {
						reach(i - cells)
					}
					if col+1 < cells && chunk[i+1]&infiniteWest == 0 {
						reach(i + 1)
					}
					if row+1 < cells && chunk[i+cells]&infiniteNorth == 0 {
						reach(i + cells)
					}
					if col > 0 && chunk[i]&infiniteWest == 0 {
						reach(i - 1)
					}
				}
				if len(queue) != len(chunk) {
					t.Fatalf("seed %d and chunk (%d, %d): reached %d of %d cells", seed, x, y, len(queue), len(chunk))
				}
				var north, west int
				for i := 0; i < cells; i++ {
					if chunk[i]&infiniteNorth == 0 {
						north++
					}
					if chunk[i*cells]&infiniteWest == 0 {
						west++
					}
				}
				if north != 2 || west != 2 {
					t.Fatalf("seed %d and chunk (%d, %d): north has %d openings and west has %d, want two on each edge", seed, x, y, north, west)
				}
			}
		}
	}
}

func TestInfiniteMazeWallQueriesAndCache(t *testing.T) {
	m := newInfiniteMaze(32)
	const chunkSize = infiniteChunkCells * cellSize
	const edge = -chunkSize
	const x = edge + cellSize/2 // The first cell on a chunk edge always has a wall.
	const radius = 17
	const tangentY = edge - wallSize/2 - radius
	if m.blocked(x, tangentY, radius) || !m.blocked(x, tangentY+.01, radius) {
		t.Fatal("collision should permit tangency and block overlap at a negative chunk boundary")
	}
	walls := m.wallsNear(x, edge, x, edge)
	if len(walls) != 1 || walls[0].Line != edge || walls[0].Axis != "h" {
		t.Fatalf("chunk boundary should report one horizontal wall, got %+v", walls)
	}
	for i := 1; i <= infiniteCacheSize*2; i++ {
		x := float64(i) * chunkSize
		m.wallsNear(x, 0, x, 0)
	}
	if len(m.chunks) != infiniteCacheSize || m.chunks[infiniteChunkCoord{-1, -1}] != nil {
		t.Fatal("chunk cache did not evict old entries")
	}
	if regenerated := m.wallsNear(x, edge, x, edge); !slices.Equal(walls, regenerated) {
		t.Fatalf("wall changed after chunk eviction: %+v became %+v", walls, regenerated)
	}
}

func TestInfiniteMazeQueriesKeepPreviousCellTangencies(t *testing.T) {
	m := newInfiniteMaze(32)
	const halfWall = wallSize / 2
	const chunkSize = infiniteChunkCells * cellSize
	for _, edge := range []float64{-chunkSize, 0, chunkSize} {
		end := edge + halfWall
		for _, axis := range []string{"h", "v"} {
			check := func(low float64) bool {
				x, y := low, edge
				if axis == "v" {
					x, y = y, x
				}
				return slices.ContainsFunc(m.wallsNear(x, y, x, y), func(w Wall) bool {
					return w.Axis == axis && (axis == "h" && w.X+w.W == end || axis == "v" && w.Y+w.H == end)
				})
			}
			if !check(end) || check(math.Nextafter(end, math.Inf(1))) {
				t.Fatalf("%s wall at chunk boundary %g lost its exact endpoint", axis, edge)
			}
		}
	}
}

func TestInfiniteProjectileSweepKeepsTangencies(t *testing.T) {
	const r = tankRadius + infiniteBulletRadius
	a := newSeededInfiniteArena(32)
	target := &infinitePilot{infiniteTank: infiniteTank{ID: 2, HP: 1}}
	a.pilots = []*infinitePilot{target}
	for _, tc := range []struct {
		name       string
		x, y, time float64
	}{
		{"start", -r, 0, 0},
		{"side", 50, r, .5},
		{"end", 100 + r, 0, 1},
	} {
		target.X, target.Y = tc.x, tc.y
		pilot, at := a.hitTarget(1, 0, 0, 0, 100, 0, infiniteBulletRadius, 1+1e-8, false)
		if pilot != target || at != tc.time {
			t.Errorf("%s tangent: got %v at %g, want target at %g", tc.name, pilot != nil, at, tc.time)
		}
	}
}
