package main

import "math"

const (
	infiniteChunkCells = 8
	infiniteCacheSize  = 128
	infiniteNorth      = 1
	infiniteWest       = 2
)

type infiniteChunkCoord struct{ x, y int }
type infiniteChunk [infiniteChunkCells * infiniteChunkCells]uint8

// infiniteMaze keeps a bounded cache of chunks derived from the seed. Its owner
// serializes access, since collision queries can populate the cache.
type infiniteMaze struct {
	seed   uint32
	chunks map[infiniteChunkCoord]*infiniteChunk
	order  [infiniteCacheSize]infiniteChunkCoord
	next   int
}

func newInfiniteMaze(seed uint32) *infiniteMaze {
	return &infiniteMaze{seed: seed, chunks: make(map[infiniteChunkCoord]*infiniteChunk)}
}

// Keep the hash, PRNG and chunk generation in sync with infinite-maze.js.
func infiniteChunkHash(seed uint32, coord infiniteChunkCoord, salt uint32) uint32 {
	n := seed ^ uint32(coord.x)*0x9e3779b1 ^ uint32(coord.y)*0x85ebca77 ^ salt
	n = (n ^ (n >> 16)) * 0x7feb352d
	n = (n ^ (n >> 15)) * 0x846ca68b
	return n ^ (n >> 16)
}

func makeInfiniteChunk(seed uint32, coord infiniteChunkCoord) *infiniteChunk {
	chunk := new(infiniteChunk)
	for i := range chunk {
		chunk[i] = infiniteNorth | infiniteWest
	}
	state := infiniteChunkHash(seed, coord, 0x243f6a88)
	if state == 0 {
		state = 1
	}
	next := func() uint32 {
		state ^= state << 13
		state ^= state >> 17
		state ^= state << 5
		return state
	}

	const cells = infiniteChunkCells
	start := int(next() % uint32(len(chunk)))
	var stack [cells * cells]int
	var visited [cells * cells]bool
	stack[0], visited[start] = start, true
	for count := 1; count > 0; {
		cell := stack[count-1]
		x, y := cell%cells, cell/cells
		var neighbors [4]int
		n := 0
		if y > 0 && !visited[cell-cells] {
			neighbors[n] = cell - cells
			n++
		}
		if x+1 < cells && !visited[cell+1] {
			neighbors[n] = cell + 1
			n++
		}
		if y+1 < cells && !visited[cell+cells] {
			neighbors[n] = cell + cells
			n++
		}
		if x > 0 && !visited[cell-1] {
			neighbors[n] = cell - 1
			n++
		}
		if n == 0 {
			count--
			continue
		}
		neighbor := neighbors[next()%uint32(n)]
		switch neighbor - cell {
		case -cells:
			chunk[cell] &^= infiniteNorth
		case 1:
			chunk[neighbor] &^= infiniteWest
		case cells:
			chunk[neighbor] &^= infiniteNorth
		case -1:
			chunk[cell] &^= infiniteWest
		}
		stack[count], visited[neighbor] = neighbor, true
		count++
	}

	// Carve some loops so there are alternate routes around dead ends.
	for i, walls := range chunk {
		if i >= cells && walls&infiniteNorth != 0 && next()%5 == 0 {
			chunk[i] &^= infiniteNorth
		}
		if i%cells != 0 && walls&infiniteWest != 0 && next()%5 == 0 {
			chunk[i] &^= infiniteWest
		}
	}

	// A chunk owns its north and west edges. Each edge has two gaps,
	// which connect the chunks on either side regardless of generation order.
	north := infiniteChunkHash(seed, coord, 0xb7e15162)
	west := infiniteChunkHash(seed, coord, 0x8aed2a6b)
	chunk[1+north%3] &^= infiniteNorth
	chunk[4+(north>>16)%3] &^= infiniteNorth
	chunk[(1+west%3)*cells] &^= infiniteWest
	chunk[(4+(west>>16)%3)*cells] &^= infiniteWest
	return chunk
}

