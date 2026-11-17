package com.leqra.android

import android.graphics.Rect
import android.os.Build
import android.view.View
import android.view.Window
import android.view.WindowInsets
import android.view.WindowInsetsController
import kotlin.math.max

@Suppress("DEPRECATION")
internal fun Window.enableImmersiveEdgeToEdge(immersive: Boolean = true) {
    // Edge-to-edge is already enforced for this app on Android 15 and later.
    if (Build.VERSION.SDK_INT in 30..34) setDecorFitsSystemWindows(false)
    setImmersiveSystemBars(immersive)
}

@Suppress("DEPRECATION")
internal fun Window.setImmersiveSystemBars(enabled: Boolean) {
    val decor = decorView
    if (Build.VERSION.SDK_INT >= 30) {
        decor.windowInsetsController?.apply {
            val bars = WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars()
            if (enabled) {
                systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                hide(bars)
            } else show(bars)
        }
    } else {
        val layout = View.SYSTEM_UI_FLAG_LAYOUT_STABLE or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
        val hidden = View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        decor.systemUiVisibility = layout or (if (enabled) hidden else 0)
    }
}

internal data class ImmersiveInsets(
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int,
    val keyboard: Int = 0,
) {
    val contentBottom: Int get() = (bottom - keyboard).coerceAtLeast(0)
}

@Suppress("DEPRECATION")
internal fun WindowInsets.immersiveInsets(): ImmersiveInsets {
    if (Build.VERSION.SDK_INT >= 30) {
        val safe = getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
        val bottom = max(safe.bottom, getInsets(WindowInsets.Type.systemGestures()).bottom)
        val keyboard = getInsets(WindowInsets.Type.ime()).bottom
        return ImmersiveInsets(safe.left, safe.top, safe.right, bottom, keyboard)
    }
    val cutout = if (Build.VERSION.SDK_INT >= 28) {
        displayCutout?.let { Rect(it.safeInsetLeft, it.safeInsetTop, it.safeInsetRight, it.safeInsetBottom) }
    } else null
    val gestures = if (Build.VERSION.SDK_INT >= 29) systemGestureInsets.bottom else 0
    // Legacy decor handles keyboard resize. Reserve only a system bar's height here.
    return ImmersiveInsets(
        max(cutout?.left ?: 0, systemWindowInsetLeft),
        max(cutout?.top ?: 0, systemWindowInsetTop),
        max(cutout?.right ?: 0, systemWindowInsetRight),
        max(max(cutout?.bottom ?: 0, gestures), minOf(systemWindowInsetBottom, stableInsetBottom)),
    )
}
