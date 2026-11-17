package com.leqra.android

import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.WindowInsets
import android.widget.FrameLayout
import android.widget.LinearLayout
import com.leqra.android.NativeStyle.add
import com.leqra.android.NativeStyle.dp
import com.leqra.android.render.NativeArenaView
import kotlin.math.max

/** The real native gameplay chrome around an immutable scene. */
internal class ShowcaseView(context: Context, private val muted: Boolean) : LinearLayout(context) {
    val header = NativeGameHeader(context, {}, {}, {})
    val status = NativeStatusView(context) {}
    val loadout = NativeHudView(context)
    private val field = FrameLayout(context)
    lateinit var arena: NativeArenaView
        private set
    lateinit var scene: ShowcaseScene
        private set
    private var portrait = resources.configuration.orientation != Configuration.ORIENTATION_LANDSCAPE
    private var safeLeft = 0
    private var safeRight = 0
    private var safeBottom = 0

    init {
        orientation = VERTICAL
        setBackgroundColor(NativeStyle.page)
        contentDescription = "Frozen leqra showcase"
        isFocusableInTouchMode = true
        add(header, gap = 0)
        add(status, gap = 0)
        field.setBackgroundColor(NativeStyle.sunken)
        addView(field, LayoutParams(-1, 0, 1f))
        add(loadout, gap = 0)
        rebuild()
        setOnApplyWindowInsetsListener { _, insets ->
            var top = 0
            if (Build.VERSION.SDK_INT >= 30) {
                val cutout = insets.getInsets(WindowInsets.Type.displayCutout())
                val gestures = insets.getInsets(WindowInsets.Type.systemGestures())
                safeLeft = cutout.left; safeRight = cutout.right; top = cutout.top
                safeBottom = max(cutout.bottom, gestures.bottom)
            } else if (Build.VERSION.SDK_INT >= 28) {
                safeLeft = insets.displayCutout?.safeInsetLeft ?: 0
                safeRight = insets.displayCutout?.safeInsetRight ?: 0
                top = insets.displayCutout?.safeInsetTop ?: 0
                safeBottom = insets.displayCutout?.safeInsetBottom ?: 0
            }
            setPadding(0, top, 0, 0)
            updateLayout()
            insets
        }
    }

    private fun rebuild() {
        if (::arena.isInitialized) arena.release()
        field.removeAllViews()
        scene = ShowcaseScene.load(context, portrait)
        arena = NativeArenaView(context).apply {
            contentDescription = "Tank arena, joystick on the left and fire on the right"
            showFrozenScene(scene.snapshot, scene.maze, scene.localID, scene.time,
                scene.effectAges, scene.outlines, scene.trails, controls = true, fitPortrait = portrait)
        }
        field.addView(arena, FrameLayout.LayoutParams(-1, -1))
        loadout.update(scene.snapshot, scene.localID, null, true, false, true, frozen = true)
        arena.fireLabel = loadout.fireLabel
        arena.fireAvailable = loadout.fireAvailable
        arena.fireProgress = loadout.advance(0L)
        status.showShowcase(scene.snapshot, scene.localID, scene.fps, scene.ping)
        updateLayout()
    }

    private fun updateLayout() {
        header.display(!portrait, (width.takeIf { it > 0 } ?: resources.displayMetrics.widthPixels) / resources.displayMetrics.density, muted, true)
        header.setPadding(context.dp(12) + safeLeft, context.dp(5), context.dp(8) + safeRight, context.dp(5))
        loadout.compact = !portrait
        loadout.safeLeft = safeLeft
        loadout.safeRight = safeRight
        loadout.safeBottom = safeBottom
        arena.safeInsets(safeLeft, 0, safeRight, 0)
        loadout.requestLayout()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        val h = MeasureSpec.getSize(heightMeasureSpec)
        val next = w <= h
        if (w > 0 && h > 0 && portrait != next) { portrait = next; rebuild() }
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        updateLayout()
    }

    override fun dispatchTouchEvent(event: MotionEvent) = true
    override fun dispatchGenericMotionEvent(event: MotionEvent) = true
    override fun dispatchKeyEvent(event: KeyEvent): Boolean =
        if (event.keyCode == KeyEvent.KEYCODE_ESCAPE || event.keyCode == KeyEvent.KEYCODE_BACK) super.dispatchKeyEvent(event) else true

    fun release() { arena.release() }
}
