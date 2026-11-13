package com.leqra.android.render

import android.graphics.*
import kotlin.math.*

object ArenaPalette {
    val tanks =
        intArrayOf(
            0xff32c5ff.toInt(),
            0xffff758f.toInt(),
            0xff3ee6c5.toInt(),
            0xffba91ff.toInt(),
            0xffffcb66.toInt(),
            0xffff7bd5.toInt(),
            0xff79d878.toInt(),
            0xff91a9ff.toInt(),
        )
    val powers =
        linkedMapOf(
            "rapid" to 0xff79d878.toInt(),
            "scatter" to 0xffba91ff.toInt(),
            "shield" to 0xff32c5ff.toInt(),
            "homing" to 0xffff7bd5.toInt(),
            "grenade" to 0xffffcb66.toInt(),
            "speed" to 0xff3ee6c5.toInt(),
            "laser" to 0xffe879ff.toInt(),
            "cannon" to 0xffff9e66.toInt(),
            "ghost" to 0xffcedaff.toInt(),
            "starman" to 0xfff9ed75.toInt(),
        )

    fun tank(index: Int) = tanks[Math.floorMod(index, tanks.size)]

    fun power(kind: String) = powers[kind] ?: 0xff32c5ff.toInt()

    fun alpha(color: Int, alpha: Float) =
        (color and 0x00ffffff) or ((alpha.coerceIn(0f, 1f) * 255).toInt() shl 24)
}

/** Immutable raster artwork uploaded once and reused by hardware Canvas/RenderThread. */
internal class NativeArt {
    private val cache = HashMap<String, Bitmap>()
    private val hulls = Array(8) { arrayOfNulls<Bitmap>(4) }
    private val barrels = arrayOfNulls<Bitmap>(8)
    private val turrets = arrayOfNulls<Bitmap>(8)
    private val pickups = HashMap<String, Bitmap>()
    private val badges = HashMap<String, Bitmap>()
    private val fuses = arrayOfNulls<Path>(257)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val path = Path()

    private fun bitmap(key: String, size: Int, draw: (Canvas) -> Unit): Bitmap =
        cache.getOrPut(key) {
            Bitmap.createBitmap(size * 3, size * 3, Bitmap.Config.ARGB_8888).also { image ->
                val canvas = Canvas(image)
                canvas.scale(3f, 3f)
                canvas.translate(size / 2f, size / 2f)
                draw(canvas)
            }
        }

    private fun fill(
        canvas: Canvas,
        color: Int,
        x: Float,
        y: Float,
        w: Float,
        h: Float,
        radius: Float = 0f,
    ) {
        paint.color = color
        paint.style = Paint.Style.FILL
        canvas.drawRoundRect(x, y, x + w, y + h, radius, radius, paint)
    }

    fun hull(color: Int, phase: Int): Bitmap {
        val c = Math.floorMod(color, 8)
        val p = Math.floorMod(phase, 4)
        return hulls[c][p] ?: createHull(c, p).also { hulls[c][p] = it }
    }

    fun barrel(color: Int): Bitmap {
        val c = Math.floorMod(color, 8)
        return barrels[c] ?: createBarrel(c).also { barrels[c] = it }
    }

    fun turret(color: Int): Bitmap {
        val c = Math.floorMod(color, 8)
        return turrets[c] ?: createTurret(c).also { turrets[c] = it }
    }

    fun pickup(kind: String): Bitmap = pickups.getOrPut(kind) { createPickup(kind) }

    fun grenadeFuse(step: Int): Path {
        val index = step.coerceIn(0, 256)
        return fuses[index]
            ?: Path()
                .apply { arcTo(-10f, -10f, 10f, 10f, -90f, index * 360f / 256, false) }
                .also { fuses[index] = it }
    }

