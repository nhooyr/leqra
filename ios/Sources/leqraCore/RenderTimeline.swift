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
    private var playbackRate = 1.0
    private var correction = (x: 0.0, y: 0.0, angle: 0.0)
    private var correctionVelocity = (x: 0.0, y: 0.0, angle: 0.0)
    private var lastInput = GameInput()
    private let motionPresenter = TankMotionPresenter()
    private let cannonFlights = CannonFlightPresenter()
    private var latest: ArenaSnapshot?
    private var sequence: UInt64 = 0
    private var lastArrival = 0.0
    private var renderNow = 0.0
    private var contactPreviousTick: Double?
    private struct PathCheck { var first: UInt64; var second: UInt64; var clear: Bool }
    private var pathChecks: [Int: PathCheck] = [:]
    private var indexedPair: (UInt64, UInt64)?
    private var oldTanks: [Int: ArenaTank] = [:]
    private var newTanks: [Int: ArenaTank] = [:]
    private var oldBullets: [Int: ArenaBullet] = [:]
    private var newBullets: [Int: ArenaBullet] = [:]
    private var ricochetPaths: [Int: ProjectileRicochetPath] = [:]
    private var checkedRicochets = Set<Int>()
    private var projectileMaze: InfiniteMaze?
    private var projectileWorld: ArenaWorld?
    private struct CurveContext: Equatable {
        var first: UInt64; var second: UInt64; var previous: UInt64?; var following: UInt64?
    }
    private struct TankCurve {
        var ax: Double; var ay: Double; var bx: Double; var by: Double
        var angleA: Double; var angleB: Double; var clear = true
    }
    private var curveContext: CurveContext?
    private var previousTanks: [Int: ArenaTank] = [:]
    private var followingTanks: [Int: ArenaTank] = [:]
    private var tankCurves: [Int: TankCurve] = [:]
    public private(set) var stale = false
    public var hasPendingProjectileFlights: Bool { cannonFlights.hasPending }
    public var authoritativeSnapshot: ArenaSnapshot? { latest }
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
        cannonFlights.reset()
        if let latest { cannonFlights.accept(latest.effects, baseline: true, throughTick: Double(latest.tick), tanks: latest.tanks) }
    }

    public func accept(_ snapshot: ArenaSnapshot, at now: Double) {
        var baselineFlights = latest == nil
        let recovering = latest != nil && (stale || now - lastArrival > 2.5)
        if let previous = latest {
            if snapshot.generation < previous.generation { return }
            if snapshot.generation == previous.generation, snapshot.tick < previous.tick { return }
            let changedView = snapshot.spectating != previous.spectating || snapshot.spectating && snapshot.following != previous.following
            if previous.generation != snapshot.generation || changedView {
                baselineFlights = true; cannonFlights.reset()
                samples.removeAll(); resetPrediction(nil); clock = nil; playbackRate = 1
                pathChecks.removeAll()
                indexedPair = nil
                oldTanks.removeAll(keepingCapacity: true); newTanks.removeAll(keepingCapacity: true)
                oldBullets.removeAll(keepingCapacity: true); newBullets.removeAll(keepingCapacity: true)
                ricochetPaths.removeAll(keepingCapacity: true); checkedRicochets.removeAll(keepingCapacity: true)
                projectileMaze = nil; projectileWorld = nil
                curveContext = nil; tankCurves.removeAll(keepingCapacity: true)
                previousTanks.removeAll(keepingCapacity: true); followingTanks.removeAll(keepingCapacity: true)
            } else if snapshot.tick <= previous.tick { return }
        }
        latest = snapshot
        if recovering {
            baselineFlights = true; cannonFlights.reset()
            samples.removeAll(); clock = nil; playbackRate = 1
        }
        cannonFlights.accept(snapshot.effects, baseline: baselineFlights, throughTick: Double(snapshot.tick), tanks: snapshot.tanks)
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
        guard !recovering else { resetPrediction(tank); return }
        guard let old = predicted, old.hp == tank.hp, old.spawnSerial == tank.spawnSerial,
              snapshot.phase == "playing", snapshot.result == nil else { resetPrediction(tank); return }
        let processed = sent[tank.ack].map { $0 + max(1, Int(tank.ackSteps)) - 1 } ?? (tank.ack == 0 ? 0 : step)
        let historyComplete = processed >= (frames.first?.step ?? step + 1) - 1
        if historyComplete, tank.hp > 0 {
            for frame in frames where frame.step > processed { move(&tank, frame.input, 1 / 60) }
        }
        // Physics adopts authority immediately. Only small presentation errors
        // ease out, so 30 Hz acknowledgements cannot jerk the tank and camera
        // by several pixels when Speed is stacked.
        let error = hypot(old.x - tank.x, old.y - tank.y)
        if !historyComplete || tank.hp <= 0 || error > 64 || (old.ghostTime > 0) != (tank.ghostTime > 0) {
            clearCorrection()
            motionPresenter.reset()
        } else {
            // The short control-transition bias and the slower authority
            // correction describe different errors. Rebase its input history
            // so the presenter does not smooth this same network delta twice.
            motionPresenter.rebase(dx: tank.x - old.x, dy: tank.y - old.y,
                                   angle: atan2(sin(tank.angle - old.angle), cos(tank.angle - old.angle)))
            // Preserve display velocity as well as position when replay moves
            // the authoritative pose. Packet jitter must not become a camera
            // speed pulse, including while turning with stacked Speed.
            var oldNext = old, newNext = tank
            move(&oldNext, lastInput, 1 / 60); move(&newNext, lastInput, 1 / 60)
            correctionVelocity.x += ((oldNext.x - old.x) - (newNext.x - tank.x)) * 60
            correctionVelocity.y += ((oldNext.y - old.y) - (newNext.y - tank.y)) * 60
            correctionVelocity.angle += (atan2(sin(oldNext.angle - old.angle), cos(oldNext.angle - old.angle))
                - atan2(sin(newNext.angle - tank.angle), cos(newNext.angle - tank.angle))) * 60
            correction.x += old.x - tank.x
            correction.y += old.y - tank.y
            correction.angle = atan2(sin(correction.angle + old.angle - tank.angle), cos(correction.angle + old.angle - tank.angle))
            let distance = hypot(correction.x, correction.y)
            let limit = tank.ghostTime > 0 ? 12.0 : 48.0
            if distance > limit { correction.x *= limit / distance; correction.y *= limit / distance }
            correction.angle = min(max(correction.angle, -0.7), 0.7)
            clampCorrection(limit: limit)
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
        renderNow = now
        let elapsed = max(0, min(0.1, dt))
        stale = now - lastArrival > 2.5
        if stale { clearCorrection(); motionPresenter.reset() }
        accumulator += elapsed
        var controls = stale || latest.result != nil ? GameInput() : input
        lastInput = controls
        while accumulator + 1e-9 >= 1 / 60 {
            accumulator = max(0, accumulator - 1 / 60)
            step += 1
            if localID >= 0, !latest.spectating {
                sequence += 1
                controls.seq = sequence
                rememberSent(at: step)
                send(controls)
            }
            if var tank = predicted, tank.hp > 0, latest.phase == "playing", latest.result == nil, !stale {
                let wasPhasing = tank.ghostTime > 0
                move(&tank, controls, 1 / 60)
                if wasPhasing != (tank.ghostTime > 0) { clearCorrection(); motionPresenter.reset() }
                predicted = tank
                frames.append(Frame(step: step, input: controls))
                if frames.count > 240 { frames.removeFirst() }
            }
        }
        advanceCorrection(dt: elapsed)
        var result = interpolated(dt: elapsed)
        if var tank = predicted {
            if tank.hp > 0, latest.phase == "playing", latest.result == nil, !stale {
                tank = motionPresenter.present(tank: tank, input: controls, tick: UInt64(step),
                    generation: latest.generation, fraction: accumulator * 60,
                    move: move, canInterpolate: { first, second in
                        TankMovement.presentationFitsBounds(tank: second, world: latest.world ?? self.maze?.world)
                            && (first.ghostTime > 0 || self.movementPathClear(from: first, to: second, world: latest.world))
                    })
            }
            if tank.hp > 0, latest.phase == "playing", latest.result == nil, !stale {
                if correction.x != 0 || correction.y != 0 {
                    var corrected = tank
                    corrected.x += correction.x; corrected.y += correction.y
                    if TankMovement.presentationFitsBounds(tank: corrected, world: latest.world ?? maze?.world)
                        && (tank.ghostTime > 0 || movementPathClear(from: tank, to: corrected, world: latest.world)) {
                        tank.x = corrected.x; tank.y = corrected.y
                    } else { correction.x = 0; correction.y = 0; correctionVelocity.x = 0; correctionVelocity.y = 0 }
                }
                tank.angle = atan2(sin(tank.angle + correction.angle), cos(tank.angle + correction.angle))
            }
            if let index = result.tanks.firstIndex(where: { $0.id == localID }) { result.tanks[index] = tank }
        }
        cannonFlights.applyContacts(to: &result.tanks, from: oldTanks, previousTick: contactPreviousTick) { [self] first, second in
            first.ghostTime > 0 || movementPathClear(from: first, to: second, world: latest.world)
        }
        return result
    }

    private func advanceCorrection(dt: Double) {
        // Exact critically damped spring integration keeps velocity continuous
        // across arrivals. First-order decay instantly changes velocity every
        // time an acknowledgement adds a new positional offset.
        let omega = 20.0, decay = exp(-omega * dt)
        func advance(_ position: inout Double, _ velocity: inout Double) {
            let impulse = (velocity + omega * position) * dt
            position = (position + impulse) * decay
            velocity = (velocity - omega * impulse) * decay
            if abs(position) < 1e-5 && abs(velocity) < 1e-4 { position = 0; velocity = 0 }
        }
        advance(&correction.x, &correctionVelocity.x)
        advance(&correction.y, &correctionVelocity.y)
        advance(&correction.angle, &correctionVelocity.angle)
        clampCorrection(limit: (predicted?.ghostTime ?? 0) > 0 ? 12 : 48)
    }

    private func clampCorrection(limit: Double) {
        let distance = hypot(correction.x, correction.y)
        if distance >= limit {
            let nx = correction.x / distance, ny = correction.y / distance
            correction.x = nx * limit; correction.y = ny * limit
            let outward = correctionVelocity.x * nx + correctionVelocity.y * ny
            if outward > 0 { correctionVelocity.x -= nx * outward; correctionVelocity.y -= ny * outward }
        }
        if abs(correction.angle) >= 0.7 {
            correction.angle = min(max(correction.angle, -0.7), 0.7)
            if correctionVelocity.angle * correction.angle > 0 { correctionVelocity.angle = 0 }
        }
    }

    public func neutralize() {
        accumulator = 0; clearCorrection(); lastInput = GameInput()
        motionPresenter.reset()
        // No display time advances while the pause menu is open. Resume from
        // the current snapshot buffer rather than retaining its old playhead.
        clock = nil; playbackRate = 1
        cannonFlights.reset()
        if let latest { cannonFlights.accept(latest.effects, baseline: true, throughTick: Double(latest.tick), tanks: latest.tanks) }
    }

    public func neutralPacket() -> GameInput {
        neutralize()
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
        clearCorrection()
        lastInput = GameInput()
        motionPresenter.reset()
        // Sequence numbers must remain increasing for the life of a socket.
    }

    private func clearCorrection() {
        correction = (0, 0, 0); correctionVelocity = (0, 0, 0)
    }

    private func interpolated(dt: Double) -> ArenaSnapshot {
        guard let newest = samples.last else { return ArenaSnapshot() }
        let target = newest.time - 0.085
        var playhead = clock ?? target
        if target - playhead > 0.6 { playhead = target }
        let fill = target - playhead
        let wantedRate = fill > 0.02 ? 1.05 : fill < -0.02 ? 0.95 : 1
        playbackRate += (wantedRate - playbackRate) * min(1, dt * 6)
        playhead += dt * playbackRate
        playhead = min(playhead, newest.time) // Freeze instead of inventing damage or wall crossings.
        clock = playhead
        var a = samples[0], b = samples[0], aIndex = 0, bIndex = 0
        for index in samples.indices.dropFirst() {
            b = samples[index]; bIndex = index
            if b.time >= playhead { break }
            a = b; aIndex = index
        }
        let preceding = aIndex > 0 ? samples[aIndex - 1] : nil
        let following = bIndex + 1 < samples.count ? samples[bIndex + 1] : nil
        let span = b.time - a.time
        let alpha = span > 0 ? max(0, min(1, (playhead - a.time) / span)) : 1
        contactPreviousTick = Double(a.state.tick)
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
            ricochetPaths.removeAll(keepingCapacity: true); checkedRicochets.removeAll(keepingCapacity: true)
        }
        let context = CurveContext(first: a.state.tick, second: b.state.tick,
                                   previous: preceding?.state.tick, following: following?.state.tick)
        if curveContext != context {
            curveContext = context
            tankCurves.removeAll(keepingCapacity: true)
            previousTanks = Dictionary((preceding?.state.tanks ?? []).map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
            followingTanks = Dictionary((following?.state.tanks ?? []).map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
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
            tank.track = first.track + (second.track - first.track) * alpha
            let delta = atan2(sin(second.angle - first.angle), cos(second.angle - first.angle))
            tank.angle = first.angle + delta * alpha
            if span > 0, span <= 0.1 {
                let curve: TankCurve
                if let cached = tankCurves[current.id] { curve = cached }
                else {
                    curve = makeCurve(from: first, to: second, start: a.time, end: b.time,
                        previous: preceding.flatMap { sample in previousTanks[current.id].map { ($0, sample.time) } },
                        following: following.flatMap { sample in followingTanks[current.id].map { ($0, sample.time) } }, world: newest.state.world)
                    tankCurves[current.id] = curve
                }
                if curve.clear {
                    let x = hermite(first.x, second.x, curve.ax, curve.bx, alpha)
                    let y = hermite(first.y, second.y, curve.ay, curve.by, alpha)
                    var candidate = tank
                    candidate.x = x; candidate.y = y
                    if TankMovement.presentationFitsBounds(tank: candidate, world: newest.state.world ?? maze?.world)
                        && (first.ghostTime > 0 || movementPointClear(x: x, y: y, world: newest.state.world)) {
                        tank = candidate
                        tank.angle = first.angle + hermite(0, delta, curve.angleA, curve.angleB, alpha)
                    } else {
                        var blocked = curve; blocked.clear = false; tankCurves[current.id] = blocked
                    }
                }
            }
            return tank
        }
        // Birth and despawn use the same presentation clock. Filtering this
        // delayed sample through newest-state membership erases a projectile
        // that hit before the playhead reaches its birth, even a visible kill.
        let visibleBullets = alpha < 1 ? a.state.bullets : b.state.bullets
        result.bullets = visibleBullets.compactMap { visible in
            guard let first = oldBullets[visible.id], let second = newBullets[visible.id] else { return visible }
            if first.bounces != second.bounces {
                if checkedRicochets.insert(visible.id).inserted {
                    if let world = newest.state.world {
                        if projectileWorld != world { projectileWorld = world; projectileMaze = InfiniteMaze(world: world) }
                    } else { projectileWorld = nil; projectileMaze = maze }
                    if let geometry = projectileMaze,
                       let path = ProjectileRicochetPath(from: first, to: second, span: span, maze: geometry) { ricochetPaths[visible.id] = path }
                }
                return ricochetPaths[visible.id]?.sample(fraction: alpha) ?? visible
            }
            var bullet = second
            bullet.x = first.x + (second.x - first.x) * alpha
            bullet.y = first.y + (second.y - first.y) * alpha
            bullet.vx = first.vx + (second.vx - first.vx) * alpha
            bullet.vy = first.vy + (second.vy - first.vy) * alpha
            return bullet
        }
        cannonFlights.append(to: &result.bullets, tick: playhead * 60, now: renderNow, authorityTick: Double(newest.state.tick), localID: localID)
        result.effects = cannonFlights.effects(result.effects)
        return result
    }

    private func hermite(_ first: Double, _ last: Double, _ start: Double, _ end: Double, _ fraction: Double) -> Double {
        let t2 = fraction * fraction, t3 = t2 * fraction
        return (2 * t3 - 3 * t2 + 1) * first + (t3 - 2 * t2 + fraction) * start
            + (-2 * t3 + 3 * t2) * last + (t3 - t2) * end
    }

    private func makeCurve(from first: ArenaTank, to second: ArenaTank, start: Double, end: Double,
                           previous: (ArenaTank, Double)?, following: (ArenaTank, Double)?, world: ArenaWorld?) -> TankCurve {
        let span = end - start, dx = second.x - first.x, dy = second.y - first.y
        let angle = atan2(sin(second.angle - first.angle), cos(second.angle - first.angle))
        var curve = TankCurve(ax: dx, ay: dy, bx: dx, by: dy, angleA: angle, angleB: angle)
        func compatible(_ tank: ArenaTank, with reference: ArenaTank) -> Bool {
            tank.hp > 0 && tank.spawnSerial == reference.spawnSerial &&
                (tank.ghostTime > 0) == (reference.ghostTime > 0) && hypot(tank.x - reference.x, tank.y - reference.y) < 160
        }
        if let (tank, time) = previous, start - time > 0, end - time <= 0.2, compatible(tank, with: first) {
            let scale = span / (end - time)
            curve.ax = (second.x - tank.x) * scale; curve.ay = (second.y - tank.y) * scale
            curve.angleA = atan2(sin(second.angle - tank.angle), cos(second.angle - tank.angle)) * scale
        }
        if let (tank, time) = following, time - end > 0, time - start <= 0.2, compatible(tank, with: second) {
            let scale = span / (time - start)
            curve.bx = (tank.x - first.x) * scale; curve.by = (tank.y - first.y) * scale
            curve.angleB = atan2(sin(tank.angle - first.angle), cos(tank.angle - first.angle)) * scale
        }
        let distance = hypot(dx, dy)
        if distance < 1e-7 { curve.ax = 0; curve.ay = 0; curve.bx = 0; curve.by = 0 }
        else {
            let limit = distance * 3
            let aLength = hypot(curve.ax, curve.ay), bLength = hypot(curve.bx, curve.by)
            if aLength > limit { curve.ax *= limit / aLength; curve.ay *= limit / aLength }
            if bLength > limit { curve.bx *= limit / bLength; curve.by *= limit / bLength }
        }
        // Neighboring buffered samples give both segments the same tangent.
        // Validate the entire curve once, so a later frame cannot enter a wall
        // or alternate between curved and straight paths in a narrow corridor.
        if maze != nil || world != nil {
            let count = max(8, Int(ceil(distance / 2)))
            var previous = first
            for index in 1...count {
                let fraction = Double(index) / Double(count)
                var point = first
                point.x = hermite(first.x, second.x, curve.ax, curve.bx, fraction)
                point.y = hermite(first.y, second.y, curve.ay, curve.by, fraction)
                if !TankMovement.presentationFitsBounds(tank: point, world: world ?? maze?.world)
                    || first.ghostTime <= 0 && !movementPathClear(from: previous, to: point, world: world) {
                    curve.clear = false; break
                }
                previous = point
            }
        }
        return curve
    }

    private func movementPathClear(from first: ArenaTank, to second: ArenaTank, world: ArenaWorld?) -> Bool {
        guard maze != nil || world != nil else { return true }
        let dx = second.x - first.x, dy = second.y - first.y
        let steps = max(1, Int(ceil(hypot(dx, dy) / 2)))
        for step in 0...steps {
            let fraction = Double(step) / Double(steps)
            let x = first.x + dx * fraction, y = first.y + dy * fraction
            if !movementPointClear(x: x, y: y, world: world) { return false }
        }
        return true
    }

    private func movementPointClear(x: Double, y: Double, world: ArenaWorld?) -> Bool {
        if let maze { return !maze.blocked(x: x, y: y, radius: 17) }
        guard let world else { return true }
        guard x >= 21, x <= world.width - 21, y >= 21, y <= world.height - 21 else { return false }
        return !world.walls.contains { wall in
            let dx = x - min(max(x, wall.x), wall.x + wall.w)
            let dy = y - min(max(y, wall.y), wall.y + wall.h)
            return dx * dx + dy * dy < 17 * 17
        }
    }
}
