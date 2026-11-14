import Foundation

/// The same seeded, unbounded maze used by the Go server and browser client.
/// Access from one simulation thread; queries populate a bounded chunk cache.
public final class InfiniteMaze {
    public static let cellSize = 84.0
    public static let wallSize = 8.0
    public let seed: UInt32
    public let world: ArenaWorld?
    private let fixedBins: [[Int]]
    private struct Coordinate: Hashable { var x: Int; var y: Int }
    private var chunks: [Coordinate: [UInt8]] = [:]
    private var order: [Coordinate] = []
    private var nextEviction = 0
    var cachedChunkCount: Int { chunks.count }

    public init(seed: UInt32) { self.seed = seed; world = nil; fixedBins = [] }
    public init(world: ArenaWorld) {
        seed = 0; self.world = world
        guard world.cols > 0, world.rows > 0 else { fixedBins = []; return }
        var bins = [[Int]](repeating: [], count: world.cols * world.rows)
        for (index, wall) in world.walls.enumerated() {
            let x0 = min(max(Int(floor(wall.x / 84)), 0), world.cols - 1)
            let x1 = min(max(Int(floor((wall.x + wall.w) / 84)), 0), world.cols - 1)
            let y0 = min(max(Int(floor(wall.y / 84)), 0), world.rows - 1)
            let y1 = min(max(Int(floor((wall.y + wall.h) / 84)), 0), world.rows - 1)
            for row in y0...max(y0, y1) { for col in x0...max(x0, x1) { bins[row * world.cols + col].append(index) } }
        }
        fixedBins = bins
    }

    private func hash(_ coord: Coordinate, _ salt: UInt32) -> UInt32 {
        var n = seed ^ (UInt32(truncatingIfNeeded: coord.x) &* 0x9e3779b1)
            ^ (UInt32(truncatingIfNeeded: coord.y) &* 0x85ebca77) ^ salt
        n = (n ^ (n >> 16)) &* 0x7feb352d
        n = (n ^ (n >> 15)) &* 0x846ca68b
        return n ^ (n >> 16)
    }

    private func chunk(_ coord: Coordinate) -> [UInt8] {
        if let cached = chunks[coord] { return cached }
        var cells = [UInt8](repeating: 3, count: 64)
        var state = hash(coord, 0x243f6a88)
        if state == 0 { state = 1 }
        func random() -> UInt32 {
            state ^= state << 13; state ^= state >> 17; state ^= state << 5
            return state
        }
        let start = Int(random() % 64)
        var visited = [Bool](repeating: false, count: 64)
        visited[start] = true
        var stack = [start]
        while let cell = stack.last {
            let x = cell % 8, y = cell / 8
            var neighbors: [Int] = []
            if y > 0 && !visited[cell - 8] { neighbors.append(cell - 8) }
            if x < 7 && !visited[cell + 1] { neighbors.append(cell + 1) }
            if y < 7 && !visited[cell + 8] { neighbors.append(cell + 8) }
            if x > 0 && !visited[cell - 1] { neighbors.append(cell - 1) }
            if neighbors.isEmpty { stack.removeLast(); continue }
            let neighbor = neighbors[Int(random() % UInt32(neighbors.count))]
            switch neighbor - cell {
            case -8: cells[cell] &= ~1
            case 1: cells[neighbor] &= ~2
            case 8: cells[neighbor] &= ~1
            default: cells[cell] &= ~2
            }
            visited[neighbor] = true
            stack.append(neighbor)
        }
        for i in cells.indices {
            if i >= 8 && cells[i] & 1 != 0 && random() % 5 == 0 { cells[i] &= ~1 }
            if i % 8 != 0 && cells[i] & 2 != 0 && random() % 5 == 0 { cells[i] &= ~2 }
        }
        let north = hash(coord, 0xb7e15162), west = hash(coord, 0x8aed2a6b)
        cells[1 + Int(north % 3)] &= ~1
        cells[4 + Int((north >> 16) % 3)] &= ~1
        cells[(1 + Int(west % 3)) * 8] &= ~2
        cells[(4 + Int((west >> 16) % 3)) * 8] &= ~2
        if order.count == 128 {
            chunks.removeValue(forKey: order[nextEviction])
            order[nextEviction] = coord
            nextEviction = (nextEviction + 1) % 128
        } else { order.append(coord) }
        chunks[coord] = cells
        return cells
    }

    public func walls(x0: Double, y0: Double, x1: Double, y1: Double) -> [MazeWall] {
        var result: [MazeWall] = []
        visitWalls(x0: x0, y0: y0, x1: x1, y1: y1) { result.append($0); return false }
        return result
    }

