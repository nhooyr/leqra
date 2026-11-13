package com.leqra.android

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.text.InputFilter
import android.view.View
import android.view.ViewGroup
import android.widget.*
import com.leqra.core.Callsigns
import com.leqra.core.GamePalette

/** The mobile web palette, spacing and typography, using native accessible controls. */
internal object NativeStyle {
    val page = Color.parseColor("#111619")
    val surface = Color.parseColor("#192127")
    val sunken = Color.parseColor("#111a1f")
    val raised = Color.parseColor("#232e33")
    val edge = Color.parseColor("#506d80")
    val text = Color.parseColor("#f1f7fc")
    val soft = Color.parseColor("#c6d5df")
    val muted = Color.parseColor("#9babbb")
    val accent = Color.parseColor("#40d5ff")
    val green = Color.parseColor("#39ff88")
    val danger = Color.parseColor("#ff4f5f")

    private val tankColors = GamePalette.displayColors.map(Color::parseColor)

    fun paint(index: Int) = tankColors[GamePalette.index(index)]

    fun Context.dp(value: Int): Int = (value * resources.displayMetrics.density + .5f).toInt()

    fun background(context: Context, color: Int = surface, radius: Int = 9, border: Int = edge) =
        GradientDrawable().apply {
            setColor(color)
            cornerRadius = context.dp(radius).toFloat()
            setStroke(context.dp(1), border)
        }

    fun panelBackground(context: Context): GradientDrawable {
        val accentPaint =
            android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { color = accent }
        return object : GradientDrawable(Orientation.TL_BR, intArrayOf(raised, surface)) {
                override fun draw(canvas: android.graphics.Canvas) {
                    super.draw(canvas)
                    canvas.drawRoundRect(
                        context.dp(24).toFloat(),
                        0f,
                        context.dp(66).toFloat(),
                        context.dp(3).toFloat(),
                        context.dp(1).toFloat(),
                        context.dp(1).toFloat(),
                        accentPaint,
                    )
                }
            }
            .apply {
                cornerRadius = context.dp(13).toFloat()
                setStroke(context.dp(1), edge)
            }
    }

    fun label(
        context: Context,
        value: String,
        size: Float = 12f,
        color: Int = text,
        bold: Boolean = false,
        mono: Boolean = false,
    ) =
        TextView(context).apply {
            text = value
            textSize = maxOf(10f, size)
            setTextColor(color)
            typeface =
                Typeface.create(
                    if (mono) "monospace" else "sans-serif",
                    if (bold) Typeface.BOLD else Typeface.NORMAL,
                )
            includeFontPadding = false
        }

    fun button(
        context: Context,
        value: String,
        action: () -> Unit,
        play: Boolean = false,
        danger: Boolean = false,
        role: String? = null,
    ): Button =
        Button(context).apply {
            text = value
            textSize = 12f
            isAllCaps = false
            typeface = Typeface.DEFAULT_BOLD
            minHeight = context.dp(44)
            minimumHeight = context.dp(44)
            setPadding(context.dp(10), context.dp(8), context.dp(10), context.dp(8))
            setTextColor(
                if (play) Color.parseColor("#06160d")
                else if (danger) NativeStyle.danger else NativeStyle.text,
            )
            background =
                background(
                    context,
                    if (play) green else raised,
                    6,
                    if (play) Color.parseColor("#72ffaa")
                    else if (danger) NativeStyle.danger else edge,
                )
            if (role == "share" || role == "text") {
                textSize = 10f
                typeface = Typeface.MONOSPACE
                setTextColor(if (role == "share") accent else muted)
                background =
                    background(
                        context,
                        if (role == "share") 0x66102e3d else 0x00000000,
                        6,
                        if (role == "share") 0x6640d5ff else 0x00000000,
                    )
            }
            background =
                RippleDrawable(
                    ColorStateList.valueOf(if (play) 0x22102618 else 0x3340d5ff),
                    background,
                    null,
                )
            stateListAnimator = null
            setOnClickListener { action() }
        }

