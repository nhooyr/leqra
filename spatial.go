package main

import (
	"math"
	"sort"
)

// Broad phase only: narrow-phase wall tests and their original iteration order
// stay unchanged. Short movement/AI rays no longer visit every maze wall.
type wallIndex struct {
	first             *Wall
	count, cols, rows int
	bins              [][]int
	all, candidates   []int
	seen              []uint32
	stamp             uint32
}

func (g *Game) wallCandidates(x, y, dx, dy, r float64) []int {
	ws := g.World.Walls
	if len(ws) == 0 {
		return nil
	}
	cols, rows := g.World.Cols, g.World.Rows
	if cols < 1 {
		cols = int(math.Ceil(g.World.Width / cellSize))
	}
	if rows < 1 {
		rows = int(math.Ceil(g.World.Height / cellSize))
	}
	if cols < 1 {
		cols = 1
	}
	if rows < 1 {
		rows = 1
	}
	z := g.spatial
	if z == nil || z.first != &ws[0] || z.count != len(ws) || z.cols != cols || z.rows != rows {
		z = &wallIndex{first: &ws[0], count: len(ws), cols: cols, rows: rows, bins: make([][]int, cols*rows), all: make([]int, len(ws)), seen: make([]uint32, len(ws)), candidates: make([]int, 0, len(ws))}
		for i, w := range ws {
			z.all[i] = i
			x0 := int(clamp(math.Floor(w.X/cellSize), 0, float64(cols-1)))
			x1 := int(clamp(math.Floor((w.X+w.W)/cellSize), 0, float64(cols-1)))
			y0 := int(clamp(math.Floor(w.Y/cellSize), 0, float64(rows-1)))
			y1 := int(clamp(math.Floor((w.Y+w.H)/cellSize), 0, float64(rows-1)))
			for yy := y0; yy <= y1; yy++ {
				for xx := x0; xx <= x1; xx++ {
					k := yy*cols + xx
					z.bins[k] = append(z.bins[k], i)
				}
			}
		}
		g.spatial = z
	}
	x0 := int(clamp(math.Floor((math.Min(x, x+dx)-r)/cellSize), 0, float64(cols-1)))
	x1 := int(clamp(math.Floor((math.Max(x, x+dx)+r)/cellSize), 0, float64(cols-1)))
	y0 := int(clamp(math.Floor((math.Min(y, y+dy)-r)/cellSize), 0, float64(rows-1)))
	y1 := int(clamp(math.Floor((math.Max(y, y+dy)+r)/cellSize), 0, float64(rows-1)))
	if len(ws) < 24 || (x1-x0+1)*(y1-y0+1) > cols*rows/3 {
		return z.all
	}
	z.stamp++
	if z.stamp == 0 {
		clear(z.seen)
		z.stamp = 1
	}
	z.candidates = z.candidates[:0]
	for yy := y0; yy <= y1; yy++ {
		for xx := x0; xx <= x1; xx++ {
			for _, i := range z.bins[yy*cols+xx] {
				if z.seen[i] != z.stamp {
					z.seen[i] = z.stamp
					z.candidates = append(z.candidates, i)
				}
			}
		}
	}
	sort.Ints(z.candidates)
	return z.candidates
}
