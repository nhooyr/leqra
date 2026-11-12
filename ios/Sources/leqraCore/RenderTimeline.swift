import Foundation

/// Native presentation runs at the display rate; simulation and input history
/// stay at the server's 60 Hz. Only movement is predicted, never hits or score.
public final class RenderTimeline {
    public typealias Move = (inout ArenaTank, GameInput, Double) -> Void
    private struct Frame { var step: Int; var input: GameInput }
    private struct Sample { var state: ArenaSnapshot; var time: Double }
    private let move: Move
    private let maze: InfiniteMaze?
    private var localID: Int
    private var samples: [Sample] = []
    private var frames: [Frame] = []
    private var sent: [UInt64: Int] = [:]
    private var predicted: ArenaTank?
    private var step = 0
    private var accumulator = 0.0
    private var clock: Double?
    private var latest: ArenaSnapshot?
    private var sequence: UInt64 = 0
    private var lastArrival = 0.0
    private struct PathCheck { var first: UInt64; var second: UInt64; var clear: Bool }
    private var pathChecks: [Int: PathCheck] = [:]
    private var indexedPair: (UInt64, UInt64)?
    private var oldTanks: [Int: ArenaTank] = [:]
    private var newTanks: [Int: ArenaTank] = [:]
    private var oldBullets: [Int: ArenaBullet] = [:]
    private var newBullets: [Int: ArenaBullet] = [:]
    private var indexedLatest: UInt64?
    private var liveBullets: [Int: ArenaBullet] = [:]
    public private(set) var stale = false
    var bufferedAcknowledgementCount: Int { sent.count }

    public init(localID: Int, initialSequence: UInt64 = 0, maze: InfiniteMaze? = nil, move: @escaping Move) {
        self.localID = localID
        self.move = move
        self.maze = maze
        sequence = initialSequence
    }

    public func setLocalID(_ id: Int) {
        guard localID != id else { return }
        localID = id
        resetPrediction(latest?.tanks.first(where: { $0.id == id }))
    }

    public func accept(_ snapshot: ArenaSnapshot, at now: Double) {
        if let previous = latest {
            if snapshot.generation < previous.generation { return }
            if previous.generation != snapshot.generation {
                samples.removeAll(); resetPrediction(nil); clock = nil
                pathChecks.removeAll()
                indexedPair = nil; indexedLatest = nil
                oldTanks.removeAll(keepingCapacity: true); newTanks.removeAll(keepingCapacity: true)
                oldBullets.removeAll(keepingCapacity: true); newBullets.removeAll(keepingCapacity: true)
                liveBullets.removeAll(keepingCapacity: true)
            } else if snapshot.tick <= previous.tick { return }
        }
        latest = snapshot
        let liveTankIDs = Set(snapshot.tanks.map(\.id))
        pathChecks = pathChecks.filter { liveTankIDs.contains($0.key) }
        lastArrival = now
        stale = false
        let timestamp = Double(snapshot.tick) / 60
        samples.append(Sample(state: snapshot, time: timestamp))
        if samples.count > 90 { samples.removeFirst(samples.count - 90) }
        if clock == nil { clock = timestamp - 0.085 }
        guard var tank = snapshot.tanks.first(where: { $0.id == localID }) else {
            resetPrediction(nil); return
        }
        guard let old = predicted, old.hp == tank.hp, old.spawnSerial == tank.spawnSerial,
              snapshot.phase == "playing" else { resetPrediction(tank); return }
        let processed = sent[tank.ack].map { $0 + max(1, Int(tank.ackSteps)) - 1 } ?? (tank.ack == 0 ? 0 : step)
        if processed >= (frames.first?.step ?? step + 1) - 1, tank.hp > 0 {
            for frame in frames where frame.step > processed { move(&tank, frame.input, 1 / 60) }
        }
        predicted = tank
        frames.removeAll { $0.step <= processed }
        sent = sent.filter { $0.value >= step - 240 }
    }

    /// Call once per display frame. Input packets are emitted on fixed steps,
    /// bounded to 60/s regardless of a 60, 90, or 120 Hz display.
    public func render(dt: Double, input: GameInput, now: Double,
                       send: (GameInput) -> Void) -> ArenaSnapshot? {
        guard let latest else { return nil }
        let elapsed = max(0, min(0.1, dt))
        stale = now - lastArrival > 2.5
        accumulator += elapsed
        var controls = stale ? GameInput() : input
        while accumulator + 1e-9 >= 1 / 60 {
            accumulator = max(0, accumulator - 1 / 60)
            step += 1
            sequence += 1
            controls.seq = sequence
            rememberSent(at: step)
            send(controls)
            if var tank = predicted, tank.hp > 0, latest.phase == "playing", !stale {
                move(&tank, controls, 1 / 60)
                predicted = tank
                frames.append(Frame(step: step, input: controls))
                if frames.count > 240 { frames.removeFirst() }
            }
        }
        var result = interpolated(dt: elapsed)
        if var tank = predicted {
            if tank.hp > 0, latest.phase == "playing", !stale { move(&tank, controls, accumulator) }
            if let index = result.tanks.firstIndex(where: { $0.id == localID }) { result.tanks[index] = tank }
        }
        return result
    }

    public func neutralize() { accumulator = 0 }

    public func neutralPacket() -> GameInput {
        accumulator = 0
        sequence += 1
        rememberSent(at: step + 1)
        return GameInput(seq: sequence)
    }

