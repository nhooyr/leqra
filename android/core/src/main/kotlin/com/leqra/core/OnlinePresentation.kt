package com.leqra.core

import kotlin.math.*

/**
 * Display-rate motion prediction only. Hits, equipment, scores and identity remain authoritative.
 */
class OnlinePresentation(
    localID: Int = 1,
    initialSequence: Long = 0,
    maze: InfiniteMaze? = null,
    private val movement: ((ArenaTank, GameInput, Double) -> Unit)? = null,
) {
    private data class Sample(val state: ArenaSnapshot, val time: Double)

    private data class Frame(val step: Int, val input: GameInput)

    private data class Curve(
        val ax: Double,
        val ay: Double,
        val bx: Double,
        val by: Double,
        val angleA: Double,
        val angleB: Double,
        var clear: Boolean = true,
    )

    /** Primitive-key tables avoid boxing every projectile lookup at120Hz. */
    private class BulletIndex {
        private var keys = IntArray(0)
        private var values = arrayOfNulls<ArenaBullet>(0)

        fun replace(bullets: List<ArenaBullet>) {
            var capacity = 16
            while (capacity < bullets.size * 2) capacity *= 2
            if (values.size < capacity) {
                keys = IntArray(capacity)
                values = arrayOfNulls(capacity)
            } else values.fill(null)
            val mask = values.size - 1
            for (bullet in bullets) {
                var index = hash(bullet.id) and mask
                while (values[index] != null && keys[index] != bullet.id) index =
                    (index + 1) and mask
                keys[index] = bullet.id
                values[index] = bullet
            }
        }

        operator fun get(id: Int): ArenaBullet? {
            if (values.isEmpty()) return null
            val mask = values.size - 1
            var index = hash(id) and mask
            while (true) {
                val value = values[index] ?: return null
                if (keys[index] == id) return value
                index = (index + 1) and mask
            }
        }

        operator fun contains(id: Int) = get(id) != null

        fun clear() {
            keys = IntArray(0)
            values = arrayOfNulls(0)
        }

        private fun hash(id: Int): Int {
            val value = id * 0x9e3779b9.toInt()
            return value xor (value ushr 16)
        }
    }

    private val samples = ArrayList<Sample>(90)
    private val primary = LocalPrediction(localID, initialSequence)
    private var secondary: LocalPrediction? = null
    private var secondaryInitialSequence = 0L
    private var latest: ArenaSnapshot? = null
    private var maze: InfiniteMaze? = maze
    private var clock: Double? = null
    private var playbackRate = 1.0
    private var lastArrival = 0.0
    private var context: List<Long?>? = null
    private var pair: Pair<Long, Long>? = null
    private var oldTanks = emptyMap<Int, ArenaTank>()
    private var newTanks = emptyMap<Int, ArenaTank>()
    private val oldBullets = BulletIndex()
    private val newBullets = BulletIndex()
    private val liveBullets = BulletIndex()
    private var indexedLatest: Long? = null
    private val pathChecks = HashMap<Int, Boolean>()
    private val curves = HashMap<Int, Curve>()
    private val ricochetPaths = HashMap<Int, RicochetPath?>()
    private var previousTanks = emptyMap<Int, ArenaTank>()
    private var followingTanks = emptyMap<Int, ArenaTank>()
    var stale = false
        private set

    internal val bufferedAcknowledgementCount
        get() = primary.sent.size

    internal val bufferedFrameCount
        get() = primary.frames.size

    internal val secondaryAcknowledgementCount
        get() = secondary?.sent?.size ?: 0

    internal val secondaryFrameCount
        get() = secondary?.frames?.size ?: 0

    /**
     * Both local seats share the remote interpolation/projectile pass, with separate authority
     * histories.
     */
    private inner class LocalPrediction(var id: Int, var sequence: Long = 0) {
        val frames = ArrayDeque<Frame>()
        val sent = LinkedHashMap<Long, Int>()
        val presenter = TankMotionPresenter()
        var predicted: ArenaTank? = null
        var step = 0
        var accumulator = 0.0
        var correctionX = 0.0
        var correctionY = 0.0
        var correctionAngle = 0.0
        var correctionVelocityX = 0.0
        var correctionVelocityY = 0.0
        var correctionVelocityAngle = 0.0
        var lastInput = GameInput()

        fun clearCorrection() {
            correctionX = 0.0
            correctionY = 0.0
            correctionAngle = 0.0
            correctionVelocityX = 0.0
            correctionVelocityY = 0.0
            correctionVelocityAngle = 0.0
            presenter.reset()
        }

        fun reset(sequence: Long) {
            this.sequence = sequence
            resetPrediction(null)
        }

        fun resetPrediction(tank: ArenaTank?) {
            predicted = tank?.copy()
            frames.clear()
            sent.clear()
            step = 0
            accumulator = 0.0
            lastInput = GameInput()
            clearCorrection()
        }

        fun neutralize() {
            accumulator = 0.0
            lastInput = GameInput()
            clearCorrection()
        }

        fun rememberSent(at: Int) {
            sent[sequence] = at
            // Sequences are monotonic, so evict only the oldest entry rather than
            // scanning240/sending tick.
            if (sent.size > 240)
                sent.entries.iterator().let {
                    it.next()
                    it.remove()
                }
        }

        fun neutralPacket(): GameInput {
            neutralize()
            sequence++
            rememberSent(step + 1)
            return GameInput(seq = sequence)
        }

        fun accept(snapshot: ArenaSnapshot, recovering: Boolean) {
            val authoritative = snapshot.tanks.firstOrNull { it.id == id }?.copy()
            val old = predicted
            if (
                authoritative == null ||
                    old == null ||
                    recovering ||
                    authoritative.hp != old.hp ||
                    authoritative.spawnSerial != old.spawnSerial ||
                    snapshot.phase != "playing"
            ) {
                resetPrediction(authoritative)
                return
            }
            val processed =
                sent[authoritative.ack]?.let { it + max(1, authoritative.ackSteps) - 1 }
                    ?: if (authoritative.ack == 0L) 0 else step
            val complete = processed >= (frames.firstOrNull()?.step ?: step + 1) - 1
            if (complete && authoritative.hp > 0)
                frames.forEach { if (it.step > processed) move(authoritative, it.input, 1.0 / 60) }
            val error = hypot(old.x - authoritative.x, old.y - authoritative.y)
            if (
                !complete ||
                    authoritative.hp <= 0 ||
                    error > 64 ||
                    (old.ghostTime > 0) != (authoritative.ghostTime > 0)
            )
                clearCorrection()
            else {
                presenter.rebase(
                    authoritative.x - old.x,
                    authoritative.y - old.y,
                    TankMovement.angleDelta(authoritative.angle, old.angle),
                )
                // Preserve displayed velocity when jitter changes replay's pose.
                // Authority and gameplay adopt the new state immediately.
                val oldNext = old.copy()
                val newNext = authoritative.copy()
                move(oldNext, lastInput, 1.0 / 60)
                move(newNext, lastInput, 1.0 / 60)
                correctionVelocityX += ((oldNext.x - old.x) - (newNext.x - authoritative.x)) * 60
                correctionVelocityY += ((oldNext.y - old.y) - (newNext.y - authoritative.y)) * 60
                correctionVelocityAngle += (TankMovement.angleDelta(oldNext.angle, old.angle) -
                    TankMovement.angleDelta(newNext.angle, authoritative.angle)) * 60
                correctionX += old.x - authoritative.x
                correctionY += old.y - authoritative.y
                correctionAngle =
                    TankMovement.angleDelta(correctionAngle + old.angle, authoritative.angle)
                clampCorrection(if (authoritative.ghostTime > 0) 12.0 else 48.0)
            }
            predicted = authoritative
            while (frames.firstOrNull()?.step?.let { it <= processed } == true) frames.removeFirst()
            sent.entries.removeAll { it.value < step - 240 }
        }

        fun advance(
            elapsed: Double,
            input: GameInput,
            newest: ArenaSnapshot,
            send: (GameInput) -> Unit,
        ): GameInput {
            if (stale) clearCorrection()
            accumulator += elapsed
            var controls = if (stale) GameInput() else input.copy()
            lastInput = controls
            while (accumulator + 1e-9 >= 1.0 / 60) {
                accumulator = max(0.0, accumulator - 1.0 / 60)
                step++
                sequence++
                controls = controls.copy(seq = sequence)
                rememberSent(step)
                send(controls)
                predicted?.let { tank ->
                    if (tank.hp > 0 && newest.phase == "playing" && !stale) {
                        val phasing = tank.ghostTime > 0
                        move(tank, controls, 1.0 / 60)
                        if (phasing != (tank.ghostTime > 0)) clearCorrection()
                        frames.addLast(Frame(step, controls.copy()))
                        if (frames.size > 240) frames.removeFirst()
                    }
                }
            }
            return controls
        }

        fun present(controls: GameInput, newest: ArenaSnapshot, elapsed: Double): ArenaTank? {
            val raw = predicted ?: return null
            advanceCorrection(elapsed)
            clampCorrection(if (raw.ghostTime > 0) 12.0 else 48.0)
            var tank = raw.copy()
            if (tank.hp > 0 && newest.phase == "playing" && !stale) {
                tank =
                    presenter.present(
                        tank,
                        controls,
                        step.toLong(),
                        newest.generation,
                        accumulator * 60,
                        ::move,
                    ) { first, second ->
                        fits(second, newest.world) &&
                            (first.ghostTime > 0 || pathClear(first, second, newest.world))
                    }
                val corrected = tank.copy(x = tank.x + correctionX, y = tank.y + correctionY)
                if (
                    fits(corrected, newest.world) &&
                        (tank.ghostTime > 0 || pathClear(tank, corrected, newest.world))
                )
                    tank = corrected
                else {
                    correctionX = 0.0
                    correctionY = 0.0
                    correctionVelocityX = 0.0
                    correctionVelocityY = 0.0
                }
                tank.angle = TankMovement.angleDelta(tank.angle + correctionAngle, 0.0)
            }
            return tank
        }

        private fun advanceCorrection(dt: Double) {
            val omega = 20.0
            val decay = exp(-omega * dt)
            var impulse = (correctionVelocityX + omega * correctionX) * dt
            correctionX = (correctionX + impulse) * decay
            correctionVelocityX = (correctionVelocityX - omega * impulse) * decay
            impulse = (correctionVelocityY + omega * correctionY) * dt
            correctionY = (correctionY + impulse) * decay
            correctionVelocityY = (correctionVelocityY - omega * impulse) * decay
            impulse = (correctionVelocityAngle + omega * correctionAngle) * dt
            correctionAngle = (correctionAngle + impulse) * decay
            correctionVelocityAngle = (correctionVelocityAngle - omega * impulse) * decay
            if (abs(correctionX) < 1e-5 && abs(correctionVelocityX) < 1e-4) { correctionX = 0.0; correctionVelocityX = 0.0 }
            if (abs(correctionY) < 1e-5 && abs(correctionVelocityY) < 1e-4) { correctionY = 0.0; correctionVelocityY = 0.0 }
            if (abs(correctionAngle) < 1e-5 && abs(correctionVelocityAngle) < 1e-4) { correctionAngle = 0.0; correctionVelocityAngle = 0.0 }
        }

        private fun clampCorrection(limit: Double) {
            val distance = hypot(correctionX, correctionY)
            if (distance >= limit) {
                val nx = correctionX / distance
                val ny = correctionY / distance
                correctionX = nx * limit
                correctionY = ny * limit
                val outward = correctionVelocityX * nx + correctionVelocityY * ny
                if (outward > 0) { correctionVelocityX -= nx * outward; correctionVelocityY -= ny * outward }
            }
            if (abs(correctionAngle) >= .7) {
                correctionAngle = correctionAngle.coerceIn(-.7, .7)
                if (correctionVelocityAngle * correctionAngle > 0) correctionVelocityAngle = 0.0
            }
        }
    }

    fun reset(initialSequence: Long = 0, localInitialSequence: Long = 0) {
        samples.clear()
        latest = null
        primary.reset(initialSequence)
        secondary?.reset(localInitialSequence)
        secondaryInitialSequence = localInitialSequence
        pair = null
        context = null
        indexedLatest = null
        pathChecks.clear()
        curves.clear()
        ricochetPaths.clear()
        clock = null
        playbackRate = 1.0
        oldTanks = emptyMap()
        newTanks = emptyMap()
        oldBullets.clear()
        newBullets.clear()
        liveBullets.clear()
        lastArrival = 0.0
        stale = false
    }

    fun setLocalID(id: Int) {
        if (id != primary.id) {
            primary.id = id
            primary.resetPrediction(latest?.tanks?.firstOrNull { it.id == id })
        }
    }

    fun setLocalIDs(primary: Int, secondary: Int? = null, localInitialSequence: Long? = null) {
        require(secondary == null || primary != secondary) {
            "Each local seat needs a different tank."
        }
        setLocalID(primary)
        secondaryInitialSequence =
            localInitialSequence ?: this.secondary?.sequence ?: secondaryInitialSequence
        if (secondary == null) this.secondary = null
        else if (this.secondary?.id != secondary) {
            this.secondary =
                LocalPrediction(secondary, secondaryInitialSequence).also { local ->
                    local.resetPrediction(latest?.tanks?.firstOrNull { it.id == secondary })
                }
        }
    }

    private fun move(tank: ArenaTank, input: GameInput, dt: Double) {
        if (movement != null) movement.invoke(tank, input, dt)
        else maze?.let { TankMovement.step(tank, input, dt, it) }
    }

    fun accept(snapshot: ArenaSnapshot, at: Double) {
        val previous = latest
        val changedView = previous != null && snapshot.spectating && previous.spectating && snapshot.following != previous.following
        if (
            previous != null &&
                (snapshot.generation < previous.generation ||
                    snapshot.generation == previous.generation && (snapshot.tick < previous.tick || snapshot.tick == previous.tick && !changedView))
        )
            return
        val recovering = previous != null && (stale || at - lastArrival > 2.5)
        if (previous != null && (previous.generation != snapshot.generation || changedView)) {
            samples.clear()
            primary.resetPrediction(null)
            secondary?.resetPrediction(null)
            clock = null
            playbackRate = 1.0
            pair = null
            context = null
            indexedLatest = null
            pathChecks.clear()
            curves.clear()
            ricochetPaths.clear()
        }
        latest = snapshot
        lastArrival = at
        stale = false
        snapshot.world?.let { if (maze?.world !== it) maze = InfiniteMaze(it) }
        if (recovering) {
            samples.clear()
            clock = null
            playbackRate = 1.0
        }
        val timestamp = snapshot.tick / 60.0
        samples.add(Sample(snapshot, timestamp))
        if (samples.size > 90) samples.removeAt(0)
        if (clock == null) clock = timestamp - .085
        pathChecks.keys.retainAll(snapshot.tanks.map { it.id }.toSet())
        primary.accept(snapshot, recovering)
        secondary?.accept(snapshot, recovering)
    }

    fun render(
        dt: Double,
        input: GameInput,
        now: Double,
        maze: InfiniteMaze? = null,
        input2: GameInput? = null,
        sendLocal: ((GameInput) -> Unit)? = null,
        send: (GameInput) -> Unit,
    ): ArenaSnapshot? {
        this.maze = maze ?: this.maze
        val newest = latest ?: return null
        val elapsed = if (dt.isFinite()) dt.coerceIn(0.0, .1) else 0.0
        stale = now - lastArrival > 2.5
        if (newest.spectating) return interpolated(elapsed, null)
        val controls = primary.advance(elapsed, input, newest, send)
        val second = secondary
        val secondControls =
            if (second != null && sendLocal != null)
                second.advance(elapsed, input2 ?: GameInput(), newest, sendLocal)
            else null
        val result = interpolated(elapsed, if (secondControls != null) second?.id else null)
        val firstTank = primary.present(controls, newest, elapsed)
        val secondTank =
            if (secondControls != null) second?.present(secondControls, newest, elapsed) else null
        result.tanks =
            result.tanks.map { tank ->
                if (tank.id == primary.id && firstTank != null) firstTank
                else if (tank.id == second?.id && secondTank != null) secondTank else tank
            }
        return result
    }

    fun neutralize() {
        primary.neutralize()
        secondary?.neutralize()
        clock = null
        playbackRate = 1.0
    }

    fun neutralPacket(): GameInput {
        neutralize()
        return primary.neutralPacket()
    }

    fun neutralLocalPacket(): GameInput? = secondary?.neutralPacket()

    private fun interpolated(dt: Double, secondaryID: Int?): ArenaSnapshot {
        val newest = samples.lastOrNull() ?: return ArenaSnapshot()
        val target = newest.time - .085
        var playhead = clock ?: target
        if (target - playhead > .6) playhead = target
        val fill = target - playhead
        val wanted = if (fill > .02) 1.05 else if (fill < -.02) .95 else 1.0
        playbackRate += (wanted - playbackRate) * min(1.0, dt * 6)
        playhead = min(playhead + dt * playbackRate, newest.time)
        clock = playhead
        var ai = 0
        var bi = 0
        for (index in 1 until samples.size) {
            bi = index
            if (samples[index].time >= playhead) break
            ai = index
        }
        val a = samples[ai]
        val b = samples[bi]
        val preceding = samples.getOrNull(ai - 1)
        val following = samples.getOrNull(bi + 1)
        val span = b.time - a.time
        val alpha = if (span > 0) ((playhead - a.time) / span).coerceIn(0.0, 1.0) else 1.0
        val result = newest.state.copy()
        if (pair != a.state.tick to b.state.tick) {
            pair = a.state.tick to b.state.tick
            oldTanks = a.state.tanks.associateBy { it.id }
            newTanks = b.state.tanks.associateBy { it.id }
            oldBullets.replace(a.state.bullets)
            newBullets.replace(b.state.bullets)
            pathChecks.clear()
            ricochetPaths.clear()
        }
        if (indexedLatest != newest.state.tick) {
            indexedLatest = newest.state.tick
            liveBullets.replace(newest.state.bullets)
        }
        val nextContext =
            listOf(a.state.tick, b.state.tick, preceding?.state?.tick, following?.state?.tick)
        if (context != nextContext) {
            context = nextContext
            curves.clear()
            previousTanks = preceding?.state?.tanks?.associateBy { it.id } ?: emptyMap()
            followingTanks = following?.state?.tanks?.associateBy { it.id } ?: emptyMap()
        }
        result.tanks =
            result.tanks.map { current ->
                if (current.id == primary.id || current.id == secondaryID) return@map current
                val first = oldTanks[current.id]
                val second = newTanks[current.id]
                if (
                    first == null ||
                        second == null ||
                        !compatible(first, second) ||
                        !compatible(second, current)
                )
                    return@map current
                if (
                    first.ghostTime <= 0 &&
                        !pathChecks.getOrPut(current.id) {
                            pathClear(first, second, newest.state.world)
                        }
                )
                    return@map current.copy(x = first.x, y = first.y, angle = first.angle)
                val delta = TankMovement.angleDelta(second.angle, first.angle)
                var tank =
                    current.copy(
                        x = first.x + (second.x - first.x) * alpha,
                        y = first.y + (second.y - first.y) * alpha,
                        angle = first.angle + delta * alpha,
                        track = first.track + (second.track - first.track) * alpha,
                    )
                if (span > 0 && span <= .1) {
                    val curve =
                        curves.getOrPut(current.id) {
                            makeCurve(
                                first,
                                second,
                                a.time,
                                b.time,
                                previousTanks[current.id],
                                preceding?.time,
                                followingTanks[current.id],
                                following?.time,
                                newest.state.world,
                            )
                        }
                    if (curve.clear) {
                        val candidate =
                            tank.copy(
                                x = hermite(first.x, second.x, curve.ax, curve.bx, alpha),
                                y = hermite(first.y, second.y, curve.ay, curve.by, alpha),
                            )
                        if (
                            fits(candidate, newest.state.world) &&
                                (first.ghostTime > 0 ||
                                    pointClear(candidate.x, candidate.y, newest.state.world))
                        ) {
                            tank = candidate
                            tank.angle =
                                first.angle + hermite(0.0, delta, curve.angleA, curve.angleB, alpha)
                        } else curve.clear = false
                    }
                }
                tank
            }
        val visible = if (alpha < 1) a.state.bullets else b.state.bullets
        result.bullets = visible.mapNotNull { bullet ->
            if (bullet.id !in liveBullets) return@mapNotNull null
            val first = oldBullets[bullet.id]
            val second = newBullets[bullet.id]
            if (first == null || second == null) bullet
            else if (first.bounces != second.bounces) {
                if (!ricochetPaths.containsKey(bullet.id)) ricochetPaths[bullet.id] = RicochetPath.between(first, second, span, maze)
                ricochetPaths[bullet.id]?.sample(second, first, alpha) ?: bullet
            }
            else
                second.copy(
                    x = first.x + (second.x - first.x) * alpha,
                    y = first.y + (second.y - first.y) * alpha,
                    vx = first.vx + (second.vx - first.vx) * alpha,
                    vy = first.vy + (second.vy - first.vy) * alpha,
                )
        }
        return result
    }

    private fun compatible(a: ArenaTank, b: ArenaTank) =
        a.hp > 0 &&
            b.hp > 0 &&
            a.spawnSerial == b.spawnSerial &&
            (a.ghostTime > 0) == (b.ghostTime > 0) &&
            hypot(a.x - b.x, a.y - b.y) < 160

    private fun hermite(a: Double, b: Double, start: Double, end: Double, t: Double): Double {
        val t2 = t * t
        val t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * a +
            (t3 - 2 * t2 + t) * start +
            (-2 * t3 + 3 * t2) * b +
            (t3 - t2) * end
    }

    private fun makeCurve(
        a: ArenaTank,
        b: ArenaTank,
        start: Double,
        end: Double,
        previous: ArenaTank?,
        previousTime: Double?,
        following: ArenaTank?,
        followingTime: Double?,
        world: ArenaWorld?,
    ): Curve {
        val span = end - start
        val dx = b.x - a.x
        val dy = b.y - a.y
        val angle = TankMovement.angleDelta(b.angle, a.angle)
        var ax = dx
        var ay = dy
        var bx = dx
        var by = dy
        var angleA = angle
        var angleB = angle
        if (
            previous != null &&
                previousTime != null &&
                start > previousTime &&
                end - previousTime <= .2 &&
                compatible(previous, a)
        ) {
            val scale = span / (end - previousTime)
            ax = (b.x - previous.x) * scale
            ay = (b.y - previous.y) * scale
            angleA = TankMovement.angleDelta(b.angle, previous.angle) * scale
        }
        if (
            following != null &&
                followingTime != null &&
                followingTime > end &&
                followingTime - start <= .2 &&
                compatible(following, b)
        ) {
            val scale = span / (followingTime - start)
            bx = (following.x - a.x) * scale
            by = (following.y - a.y) * scale
            angleB = TankMovement.angleDelta(following.angle, a.angle) * scale
        }
        val distance = hypot(dx, dy)
        if (distance < 1e-7) {
            ax = 0.0
            ay = 0.0
            bx = 0.0
            by = 0.0
        } else {
            val limit = distance * 3
            val al = hypot(ax, ay)
            val bl = hypot(bx, by)
            if (al > limit) {
                ax *= limit / al
                ay *= limit / al
            }
            if (bl > limit) {
                bx *= limit / bl
                by *= limit / bl
            }
        }
        val curve = Curve(ax, ay, bx, by, angleA, angleB)
        if (maze != null || world != null) {
            var prior = a
            val count = max(8, ceil(distance / 2).toInt())
            for (index in 1..count) {
                val t = index.toDouble() / count
                val point =
                    a.copy(x = hermite(a.x, b.x, ax, bx, t), y = hermite(a.y, b.y, ay, by, t))
                if (!fits(point, world) || a.ghostTime <= 0 && !pathClear(prior, point, world)) {
                    curve.clear = false
                    break
                }
                prior = point
            }
        }
        return curve
    }

    private fun fits(tank: ArenaTank, world: ArenaWorld?) =
        TankMovement.presentationFitsBounds(tank, world ?: maze?.world)

    private fun pathClear(a: ArenaTank, b: ArenaTank, world: ArenaWorld?): Boolean {
        if (maze == null && world == null) return true
        val count = max(1, ceil(hypot(b.x - a.x, b.y - a.y) / 2).toInt())
        for (index in 0..count) {
            val t = index.toDouble() / count
            if (!pointClear(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, world)) return false
        }
        return true
    }

    private fun pointClear(x: Double, y: Double, world: ArenaWorld?): Boolean {
        maze?.let {
            return !it.blocked(x, y, 17.0)
        }
        if (world == null) return true
        if (x < 21 || y < 21 || x > world.width - 21 || y > world.height - 21) return false
        return world.walls.none {
            val dx = x - x.coerceIn(it.x, it.x + it.w)
            val dy = y - y.coerceIn(it.y, it.y + it.h)
            dx * dx + dy * dy < 289
        }
    }
}
