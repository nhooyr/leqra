package com.leqra.android

import android.content.Context
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import com.leqra.android.NativeStyle.add
import com.leqra.android.NativeStyle.background
import com.leqra.android.NativeStyle.button
import com.leqra.android.NativeStyle.column
import com.leqra.android.NativeStyle.dp
import com.leqra.android.NativeStyle.label
import com.leqra.android.NativeStyle.row

/** Shared gameplay header, including the static screenshot presentation. */
internal class NativeGameHeader(context: Context, openVersion: () -> Unit, toggleSound: () -> Unit, openMenu: () -> Unit) : LinearLayout(context) {
    val brandMark = NativeStyle.brandIcon(context)
    val brandSubtitle = label(context, "TANK ARENA", 10f, NativeStyle.muted, mono = true)
    val soundButton = compactButton("SFX", toggleSound)
    val menuButton = compactButton("☰", openMenu).apply { contentDescription = "Open menu" }

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(context.dp(12), context.dp(5), context.dp(8), context.dp(5))
        val brand = row(context).apply { setPadding(0, 0, context.dp(8), 0) }
        brand.add(brandMark, 36, 36, gap = 0)
        val names = column(context)
        names.add(label(context, "leqra", 17f, NativeStyle.text, true).apply { contentDescription = "leqra" }, gap = 3)
        names.add(brandSubtitle, gap = 0)
        brand.add(names, width = -2, gap = 0)
        add(brand, width = -2, gap = 0)
        add(label(context, "v${BuildConfig.VERSION_NAME}", 10f, NativeStyle.muted, mono = true).apply {
            contentDescription = "View leqra on GitHub"
            setPadding(context.dp(6), context.dp(7), context.dp(6), context.dp(7))
            background = background(context, NativeStyle.surface, 8, 0xff34434a.toInt())
            isClickable = true
            isFocusable = true
            setOnClickListener { openVersion() }
        }, width = -2, gap = 0)
        addView(View(context), LayoutParams(0, 0, 1f))
        add(soundButton, 44, gap = 0)
        add(menuButton, 44, gap = 0)
    }

    fun display(landscape: Boolean, widthDp: Float, muted: Boolean, playing: Boolean) {
        brandSubtitle.visibility = if (landscape) View.GONE else View.VISIBLE
        brandMark.visibility = if (widthDp < 375) View.GONE else View.VISIBLE
        soundButton.text = ""
        soundButton.setCompoundDrawablesWithIntrinsicBounds(NativeStyle.icon(context, if (muted) "muted" else "sound"), null, null, null)
        soundButton.contentDescription = if (muted) "Unmute sound" else "Mute sound"
        menuButton.text = if (playing) "Ⅱ" else "☰"
    }

    private fun compactButton(value: String, action: () -> Unit) = button(context, value, action).apply {
        textSize = 12f
        minWidth = 0
        minimumWidth = 0
        setPadding(0, context.dp(8), 0, context.dp(8))
    }
}