    private func rememberSent(at step: Int) {
        sent[sequence] = step
        // Pongs can keep a socket open during prolonged snapshot loss.
        // Bound history on transmission, even if accept never runs again.
        let oldest = sequence > 239 ? sequence - 239 : 0
        sent = sent.filter { $0.key >= oldest }
    }

    private func resetPrediction(_ tank: ArenaTank?) {
        predicted = tank
        frames.removeAll(); sent.removeAll(); step = 0; accumulator = 0
        // Sequence numbers must remain increasing for the life of a socket.
    }

    private func interpolated(dt: Double) -> ArenaSnapshot {
        guard let newest = samples.last else { return ArenaSnapshot() }
        let target = newest.time - 0.085
        var playhead = clock ?? target
        if target - playhead > 0.6 { playhead = target }
        let fill = target - playhead
        playhead += dt * (fill > 0.02 ? 1.05 : fill < -0.02 ? 0.95 : 1)
        playhead = min(playhead, newest.time) // Freeze instead of inventing damage or wall crossings.
        clock = playhead
        var a = samples[0], b = samples[0]
        for sample in samples.dropFirst() {
            b = sample
            if b.time >= playhead { break }
            a = b
        }
        let span = b.time - a.time
        let alpha = span > 0 ? max(0, min(1, (playhead - a.time) / span)) : 1
        var result = newest.state
        // Several display frames share each 30 Hz snapshot pair. Index those
        // immutable samples once instead of rebuilding large projectile maps
        // at 120 Hz during Starman fire.
        if indexedPair?.0 != a.state.tick || indexedPair?.1 != b.state.tick {
            oldTanks = Dictionary(a.state.tanks.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
            newTanks = Dictionary(b.state.tanks.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
            oldBullets = Dictionary(a.state.bullets.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
            newBullets = Dictionary(b.state.bullets.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
            indexedPair = (a.state.tick, b.state.tick)
        }
        if indexedLatest != newest.state.tick {
            liveBullets = Dictionary(newest.state.bullets.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
            indexedLatest = newest.state.tick
        }
        result.tanks = result.tanks.map { current in
            guard let first = oldTanks[current.id], let second = newTanks[current.id],
                  first.hp > 0, second.hp > 0, current.hp > 0,
                  first.spawnSerial == second.spawnSerial, second.spawnSerial == current.spawnSerial,
                  (first.ghostTime > 0) == (second.ghostTime > 0),
                  (second.ghostTime > 0) == (current.ghostTime > 0),
                  hypot(first.x - second.x, first.y - second.y) < 160 else { return current }
            var tank = current
            // A straight blend between two valid positions can cut the inside
            // of an L-shaped corridor. Check each sample pair once, then hold
            // its first valid pose instead of drawing through a wall.
            if first.ghostTime <= 0 {
                let cached = pathChecks[current.id]
                let clear: Bool
                if let cached, cached.first == a.state.tick, cached.second == b.state.tick { clear = cached.clear }
                else {
                    clear = movementPathClear(from: first, to: second, world: newest.state.world)
                    pathChecks[current.id] = PathCheck(first: a.state.tick, second: b.state.tick, clear: clear)
                }
                if !clear {
                    tank.x = first.x; tank.y = first.y; tank.angle = first.angle
                    return tank
                }
            }
            tank.x = first.x + (second.x - first.x) * alpha
            tank.y = first.y + (second.y - first.y) * alpha
            let delta = atan2(sin(second.angle - first.angle), cos(second.angle - first.angle))
            tank.angle = first.angle + delta * alpha
            return tank
        }
        // New bullets enter at the same delayed timestamp as existing ones.
        // Showing them at newest-time and later moving them onto this timeline
        // makes every fresh shot jump backwards after the buffer fills.
        let visibleBullets = alpha < 1 ? a.state.bullets : b.state.bullets
        result.bullets = visibleBullets.compactMap { visible in
            guard let current = liveBullets[visible.id] else { return nil }
            guard let first = oldBullets[current.id], let second = newBullets[current.id],
                  first.bounces == second.bounces else { return visible }
            var bullet = second
            bullet.x = first.x + (second.x - first.x) * alpha
            bullet.y = first.y + (second.y - first.y) * alpha
            bullet.vx = first.vx + (second.vx - first.vx) * alpha
            bullet.vy = first.vy + (second.vy - first.vy) * alpha
            return bullet
        }
        return result
    }

    private func movementPathClear(from first: ArenaTank, to second: ArenaTank, world: ArenaWorld?) -> Bool {
        guard maze != nil || world != nil else { return true }
        let dx = second.x - first.x, dy = second.y - first.y
        let steps = max(1, Int(ceil(hypot(dx, dy) / 2)))
        for step in 0...steps {
            let fraction = Double(step) / Double(steps)
            let x = first.x + dx * fraction, y = first.y + dy * fraction
            if let maze {
                if maze.blocked(x: x, y: y, radius: 17) { return false }
            } else if let world {
                guard x >= 21, x <= world.width - 21, y >= 21, y <= world.height - 21 else { return false }
                if world.walls.contains(where: { wall in
                    let dx = x - min(max(x, wall.x), wall.x + wall.w)
                    let dy = y - min(max(y, wall.y), wall.y + wall.h)
                    return dx * dx + dy * dy < 17 * 17
                }) { return false }
            }
        }
        return true
    }
}
