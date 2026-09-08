package main

import (
	"math"
	"testing"
)

func Test415MazePickupTiers(t *testing.T) {
	tests := []struct {
		name       string
		cols, rows int
		cap, start int
		lifetime   float64
	}{
		{"compact", 7, 7, 5, 2, 13},
		{"standard", 9, 8, 7, 3, 18},
		{"large", 12, 10, 12, 4, 32},
		{"huge", 14, 12, 17, 5, 45},
		{"giant", 16, 14, 23, 6, 61},
		{"ultrawide", 24, 14, 34, 7, 90},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := pickupCap(tt.cols, tt.rows); got != tt.cap {
				t.Fatalf("pickup cap=%d want %d", got, tt.cap)
			}
			if got := startingPickups(tt.cols, tt.rows); got != tt.start {
				t.Fatalf("starting pickups=%d want %d", got, tt.start)
			}
			if got := pickupLifetime(tt.cols, tt.rows); math.Abs(got-tt.lifetime) > 1e-12 {
				t.Fatalf("pickup lifetime=%v want %v", got, tt.lifetime)
			}
		})
	}
}

func Test415UltraWideRulesAndRound(t *testing.T) {
	rules := defaultRules()
	rules.MapSize = "ultrawide"
	if err := validateRules(rules); err != nil {
		t.Fatalf("ultra-wide rules rejected: %v", err)
	}
	g := newGame(415)
	g.Rules = rules
	g.startMatch(testPlayers(8))
	if g.World.Cols != 24 || g.World.Rows != 14 || g.World.Width != 24*cellSize || g.World.Height != 14*cellSize {
		t.Fatalf("ultra-wide world=%+v", g.World)
	}
	if len(g.Pickups) != 7 {
		t.Fatalf("seed pickups=%d want 7", len(g.Pickups))
	}
	for i, p := range g.Pickups {
		if p == nil || math.Abs(p.Life-90) > 1e-12 {
			t.Fatalf("pickup %d lifetime=%v want 90", i, p.Life)
		}
	}
}

func Test415SpawnedPickupUsesCurrentMazeLifetime(t *testing.T) {
	g := newGame(4151)
	g.Rules.MapSize = "giant"
	g.startMatch(testPlayers(2))
	g.Pickups = nil
	g.spawnPower()
	if len(g.Pickups) != 1 || math.Abs(g.Pickups[0].Life-61) > 1e-12 {
		t.Fatalf("giant spawned pickup=%+v", g.Pickups)
	}

	g.Rules.MapSize = "ultrawide"
	g.startRound(testPlayers(2))
	g.Pickups = nil
	g.spawnPower()
	if len(g.Pickups) != 1 || math.Abs(g.Pickups[0].Life-90) > 1e-12 {
		t.Fatalf("ultra-wide spawned pickup=%+v", g.Pickups)
	}
}