    fun stickBase(): Bitmap =
        cache["stick-base"]
            ?: bitmap("stick-base", 96) { c ->
                val p = Paint(Paint.ANTI_ALIAS_FLAG)
                p.shader =
                    RadialGradient(
                        0f,
                        0f,
                        48f,
                        intArrayOf(0xff324249.toInt(), 0xff232e33.toInt(), 0xff192127.toInt()),
                        floatArrayOf(0f, .64f, .65f),
                        Shader.TileMode.CLAMP,
                    )
                c.drawCircle(0f, 0f, 48f, p)
                p.shader = null
                p.color = 0xff111a1f.toInt()
                p.style = Paint.Style.STROKE
                p.strokeWidth = 8f
                c.drawCircle(0f, 0f, 43.5f, p)
                p.color = 0x2a324249
                p.strokeWidth = 1f
                c.drawLine(-36f, -1f, 34f, -1f, p)
                c.drawLine(-1f, -36f, -1f, 34f, p)
            }

    fun stickKnob(): Bitmap =
        cache["stick-knob"]
            ?: bitmap("stick-knob", 44) { c ->
                val p = Paint(Paint.ANTI_ALIAS_FLAG)
                p.shader =
                    LinearGradient(
                        -22f,
                        -22f,
                        22f,
                        22f,
                        0xff324249.toInt(),
                        0xff232e33.toInt(),
                        Shader.TileMode.CLAMP,
                    )
                c.drawCircle(0f, 0f, 22f, p)
                p.shader = null
                p.color = 0x1500c8ff
                c.drawCircle(0f, 0f, 8f, p)
                p.style = Paint.Style.STROKE
                p.strokeWidth = 1f
                p.color = 0x8000c8ff.toInt()
                c.drawCircle(0f, 0f, 8f, p)
            }

    fun fireButton(held: Boolean, detonate: Boolean): Bitmap {
        val key =
            if (detonate) if (held) "fire-boom-held" else "fire-boom"
            else if (held) "fire-held" else "fire"
        return cache[key]
            ?: bitmap(key, 91) { c ->
                val first = if (detonate) 0xff635036.toInt() else 0xff194654.toInt()
                val last = if (detonate) 0xff39291d.toInt() else 0xff102e3d.toInt()
                val p = Paint(Paint.ANTI_ALIAS_FLAG)
                if (held) p.color = if (detonate) first else 0xff087693.toInt()
                else
                    p.shader =
                        RadialGradient(-10.9f, -18.2f, 52f, first, last, Shader.TileMode.CLAMP)
                c.drawCircle(0f, 0f, 45.5f, p)
                p.shader = null
                p.color = last
                p.strokeWidth = 4f
                p.style = Paint.Style.STROKE
                c.drawCircle(0f, 0f, 41.5f, p)
            }
    }

    private fun createHull(color: Int, phase: Int): Bitmap =
        bitmap("h:$color:$phase", 48) { c ->
            val ink = ArenaPalette.tank(color)
            fill(c, 0xa802080b.toInt(), -20f, -11f, 40f, 31f, 6f)
            for (side in intArrayOf(-1, 1)) {
                fill(c, 0xff0b1116.toInt(), -19f, if (side < 0) -17f else 9f, 37f, 9f, 3f)
                paint.color = 0xa6849392.toInt()
                paint.strokeWidth = 1f
                for (i in 0..6) {
                    val x = -16f + i * 5 + phase
                    c.drawLine(
                        x,
                        if (side < 0) -16f else 10f,
                        x,
                        if (side < 0) -10f else 16f,
                        paint,
                    )
                }
            }
            fill(c, ink, -17f, -12f, 34f, 24f, 5f)
            fill(c, 0x30000000, -15f, -10f, 7f, 20f, 2f)
            paint.color = 0x58ffffff
            c.drawLine(-12f, -10f, 12f, -10f, paint)
            fill(c, 0x660c1518, -12f, -6f, 3f, 12f)
        }