    fun field(context: Context, value: String, hint: String = "", limit: Int = 16): EditText =
        EditText(context).apply {
            setText(value)
            this.hint = hint
            textSize = 16f
            setTextColor(NativeStyle.text)
            setHintTextColor(muted)
            typeface = Typeface.MONOSPACE
            setSingleLine(true)
            filters =
                arrayOf(
                    InputFilter { source, start, end, dest, dstart, dend ->
                        val existing = dest.toString()
                        val remaining =
                            limit -
                                existing.codePointCount(0, dstart) -
                                existing.codePointCount(dend, existing.length)
                        val incoming = source.subSequence(start, end).toString()
                        if (incoming.codePointCount(0, incoming.length) <= remaining) null
                        else Callsigns.limit(incoming, remaining)
                    },
                )
            setPadding(context.dp(10), context.dp(8), context.dp(10), context.dp(8))
            background = background(context, sunken, 6)
            minHeight = context.dp(46)
            inputType =
                android.text.InputType.TYPE_CLASS_TEXT or
                    android.text.InputType.TYPE_TEXT_FLAG_CAP_WORDS or
                    android.text.InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
        }

    fun disclosure(
        context: Context,
        title: String,
        detail: String = "",
        expanded: Boolean,
        action: () -> Unit,
    ): LinearLayout =
        row(context).apply {
            minimumHeight = context.dp(44)
            setPadding(context.dp(14), 0, context.dp(14), 0)
            background =
                RippleDrawable(
                    ColorStateList.valueOf(0x2240d5ff),
                    background(context, surface, 7),
                    null,
                )
            isClickable = true
            isFocusable = true
            contentDescription =
                "$title, ${if(detail.isNotEmpty()) "$detail, " else ""}${if(expanded) "Expanded" else "Collapsed"}"
            setOnClickListener { action() }
            weighted(
                label(context, title, 14f, text, true).apply {
                    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                },
                gap = 8,
            )
            if (detail.isNotEmpty())
                add(
                    label(context, detail, 10f, accent, mono = true).apply {
                        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                    },
                    width = -2,
                    gap = 0,
                )
            add(
                label(context, "›", 24f, accent, true).apply {
                    rotation = if (expanded) 90f else 0f
                    gravity = android.view.Gravity.CENTER
                    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                },
                28,
                44,
                gap = 0,
            )
        }

    fun paintChip(
        context: Context,
        color: Int,
        selected: Boolean,
    ): android.graphics.drawable.Drawable =
        object : android.graphics.drawable.Drawable() {
            private val ink = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)

            override fun draw(canvas: android.graphics.Canvas) {
                val half = context.dp(11).toFloat()
                val x = bounds.exactCenterX()
                val y = bounds.exactCenterY()
                val radius = context.dp(4).toFloat()
                ink.style = android.graphics.Paint.Style.FILL
                ink.color = color
                canvas.drawRoundRect(x - half, y - half, x + half, y + half, radius, radius, ink)
                if (selected) {
                    ink.style = android.graphics.Paint.Style.STROKE
                    ink.color = 0xfff1f7fc.toInt()
                    ink.strokeWidth = context.dp(2).toFloat()
                    val rim = context.dp(2).toFloat()
                    canvas.drawRoundRect(
                        x - half - rim,
                        y - half - rim,
                        x + half + rim,
                        y + half + rim,
                        radius,
                        radius,
                        ink,
                    )
                }
            }

            override fun setAlpha(alpha: Int) {
                ink.alpha = alpha
            }

            override fun setColorFilter(filter: android.graphics.ColorFilter?) {
                ink.colorFilter = filter
            }