    @discardableResult
    private func visitWalls(x0: Double, y0: Double, x1: Double, y1: Double,
                            visit: (MazeWall) -> Bool) -> Bool {
        // Bound malformed snapshots and prevent overflowing Int conversion.
        guard [x0, y0, x1, y1].allSatisfy({ $0.isFinite && abs($0) < 1e14 }),
              x0 <= x1, y0 <= y1, x1 - x0 < 84 * 256, y1 - y0 < 84 * 256 else { return false }
        if let world {
            let candidates: [Int]
            if fixedBins.isEmpty { candidates = Array(world.walls.indices) }
            else {
                let firstX = min(max(Int(floor(x0 / 84)), 0), world.cols - 1)
                let lastX = min(max(Int(floor(x1 / 84)), 0), world.cols - 1)
                let firstY = min(max(Int(floor(y0 / 84)), 0), world.rows - 1)
                let lastY = min(max(Int(floor(y1 / 84)), 0), world.rows - 1)
                if firstX == lastX && firstY == lastY { candidates = fixedBins[firstY * world.cols + firstX] }
                else if (lastX - firstX + 1) * (lastY - firstY + 1) > world.cols * world.rows / 3 { candidates = Array(world.walls.indices) }
                else {
                    var indices = Set<Int>()
                    for row in firstY...lastY { for col in firstX...lastX { indices.formUnion(fixedBins[row * world.cols + col]) } }
                    candidates = indices.sorted()
                }
            }
            for index in candidates {
                let wall = world.walls[index]
                guard wall.x <= x1 && wall.x + wall.w >= x0 && wall.y <= y1 && wall.y + wall.h >= y0 else { continue }
                if visit(wall) { return true }
            }
            return false
        }
        let firstX = Int(ceil((x0 - 4) / 84)) - 1, firstY = Int(ceil((y0 - 4) / 84)) - 1
        let lastX = Int(floor((x1 + 4) / 84)), lastY = Int(floor((y1 + 4) / 84))
        let chunkX0 = Int(floor(Double(firstX) / 8)), chunkX1 = Int(floor(Double(lastX) / 8))
        let chunkY0 = Int(floor(Double(firstY) / 8)), chunkY1 = Int(floor(Double(lastY) / 8))
        for cy in chunkY0...chunkY1 {
            for cx in chunkX0...chunkX1 {
                let cells = chunk(Coordinate(x: cx, y: cy)), baseX = cx * 8, baseY = cy * 8
                for y in max(firstY, baseY)...min(lastY, baseY + 7) {
                    for x in max(firstX, baseX)...min(lastX, baseX + 7) {
                        let bits = cells[(y - baseY) * 8 + x - baseX]
                        let wx = Double(x) * 84, wy = Double(y) * 84
                        if bits & 1 != 0 {
                            let wall = MazeWall(x: wx - 4, y: wy - 4, w: 92, h: 8, axis: "h", line: wy)
                            if wall.x <= x1 && wall.x + wall.w >= x0 && wall.y <= y1 && wall.y + wall.h >= y0 && visit(wall) { return true }
                        }
                        if bits & 2 != 0 {
                            let wall = MazeWall(x: wx - 4, y: wy - 4, w: 8, h: 92, axis: "v", line: wx)
                            if wall.x <= x1 && wall.x + wall.w >= x0 && wall.y <= y1 && wall.y + wall.h >= y0 && visit(wall) { return true }
                        }
                    }
                }
            }
        }
        return false
    }

    public func blocked(x: Double, y: Double, radius: Double) -> Bool {
        guard x.isFinite, y.isFinite, radius.isFinite, radius >= 0 else { return true }
        if let world, x < 4 + radius || x > world.width - 4 - radius || y < 4 + radius || y > world.height - 4 - radius { return true }
        return visitWalls(x0: x - radius, y0: y - radius, x1: x + radius, y1: y + radius) { wall in
            let dx = x - min(max(x, wall.x), wall.x + wall.w)
            let dy = y - min(max(y, wall.y), wall.y + wall.h)
            return dx * dx + dy * dy < radius * radius
        }
    }

    public func phaseExit(x: Double, y: Double, radius: Double = 17) -> (x: Double, y: Double) {
        guard blocked(x: x, y: y, radius: radius) else { return (x, y) }
        let cx = Int(floor(x / 84)), cy = Int(floor(y / 84)), margin = 4 + radius + 0.01
        var best = Double.infinity, result = (x: x, y: y)
        for row in (cy - 1)...(cy + 1) {
            for col in (cx - 1)...(cx + 1) {
                let xx = min(max(x, Double(col) * 84 + margin), Double(col + 1) * 84 - margin)
                let yy = min(max(y, Double(row) * 84 + margin), Double(row + 1) * 84 - margin)
                let distance = hypot(xx - x, yy - y)
                if distance < best - 1e-8 { best = distance; result = (xx, yy) }
            }
        }
        return result
    }