    private fun createBarrel(color: Int): Bitmap =
        bitmap("b:$color", 64) { c ->
            fill(c, 0xff0a121a.toInt(), 4f, -4.5f, 26f, 9f, 2f)
            fill(c, ArenaPalette.tank(color), 5f, -3f, 23f, 6f)
            fill(c, 0x8ae4f0d9.toInt(), 26f, -3.5f, 3f, 7f)
        }

    private fun createTurret(color: Int): Bitmap =
        bitmap("t:$color", 24) { c ->
            paint.style = Paint.Style.FILL
            paint.color = 0x42000000
            c.drawCircle(0f, 2f, 9.5f, paint)
            paint.color = ArenaPalette.tank(color)
            c.drawCircle(0f, 0f, 9f, paint)
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 2f
            paint.color = 0x70091219
            c.drawCircle(0f, 0f, 9f, paint)
            paint.style = Paint.Style.FILL
            paint.color = 0xff172124.toInt()
            c.drawCircle(-1f, 0f, 3.2f, paint)
        }

    fun wreck(): Bitmap =
        bitmap("wreck", 48) { c ->
            fill(c, 0xff091116.toInt(), -18f, -16f, 36f, 32f, 5f)
            paint.color = 0xff46545a.toInt()
            paint.strokeWidth = 2f
            c.drawLine(-8f, -8f, 8f, 8f, paint)
            c.drawLine(8f, -8f, -8f, 8f, paint)
        }

    private fun createPickup(kind: String): Bitmap =
        bitmap("p:$kind", 42) { c ->
            val ink = ArenaPalette.power(kind)
            // Layered translucent outlines retain the browser halo without a per-frame blur.
            for (i in 4 downTo 1) {
                paint.color = ArenaPalette.alpha(ink, .035f)
                paint.style = Paint.Style.STROKE
                paint.strokeWidth = i * 2f
                c.drawRoundRect(-13f, -13f, 13f, 13f, 6f, 6f, paint)
            }
            fill(c, 0xff152126.toInt(), -13f, -13f, 26f, 26f, 6f)
            paint.color = ink
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 1.5f
            c.drawRoundRect(-13f, -13f, 13f, 13f, 6f, 6f, paint)
            drawPower(c, kind)
        }

    fun badge(kind: String): Bitmap =
        badges.getOrPut(kind) {
            bitmap("badge:$kind", 64) { c ->
                paint.color = 0xe80b141b.toInt()
                paint.style = Paint.Style.FILL
                c.drawCircle(0f, 0f, 27f, paint)
                paint.color = ArenaPalette.power(kind)
                paint.style = Paint.Style.STROKE
                paint.strokeWidth = 3f
                c.drawCircle(0f, 0f, 27f, paint)
                c.scale(1.38f, 1.38f)
                drawPower(c, kind)
            }
        }

    private fun poly(
        c: Canvas,
        vararg coords: Float,
        close: Boolean = false,
        fill: Boolean = false,
    ) {
        path.rewind()
        path.moveTo(coords[0], coords[1])
        var i = 2
        while (i < coords.size) {
            path.lineTo(coords[i], coords[i + 1])
            i += 2
        }
        if (close) path.close()
        paint.style = if (fill) Paint.Style.FILL else Paint.Style.STROKE
        c.drawPath(path, paint)
    }

