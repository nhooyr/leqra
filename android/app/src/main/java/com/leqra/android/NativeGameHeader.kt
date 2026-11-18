package com.leqra.android

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.drawable.Drawable
import android.graphics.drawable.InsetDrawable
import android.graphics.drawable.RippleDrawable
import android.view.Gravity
import android.view.View
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import com.leqra.android.NativeStyle.add
import com.leqra.android.NativeStyle.background
import com.leqra.android.NativeStyle.button
import com.leqra.android.NativeStyle.column
import com.leqra.android.NativeStyle.dp
import com.leqra.android.NativeStyle.label
import com.leqra.android.NativeStyle.row

/** Shared gameplay header, including the static screenshot presentation. */
internal class NativeGameHeader(
    context: Context,
    openVersion: () -> Unit,
    toggleSound: () -> Unit,
    openMenu: () -> Unit,
    toggleFullscreen: () -> Unit = {},
    openRoom: () -> Unit = {},
    openSidebar: (() -> Unit)? = null,
) : LinearLayout(context) {
    private val brand = row(context)
    private val brandMark = NativeStyle.brandIcon(context)
    private val brandSubtitle = label(context, "TANK ARENA", 10f, NativeStyle.muted, mono = true)
    private val roomButton = button(context, "ROOM", openRoom, role = "share").apply {
        minimumWidth = 0
        minWidth = 0
        setPadding(context.dp(6), 0, context.dp(6), 0)
        visibility = GONE
    }
    private val soundButton = iconButton(toggleSound)
    private val fullscreenButton = iconButton(toggleFullscreen)
    private val hasSidebar = openSidebar != null
    private val sidebarButton = iconButton { openSidebar?.invoke() }.apply {
        displayIcon(context.getDrawable(R.drawable.ic_sidebar), "Open sidebar")
        visibility = if (hasSidebar) VISIBLE else GONE
    }
    private val menuButton = iconButton(openMenu)
    private var soundMuted: Boolean? = null
    private var fullscreenActive: Boolean? = null
    private var inGame: Boolean? = null

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(context.dp(12), context.dp(5), context.dp(8), context.dp(5))
        brand.add(brandMark, 36, 36, gap = 0)
        val names = column(context)
        names.add(label(context, "leqra", 17f, NativeStyle.text, true).apply { contentDescription = "leqra" }, gap = 3)
        names.add(brandSubtitle, gap = 0)
        brand.add(names, width = -2, gap = 0)
        add(brand, width = -2, gap = 0)
        add(label(context, "v${BuildConfig.VERSION_NAME}", 10f, NativeStyle.muted, mono = true).apply {
            contentDescription = "View leqra on GitHub"
            gravity = Gravity.CENTER_VERTICAL
            minHeight = context.dp(32)
            setPaddingRelative(context.dp(5), 0, context.dp(5), 0)
            compoundDrawablePadding = context.dp(4)
            setCompoundDrawablesRelativeWithIntrinsicBounds(R.drawable.ic_github, 0, 0, 0)
            background = background(context, NativeStyle.surface, 8, 0xff34434a.toInt())
            isClickable = true
            isFocusable = true
            setOnClickListener { openVersion() }
        }, width = -2, gap = 0)
        addView(View(context), LayoutParams(0, 0, 1f))
        add(roomButton, -2, 36, gap = 0)
        add(soundButton, 44, 44, gap = 0)
        add(fullscreenButton, 44, 44, gap = 0)
        add(sidebarButton, 44, 44, gap = 0)
        add(menuButton, 44, 44, gap = 0)
    }

    fun display(
        landscape: Boolean,
        widthDp: Float,
        muted: Boolean,
        playing: Boolean,
        fullscreen: Boolean = false,
        roomCode: String? = null,
        showSidebar: Boolean = true,
    ) {
        val sidebarVisible = hasSidebar && showSidebar
        val compact = widthDp < (if (sidebarVisible) 390 else 375) || (roomCode != null && widthDp < 500)
        brandSubtitle.visibility = if (landscape || (compact && sidebarVisible)) View.GONE else View.VISIBLE
        brandMark.visibility = if (compact) GONE else VISIBLE
        sidebarButton.visibility = if (sidebarVisible) VISIBLE else GONE
        val brandGap = context.dp(if (compact) 4 else 8)
        if (brand.paddingEnd != brandGap) brand.setPaddingRelative(0, 0, brandGap, 0)
        roomButton.visibility = if (roomCode == null) GONE else VISIBLE
        if (roomCode != null) roomButton.contentDescription = "Room $roomCode"
        if (soundMuted != muted) {
            soundMuted = muted
            soundButton.displayIcon(if (muted) "muted" else "sound", if (muted) "Unmute sound" else "Mute sound", !muted)
        }
        if (fullscreenActive != fullscreen) {
            fullscreenActive = fullscreen
            fullscreenButton.displayIcon("fullscreen", if (fullscreen) "Exit fullscreen" else "Enter fullscreen", fullscreen)
        }
        if (inGame != playing) {
            inGame = playing
            menuButton.displayIcon(if (playing) "pause" else "controls", if (playing) "Pause game" else "Controls")
        }
    }

    private fun iconButton(action: () -> Unit) = ImageButton(context).apply {
        scaleType = ImageView.ScaleType.CENTER
        stateListAnimator = null
        setOnClickListener { action() }
    }

    private fun ImageButton.displayIcon(kind: String, description: String, active: Boolean = false) =
        displayIcon(NativeStyle.icon(context, kind, active), description, active)

    private fun ImageButton.displayIcon(icon: Drawable?, description: String, active: Boolean = false) {
        setImageDrawable(icon)
        contentDescription = description
        background = InsetDrawable(
            RippleDrawable(
                ColorStateList.valueOf(0x3340d5ff),
                background(context, NativeStyle.surface, 8, if (active) 0x6640d5ff else NativeStyle.edge),
                null,
            ),
            context.dp(4),
        )
        setPadding(0, 0, 0, 0)
    }
}