            @Deprecated("Drawable opacity is no longer used")
            override fun getOpacity() = android.graphics.PixelFormat.TRANSLUCENT
        }

    fun icon(context: Context, kind: String): android.graphics.drawable.Drawable =
        object : android.graphics.drawable.Drawable() {
            private val ink = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
            private val shape = android.graphics.Path()

            override fun getIntrinsicWidth() = context.dp(20)

            override fun getIntrinsicHeight() = context.dp(20)

            override fun draw(canvas: android.graphics.Canvas) {
                canvas.save()
                canvas.translate(bounds.left.toFloat(), bounds.top.toFloat())
                canvas.scale(bounds.width() / 24f, bounds.height() / 24f)
                ink.color = if (kind == "muted") muted else accent
                ink.strokeWidth = 1.8f
                ink.style = android.graphics.Paint.Style.STROKE
                if (kind == "chat") {
                    canvas.drawRoundRect(2f, 3f, 22f, 18f, 4f, 4f, ink)
                    shape.rewind()
                    shape.moveTo(7f, 18f)
                    shape.lineTo(7f, 22f)
                    shape.lineTo(12f, 18f)
                    canvas.drawPath(shape, ink)
                } else {
                    ink.style = android.graphics.Paint.Style.FILL
                    canvas.drawRect(2f, 8f, 7f, 16f, ink)
                    shape.rewind()
                    shape.moveTo(7f, 8f)
                    shape.lineTo(12f, 4f)
                    shape.lineTo(12f, 20f)
                    shape.lineTo(7f, 16f)
                    shape.close()
                    canvas.drawPath(shape, ink)
                    ink.style = android.graphics.Paint.Style.STROKE
                    if (kind == "muted") {
                        canvas.drawLine(16f, 8f, 22f, 16f, ink)
                        canvas.drawLine(16f, 16f, 22f, 8f, ink)
                    } else {
                        canvas.drawArc(10f, 7f, 20f, 17f, -50f, 100f, false, ink)
                        canvas.drawArc(8f, 3f, 24f, 21f, -50f, 100f, false, ink)
                    }
                }
                canvas.restore()
            }

            override fun setAlpha(alpha: Int) {
                ink.alpha = alpha
            }

            override fun setColorFilter(filter: android.graphics.ColorFilter?) {
                ink.colorFilter = filter
            }

            @Deprecated("Drawable opacity is no longer used")
            override fun getOpacity() = android.graphics.PixelFormat.TRANSLUCENT
        }

    fun tankMark(context: Context): View =
        object : View(context) {
                private val ink = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)

                override fun onDraw(canvas: android.graphics.Canvas) {
                    super.onDraw(canvas)
                    val scale = width / 32f
                    canvas.save()
                    canvas.scale(scale, scale)
                    canvas.rotate(-4f, 16f, 16f)
                    ink.color = 0x1640d5ff
                    canvas.drawRoundRect(1f, 1f, 31f, 31f, 6f, 6f, ink)
                    ink.style = android.graphics.Paint.Style.STROKE
                    ink.strokeWidth = 1f
                    ink.color = 0x6640d5ff
                    canvas.drawRoundRect(1f, 1f, 31f, 31f, 6f, 6f, ink)
                    ink.style = android.graphics.Paint.Style.FILL
                    ink.color = accent
                    canvas.drawRoundRect(7f, 11f, 12f, 26f, 2f, 2f, ink)
                    canvas.drawRoundRect(20f, 11f, 25f, 26f, 2f, 2f, ink)
                    canvas.drawRoundRect(11f, 12f, 21f, 25f, 3f, 3f, ink)
                    canvas.drawRect(14.5f, 5f, 17.5f, 17f, ink)
                    ink.color = page
                    canvas.drawCircle(16f, 18f, 4f, ink)
                    canvas.restore()
                }
            }
            .apply { importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO }

    fun column(context: Context, padding: Int = 0) =
        LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(
                context.dp(padding),
                context.dp(padding),
                context.dp(padding),
                context.dp(padding),
            )
        }

    fun row(context: Context) =
        LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = android.view.Gravity.CENTER_VERTICAL
        }

    fun LinearLayout.add(
        view: View,
        width: Int = ViewGroup.LayoutParams.MATCH_PARENT,
        height: Int = ViewGroup.LayoutParams.WRAP_CONTENT,
        gap: Int = 8,
    ) {
        addView(
            view,
            LinearLayout.LayoutParams(
                    if (width < 0) width else context.dp(width),
                    if (height < 0) height else context.dp(height),
                )
                .apply { bottomMargin = context.dp(gap) },
        )
    }

    fun LinearLayout.weighted(view: View, weight: Float = 1f, gap: Int = 6) {
        addView(
            view,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, weight).apply {
                marginEnd = context.dp(gap)
            },
        )
    }
}
