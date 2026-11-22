package com.leqra.android

import android.content.Context
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.view.View
import com.leqra.core.ArenaSnapshot
import com.leqra.core.PilotReadout
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/** The iOS loadout hierarchy, drawn without rebuilding a text hierarchy on every game frame. */
internal class NativeHudView(context: Context) : View(context) {
    var onHeightChanged: ((Float) -> Unit)? = null
    var compact = false
        set(value) {
            if (field == value) return
            field = value
            requestLayout()
            invalidate()
        }

    var stacked = false
        set(value) {
            if (field == value) return
            field = value
            requestLayout()
            invalidate()
        }

    var safeLeft = 0
    var safeRight = 0
    var safeBottom = 0
    private var density = resources.displayMetrics.density
    private var fontScale = resources.configuration.fontScale.coerceAtLeast(1f)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val slots = ArrayList<Slot>(2)
    private var frameNanos = 0L
    private var description = ""
    private var primarySlot: Slot? = null
    private var compactSecondY = 0f
    var fireLabel = "FIRE"
        private set

    var fireAvailable = false
        private set

    private val spectator = TextBlock(10f, false)
    private val measurePaint =
        TextPaint(Paint.ANTI_ALIAS_FLAG).apply { typeface = Typeface.MONOSPACE }

    private fun textHeight(value: String, width: Float, size: Float = 10f): Float {
        measurePaint.textSize = size * fontScale
        return StaticLayout.Builder.obtain(
                value,
                0,
                value.length,
                measurePaint,
                max(1, width.toInt()),
            )
            .setIncludePad(false)
            .build()
            .height
            .toFloat()
    }

    var contentUpdates = 0L
        private set

    private inner class TextBlock(private val size: Float, bold: Boolean) {
        val ink =
            TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                typeface =
                    Typeface.create(
                        Typeface.MONOSPACE,
                        if (bold) Typeface.BOLD else Typeface.NORMAL,
                    )
            }
        private var text = ""
        private var width = 0
        private var scale = 0f
        private var layout: StaticLayout? = null

        fun measure(value: String, available: Float): Float {
            val wantedWidth = max(1, available.toInt())
            if (layout == null || text != value || width != wantedWidth || scale != fontScale) {
                text = value
                width = wantedWidth
                scale = fontScale
                ink.textSize = size * fontScale
                layout =
                    StaticLayout.Builder.obtain(value, 0, value.length, ink, width)
                        .setAlignment(Layout.Alignment.ALIGN_NORMAL)
                        .setIncludePad(false)
                        .build()
            }
            return layout?.height?.toFloat() ?: 0f
        }

