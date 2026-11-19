package com.leqra.android.render

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.text.Layout
import android.text.SpannableString
import android.text.Spanned
import android.text.StaticLayout
import android.text.TextPaint
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import com.leqra.core.DeathNotice
import com.leqra.core.GamePalette
import kotlin.math.ceil
import kotlin.math.max

/** Cached screen-space text, shared by fixed and split Infinity viewports. */
internal class NativeDeathNotice {
    private var previous: DeathNotice? = null
    private var previousWidth = 0
    private val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = Typeface.MONOSPACE
        color = 0xffd8e9c5.toInt()
    }
    private val background = Paint(Paint.ANTI_ALIAS_FLAG)
    val bounds = RectF()
    var layout: StaticLayout? = null
        private set
    val fontSize: Float get() = paint.textSize
    var visible = false
        private set

    fun draw(canvas: Canvas, notice: DeathNotice?, size: Float, maximumWidth: Float, x: Float, y: Float) {
        visible = notice != null
        if (notice == null) { bounds.setEmpty(); return }
        val width = max(10, (maximumWidth - 24).toInt())
        if (previous != notice || previousWidth != width || paint.textSize != size) {
            previous = notice; previousWidth = width; paint.textSize = size
            val text = SpannableString(notice.text)
            val start = "Killed by ".length
            text.setSpan(StyleSpan(Typeface.BOLD), start, text.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            if (notice.color.isNotEmpty()) {
                val index = GamePalette.colors.indexOfFirst { it.equals(notice.color, ignoreCase = true) }
                val color = if (index >= 0) ArenaPalette.tank(index) else runCatching { Color.parseColor(notice.color) }.getOrNull()
                if (color != null) text.setSpan(ForegroundColorSpan(color), start, text.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, width)
                .setAlignment(Layout.Alignment.ALIGN_CENTER).setIncludePad(false)
                .setLineSpacing(0f, 1.25f).build()
        }
        val text = layout ?: return
        var textWidth = 0f
        for (line in 0 until text.lineCount) textWidth = max(textWidth, text.getLineWidth(line))
        val halfWidth = ceil(textWidth / 2) + 12
        val halfHeight = text.height / 2f + 8
        bounds.set(x - halfWidth, y - halfHeight, x + halfWidth, y + halfHeight)
        background.style = Paint.Style.FILL
        background.color = 0xf0192127.toInt()
        canvas.drawRoundRect(bounds, 5f, 5f, background)
        background.style = Paint.Style.STROKE
        background.strokeWidth = 1f
        background.color = 0xff34434a.toInt()
        canvas.drawRoundRect(bounds, 5f, 5f, background)
        canvas.save()
        canvas.translate(x - text.width / 2f, y - text.height / 2f)
        text.draw(canvas)
        canvas.restore()
    }
}