func (m *infiniteMaze) chunk(coord infiniteChunkCoord) *infiniteChunk {
	if chunk := m.chunks[coord]; chunk != nil {
		return chunk
	}
	chunk := makeInfiniteChunk(m.seed, coord)
	if len(m.chunks) == len(m.order) {
		delete(m.chunks, m.order[m.next])
	}
	m.chunks[coord] = chunk
	m.order[m.next] = coord
	m.next = (m.next + 1) % len(m.order)
	return chunk
}

func infiniteChunkIndex(cell int) int {
	chunk := cell / infiniteChunkCells
	if cell%infiniteChunkCells < 0 {
		chunk--
	}
	return chunk
}

func (m *infiniteMaze) visitWalls(x0, y0, x1, y1 float64, visit func(Wall) bool) bool {
	if !(x0 <= x1 && y0 <= y1) || math.IsInf(x0, 0) || math.IsInf(y0, 0) || math.IsInf(x1, 0) || math.IsInf(y1, 0) {
		return false
	}
	const halfWall = wallSize / 2
	// A wall owned by the previous cell can reach the query only if its
	// far edge touches the query. Keep tangencies without scanning a spare row or column.
	firstX := int(math.Ceil((x0-halfWall)/cellSize)) - 1
	firstY := int(math.Ceil((y0-halfWall)/cellSize)) - 1
	lastX := int(math.Floor((x1 + halfWall) / cellSize))
	lastY := int(math.Floor((y1 + halfWall) / cellSize))
	const cells = infiniteChunkCells
	for cy := infiniteChunkIndex(firstY); cy <= infiniteChunkIndex(lastY); cy++ {
		baseY := cy * cells
		for cx := infiniteChunkIndex(firstX); cx <= infiniteChunkIndex(lastX); cx++ {
			baseX := cx * cells
			chunk := m.chunk(infiniteChunkCoord{cx, cy})
			for y := max(firstY, baseY); y <= min(lastY, baseY+cells-1); y++ {
				for x := max(firstX, baseX); x <= min(lastX, baseX+cells-1); x++ {
					walls := chunk[(y-baseY)*cells+x-baseX]
					wx, wy := float64(x)*cellSize, float64(y)*cellSize
					if walls&infiniteNorth != 0 {
						wall := Wall{X: wx - halfWall, Y: wy - halfWall, W: cellSize + wallSize, H: wallSize, Axis: "h", Line: wy}
						if wall.X <= x1 && wall.X+wall.W >= x0 && wall.Y <= y1 && wall.Y+wall.H >= y0 && visit(wall) {
							return true
						}
					}
					if walls&infiniteWest != 0 {
						wall := Wall{X: wx - halfWall, Y: wy - halfWall, W: wallSize, H: cellSize + wallSize, Axis: "v", Line: wx}
						if wall.X <= x1 && wall.X+wall.W >= x0 && wall.Y <= y1 && wall.Y+wall.H >= y0 && visit(wall) {
							return true
						}
					}
				}
			}
		}
	}
	return false
}

func (m *infiniteMaze) wallsNear(x0, y0, x1, y1 float64) []Wall {
	var walls []Wall
	m.visitWalls(x0, y0, x1, y1, func(w Wall) bool {
		walls = append(walls, w)
		return false
	})
	return walls
}

// blocked tests circle/rectangle overlap. A circle tangent to a wall can move
// along it, matching the finite maze collision behavior.
func (m *infiniteMaze) blocked(x, y, radius float64) bool {
	return m.visitWalls(x-radius, y-radius, x+radius, y+radius, func(w Wall) bool {
		dx := x - min(max(x, w.X), w.X+w.W)
		dy := y - min(max(y, w.Y), w.Y+w.H)
		return dx*dx+dy*dy < radius*radius
	})
}