    private fun drawPower(c: Canvas, kind: String) {
        paint.color = ArenaPalette.power(kind)
        paint.strokeWidth = 2f
        paint.strokeCap = Paint.Cap.ROUND
        paint.strokeJoin = Paint.Join.ROUND
        paint.style = Paint.Style.STROKE
        when (kind) {
            "rapid" ->
                for (i in 0..2) {
                    val y = -6f + i * 6
                    c.drawLine(-9f, y, -3f, y, paint)
                    poly(
                        c,
                        0f,
                        y - 1.7f,
                        6f,
                        y - 1.7f,
                        9f,
                        y,
                        6f,
                        y + 1.7f,
                        0f,
                        y + 1.7f,
                        close = true,
                        fill = true,
                    )
                }
            "scatter" -> {
                paint.strokeWidth = 2.4f
                for (y in floatArrayOf(-7f, 0f, 7f)) {
                    poly(c, -10f, 0f, -3f, 0f, 10f, y)
                    c.drawCircle(10f, y, 1.35f, paint)
                }
                for (y in floatArrayOf(-4f, 4f)) c.drawLine(-12f, y, -7f, y, paint)
            }
            "homing" -> {
                poly(c, 0f, -9f, 4f, -2f, 3f, 5f, 0f, 3f, -3f, 5f, -4f, -2f, close = true)
                c.drawLine(-3f, 2f, -7f, 7f, paint)
                c.drawLine(3f, 2f, 7f, 7f, paint)
                c.drawLine(0f, 6f, 0f, 9f, paint)
            }
            "laser" -> {
                c.drawRect(-11f, -5f, -5f, 5f, paint)
                c.drawLine(-8f, -2f, -8f, 2f, paint)
                c.drawLine(-1f, 0f, 11f, 0f, paint)
                paint.style = Paint.Style.FILL
                c.drawRect(-5f, -3f, -2f, 3f, paint)
            }
            "grenade" -> {
                c.drawOval(-6f, -4f, 6f, 8f, paint)
                c.drawRect(-2f, -7f, 2f, -4f, paint)
                path.rewind()
                path.moveTo(1f, -8f)
                path.quadTo(6f, -11f, 8f, -5f)
                c.drawPath(path, paint)
                c.drawLine(0f, 0f, 0f, 4f, paint)
            }
            "ghost" -> {
                path.rewind()
                path.moveTo(-8f, 9f)
                path.lineTo(-8f, -2f)
                path.cubicTo(-8f, -12f, 8f, -12f, 8f, -2f)
                path.lineTo(8f, 9f)
                path.lineTo(4f, 6f)
                path.lineTo(0f, 9f)
                path.lineTo(-4f, 6f)
                path.close()
                c.drawPath(path, paint)
                paint.style = Paint.Style.FILL
                c.drawCircle(-3f, -1f, 1.2f, paint)
                c.drawCircle(3f, -1f, 1.2f, paint)
            }
            "starman" -> {
                path.rewind()
                for (i in 0..9) {
                    val angle = i * PI / 5 - PI / 2
                    val r = if (i % 2 == 0) 10.0 else 4.5
                    val x = (cos(angle) * r).toFloat()
                    val y = (sin(angle) * r).toFloat()
                    if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                }
                path.close()
                c.drawPath(path, paint)
            }
            "cannon" -> {
                paint.style = Paint.Style.FILL
                c.drawCircle(4f, 0f, 5f, paint)
                for (y in floatArrayOf(-4f, 0f, 4f)) c.drawLine(
                    if (y == 0f) -12f else -10f,
                    y,
                    if (y == 0f) -4f else -5f,
                    y,
                    paint,
                )
            }
            "speed" -> for (x in floatArrayOf(-5f, 2f)) poly(c, x - 2, -7f, x + 4, 0f, x - 2, 7f)
            else -> {
                path.rewind()
                path.moveTo(0f, -8f)
                path.lineTo(7f, -5f)
                path.lineTo(6f, 3f)
                path.quadTo(4f, 7f, 0f, 9f)
                path.quadTo(-4f, 7f, -6f, 3f)
                path.lineTo(-7f, -5f)
                path.close()
                c.drawPath(path, paint)
            }
        }
        paint.style = Paint.Style.FILL
        paint.strokeCap = Paint.Cap.BUTT
    }

    fun clear() {
        // RenderThread may still reference the last display list. Let Android
        // release its shared bitmap backing after both threads stop using it.
        cache.clear()
        hulls.forEach { it.fill(null) }
        barrels.fill(null)
        turrets.fill(null)
        pickups.clear()
        badges.clear()
        fuses.fill(null)
    }
}
