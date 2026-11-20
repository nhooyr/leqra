package com.leqra.android

import android.os.Build
import android.view.Display
import android.view.View
import android.view.Window
import kotlin.math.abs

internal fun Window.applyArenaRefreshRate(
    arena: View,
    display: Display,
    interactive: Boolean,
    highRefresh: Boolean,
) {
    val current = display.mode
    val compatible =
        display.supportedModes.filter {
            it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight
        }
    val best =
        if (highRefresh) compatible.maxByOrNull { it.refreshRate }
        else compatible.minByOrNull { abs(it.refreshRate - 60f) }
    val target = if (interactive) best?.modeId ?: 0 else 0
    val rate = if (interactive) if (highRefresh) best?.refreshRate ?: 60f else 60f else 30f
    // Android 15+ considers the view's vote as well as the window's display mode.
    if (Build.VERSION.SDK_INT >= 35 && arena.requestedFrameRate != rate)
        arena.requestedFrameRate = rate
    if (attributes.preferredDisplayModeId != target || attributes.preferredRefreshRate != rate) {
        attributes = attributes.apply {
            preferredDisplayModeId = target
            preferredRefreshRate = rate
        }
    }
}