    struct RayHit { var fraction: Double; var nx: Double; var ny: Double }

    public func laserGuide(x: Double, y: Double, angle: Double, range: Double = 36 * 84,
                           radius: Double = 3, maxSegments: Int = 256) -> [BeamPoint] {
        projectileGuide(x: x, y: y, angle: angle, kind: "laser", range: range, radius: radius, maxSegments: maxSegments)
    }

    /// Pure geometry for native aim guides; never chooses a target or awards a hit.
    public func projectileGuide(x: Double, y: Double, angle: Double, kind: String,
                                range: Double, radius: Double, maxSegments: Int = 128) -> [BeamPoint] {
        guard [x, y, angle, range, radius].allSatisfy(\.isFinite), range > 0, radius >= 0,
              let launch = launchRay(x: x, y: y, angle: angle, kind: kind, radius: radius) else { return [] }
        var x = launch.x, y = launch.y, ux = launch.ux, uy = launch.uy
        var remaining = max(0, min(range, 20000) - launch.distance)
        var points: [BeamPoint] = []
        for index in 0..<max(0, min(maxSegments, kind == "laser" ? 256 : 128)) {
            let wall = projectileHit(kind: kind, x: x, y: y, dx: ux * remaining, dy: uy * remaining, radius: radius)
            let length = remaining * (wall?.fraction ?? 1)
            if index == 0 {
                let crop = launch.bounced ? 0 : 28.0
                points.append(BeamPoint(x: x + ux * min(crop, length), y: y + uy * min(crop, length)))
            }
            x += ux * length; y += uy * length; remaining -= length
            points.append(BeamPoint(x: x, y: y))
            guard let wall, remaining > 1e-7 else { break }
            if wall.nx != 0 { ux = -ux }; if wall.ny != 0 { uy = -uy }
            let nudge = min(0.001, remaining)
            x += ux * nudge; y += uy * nudge; remaining -= nudge
        }
        return points
    }

