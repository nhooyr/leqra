package main

import (
	"math"
	"math/bits"
)

// Broad phase only: narrow-phase wall tests and their original iteration order
// stay unchanged. Short movement/AI rays no longer visit every maze wall.
type wallIndex struct {
	first             *Wall
	count, cols, rows int
	bins              [][]int
	all, candidates   []int
	mask              []uint64
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
		z = &wallIndex{first: &ws[0], count: len(ws), cols: cols, rows: rows, bins: make([][]int, cols*rows), all: make([]int, len(ws)), mask: make([]uint64, (len(ws)+63)/64), candidates: make([]int, 0, len(ws))}
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
	// A cell bin already contains each wall once in authoritative order. Most
	// short movement sweeps can read it directly without collecting candidates.
	if x0 == x1 && y0 == y1 {
		return z.bins[y0*cols+x0]
	}
	// Deduplicate overlapping cell bins without sorting on each query. Reading
	// set bits in ascending order preserves the original collision wall order.
	clear(z.mask)
	z.candidates = z.candidates[:0]
	for yy := y0; yy <= y1; yy++ {
		for xx := x0; xx <= x1; xx++ {
			for _, i := range z.bins[yy*cols+xx] {
				z.mask[i>>6] |= uint64(1) << (i & 63)
			}
		}
	}
	for word, mask := range z.mask {
		for mask != 0 {
			z.candidates = append(z.candidates, word*64+bits.TrailingZeros64(mask))
			mask &= mask - 1
		}
	}
	return z.candidates
}