        fun draw(
            canvas: Canvas,
            value: String,
            x: Float,
            y: Float,
            width: Float,
            color: Int,
        ): Float {
            val height = measure(value, width)
            ink.color = color
            canvas.save()
            canvas.translate(x, y)
            layout?.draw(canvas)
            canvas.restore()
            return height
        }
    }

    private data class Content(
        val identity: String,
        val color: Int,
        val weapon: String,
        val buffs: String,
        val readiness: String,
        val available: Int,
        val capacity: Int,
        val unlimited: Boolean,
        val firingSeconds: Double?,
        val locked: Boolean,
    )

    private inner class Slot {
        var content: Content? = null
        var progress = 1.0
        var animateCooldown = false
        var cooldownTotal = .34
        var sampledNanos = 0L
        val identity = TextBlock(11f, true)
        val weapon = TextBlock(10f, false)
        val buffs = TextBlock(10f, false)
        val readiness = TextBlock(10f, false)
        val ammunition = TextBlock(10f, false)
        val lock = TextBlock(10f, true)

        fun progressAt(nanos: Long): Double =
            if (animateCooldown)
                (progress + max(0.0, (nanos - sampledNanos) / 1e9) / cooldownTotal).coerceIn(
                    0.0,
                    1.0,
                )
            else progress
    }

    init {
        setBackgroundColor(NativeStyle.surface)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        isFocusable = false
        isClickable = false
    }

    fun update(
        snapshot: ArenaSnapshot,
        localID: Int,
        localID2: Int?,
        infinity: Boolean,
        paused: Boolean,
        online: Boolean,
        frozen: Boolean = false,
        onlySeat: Int? = null,
    ) {
        val first = if (onlySeat == 1) null else snapshot.tanks.firstOrNull { it.id == localID }
        val second =
            if (onlySeat == 0) null
            else localID2?.let { id -> snapshot.tanks.firstOrNull { it.id == id } }
        val count = (if (first != null) 1 else 0) + (if (second != null) 1 else 0)
        val previousCount = slots.size
        while (slots.size < count) slots.add(Slot())
        while (slots.size > count) slots.removeAt(slots.lastIndex)
        var changed = previousCount != count
        var namesChanged = false
        var layoutMayGrow = false
        var index = 0
        primarySlot = null
        fireAvailable = false
        val now = System.nanoTime()
        for (seat in 0..1) {
            val tank = if (seat == 0) first else second
            if (tank == null) continue
            val slot = slots[index++]
            val readout = PilotReadout(tank, snapshot, infinity, paused, online)
            if (seat == 0) {
                primarySlot = slot
                fireLabel = readout.fireLabel
                fireAvailable = tank.hp > 0 && readout.progress > 0
            }
            val content =
                Content(
                    "${tank.name} (P${seat + 1})",
                    NativeStyle.paint(tank.colorIndex),
                    readout.weapon,
                    readout.buffs,
                    readout.readiness,
                    readout.available,
                    readout.capacity,
                    readout.unlimited,
                    readout.firingSeconds,
                    readout.locked,
                )
            if (content != slot.content) {
                if (content.identity != slot.content?.identity) namesChanged = true
                val old = slot.content
                // Readiness and lock messages have a reserved envelope; only new equipment
                // can require more height, so firing does not trigger a layout every shot.
                if (
                    old == null ||
                        content.weapon.length > old.weapon.length ||
                        content.buffs.length > old.buffs.length ||
                        (content.firingSeconds != null) != (old.firingSeconds != null) ||
                        content.unlimited != old.unlimited
                )
                    layoutMayGrow = true
                slot.content = content
                changed = true
            }
            slot.progress = readout.progress
            slot.animateCooldown = !frozen && !paused && readout.readiness.startsWith("COOLDOWN ")
            slot.cooldownTotal =
                tank.cooldownTotal.takeIf { it > 0 }
                    ?: when (tank.power) {
                        "cannon" -> .85 / 3
                        "laser" -> .85 / 3
                        "scatter" -> .27
                        "homing" -> .36
                        "grenade" -> .8
                        else -> .34
                    }
            slot.sampledNanos = now
        }
        if (previousCount != count || namesChanged || layoutMayGrow) requestLayout()
        if (changed) {
            contentUpdates++
            val nextDescription =
                if (slots.isEmpty()) "Spectating"
                else
                    slots.joinToString(". ") { slot ->
                        slot.content!!.let {
                            "${it.identity}, ${it.weapon}, ${it.buffs}, ${it.readiness}, ${it.available} of ${it.capacity} ammunition slots"
                        }
                    }
            if (nextDescription != description) {
                description = nextDescription
                contentDescription = nextDescription
            }
        }
        // Progress changes are independent of text, so cooldowns stay smooth without text layout
        // work.
        invalidate()
    }

    fun advance(nanos: Long): Double {
        frameNanos = nanos
        if (slots.any { it.animateCooldown && it.progressAt(nanos) < 1.0 }) invalidate()
        return primarySlot?.progressAt(nanos) ?: 0.0
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        density = resources.displayMetrics.density
        fontScale = newConfig.fontScale.coerceAtLeast(1f)
        requestLayout()
        invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val columns = if (stacked) 1 else max(1, slots.size)
        var height =
            (if (compact) if (columns > 1) 84f else 54f else if (columns > 1) 136f else 97f) *
                fontScale
        val usable = (width - safeLeft - safeRight) / density - 26f
        val cellWidth = (usable - if (columns > 1) 16f else 0f) / columns
        var compactTop = 0f
        var compactBottom = 0f
        for (slot in slots) {
            val identity = slot.content?.identity ?: ""
            if (compact) {
                val identityWidth = min(190f, cellWidth * .28f)
                val identityHeight =
                    textHeight(identity, identityWidth, 11f) +
                        3f +
                        textHeight("⚠ HOMING LOCK", identityWidth)
                val detailsWidth = cellWidth - identityWidth - 12f
                val ammoWidth = min(112f, detailsWidth * .48f)
                val top =
                    max(
                        textHeight("FIRE LEFT 3.0 / 3s", ammoWidth) + 6f,
                        textHeight(
                            "MACHINE GUN, EXPIRES 10s",
                            max(1f, detailsWidth - ammoWidth - 10f),
                        ),
                    )
                val textWidth = max(1f, detailsWidth - min(100f, detailsWidth * .2f) - 8f)
                val readinessWidth = min(150f * fontScale, textWidth * .58f)
                var bottom =
                    max(
                        textHeight("SPAWN PROTECTION", readinessWidth),
                        textHeight(
                            "SHD×5 SPD×512 STAR12",
                            max(1f, textWidth - readinessWidth - 12f),
                        ),
                    )
                slot.content?.let { content ->
                    val readyWidth = compactReadinessWidth(textWidth, content)
                    val buffsWidth =
                        if (content.buffs.isEmpty()) 0f else max(1f, textWidth - readyWidth - 12f)
                    bottom = max(bottom, textHeight(content.readiness, readyWidth))
                    if (content.buffs.isNotEmpty())
                        bottom = max(bottom, textHeight(content.buffs, buffsWidth))
                }
                compactTop = max(compactTop, top)
                compactBottom = max(compactBottom, bottom)
                height = max(height, identityHeight + 12f)
            } else {
                val ammoWidth = min(112f, cellWidth * .4f)
                val equipmentWidth = max(1f, cellWidth - ammoWidth - 10f)
                val identityHeight =
                    textHeight(identity, cellWidth, 11f) +
                        3f +
                        textHeight("⚠ HOMING LOCK", cellWidth)
                var equipment =
                    max(
                        textHeight("FIRE LEFT 3.0 / 3s", ammoWidth) + 6f,
                        textHeight("MACHINE GUN, EXPIRES 10s", equipmentWidth) +
                            3f +
                            textHeight("SHD×5 SPD×512 STAR12", equipmentWidth),
                    )
                slot.content?.let { content ->
                    equipment =
                        max(
                            equipment,
                            textHeight(content.weapon, equipmentWidth) +
                                3f +
                                textHeight(content.buffs, equipmentWidth),
                        )
                }
                val readinessWidth = min(150f * fontScale, cellWidth * .55f)
                val readinessHeight =
                    max(
                        textHeight("SPAWN PROTECTION", readinessWidth),
                        textHeight(slot.content?.readiness.orEmpty(), readinessWidth),
                    )
                height =
                    max(
                        height,
                        8f + identityHeight + 5f + equipment + 5f + readinessHeight + 8f,
                    )
            }
        }
        if (compact) {
            compactSecondY = 6f + compactTop + 6f
            height = max(height, compactSecondY + compactBottom + 6f)
        }
        if (stacked) height *= max(1, slots.size)
        setMeasuredDimension(
            width,
            resolveSize(ceil(height * density + safeBottom).toInt(), heightMeasureSpec),
        )
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (h != oldh) onHeightChanged?.invoke(h / density)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.save()
        canvas.scale(density, density)
        val width = width / density
        val height = (height - safeBottom) / density
        paint.color = 0xff34434a.toInt()
        canvas.drawRect(0f, 0f, width, 1f, paint)
        val left = safeLeft / density + 13f
        val right = width - safeRight / density - 13f
        if (slots.isEmpty())
            spectator.draw(canvas, "SPECTATING", left, 8f, right - left, NativeStyle.soft)
        else {
            val gap = if (!stacked && slots.size > 1) 16f else 0f
            val cellWidth =
                if (stacked) right - left else (right - left - gap * (slots.size - 1)) / slots.size
            val cellHeight = if (stacked) height / slots.size else height
            slots.forEachIndexed { index, slot ->
                canvas.save()
                if (stacked) {
                    canvas.translate(0f, index * cellHeight)
                    if (index > 0) {
                        paint.color = 0xff34434a.toInt()
                        canvas.drawRect(0f, 0f, width, 1f, paint)
                    }
                }
                drawSlot(
                    canvas,
                    slot,
                    if (stacked) left else left + index * (cellWidth + gap),
                    cellWidth,
                    cellHeight,
                )
                canvas.restore()
            }
        }
        paint.color = 0xff34434a.toInt()
        canvas.drawRect(0f, height - 1f, width, height, paint)
        canvas.restore()
    }

    private fun drawSlot(canvas: Canvas, slot: Slot, x: Float, width: Float, height: Float) {
        val content = slot.content ?: return
        if (compact) {
            val identityWidth = min(190f, width * .28f)
            val identityHeight =
                slot.identity.draw(canvas, content.identity, x, 6f, identityWidth, content.color)
            if (content.locked)
                slot.lock.draw(
                    canvas,
                    "⚠ HOMING LOCK",
                    x,
                    6f + identityHeight + 3f,
                    identityWidth,
                    NativeStyle.danger,
                )
            val detailsX = x + identityWidth + 12f
            val detailsWidth = width - identityWidth - 12f
            val ammoWidth =
                if (content.firingSeconds != null) min(112f, detailsWidth * .48f)
                else if (content.unlimited) 25f else 60f
            drawAmmo(canvas, slot, detailsX, 6f, ammoWidth)
            slot.weapon.draw(
                canvas,
                content.weapon,
                detailsX + ammoWidth + 10f,
                6f,
                max(1f, detailsWidth - ammoWidth - 10f),
                NativeStyle.accent,
            )
            val secondY = compactSecondY
            val barWidth = min(100f, detailsWidth * .2f)
            val textWidth = max(1f, detailsWidth - barWidth - 8f)
            val readinessWidth = compactReadinessWidth(textWidth, content)
            val buffsWidth =
                if (content.buffs.isEmpty()) 0f else max(1f, textWidth - readinessWidth - 12f)
            if (content.buffs.isNotEmpty())
                slot.buffs.draw(
                    canvas,
                    content.buffs,
                    detailsX,
                    secondY,
                    buffsWidth,
                    0xff75f0cb.toInt(),
                )
            val readinessX = detailsX + if (content.buffs.isNotEmpty()) buffsWidth + 12f else 0f
            slot.readiness.draw(
                canvas,
                content.readiness,
                readinessX,
                secondY,
                readinessWidth,
                NativeStyle.soft,
            )
            progress(
                canvas,
                slot.progressAt(frameNanos),
                detailsX + detailsWidth - barWidth,
                secondY + 5f * fontScale,
                barWidth,
                content.color,
            )
        } else {
            val identityHeight =
                slot.identity.draw(canvas, content.identity, x, 8f, width, content.color)
            val lockHeight =
                if (content.locked)
                    slot.lock.draw(
                        canvas,
                        "⚠ HOMING LOCK",
                        x,
                        8f + identityHeight + 3f,
                        width,
                        NativeStyle.danger,
                    ) + 3f
                else 0f
            val equipmentY = 8f + identityHeight + lockHeight + 5f
            val ammoWidth = if (content.firingSeconds != null) min(112f, width * .4f) else 60f
            drawAmmo(canvas, slot, x, equipmentY, ammoWidth)
            val equipmentX = x + ammoWidth + 10f
            val equipmentWidth = max(1f, width - ammoWidth - 10f)
            val weaponHeight =
                slot.weapon.draw(
                    canvas,
                    content.weapon,
                    equipmentX,
                    equipmentY,
                    equipmentWidth,
                    NativeStyle.accent,
                )
            slot.buffs.draw(
                canvas,
                content.buffs,
                equipmentX,
                equipmentY + weaponHeight + 3f,
                equipmentWidth,
                0xff75f0cb.toInt(),
            )
            val readinessWidth = min(150f * fontScale, width * .55f)
            val readinessY = height - 8f - slot.readiness.measure(content.readiness, readinessWidth)
            slot.readiness.draw(
                canvas,
                content.readiness,
                x,
                readinessY,
                readinessWidth,
                NativeStyle.soft,
            )
            progress(
                canvas,
                slot.progressAt(frameNanos),
                x + readinessWidth + 8f,
                readinessY + 5f * fontScale,
                max(0f, width - readinessWidth - 8f),
                content.color,
            )
        }
    }

    private fun compactReadinessWidth(width: Float, content: Content): Float {
        if (content.buffs.isEmpty()) return width
        measurePaint.textSize = 10f * fontScale
        return min(
            min(150f * fontScale, width * .58f),
            max(40f, measurePaint.measureText(content.readiness) + 2f),
        )
    }

    private fun drawAmmo(canvas: Canvas, slot: Slot, x: Float, y: Float, width: Float) {
        val content = slot.content ?: return
        if (content.unlimited) {
            paint.color = NativeStyle.accent
            paint.textSize = 19f * fontScale
            paint.typeface = Typeface.MONOSPACE
            canvas.drawText("∞", x, y + 17f * fontScale, paint)
        } else if (content.firingSeconds != null) {
            val rounded = ceil(content.firingSeconds * 10) / 10
            val labelHeight =
                slot.ammunition.draw(
                    canvas,
                    "FIRE LEFT $rounded / 3s",
                    x,
                    y,
                    width,
                    NativeStyle.accent,
                )
            progress(
                canvas,
                (content.firingSeconds / 3).coerceIn(0.0, 1.0),
                x,
                y + labelHeight + 3f,
                width,
                NativeStyle.accent,
            )
        } else {
            val count = min(12, content.capacity)
            val active =
                ceil(content.available.toDouble() / max(1, content.capacity) * count).toInt()
            for (index in 0 until count) {
                paint.color = if (index < active) content.color else 0xff324249.toInt()
                val px = x + index * 5f
                canvas.drawRoundRect(px, y + 2f, px + 4f, y + 13f, 2f, 2f, paint)
            }
        }
    }

    private fun progress(
        canvas: Canvas,
        amount: Double,
        x: Float,
        y: Float,
        width: Float,
        color: Int,
    ) {
        if (width <= 0) return
        paint.color = 0xff324249.toInt()
        canvas.drawRect(x, y, x + width, y + 3f, paint)
        paint.color = color
        canvas.drawRect(x, y, x + width * amount.coerceIn(0.0, 1.0).toFloat(), y + 3f, paint)
    }
}
