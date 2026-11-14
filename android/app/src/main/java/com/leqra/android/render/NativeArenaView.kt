package com.leqra.android.render

import android.content.Context
import android.graphics.*
import android.util.AttributeSet
import android.util.SparseArray
import android.view.*
import com.leqra.core.*
import kotlin.math.*

/** Native display-paced hardware Canvas. The owner supplies fractional simulation snapshots. */
class NativeArenaView
@JvmOverloads
constructor(context: Context, attributes: AttributeSet? = null) :
    View(context, attributes), Choreographer.FrameCallback {
    var onFrame: ((Long) -> Unit)? = null
    var onInput: ((GameInput) -> Unit)? = null
    var onFirstFrame: (() -> Unit)? = null
    var showControls = true
        set(value) {
            val clear = field && !value
            field = value
            if (clear) resetControls()
        }

    var hudHeightDp = 0f
    var overlayHudHeightDp = 0f
    var controlsLayout = true
    var fireLabel = "FIRE"
    var fireHint = "HOLD TO FIRE"
    var fireProgress = 1.0
        set(value) {
            field = if (value.isFinite()) value.coerceIn(0.0, 1.0) else 0.0
        }

    var fireAvailable = true
    var encounterNotice: String? = null
    /** Camera target is separate from local identity; a viewer never labels a tank P1. */
    var followingID: Int? = null
    private var noticeLayoutText: String? = null
    private var noticeLayoutWidth = 0f
    private var noticeLayoutSize = 0f
    private var noticeLines: List<String> = emptyList()
    val input = GameInput(touchAim = true)
    var renderedFrames: Long = 0
        private set

    var lastRenderNanos: Long = 0
        private set

    var maxRenderNanos: Long = 0
        private set

    val terrainTilesBuilt: Long
        get() = terrain.tilesBuilt

    val terrainCachedBytes: Long
        get() = terrain.cachedBytes

    val terrainFallbackDraws: Long
        get() = terrain.fallbackDraws

    private var density = resources.displayMetrics.density
    private var textScale = resources.configuration.fontScale.coerceAtLeast(1f)
    private val boldTypeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
    private val countText = Array(181) { it.toString() }
    private val countWidths = FloatArray(181)
    private var countFontSize = -1f
    private val art = NativeArt()
    private val terrain = TerrainCache { postInvalidateOnAnimation() }
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val textPaint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = Typeface.MONOSPACE
            textAlign = Paint.Align.CENTER
        }
    private val path = Path()
    private val destination = RectF()
    private val viewport = RectF()
    private val safe = RectF()
    private var snapshot: ArenaSnapshot? = null
    private var geometry: InfiniteMaze? = null
    private var localID = 1
    private var localID2: Int? = null
    private var infinity = true
    private var online = false
    private var generation: Int? = null
    private val seenEffectIDs = LinkedHashSet<Int>()
    private var lastSnapshotTick: Long? = null
    private var projectileFrame = 0L

    private class RapidBatch {
        var heads = FloatArray(512)
        var tails = FloatArray(1024)
        var count = 0

        fun add(b: ArenaBullet, originX: Double, originY: Double) {
            if ((count + 1) * 4 > tails.size) {
                heads = heads.copyOf(heads.size * 2)
                tails = tails.copyOf(tails.size * 2)
            }
            val x = (b.x - originX).toFloat()
            val y = (b.y - originY).toFloat()
            val length = hypot(b.vx, b.vy)
            val dx = if (length > 0) (b.vx / length * 8).toFloat() else 8f
            val dy = if (length > 0) (b.vy / length * 8).toFloat() else 0f
            heads[count * 2] = x
            heads[count * 2 + 1] = y
            tails[count * 4] = x - dx
            tails[count * 4 + 1] = y - dy
            tails[count * 4 + 2] = x
            tails[count * 4 + 3] = y
            count++
        }
    }

    private class ProjectileHistory(val kind: String, val color: Int) {
        val points = DoubleArray(14)
        var start = 0
        var count = 0
        var bounce = -1
        var lastTime = Double.NEGATIVE_INFINITY
        var seen = 0L
        var vx = Double.NaN
        var vy = Double.NaN
        var angle = 0f

        fun update(b: ArenaBullet, time: Double, frame: Long) {
            seen = frame
            if (b.vx != vx || b.vy != vy) {
                vx = b.vx
                vy = b.vy
                angle = (atan2(vy, vx) * 180 / PI).toFloat()
            }
            if (count > 0) {
                val last = (start + count - 1) % 7
                val elapsed = time - lastTime
                val allowed = max(64.0, hypot(b.vx, b.vy) * max(1.0 / 60, elapsed) * 2)
                if (
                    elapsed > .15 ||
                        hypot(b.x - points[last * 2], b.y - points[last * 2 + 1]) > allowed
                ) {
                    count = 0
                    start = 0
                    lastTime = Double.NEGATIVE_INFINITY
                }
            }
            if (b.bounces != bounce) {
                bounce = b.bounces
                count = 0
                start = 0
                lastTime = Double.NEGATIVE_INFINITY
            }
            if (time - lastTime >= 1.0 / 60 - 1e-6) {
                if (count < 7) {
                    val slot = (start + count) % 7
                    points[slot * 2] = b.x
                    points[slot * 2 + 1] = b.y
                    count++
                } else {
                    points[start * 2] = b.x
                    points[start * 2 + 1] = b.y
                    start = (start + 1) % 7
                }
                lastTime = time
            }
        }
    }

    private val rapidBatches = Array(8) { RapidBatch() }
    private val projectileHistory = SparseArray<ProjectileHistory>()
    private val trails = Array(24) { Path() }
    private var removals = IntArray(256)
    private var running = false
    private var firstFrame = false
    private var frameTime = 0.0
    private var zoom = 1f
    private var cameraX = 0.0
    private var cameraY = 0.0
    private var originX = 0.0
    private var originY = 0.0
    private var worldLeft = 0.0
    private var worldTop = 0.0
    private var worldRight = 0.0
    private var worldBottom = 0.0
    private var stickPointer = -1
    private var firePointer = -1
    private var stickX = 82f
    private var stickY = 100f
    private var fireX = 300f
    private var fireY = 100f
    private var knobX = 0f
    private var knobY = 0f
    private var fireHeld = false

    private data class VisualEffect(val effect: ArenaEffect, val began: Double, val shape: Path?)

    private val effects = ArrayList<VisualEffect>(64)

    private data class Label(
        val name: String,
        val seat: Int,
        val bot: Boolean,
        val maxWidth: Float,
        val fontSize: Float,
        val width: Float,
        val height: Float,
        val lines: List<String>,
    )

    private val labels = HashMap<Int, Label>()
    private val haloDash = DashPathEffect(floatArrayOf(3f, 6f), 0f)
    private val ghostDash = DashPathEffect(floatArrayOf(3f, 4f), 0f)
    private val starColors =
        intArrayOf(
            0xffff758f.toInt(),
            0xfff9ed75.toInt(),
            0xff79d878.toInt(),
            0xff62dcff.toInt(),
            0xffba91ff.toInt(),
        )
    private val dash = DashPathEffect(floatArrayOf(3f, 7f), 0f)
    private val guidePath = Path()
    private var guideSignature = 0L
    private var guideReady = false

    init {
        setBackgroundColor(0xff10181e.toInt())
        isFocusable = true
        isFocusableInTouchMode = true
        contentDescription =
            "leqra arena. Drag the left joystick to steer and hold the right fire button to fire."
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        // Keep hardware acceleration enabled: display lists render on Android's RenderThread.
        setLayerType(LAYER_TYPE_NONE, null)
    }

    fun start() {
        if (running) return
        running = true
        keepScreenOn = true
        Choreographer.getInstance().postFrameCallback(this)
    }

    fun pause() {
        running = false
        keepScreenOn = false
        Choreographer.getInstance().removeFrameCallback(this)
        resetControls()
    }

    fun release() {
        pause()
        terrain.release()
        art.clear()
        snapshot = null
    }

    fun safeInsets(left: Int, top: Int, right: Int, bottom: Int) {
        safe.set(left / density, top / density, right / density, bottom / density)
        invalidate()
    }

    fun setSafeInsets(left: Int, top: Int, right: Int, bottom: Int) =
        safeInsets(left, top, right, bottom)

    fun resetWorld() {
        generation = null
        effects.clear()
        labels.clear()
        terrain.clear()
        seenEffectIDs.clear()
        lastSnapshotTick = null
        projectileHistory.clear()
        guideReady = false
    }

    fun resetControls() {
        stickPointer = -1
        firePointer = -1
        knobX = 0f
        knobY = 0f
        fireHeld = false
        input.forward = false
        input.reverse = false
        input.left = false
        input.right = false
        input.fire = false
        input.stickX = 0.0
        input.stickY = 0.0
        onInput?.invoke(input.copy())
        invalidate()
    }

    fun submit(
        snapshot: ArenaSnapshot,
        localID: Int,
        maze: InfiniteMaze?,
        localID2: Int? = null,
        online: Boolean = false,
    ) {
        val changedWorld =
            generation != snapshot.generation ||
                lastSnapshotTick?.let { snapshot.tick < it } == true ||
                geometry?.seed != maze?.seed
        if (changedWorld) {
            effects.clear()
            labels.clear()
            seenEffectIDs.clear()
            projectileHistory.clear()
            guideReady = false
        }
        lastSnapshotTick = snapshot.tick
        this.snapshot = snapshot
        this.localID = localID
        this.localID2 = localID2
        this.geometry = maze
        this.infinity = snapshot.world == null
        this.online = online
        terrain.configure(maze, snapshot.world)
        if (generation != snapshot.generation) {
            generation = snapshot.generation
            effects.clear()
            labels.clear()
            seenEffectIDs.clear()
        }
        if (labels.size > 128) labels.keys.retainAll(snapshot.tanks.map { it.id }.toSet())
        val now = if (frameTime > 0) frameTime else System.nanoTime() / 1e9
        for (effect in snapshot.effects) if (effect.id > 0 && seenEffectIDs.add(effect.id)) {
            if (seenEffectIDs.size > 512) seenEffectIDs.iterator().let { it.next(); it.remove() }
            if (
                !effect.kind.startsWith("shot") &&
                    effect.kind != "roundEnd" &&
                    effect.kind != "objective" && effect.kind != "projectileFlight"
            ) {
                if (effects.size == 64) effects.removeAt(0)
                val shape =
                    when {
                        effect.kind == "laser" && effect.points.size >= 2 ->
                            Path().apply {
                                moveTo(0f, 0f)
                                for (i in 1 until effect.points.size) lineTo(
                                    (effect.points[i].x - effect.points[0].x).toFloat(),
                                    (effect.points[i].y - effect.points[0].y).toFloat(),
                                )
                            }
                        effect.kind == "blast" && maze != null ->
                            Path().apply {
                                for (i in 0 until 24) {
                                    val angle = i * PI * 2 / 24
                                    val end =
                                        maze
                                            .projectileGuide(
                                                effect.x,
                                                effect.y,
                                                angle,
                                                "",
                                                220.0,
                                                0.0,
                                                1,
                                            )
                                            .lastOrNull()
                                    val x = ((end?.x ?: effect.x) - effect.x).toFloat()
                                    val y = ((end?.y ?: effect.y) - effect.y).toFloat()
                                    if (i == 0) moveTo(x, y) else lineTo(x, y)
                                }
                                close()
                            }
                        else -> null
                    }
                effects += VisualEffect(effect, now, shape)
            }
        }
        invalidate()
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (!running) return
        frameTime = frameTimeNanos / 1e9
        onFrame?.invoke(frameTimeNanos)
        invalidate()
        Choreographer.getInstance().postFrameCallback(this)
    }

    override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
        super.onWindowFocusChanged(hasWindowFocus)
        if (!hasWindowFocus) resetControls()
    }

    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        density = resources.displayMetrics.density
        textScale = newConfig.fontScale.coerceAtLeast(1f)
        labels.clear()
        resetControls()
        requestApplyInsets()
    }

    override fun onDetachedFromWindow() {
        pause()
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val start = System.nanoTime()
        canvas.save()
        canvas.scale(density, density)
        val width = width / density
        val height = height / density
        val landscape = width > height
        viewport.set(
            if (infinity) 0f else safe.left,
            safe.top + hudHeightDp,
            if (infinity) width else width - safe.right,
            height -
                safe.bottom -
                if (!infinity && !landscape && controlsLayout) 119f + overlayHudHeightDp else 0f,
        )
        if (viewport.width() <= 0 || viewport.height() <= 0) {
            canvas.restore()
            return
        }
        val fixedPortrait = !infinity && !landscape
        stickX = safe.left + if (fixedPortrait) 93f else 84f
        stickY = height - safe.bottom - if (fixedPortrait) 59.5f else 67.5f
        fireX = width - safe.right - if (fixedPortrait) 85.5f else 63.5f
        fireY = stickY
        val state = snapshot
        if (state != null) {
            updateCamera(state, landscape)
            canvas.save()
            canvas.clipRect(viewport)
            canvas.translate(
                viewport.centerX() - ((cameraX - originX) * zoom).toFloat(),
                viewport.centerY() - ((cameraY - originY) * zoom).toFloat(),
            )
            canvas.scale(zoom, zoom)
            val fixedWorld = state.world
            if (fixedWorld != null) {
                fill(0x9902080b.toInt())
                canvas.drawRect(
                    2f,
                    5f,
                    fixedWorld.width.toFloat() + 2,
                    fixedWorld.height.toFloat() + 5,
                    paint,
                )
                canvas.save()
                canvas.clipRect(0f, 0f, fixedWorld.width.toFloat(), fixedWorld.height.toFloat())
                terrain.draw(
                    canvas,
                    max(0.0, worldLeft),
                    max(0.0, worldTop),
                    min(fixedWorld.width - .01, worldRight),
                    min(fixedWorld.height - .01, worldBottom),
                    originX,
                    originY,
                )
                canvas.restore()
                stroke(0xff829285.toInt(), 2f)
                canvas.drawRect(
                    1f,
                    1f,
                    fixedWorld.width.toFloat() - 1,
                    fixedWorld.height.toFloat() - 1,
                    paint,
                )
            } else
                terrain.draw(canvas, worldLeft, worldTop, worldRight, worldBottom, originX, originY)
            drawObjectives(canvas, state)
            for (pickup in state.pickups) if (isVisible(pickup.x, pickup.y, 30.0)) {
                val alpha = if (pickup.life < 3) (.5 + .4 * sin(frameTime * 12)).toFloat() else 1f
                val pulse = (sin(frameTime * 3 + pickup.x) * .5 + .5).toFloat()
                val half = 18 * (1 + pulse / 18)
                stroke(ArenaPalette.alpha(ArenaPalette.power(pickup.type), .2f * alpha), 1.5f)
                canvas.drawRoundRect(
                    rx(pickup.x) - half,
                    ry(pickup.y) - half,
                    rx(pickup.x) + half,
                    ry(pickup.y) + half,
                    9f,
                    9f,
                    paint,
                )
                paint.style = Paint.Style.FILL
                paint.alpha = (alpha * 255).toInt()
                destination.set(
                    rx(pickup.x) - 21,
                    ry(pickup.y) - 21,
                    rx(pickup.x) + 21,
                    ry(pickup.y) + 21,
                )
                canvas.drawBitmap(art.pickup(pickup.type), null, destination, paint)
            }
            paint.alpha = 255
            drawGuide(canvas, state)
            for (tank in state.tanks) if (
                isVisible(tank.x, tank.y, 100.0) && (!infinity || tank.hp > 0)
            )
                drawTank(canvas, tank)
            drawBullets(canvas, state)
            drawMissileWarnings(canvas, state)
            drawEffects(canvas)
            canvas.restore()
            for (tank in state.tanks) if (isVisible(tank.x, tank.y, 0.0) && tank.hp > 0)
                drawIdentity(canvas, tank)
            drawPhase(canvas, state)
            drawEncounterNotice(canvas)
        }
        if (showControls) drawControls(canvas, width, height, state)
        canvas.restore()
        renderedFrames++
        lastRenderNanos = System.nanoTime() - start
        maxRenderNanos = max(maxRenderNanos, lastRenderNanos)
        if (!firstFrame && state != null) {
            firstFrame = true
            post { onFirstFrame?.invoke() }
        }
    }

    private fun updateCamera(state: ArenaSnapshot, landscape: Boolean) {
        val world = state.world
        if (world != null) {
            cameraX = world.width / 2
            cameraY = world.height / 2
            zoom =
                min(
                        (viewport.width() - if (landscape && controlsLayout) 264f else 12f) /
                            world.width.toFloat(),
                        (viewport.height() - 12) / world.height.toFloat(),
                    )
                    .coerceAtLeast(.05f)
        } else {
            val focus = state.tanks.firstOrNull { it.id == (followingID ?: localID) } ?: if (followingID == null) state.tanks.firstOrNull() else null
            if (focus != null) {
                cameraX = focus.x
                cameraY = focus.y
            } else if (followingID == 0) {
                cameraX = 0.0
                cameraY = 0.0
            }
            zoom = (min(viewport.width(), viewport.height()) / 420f).coerceIn(.7f, 1.2f)
        }
        originX = if (infinity) floor(cameraX / 336) * 336 else 0.0
        originY = if (infinity) floor(cameraY / 336) * 336 else 0.0
        worldLeft = cameraX - viewport.width() / zoom / 2
        worldTop = cameraY - viewport.height() / zoom / 2
        worldRight = cameraX + viewport.width() / zoom / 2
        worldBottom = cameraY + viewport.height() / zoom / 2
    }

    private fun rx(x: Double) = (x - originX).toFloat()

    private fun ry(y: Double) = (y - originY).toFloat()

    private fun isVisible(x: Double, y: Double, margin: Double) =
        x + margin >= worldLeft &&
            x - margin <= worldRight &&
            y + margin >= worldTop &&
            y - margin <= worldBottom

    private fun drawBitmap(canvas: Canvas, image: Bitmap, half: Float) {
        destination.set(-half, -half, half, half)
        canvas.drawBitmap(image, null, destination, paint)
    }

    private fun stroke(color: Int, width: Float) {
        paint.color = color
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = width
        paint.pathEffect = null
    }

    private fun fill(color: Int) {
        paint.color = color
        paint.style = Paint.Style.FILL
        paint.pathEffect = null
    }

    private fun drawTank(canvas: Canvas, tank: ArenaTank) {
        val local = tank.id == localID || tank.id == localID2
        val color = ArenaPalette.tank(tank.colorIndex)
        canvas.save()
        canvas.translate(rx(tank.x), ry(tank.y))
        if (tank.hp > 0) {
            val shields = if (tank.shield > 0) tank.shieldCharges.coerceIn(1, 5) else 0
            if (shields > 0) {
                stroke(ArenaPalette.alpha(ArenaPalette.power("shield"), .78f), 1.6f)
                for (i in 0 until shields) canvas.drawCircle(0f, 0f, 26f + i * 4, paint)
            } else if (tank.invulnerable > 0) {
                stroke(ArenaPalette.alpha(if (local) color else 0xffd8e9c5.toInt(), .55f), 1.3f)
                canvas.drawCircle(0f, 0f, if (local) 34f else 25f, paint)
            } else if (local) {
                stroke(ArenaPalette.alpha(color, .2f), 1f)
                paint.pathEffect = haloDash
                canvas.drawCircle(0f, 0f, 23f, paint)
                paint.pathEffect = null
            }
            if (tank.starmanTime > 0)
                for (i in starColors.indices) {
                    stroke(starColors[i], 2.5f)
                    canvas.drawArc(-24f, -24f, 24f, 24f, i * 72f, 61.2f, false, paint)
                }
        }
        canvas.rotate((tank.angle * 180 / PI).toFloat())
        if (tank.speedTime > 0 && tank.hp > 0) {
            stroke(ArenaPalette.power("speed"), 2f)
            for (i in 0 until tank.speedStacks.coerceIn(1, 5)) for (side in intArrayOf(-1, 1)) {
                val y = side * (8f + i * 2.2f)
                canvas.drawLine(-22f, y, -34f - i * 3, y, paint)
            }
        }
        paint.style = Paint.Style.FILL
        paint.alpha =
            if (tank.hp <= 0) 153
            else if (tank.ghostTime > 0) if (tank.starmanTime > 0) 214 else 148 else 255
        val phase = Math.floorMod(floor(tank.track / 2).toInt(), 4)
        drawBitmap(canvas, if (tank.hp > 0) art.hull(tank.colorIndex, phase) else art.wreck(), 24f)
        if (tank.hp > 0) {
            canvas.save()
            canvas.translate((-tank.recoil * 4).toFloat(), 0f)
            drawBitmap(canvas, art.barrel(tank.colorIndex), 32f)
            canvas.restore()
            drawBitmap(canvas, art.turret(tank.colorIndex), 12f)
            if (tank.ghostTime > 0 && !infinity) {
                stroke(ArenaPalette.power("ghost"), 1.6f)
                paint.pathEffect = ghostDash
                canvas.drawRoundRect(-23f, -21f, 23f, 21f, 9f, 9f, paint)
                paint.pathEffect = null
            }
        }
        paint.alpha = 255
        canvas.restore()
        if (tank.hp > 0) drawBadges(canvas, tank)
    }

    private fun drawBadges(canvas: Canvas, tank: ArenaTank) {
        var index = 0
        fun badge(kind: String, count: Int?, remaining: Double) {
            if (index >= 4) return
            val scale = max(1f, .72f / zoom)
            val size = 24 * scale
            val inkRadius = size * 28.5f / 64
            val radius =
                max(
                    30 + inkRadius + 1.5f * scale,
                    (inkRadius * 2 + 1.5f * scale) / (2 * sin(PI / 8)).toFloat(),
                )
            val angle = index++ * -PI / 4
            val x = rx(tank.x) + (cos(angle) * radius).toFloat()
            val y = ry(tank.y) + (sin(angle) * radius).toFloat()
            val fade = (remaining / (if (kind == "starman") 1 else 3)).coerceIn(0.0, 1.0)
            val alpha = (fade * fade * (3 - 2 * fade) * 255).toInt()
            if (alpha <= 0) return
            canvas.save()
            canvas.translate(x, y)
            paint.style = Paint.Style.FILL
            paint.alpha = alpha
            drawBitmap(canvas, art.badge(kind), size / 2)
            canvas.restore()
            paint.alpha = 255
            if (count != null) {
                textPaint.typeface = boldTypeface
                textPaint.textSize = max(10 * size / 24, 10 * textScale / zoom)
                val text = countText.getOrNull(count) ?: count.toString()
                if (countFontSize != textPaint.textSize) {
                    countFontSize = textPaint.textSize
                    countWidths.fill(0f)
                }
                val width =
                    if (count in countWidths.indices) {
                        if (countWidths[count] == 0f)
                            countWidths[count] = textPaint.measureText(text) + 4
                        countWidths[count]
                    } else textPaint.measureText(text) + 4
                val height = textPaint.textSize + 2
                val right = x + size / 2 - 2
                val bottom = y + size / 2 - 1
                fill(ArenaPalette.alpha(0xff08131b.toInt(), alpha / 255f * .96f))
                canvas.drawRoundRect(
                    right - width,
                    bottom - height,
                    right + 2,
                    bottom + 1,
                    2f,
                    2f,
                    paint,
                )
                textPaint.color = ArenaPalette.alpha(0xfff3f8ff.toInt(), alpha / 255f)
                textPaint.textAlign = Paint.Align.RIGHT
                canvas.drawText(text, right, bottom - 1, textPaint)
                textPaint.textAlign = Paint.Align.CENTER
            }
        }
        if (tank.power.isNotEmpty() && tank.powerTime > 0)
            badge(
                tank.power,
                if (tank.power == "rapid") tank.machineRounds else tank.charges,
                tank.powerTime + tank.starmanTime,
            )
        if (tank.shield > 0) badge("shield", tank.shieldCharges.coerceIn(1, 5), tank.shield)
        if (tank.speedTime > 0) badge("speed", tank.speedStacks.coerceIn(1, 5), tank.speedTime)
        if (tank.starmanTime > 0) badge("starman", null, tank.starmanTime)
        else if (tank.ghostTime > 0) badge("ghost", null, tank.ghostTime)
    }

    private fun drawIdentity(canvas: Canvas, tank: ArenaTank) {
        val seat = if (tank.id == localID) 1 else if (tank.id == localID2) 2 else 0
        textPaint.typeface = if (seat > 0) boldTypeface else Typeface.MONOSPACE
        textPaint.textSize = max(10f * textScale, if (infinity) 11f * zoom else 10f * zoom)
        val maxWidth = min(190f, viewport.width() - 20).coerceAtLeast(40f)
        var label = labels[tank.id]
        if (
            label == null ||
                label.name != tank.name ||
                label.seat != seat ||
                label.bot != tank.bot ||
                label.maxWidth != maxWidth ||
                label.fontSize != textPaint.textSize
        ) {
            val text = PilotIdentity.label(tank.name, tank.bot, seat)
            val lines = ArrayList<String>()
            var start = 0
            var actualWidth = 36f
            while (start < text.length) {
                var count =
                    textPaint
                        .breakText(text, start, text.length, true, maxWidth - 10, null)
                        .coerceAtLeast(1)
                if (
                    start + count < text.length &&
                        Character.isHighSurrogate(text[start + count - 1]) &&
                        Character.isLowSurrogate(text[start + count])
                )
                    count = if (count > 1) count - 1 else 2
                val line = text.substring(start, start + count)
                lines += line
                actualWidth = max(actualWidth, textPaint.measureText(line) + 10)
                start += count
            }
            label =
                Label(
                    tank.name,
                    seat,
                    tank.bot,
                    maxWidth,
                    textPaint.textSize,
                    actualWidth,
                    lines.size * (textPaint.textSize + 3) + 4,
                    lines,
                )
            labels[tank.id] = label
        }
        val warningHeight = if (tank.isGodlikeBot) textPaint.textSize + 10 else 0f
        val warningWidth =
            if (tank.isGodlikeBot) {
                textPaint.typeface = boldTypeface
                val measured = textPaint.measureText("GODLIKE") + 12
                textPaint.typeface = if (seat > 0) boldTypeface else Typeface.MONOSPACE
                measured
            } else 0f
        val identityWidth = max(label.width, warningWidth)
        val x =
            (viewport.centerX() + ((tank.x - cameraX) * zoom).toFloat()).coerceIn(
                max(viewport.left, safe.left) + identityWidth / 2 + 6,
                max(
                    max(viewport.left, safe.left) + identityWidth / 2 + 6,
                    min(viewport.right, width / density - safe.right) - identityWidth / 2 - 6,
                ),
            )
        val y =
            (viewport.centerY() + ((tank.y - cameraY) * zoom).toFloat() - max(30f, 36f * zoom))
                .coerceIn(
                    viewport.top + label.height + warningHeight + 6,
                    max(viewport.top + label.height + warningHeight + 6, viewport.bottom - 6),
                )
        if (tank.isGodlikeBot) {
            textPaint.typeface = boldTypeface
            val top = y - label.height - warningHeight
            fill(0xff302217.toInt())
            canvas.drawRoundRect(
                x - warningWidth / 2,
                top,
                x + warningWidth / 2,
                y - label.height - 3,
                3f,
                3f,
                paint,
            )
            textPaint.color = 0xffffc46b.toInt()
            canvas.drawText("GODLIKE", x, top + textPaint.textSize + 2, textPaint)
            textPaint.typeface = if (seat > 0) boldTypeface else Typeface.MONOSPACE
        }
        fill(0xdb0e171d.toInt())
        canvas.drawRoundRect(
            x - label.width / 2,
            y - label.height,
            x + label.width / 2,
            y,
            3f,
            3f,
            paint,
        )
        textPaint.color = ArenaPalette.tank(tank.colorIndex)
        for ((index, line) in label.lines.withIndex()) canvas.drawText(
            line,
            x,
            y - label.height + 2 + textPaint.textSize + index * (textPaint.textSize + 3),
            textPaint,
        )
    }

    private fun drawBullets(canvas: Canvas, state: ArenaSnapshot) {
        projectileFrame++
        rapidBatches.forEach { it.count = 0 }
        trails.forEach(Path::rewind)
        for (bullet in state.bullets) {
            if (!isVisible(bullet.x, bullet.y, if (bullet.kind == "rapid") 45.0 else 128.0))
                continue
            val color = Math.floorMod(bullet.colorIndex, 8)
            if (bullet.kind == "rapid") rapidBatches[color].add(bullet, originX, originY)
            else {
                var history = projectileHistory[bullet.id]
                if (history == null || history.kind != bullet.kind || history.color != color) {
                    history = ProjectileHistory(bullet.kind, color)
                    projectileHistory.put(bullet.id, history)
                }
                history.update(bullet, frameTime, projectileFrame)
                val trail =
                    trails[
                        color * 3 +
                            when (bullet.kind) {
                                "cannon" -> 2
                                "homing" -> 1
                                else -> 0
                            }]
                for (index in 0 until history.count) {
                    val slot = (history.start + index) % 7
                    val x = rx(history.points[slot * 2])
                    val y = ry(history.points[slot * 2 + 1])
                    if (index == 0) trail.moveTo(x, y) else trail.lineTo(x, y)
                }
                trail.lineTo(rx(bullet.x), ry(bullet.y))
            }
        }
        var removed = 0
        val size = projectileHistory.size()
        if (removals.size < size) removals = IntArray(max(size, removals.size * 2))
        for (index in 0 until size) if (projectileHistory.valueAt(index).seen != projectileFrame)
            removals[removed++] = projectileHistory.keyAt(index)
        repeat(removed) { projectileHistory.delete(removals[it]) }
        paint.strokeCap = Paint.Cap.ROUND
        for (index in trails.indices) if (!trails[index].isEmpty) {
            stroke(
                ArenaPalette.alpha(ArenaPalette.tank(index / 3), .16f),
                when (index % 3) {
                    2 -> 12f
                    1 -> 4f
                    else -> 3f
                },
            )
            canvas.drawPath(trails[index], paint)
        }
        for (color in rapidBatches.indices) {
            val batch = rapidBatches[color]
            if (batch.count == 0) continue
            stroke(ArenaPalette.alpha(ArenaPalette.tank(color), .55f), 7f / 3)
            paint.strokeCap = Paint.Cap.BUTT
            canvas.drawLines(batch.tails, 0, batch.count * 4, paint)
            stroke(ArenaPalette.tank(color), 7f / 3)
            paint.strokeCap = Paint.Cap.ROUND
            canvas.drawPoints(batch.heads, 0, batch.count * 2, paint)
        }
        paint.strokeCap = Paint.Cap.BUTT
        for (bullet in state.bullets) if (
            bullet.kind != "rapid" && isVisible(bullet.x, bullet.y, 128.0)
        )
            drawBullet(canvas, bullet)
    }

    private fun drawBullet(canvas: Canvas, bullet: ArenaBullet) {
        val color = ArenaPalette.tank(bullet.colorIndex)
        canvas.save()
        canvas.translate(rx(bullet.x), ry(bullet.y))
        canvas.rotate(projectileHistory[bullet.id]?.angle ?: 0f)
        when (bullet.kind) {
            "homing" -> {
                fill(ArenaPalette.alpha(ArenaPalette.power("homing"), .8f))
                path.rewind()
                path.moveTo(-7f, -3f)
                path.lineTo(-7f - (9 + sin(frameTime * 30) * 4).toFloat(), 0f)
                path.lineTo(-7f, 3f)
                path.close()
                canvas.drawPath(path, paint)
                fill(color)
                path.rewind()
                path.moveTo(10f, 0f)
                path.lineTo(-4f, 5f)
                path.lineTo(-8f, 8f)
                path.lineTo(-6f, 0f)
                path.lineTo(-8f, -8f)
                path.lineTo(-4f, -5f)
                path.close()
                canvas.drawPath(path, paint)
                fill(0xfffff6e5.toInt())
                canvas.drawRect(-1f, -1.5f, 5f, 1.5f, paint)
            }
            "grenade" -> {
                fill(0xff253039.toInt())
                canvas.drawCircle(0f, 0f, 6f, paint)
                stroke(color, 2f)
                canvas.drawCircle(0f, 0f, 6f, paint)
                fill(ArenaPalette.power("grenade"))
                canvas.drawCircle(0f, 2f, 2f, paint)
                stroke(ArenaPalette.power("grenade"), 1.4f)
                canvas.drawPath(
                    art.grenadeFuse((bullet.life / 10 * 256).roundToInt().coerceIn(0, 256)),
                    paint,
                )
            }
            "rapid" -> {
                fill(ArenaPalette.alpha(color, .55f))
                canvas.drawRect(-8f, -1.17f, 0f, 1.17f, paint)
                fill(color)
                canvas.drawCircle(0f, 0f, 1.17f, paint)
            }
            else -> {
                val radius = if (bullet.kind == "cannon") 18f else 4.5f
                fill(color)
                canvas.drawCircle(0f, 0f, radius, paint)
                fill(0xfffbffe8.toInt())
                canvas.drawCircle(0f, 0f, if (bullet.kind == "cannon") 8.4f else 2.1f, paint)
            }
        }
        canvas.restore()
    }

    private fun drawGuide(canvas: Canvas, state: ArenaSnapshot) {
        val tank = state.tanks.firstOrNull { it.id == localID && it.hp > 0 } ?: return
        val maze = geometry ?: return
        if (infinity && tank.power != "laser") return
        var signature = tank.x.toBits()
        fun mix(value: Long) {
            signature = (signature xor value) * 1099511628211L
        }
        mix(tank.y.toBits())
        mix(tank.angle.toBits())
        mix(tank.power.hashCode().toLong())
        mix(originX.toBits())
        mix(originY.toBits())
        mix(maze.seed.toLong())
        mix(state.generation.toLong())
        if (!infinity) {
            mix(if (state.rules?.friendlyFire == true) 1 else 0)
            mix(tank.team.toLong())
            for (other in state.tanks) {
                mix(other.id.toLong())
                mix(other.x.toBits())
                mix(other.y.toBits())
                mix(other.hp.toLong())
                mix(if (other.invulnerable > 0) 1 else 0)
                mix(other.team.toLong())
            }
        }
        if (!guideReady || guideSignature != signature) {
            guideReady = true
            guideSignature = signature
            val points =
                if (tank.power == "laser")
                    maze.laserGuide(
                        tank.x,
                        tank.y,
                        tank.angle,
                        if (infinity) 18 * 84.0
                        else 2 * ((state.world?.width ?: 756.0) + (state.world?.height ?: 588.0)),
                    )
                else
                    maze.projectileGuide(
                        tank.x,
                        tank.y,
                        tank.angle,
                        tank.power,
                        112.0,
                        when (tank.power) {
                            "cannon" -> 14.0
                            "grenade" -> 6.0
                            "homing" -> 5.0
                            "rapid" -> 3.5 / 3
                            else -> 3.5
                        },
                        if (tank.power == "cannon") 32 else 2,
                    )
            if (points.size < 2) {
                guidePath.rewind()
                return
            }
            guidePath.rewind()
            guidePath.moveTo(rx(points[0].x), ry(points[0].y))
            val radius =
                when (tank.power) {
                    "laser" -> 3.0
                    "cannon" -> 14.0
                    "grenade" -> 6.0
                    "homing" -> 5.0
                    "rapid" -> 3.5 / 3
                    else -> 3.5
                }
            for (index in 1 until points.size) {
                val first = points[index - 1]
                val last = points[index]
                val dx = last.x - first.x
                val dy = last.y - first.y
                val length = dx * dx + dy * dy
                var nearest = 1.0
                if (!infinity && length > 0)
                    for (other in state.tanks) {
                        if (
                            other.id == tank.id ||
                                other.hp <= 0 ||
                                other.invulnerable > 0 ||
                                state.rules?.friendlyFire != true &&
                                    tank.team != 0 &&
                                    other.team == tank.team
                        )
                            continue
                        val px = first.x - other.x
                        val py = first.y - other.y
                        val dot = px * dx + py * dy
                        val c = px * px + py * py - (17 + radius) * (17 + radius)
                        val discriminant = dot * dot - length * c
                        if (c <= 0) nearest = 0.0
                        else if (dot < 0 && discriminant >= 0) {
                            val at = (-dot - sqrt(discriminant)) / length
                            if (at >= 0 && at < nearest) nearest = at
                        }
                    }
                guidePath.lineTo(rx(first.x + dx * nearest), ry(first.y + dy * nearest))
                if (nearest < 1) break
            }
        }
        stroke(
            ArenaPalette.alpha(
                if (tank.power == "laser" && infinity) ArenaPalette.power("laser")
                else ArenaPalette.tank(tank.colorIndex),
                if (tank.power == "laser") .48f else .28f,
            ),
            1.3f,
        )
        paint.pathEffect = dash
        canvas.drawPath(guidePath, paint)
        paint.pathEffect = null
    }

    private fun drawMissileWarnings(canvas: Canvas, state: ArenaSnapshot) {
        val tank = state.tanks.firstOrNull { it.id == localID && it.hp > 0 } ?: return
        if (state.phase != "playing" || state.result != null) return
        var count = 0
        for (bullet in state.bullets) {
            if (
                (bullet.kind != "homing" && bullet.kind != "grenade") ||
                    bullet.target != tank.id ||
                    bullet.owner == tank.id
            )
                continue
            if (count++ >= 3) break
            canvas.save()
            canvas.translate(rx(tank.x), ry(tank.y))
            canvas.rotate((atan2(bullet.y - tank.y, bullet.x - tank.x) * 180 / PI).toFloat())
            path.rewind()
            path.moveTo(41f, -6f)
            path.lineTo(35f, 0f)
            path.lineTo(41f, 6f)
            stroke(ArenaPalette.power(bullet.kind), 2.5f)
            canvas.drawPath(path, paint)
            canvas.restore()
        }
    }

    private fun drawEffects(canvas: Canvas) {
        var index = 0
        while (index < effects.size) {
            val visual = effects[index]
            val effect = visual.effect
            val duration = if (effect.kind == "laser") if (infinity) .18 else .23 else .43
            val age = ((frameTime - visual.began) / duration).coerceAtLeast(0.0)
            if (age >= 1) {
                effects.removeAt(index)
                continue
            }
            index++
            if (effect.kind == "laser" && visual.shape != null) {
                canvas.save()
                canvas.translate(rx(effect.points[0].x), ry(effect.points[0].y))
                stroke(
                    ArenaPalette.alpha(
                        ArenaPalette.power("laser"),
                        ((1 - age) * if (infinity) .45 else .2).toFloat(),
                    ),
                    if (infinity) 7f else 14f,
                )
                canvas.drawPath(visual.shape, paint)
                if (!infinity) {
                    stroke(ArenaPalette.alpha(ArenaPalette.power("laser"), (1 - age).toFloat()), 6f)
                    canvas.drawPath(visual.shape, paint)
                }
                stroke(ArenaPalette.alpha(0xfffff2ff.toInt(), (1 - age).toFloat()), 2f)
                canvas.drawPath(visual.shape, paint)
                canvas.restore()
            } else {
                val color =
                    when (effect.kind) {
                        "hit" -> 0xfff7ecbb.toInt()
                        "blast" -> ArenaPalette.power("grenade")
                        else -> ArenaPalette.power(effect.kind)
                    }
                if (effect.kind == "blast" && visual.shape != null) {
                    canvas.save()
                    canvas.translate(rx(effect.x), ry(effect.y))
                    val size = (.65 + .35 * age).toFloat()
                    canvas.scale(size, size)
                    fill(ArenaPalette.alpha(color, (.088 * (1 - age)).toFloat()))
                    canvas.drawPath(visual.shape, paint)
                    stroke(ArenaPalette.alpha(color, (.8 * (1 - age)).toFloat()), 3f)
                    canvas.drawPath(visual.shape, paint)
                    canvas.restore()
                } else {
                    val radius =
                        (14 +
                                (if (effect.kind == "blast") 206
                                else if (effect.kind == "hit") 56 else 35) * age)
                            .toFloat()
                    stroke(
                        ArenaPalette.alpha(color, (.8 * (1 - age)).toFloat()),
                        if (effect.kind == "blast") 3f else 2f,
                    )
                    canvas.drawCircle(rx(effect.x), ry(effect.y), radius, paint)
                }
            }
        }
    }

    private fun drawObjectives(canvas: Canvas, state: ArenaSnapshot) {
        val objectives = state.objectives ?: return
        if (objectives.suddenDeath) return
        fun teamColor(team: Int): Int =
            ArenaPalette.tank(
                state.tanks.lastOrNull { it.team == team }?.colorIndex ?: max(0, team - 1),
            )
        if (objectives.mode == "koth" || objectives.mode == "king") {
            val ink =
                if (objectives.contested) 0xffffcb66.toInt()
                else if (objectives.owner > 0) teamColor(objectives.owner)
                else if (objectives.owner < 0)
                    ArenaPalette.tank(
                        state.tanks.firstOrNull { it.id == -objectives.owner - 1 }?.colorIndex ?: 0,
                    )
                else 0xffe7eadd.toInt()
            fill(ArenaPalette.alpha(ink, .08f))
            canvas.drawCircle(
                rx(objectives.hillX),
                ry(objectives.hillY),
                objectives.radius.toFloat(),
                paint,
            )
            stroke(ArenaPalette.alpha(ink, .7f), 2f)
            canvas.drawCircle(
                rx(objectives.hillX),
                ry(objectives.hillY),
                objectives.radius.toFloat(),
                paint,
            )
        }
        for (flag in objectives.flags) {
            val color = teamColor(flag.team)
            stroke(ArenaPalette.alpha(color, .3f), 2f)
            canvas.drawCircle(rx(flag.homeX), ry(flag.homeY), 28f, paint)
            canvas.save()
            canvas.translate(rx(flag.x), ry(flag.y))
            fill(0xee101a24.toInt())
            canvas.drawRoundRect(-21f, -23f, 21f, 20f, 8f, 8f, paint)
            stroke(color, 1.7f)
            canvas.drawRoundRect(-21f, -23f, 21f, 20f, 8f, 8f, paint)
            stroke(0xfffffef2.toInt(), 2.5f)
            canvas.drawLine(-9f, 13f, -9f, -17f, paint)
            fill(color)
            path.rewind()
            path.moveTo(-7f, -17f)
            path.lineTo(15f, -13f)
            path.lineTo(10f, -6f)
            path.lineTo(-7f, -9f)
            path.close()
            canvas.drawPath(path, paint)
            canvas.restore()
        }
    }

    private fun drawEncounterNotice(canvas: Canvas) {
        val message = encounterNotice ?: return
        textPaint.typeface = boldTypeface
        textPaint.textSize = 12f * textScale
        val maxWidth = min(460f, max(40f, viewport.width() - 40))
        if (
            noticeLayoutText != message ||
                noticeLayoutWidth != maxWidth ||
                noticeLayoutSize != textPaint.textSize
        ) {
            val lines = ArrayList<String>()
            var start = 0
            while (start < message.length) {
                val count =
                    textPaint
                        .breakText(message, start, message.length, true, maxWidth - 20, null)
                        .coerceAtLeast(1)
                lines.add(message.substring(start, start + count))
                start += count
            }
            noticeLines = lines
            noticeLayoutText = message
            noticeLayoutWidth = maxWidth
            noticeLayoutSize = textPaint.textSize
        }
        val lineHeight = textPaint.textSize + 4
        val top = viewport.top + 10
        val center = viewport.centerX()
        fill(0xee302217.toInt())
        canvas.drawRoundRect(
            center - maxWidth / 2,
            top,
            center + maxWidth / 2,
            top + noticeLines.size * lineHeight + 12,
            6f,
            6f,
            paint,
        )
        textPaint.color = 0xffffc46b.toInt()
        noticeLines.forEachIndexed { index, line ->
            canvas.drawText(
                line,
                center,
                top + textPaint.textSize + 4 + index * lineHeight,
                textPaint,
            )
        }
    }

    private fun drawPhase(canvas: Canvas, state: ArenaSnapshot) {
        val text =
            when (state.phase) {
                "countdown" -> ceil(state.phaseTime).toInt().coerceAtLeast(1).toString()
                "roundOver" -> if (state.winner < 0) "DRAW" else "ROUND COMPLETE"
                else -> ""
            }
        if (text.isEmpty()) return
        textPaint.textSize = 28f * textScale
        textPaint.typeface = boldTypeface
        textPaint.color = 0xffe5edf2.toInt()
        val w = textPaint.measureText(text) + 32
        fill(0xe610181e.toInt())
        canvas.drawRoundRect(
            viewport.centerX() - w / 2,
            viewport.centerY() - 28,
            viewport.centerX() + w / 2,
            viewport.centerY() + 20,
            8f,
            8f,
            paint,
        )
        canvas.drawText(text, viewport.centerX(), viewport.centerY() + 8, textPaint)
    }

    private fun drawControls(canvas: Canvas, width: Float, height: Float, state: ArenaSnapshot?) {
        val fixedPortrait = !infinity && width < height
        if (fixedPortrait) {
            fill(0xff192127.toInt())
            canvas.drawRect(0f, height - safe.bottom - 119f, width, height, paint)
            stroke(0xff34434a.toInt(), 1f)
            canvas.drawLine(
                0f,
                height - safe.bottom - 119,
                width,
                height - safe.bottom - 119,
                paint,
            )
        }
        paint.alpha = 255
        paint.style = Paint.Style.FILL
        destination.set(stickX - 48, stickY - 48, stickX + 48, stickY + 48)
        canvas.drawBitmap(art.stickBase(), null, destination, paint)
        stroke(0xff506d80.toInt(), 1.5f)
        canvas.drawCircle(stickX, stickY, 48f, paint)
        paint.style = Paint.Style.FILL
        destination.set(
            stickX + knobX - 22,
            stickY + knobY - 22,
            stickX + knobX + 22,
            stickY + knobY + 22,
        )
        canvas.drawBitmap(art.stickKnob(), null, destination, paint)
        stroke(0xff506d80.toInt(), 1.5f)
        canvas.drawCircle(stickX + knobX, stickY + knobY, 22f, paint)
        val detonate = fireLabel == "BOOM"
        val color = if (detonate) 0xffffc46b.toInt() else 0xff40d5ff.toInt()
        paint.style = Paint.Style.FILL
        paint.alpha = 255
        destination.set(fireX - 45.5f, fireY - 45.5f, fireX + 45.5f, fireY + 45.5f)
        canvas.drawBitmap(art.fireButton(fireHeld, detonate), null, destination, paint)
        stroke(ArenaPalette.alpha(color, .63f), 2f)
        canvas.drawCircle(fireX, fireY, 45.5f, paint)
        stroke(0x3040d5ff, 2.5f)
        canvas.drawCircle(fireX, fireY, 53.5f, paint)
        stroke(color, 2.5f)
        canvas.drawArc(
            fireX - 53.5f,
            fireY - 53.5f,
            fireX + 53.5f,
            fireY + 53.5f,
            -90f,
            fireProgress.toFloat() * 360,
            false,
            paint,
        )
        stroke(0xff32c5ff.toInt(), 1.575f)
        val cy = fireY - 6
        canvas.drawCircle(fireX, cy, 7f, paint)
        canvas.drawLine(fireX - 11.375f, cy, fireX - 5.25f, cy, paint)
        canvas.drawLine(fireX + 5.25f, cy, fireX + 11.375f, cy, paint)
        canvas.drawLine(fireX, cy - 11.375f, fireX, cy - 5.25f, paint)
        canvas.drawLine(fireX, cy + 5.25f, fireX, cy + 11.375f, paint)
        fill(0xff32c5ff.toInt())
        canvas.drawCircle(fireX, cy, 1.75f, paint)
        textPaint.typeface = Typeface.MONOSPACE
        textPaint.textSize = 10f * textScale
        textPaint.color = 0xff9babbb.toInt()
        canvas.drawText("STEER", stickX, height - safe.bottom - 8, textPaint)
        textPaint.color = color
        canvas.drawText(fireLabel, fireX, fireY + 18, textPaint)
        if (fixedPortrait) {
            textPaint.color = 0xff9babbb.toInt()
            canvas.drawText("LET IT RIP", fireX, height - safe.bottom - 8, textPaint)
            val maximum = max(40f, width - 260)
            var start = 0
            var line = 0
            while (start < fireHint.length) {
                var count =
                    textPaint
                        .breakText(fireHint, start, fireHint.length, true, maximum, null)
                        .coerceAtLeast(1)
                if (start + count < fireHint.length) {
                    val space = fireHint.lastIndexOf(' ', start + count - 1)
                    if (space > start) count = space - start
                }
                canvas.drawText(
                    fireHint,
                    start,
                    start + count,
                    width / 2,
                    height - safe.bottom - 59 + line * (textPaint.textSize + 2),
                    textPaint,
                )
                start += count
                while (start < fireHint.length && fireHint[start] == ' ') start++
                line++
            }
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!showControls) {
            if (event.actionMasked == MotionEvent.ACTION_CANCEL) resetControls()
            return false
        }
        val action = event.actionMasked
        val index = event.actionIndex
        val pointer = event.getPointerId(index)
        fun update(index: Int) {
            val dx = event.getX(index) / density - stickX
            val dy = event.getY(index) / density - stickY
            val divisor = max(29f, hypot(dx, dy))
            knobX = dx * 29 / divisor
            knobY = dy * 29 / divisor
            input.stickX = (dx / divisor).toDouble()
            input.stickY = (dy / divisor).toDouble()
            input.touchAim = true
            input.aimOnly = false
        }
        when (action) {
            MotionEvent.ACTION_DOWN,
            MotionEvent.ACTION_POINTER_DOWN -> {
                parent?.requestDisallowInterceptTouchEvent(true)
                requestFocus()
                val x = event.getX(index) / density
                val y = event.getY(index) / density
                if (
                    x < width / density / 2 &&
                        stickPointer < 0 &&
                        y > max(safe.top + hudHeightDp, height / density * .25f)
                ) {
                    stickPointer = pointer
                    update(index)
                } else if (
                    x >= width / density / 2 &&
                        firePointer < 0 &&
                        y > height / density - max(210f, height / density * .38f)
                ) {
                    firePointer = pointer
                    input.fire = true
                    fireHeld = true
                }
            }
            MotionEvent.ACTION_MOVE -> {
                val stick = event.findPointerIndex(stickPointer)
                if (stick >= 0) update(stick)
            }
            MotionEvent.ACTION_UP,
            MotionEvent.ACTION_POINTER_UP -> {
                if (pointer == stickPointer) {
                    stickPointer = -1
                    knobX = 0f
                    knobY = 0f
                    input.stickX = 0.0
                    input.stickY = 0.0
                }
                if (pointer == firePointer) {
                    firePointer = -1
                    input.fire = false
                    fireHeld = false
                }
                if (action == MotionEvent.ACTION_UP) performClick()
            }
            MotionEvent.ACTION_CANCEL -> {
                resetControls()
                return true
            }
        }
        onInput?.invoke(input.copy())
        invalidate()
        return true
    }

    override fun performClick(): Boolean {
        super.performClick()
        return true
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean =
        key(keyCode, true) || super.onKeyDown(keyCode, event)

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean =
        key(keyCode, false) || super.onKeyUp(keyCode, event)

    private fun key(code: Int, down: Boolean): Boolean {
        when (code) {
            KeyEvent.KEYCODE_W,
            KeyEvent.KEYCODE_DPAD_UP -> input.forward = down
            KeyEvent.KEYCODE_S,
            KeyEvent.KEYCODE_DPAD_DOWN -> input.reverse = down
            KeyEvent.KEYCODE_A,
            KeyEvent.KEYCODE_DPAD_LEFT -> input.left = down
            KeyEvent.KEYCODE_D,
            KeyEvent.KEYCODE_DPAD_RIGHT -> input.right = down
            KeyEvent.KEYCODE_SPACE,
            KeyEvent.KEYCODE_BUTTON_A,
            KeyEvent.KEYCODE_BUTTON_R1 -> {
                input.fire = down
                fireHeld = down
            }
            else -> return false
        }
        input.touchAim = false
        onInput?.invoke(input.copy())
        return true
    }

    override fun onGenericMotionEvent(event: MotionEvent): Boolean {
        if (
            event.source and InputDevice.SOURCE_JOYSTICK != 0 &&
                event.action == MotionEvent.ACTION_MOVE
        ) {
            val x = event.getAxisValue(MotionEvent.AXIS_X)
            val y = event.getAxisValue(MotionEvent.AXIS_Y)
            input.stickX = if (abs(x) < .15) 0.0 else x.toDouble()
            input.stickY = if (abs(y) < .15) 0.0 else y.toDouble()
            input.touchAim = true
            onInput?.invoke(input.copy())
            return true
        }
        return super.onGenericMotionEvent(event)
    }
}
