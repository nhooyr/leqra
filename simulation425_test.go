package main

import (
	"fmt"
	"math"
	"slices"
	"testing"
)

func TestBotStopsMovingAfterOwnGrenadeKillsIt425(t *testing.T) {
	g := battle(2)
	bot := g.Tanks[0]
	bot.Bot = true
	bot.AI = &BotState{Think: 1, MoveAngle: 0, Drive: 1}
	g.Bullets = []*Bullet{{Owner: bot.ID, Kind: "grenade", X: 140, Y: bot.Y, R: 6, Age: 1, Life: 9}}
	x, y := bot.X, bot.Y
	g.botControl(bot, tickDT)
	if bot.Alive || !g.Bullets[0].Dead {
		t.Fatal("fixture did not trigger a lethal remote grenade blast")
	}
	if bot.X != x || bot.Y != y || bot.VX != 0 || bot.VY != 0 {
		t.Fatalf("eliminated bot kept moving: position=(%v,%v), velocity=(%v,%v)", bot.X, bot.Y, bot.VX, bot.VY)
	}
}

// Exhaustive Dijkstra is a test-only reference for the former route selection.
// Cell-index tie breaks and allied-route penalties affect bot behavior, so check
// the complete selected route rather than only its total cost.
func referenceBotPath425(g *Game, bot, target *Tank) []int {
	n := g.World.Cols * g.World.Rows
	from, to := g.cellAt(bot.X, bot.Y), g.cellAt(target.X, target.Y)
	if from == to {
		return nil
	}
	cost, prev, closed, penalty := make([]float64, n), make([]int, n), make([]bool, n), make([]float64, n)
	for i := range cost {
		cost[i], prev[i] = math.Inf(1), -1
	}
	cost[from] = 0
	for _, ally := range g.Tanks {
		if ally != nil && ally.Alive && ally.ID != bot.ID && bot.Team > 0 && ally.Team == bot.Team && ally.AI != nil {
			for _, cell := range ally.AI.Path {
				if cell >= 0 && cell < n {
					penalty[cell] += .65
				}
			}
			penalty[g.cellAt(ally.X, ally.Y)]++
		}
	}
	for iteration := 0; iteration < n; iteration++ {
		at, best := -1, math.Inf(1)
		for i := range cost {
			if !closed[i] && cost[i] < best {
				at, best = i, cost[i]
			}
		}
		if at < 0 || at == to {
			break
		}
		closed[at] = true
		for _, next := range g.Neighbors[at] {
			if v := cost[at] + 1 + penalty[next]; v < cost[next] {
				cost[next], prev[next] = v, at
			}
		}
	}
	if prev[to] < 0 {
		return nil
	}
	var path []int
	for at := to; at != from; at = prev[at] {
		path = append(path, at)
	}
	slices.Reverse(path)
	return path
}

func TestBotRouteMatchesExhaustiveSearch425(t *testing.T) {
	for seed := int64(0); seed < 12; seed++ {
		g := newGame(seed)
		bot := &Tank{ID: 0, Alive: true, Team: 1, R: tankRadius, AI: &BotState{}}
		g.Tanks[0] = bot
		// Reuse one bot across shrinking and growing mazes to exercise its buffers.
		for _, dimensions := range [][2]int{{10, 7}, {24, 14}, {8, 6}, {18, 14}, {14, 10}} {
			cols, rows := dimensions[0], dimensions[1]
			g.makeMaze(cols, rows)
			g.buildNavigation()
			n := cols * rows
			for scenario := 0; scenario < 10; scenario++ {
				from, to := g.rng.Intn(n), g.rng.Intn(n)
				bot.X, bot.Y = g.cellCenter(from)
				target := &Tank{}
				target.X, target.Y = g.cellCenter(to)
				for id := 1; id < maxTanks; id++ {
					ally := &Tank{ID: id, Team: 1 + scenario%2, Alive: id%3 != scenario%3, AI: &BotState{}}
					ally.X, ally.Y = g.cellCenter(g.rng.Intn(n))
					for i := 0; i < 20; i++ {
						ally.AI.Path = append(ally.AI.Path, g.rng.Intn(n))
					}
					g.Tanks[id] = ally
				}
				want := referenceBotPath425(g, bot, target)
				got := g.botPath(bot, target)
				if !slices.Equal(got, want) {
					t.Fatalf("seed=%d maze=%dx%d scenario=%d from=%d to=%d: got %v, want %v", seed, cols, rows, scenario, from, to, got, want)
				}
			}
		}
	}
}

func TestBotRouteSameCellAndUnreachable425(t *testing.T) {
	g := newGame(425)
	g.World = World{Cols: 3, Rows: 1}
	g.Neighbors = [][]int{{1}, {0}, nil}
	bot := &Tank{ID: 0, X: 42, Y: 42, AI: &BotState{}}
	for _, x := range []float64{42, 210, 126, 210, 42, 126} {
		target := &Tank{X: x, Y: 42}
		if got, want := g.botPath(bot, target), referenceBotPath425(g, bot, target); !slices.Equal(got, want) {
			t.Fatalf("target x=%v: got %v, want %v", x, got, want)
		}
	}
}

func BenchmarkBotRoute425(b *testing.B) {
	for _, dimensions := range [][2]int{{10, 7}, {18, 14}, {24, 14}} {
		b.Run(fmt.Sprintf("%dx%d", dimensions[0], dimensions[1]), func(b *testing.B) {
			g := newGame(425)
			g.makeMaze(dimensions[0], dimensions[1])
			g.buildNavigation()
			n := g.World.Cols * g.World.Rows
			bot := &Tank{ID: 0, X: 42, Y: 42, AI: &BotState{}}
			target := &Tank{}
			target.X, target.Y = g.cellCenter(n - 1)
			g.botPath(bot, target)
			b.ReportAllocs()
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				g.botPath(bot, target)
			}
		})
	}
}