    public struct LaunchRay: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var ux: Double
        public var uy: Double
        public var distance: Double
        public var bounced: Bool
    }

    /// Initial overlaps belong to launch handling, not ordinary wall sweeps.
    /// A phased pilot fires from a nearby clear face on the incoming side;
    /// the projectile reflects there instead of tunneling through the wall.
    public func launchRay(x: Double, y: Double, angle: Double, kind: String, radius: Double) -> LaunchRay? {
        guard [x, y, angle, radius].allSatisfy(\.isFinite), radius >= 0 else { return nil }
        let ux = cos(angle), uy = sin(angle)
        let original = LaunchRay(x: x, y: y, ux: ux, uy: uy, distance: 0, bounced: false)
        guard kind != "cannon" else { return original }
        let overlapping = walls(x0: x - radius, y0: y - radius, x1: x + radius, y1: y + radius).filter {
            x >= $0.x - radius && x <= $0.x + $0.w + radius && y >= $0.y - radius && y <= $0.y + $0.h + radius
        }
        guard !overlapping.isEmpty || isMuzzleBlocked(x: x, y: y, kind: kind, radius: radius) else { return original }
        var xs = [x], ys = [y]
        for wall in overlapping {
            xs.append(contentsOf: [wall.x - radius - 0.12, wall.x + wall.w + radius + 0.12])
            ys.append(contentsOf: [wall.y - radius - 0.12, wall.y + wall.h + radius + 0.12])
        }
        xs.sort(); ys.sort()
        var best: (x: Double, y: Double, squared: Double)?
        for ax in xs { for ay in ys {
            let dx = ax - x, dy = ay - y, squared = dx * dx + dy * dy
            guard squared <= 32 * 32 + 1e-7, dx * ux + dy * uy <= 1e-7,
                  !isMuzzleBlocked(x: ax, y: ay, kind: kind, radius: radius) else { continue }
            if let old = best {
                if squared > old.squared + 1e-7 { continue }
                if abs(squared - old.squared) <= 1e-7 && (ax > old.x || ax == old.x && ay >= old.y) { continue }
            }
            best = (ax, ay, squared)
        } }
        guard let best else { return nil }
        let nx = best.x == x ? 0.0 : best.x > x ? 1.0 : -1.0
        let ny = best.y == y ? 0.0 : best.y > y ? 1.0 : -1.0
        return LaunchRay(x: best.x, y: best.y,
                         ux: ux * nx < -1e-9 ? -ux : ux,
                         uy: uy * ny < -1e-9 ? -uy : uy,
                         distance: sqrt(best.squared), bounced: true)
    }

    public func isMuzzleBlocked(x: Double, y: Double, kind: String, radius: Double) -> Bool {
        guard kind != "cannon" else { return false }
        guard [x, y, radius].allSatisfy(\.isFinite), radius >= 0 else { return true }
        if let world, x < 4 + radius || x > world.width - 4 - radius || y < 4 + radius || y > world.height - 4 - radius { return true }
        return visitWalls(x0: x - radius, y0: y - radius, x1: x + radius, y1: y + radius) { wall in
            x >= wall.x - radius && x <= wall.x + wall.w + radius && y >= wall.y - radius && y <= wall.y + wall.h + radius
        }
    }

    func projectileHit(kind: String, x: Double, y: Double, dx: Double, dy: Double, radius: Double) -> RayHit? {
        guard kind == "cannon" else { return rayHit(x: x, y: y, dx: dx, dy: dy, radius: radius) }
        guard let world else { return nil }
        var best: RayHit?
        func consider(_ at: Double, _ nx: Double, _ ny: Double) {
            guard at >= -1e-7, at <= 1 + 1e-7 else { return }
            let at = min(max(at, 0), 1)
            if best == nil || at < best!.fraction - 1e-7 { best = RayHit(fraction: at, nx: nx, ny: ny) }
            else if abs(at - best!.fraction) < 1e-7 {
                if nx != 0 { best!.nx = nx }; if ny != 0 { best!.ny = ny }
            }
        }
        let margin = 4 + radius
        if dx > 1e-9 { consider((world.width - margin - x) / dx, -1, 0) }
        else if dx < -1e-9 { consider((margin - x) / dx, 1, 0) }
        if dy > 1e-9 { consider((world.height - margin - y) / dy, 0, -1) }
        else if dy < -1e-9 { consider((margin - y) / dy, 0, 1) }
        return best
    }

    /// Contact effects must respect a wall even if the phased attacker starts
    /// inside it. Projectile sweeps intentionally ignore that initial overlap.
    func segmentBlocked(x: Double, y: Double, dx: Double, dy: Double) -> Bool {
        visitWalls(x0: min(x, x + dx), y0: min(y, y + dy), x1: max(x, x + dx), y1: max(y, y + dy)) { wall in
            var enter = -Double.infinity, exit = Double.infinity
            if abs(dx) < 1e-9 { if x < wall.x || x > wall.x + wall.w { return false } }
            else {
                let a = (wall.x - x) / dx, b = (wall.x + wall.w - x) / dx
                enter = max(enter, min(a, b)); exit = min(exit, max(a, b))
            }
            if abs(dy) < 1e-9 { if y < wall.y || y > wall.y + wall.h { return false } }
            else {
                let a = (wall.y - y) / dy, b = (wall.y + wall.h - y) / dy
                enter = max(enter, min(a, b)); exit = min(exit, max(a, b))
            }
            return enter <= exit && exit >= 0 && enter <= 1
        }
    }

    func rayHit(x: Double, y: Double, dx: Double, dy: Double, radius: Double) -> RayHit? {
        var nearest: RayHit?
        visitWalls(x0: min(x, x + dx) - radius, y0: min(y, y + dy) - radius,
                   x1: max(x, x + dx) + radius, y1: max(y, y + dy) + radius) { wall in
            let minX = wall.x - radius, maxX = wall.x + wall.w + radius
            let minY = wall.y - radius, maxY = wall.y + wall.h + radius
            var tx1 = -Double.infinity, tx2 = Double.infinity, ty1 = -Double.infinity, ty2 = Double.infinity
            if abs(dx) < 1e-9 { if x < minX || x > maxX { return false } }
            else { tx1 = (minX - x) / dx; tx2 = (maxX - x) / dx; if tx1 > tx2 { swap(&tx1, &tx2) } }
            if abs(dy) < 1e-9 { if y < minY || y > maxY { return false } }
            else { ty1 = (minY - y) / dy; ty2 = (maxY - y) / dy; if ty1 > ty2 { swap(&ty1, &ty2) } }
            let enter = max(tx1, ty1), exit = min(tx2, ty2)
            guard enter <= exit, exit >= 0, enter <= 1, enter >= -0.0001 else { return false }
            let nx = abs(tx1 - ty1) < 1e-7 || tx1 > ty1 ? (dx > 0 ? -1.0 : 1.0) : 0
            let ny = abs(tx1 - ty1) < 1e-7 || ty1 > tx1 ? (dy > 0 ? -1.0 : 1.0) : 0
            if nearest == nil || enter < nearest!.fraction - 1e-7 { nearest = RayHit(fraction: max(0, enter), nx: nx, ny: ny) }
            else if abs(enter - nearest!.fraction) < 1e-7 {
                if nx != 0 { nearest!.nx = nx }; if ny != 0 { nearest!.ny = ny }
            }
            return false
        }
        return nearest
    }
}
