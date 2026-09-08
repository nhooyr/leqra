package main

import (
	"math"
	"testing"
)

func TestWallRayIncludesSweepEndpoint(t *testing.T) {
	for _, tc := range []struct {
		name                 string
		x, y, dx, dy, radius float64
		want                 RayHit
	}{
		{"right", 50, 104, 50, 0, 0, RayHit{1, -1, 0}},
		{"left", 150, 104, -42, 0, 0, RayHit{1, 1, 0}},
		{"down", 104, 50, 0, 50, 0, RayHit{1, 0, -1}},
		{"up", 104, 150, 0, -42, 0, RayHit{1, 0, 1}},
		{"corner", 50, 50, 50, 50, 0, RayHit{1, -1, -1}},
		{"expanded", 50, 104, 46.5, 0, 3.5, RayHit{1, -1, 0}},
		{"just before endpoint", 50, 104, 50 / (1 - 5e-8), 0, 0, RayHit{1 - 5e-8, -1, 0}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			g := newGame(1)
			g.World = World{Width: 200, Height: 200, Walls: []Wall{{X: 100, Y: 100, W: 8, H: 8}}}
			got, ok := g.rayWallsHit(tc.x, tc.y, tc.dx, tc.dy, tc.radius)
			if !ok || math.Abs(got.T-tc.want.T) > 1e-12 || got.NX != tc.want.NX || got.NY != tc.want.NY {
				t.Fatalf("endpoint contact = %+v/%v, want %+v", got, ok, tc.want)
			}
			if !g.rayBlocked(tc.x, tc.y, tc.dx, tc.dy, tc.radius) {
				t.Fatal("endpoint contact did not block line of sight")
			}
		})
	}
}

func TestWallRayEndpointMergesCornerNormals(t *testing.T) {
	g := newGame(1)
	g.World = World{Width: 200, Height: 200, Walls: []Wall{
		{X: 100, Y: 0, W: 8, H: 200},
		{X: 0, Y: 100, W: 200, H: 8},
	}}
	got, ok := g.rayWallsHit(50, 50, 50, 50, 0)
	if !ok || got != (RayHit{1, -1, -1}) {
		t.Fatalf("endpoint corner = %+v/%v, want both reflection normals", got, ok)
	}
}

func TestRayBlockedMatchesCollisionQuery(t *testing.T) {
	for _, size := range []string{"compact", "standard", "large", "huge", "giant", "ultrawide"} {
		for _, kind := range []string{"movement", "aiming", "laser"} {
			g, queries := spatialFixture441(kind, size)
			for i, q := range queries {
				_, want := g.rayWallsHit(q.x, q.y, q.dx, q.dy, q.r)
				if got := g.rayBlocked(q.x, q.y, q.dx, q.dy, q.r); got != want {
					t.Fatalf("%s %s query %d: blocked = %v, collision = %v", size, kind, i, got, want)
				}
			}
		}
	}
	g := newGame(1)
	g.World = World{Width: 200, Height: 200, Walls: []Wall{{X: 100, Y: 100, W: 8, H: 8}}}
	for _, tc := range []struct {
		name string
		q    spatialQuery441
		want bool
	}{
		{"beyond segment", spatialQuery441{x: 50, y: 104, dx: 49.999}, false},
		{"stationary inside", spatialQuery441{x: 104, y: 104}, false},
		{"moving from inside", spatialQuery441{x: 104, y: 104, dx: 50}, false},
		{"departing surface", spatialQuery441{x: 100, y: 104, dx: -50}, false},
		{"entering surface", spatialQuery441{x: 100, y: 104, dx: 50}, true},
		{"tiny horizontal axis", spatialQuery441{x: 104, y: 50, dx: 1e-10, dy: 50}, true},
		{"parallel outside", spatialQuery441{x: 99, y: 50, dy: 100}, false},
		{"tangent edge", spatialQuery441{x: 50, y: 100, dx: 100}, true},
		{"within entry tolerance", spatialQuery441{x: 100.00005, y: 104, dx: 1}, true},
		{"past entry tolerance", spatialQuery441{x: 100.001, y: 104, dx: 1}, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			q := tc.q
			_, hit := g.rayWallsHit(q.x, q.y, q.dx, q.dy, q.r)
			if got := g.rayBlocked(q.x, q.y, q.dx, q.dy, q.r); got != tc.want || hit != tc.want {
				t.Fatalf("boundary query %+v: blocked = %v, collision = %v, want %v", q, got, hit, tc.want)
			}
		})
	}
	if g.rayBlocked(50, 104, 49.999, 0, 0) {
		t.Fatal("wall beyond the segment blocked the ray")
	}
}

var rayBlockedSink bool

func BenchmarkRayBlocked(b *testing.B) {
	for _, kind := range []string{"movement", "aiming", "laser"} {
		b.Run(kind, func(b *testing.B) {
			g, queries := spatialFixture441(kind)
			b.ReportAllocs()
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				q := queries[i%len(queries)]
				rayBlockedSink = g.rayBlocked(q.x, q.y, q.dx, q.dy, q.r)
			}
		})
	}
}
