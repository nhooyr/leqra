package com.leqra.android.render

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager

/** Only packaged in debug builds; a deterministic full-screen GPU benchmark surface. */
class RenderBenchmarkActivity : Activity() {
    lateinit var arena: NativeArenaView
        private set

    private var scene: RenderStressScene? = null
    private var began = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= 28)
            window.attributes =
                window.attributes.apply {
                    layoutInDisplayCutoutMode =
                        WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                }
        if (Build.VERSION.SDK_INT >= 30) {
            window.setDecorFitsSystemWindows(false)
            // PhoneWindow's controller getter assumes its decor already exists.
            window.decorView
            window.insetsController?.apply {
                hide(WindowInsets.Type.systemBars())
                systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else
            @Suppress("DEPRECATION")
            run {
                window.decorView.systemUiVisibility =
                    View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                        View.SYSTEM_UI_FLAG_FULLSCREEN or
                        View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                        View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                        View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                        View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            }
        @Suppress("DEPRECATION") val display = windowManager.defaultDisplay
        val best =
            display.supportedModes
                .filter {
                    it.physicalWidth == display.mode.physicalWidth &&
                        it.physicalHeight == display.mode.physicalHeight
                }
                .maxByOrNull { it.refreshRate }
        if (best != null)
            window.attributes =
                window.attributes.apply {
                    preferredDisplayModeId = best.modeId
                    preferredRefreshRate = best.refreshRate
                }
        arena =
            NativeArenaView(this).apply {
                hudHeightDp = 0f
                if (Build.VERSION.SDK_INT >= 35) requestedFrameRate = best?.refreshRate ?: 60f
            }
        setContentView(arena)
        arena.onFrame = { nanos ->
            if (began == 0L) began = nanos
            scene?.let { arena.submit(it.update((nanos - began) / 1e9), 1, it.maze) }
        }
    }

    fun configure(fixed: Boolean) {
        scene = RenderStressScene(fixed)
        began = 0
        arena.resetWorld()
    }

    override fun onResume() {
        super.onResume()
        if (::arena.isInitialized) arena.start()
    }

    override fun onPause() {
        if (::arena.isInitialized) arena.pause()
        super.onPause()
    }

    override fun onDestroy() {
        if (::arena.isInitialized) arena.release()
        super.onDestroy()
    }
}
