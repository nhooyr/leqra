package com.leqra.android

import android.app.Dialog
import android.content.Context
import android.os.Build
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.widget.LinearLayout
import android.widget.ScrollView
import com.leqra.android.NativeStyle.add
import com.leqra.android.NativeStyle.background
import com.leqra.android.NativeStyle.button
import com.leqra.android.NativeStyle.column
import com.leqra.android.NativeStyle.dp
import com.leqra.android.NativeStyle.label
import com.leqra.android.NativeStyle.row
import com.leqra.android.NativeStyle.soft
import com.leqra.android.NativeStyle.surface
import com.leqra.android.NativeStyle.weighted
import com.leqra.android.audio.AudioCue
import com.leqra.android.audio.AudioEventRouter
import com.leqra.android.render.NativeArenaView

internal const val QUICK_TOUR_SEEN = "quickTourSeen"

internal class QuickTour(context: Context, private val highRefresh: Boolean, playSound: (AudioCue) -> Unit) : Dialog(context) {
    private val pages = listOf(
        "Drive and aim" to
            "Drag the left stick to drive. Touch near your tank to aim without moving.",
        "Fire" to
            "Hold the right Fire button to shoot a round.",
        "Score a point" to
            "Destroy the stationary tank to score a point.",
    )
    private var page = 0
    private var lastFrame: Long? = null
    private val practice = QuickTourPractice()
    private val audioEvents = AudioEventRouter()
    private val arena = NativeArenaView(context).apply {
        controlsLayout = false
        keyboardInputEnabled = false
        showTankLabels = false
        submit(practice.advance(input, 0.0), practice.tankID, practice.maze)
    }
    private val lesson = column(context)
    private val instructions = column(context)
    private val arenaPanel = column(context)
    private val score = label(context, "score: 0", 10f, NativeStyle.paint(0), mono = true).apply {
        gravity = Gravity.CENTER
        accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        minimumHeight = context.dp(39)
        setPadding(context.dp(12), context.dp(6), context.dp(12), context.dp(6))
        setBackgroundColor(surface)
        visibility = View.GONE
    }

    init {
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        setCanceledOnTouchOutside(false)

        val panel = column(context, 22)
        val header = row(context)
        header.weighted(label(context, "Quick tour", 23f, bold = true).apply {
            if (Build.VERSION.SDK_INT >= 28) isAccessibilityHeading = true
        })
        header.add(button(context, "×", { cancel() }, role = "text").apply {
            textSize = 22f
            contentDescription = "Close Quick tour"
        }, width = 44, height = 44, gap = 0)
        panel.add(header, gap = 14)

        val title = label(context, "", 20f, bold = true).apply {
            if (Build.VERSION.SDK_INT >= 28) isAccessibilityHeading = true
        }
        val message = label(context, "", 14f).apply { setLineSpacing(context.dp(4).toFloat(), 1f) }
        val progress = label(context, "", 10f, soft, mono = true)
        instructions.apply {
            add(title, gap = 8)
            add(message, gap = 12)
            add(progress, gap = 0)
        }
        lesson.add(instructions, gap = 12)
        arenaPanel.add(score, gap = 0)
        arenaPanel.add(arena, height = 220, gap = 0)
        lesson.add(arenaPanel, gap = 0)
        val scroll = ScrollView(context).apply { addView(lesson) }
        panel.addView(scroll, LinearLayout.LayoutParams(-1, -2, 1f).apply { bottomMargin = context.dp(18) })

        val next = button(context, "NEXT", {}, role = "primary")
        panel.add(next, gap = 0)
        fun canAdvance() = when (page) {
            0 -> practice.moved
            1 -> practice.fired
            else -> practice.score > 0
        }
        fun updateNext() {
            val enabled = canAdvance()
            if (next.isEnabled == enabled) return
            next.isEnabled = enabled
            next.alpha = if (enabled) 1f else .45f
        }
        var fireHeld = false
        arena.onInput = { input ->
            if (fireHeld != input.fire) {
                fireHeld = input.fire
                practice.captureFire(fireHeld)
            }
        }
        arena.onControlsReset = practice::resetFire
        var shownScore = 0
        arena.onFrame = { time ->
            val elapsed = lastFrame?.let { (time - it) / 1e9 } ?: 0.0
            lastFrame = time
            val now = time / 1e9
            val state = practice.advance(arena.input, elapsed, nowSeconds = now)
            arena.submit(state, practice.tankID, practice.maze)
            audioEvents.consume(state, practice.tankID, infinity = false, online = false, now = now)
                .forEach { playSound(it.cue) }
            val pilot = state.tanks.first()
            arena.fireProgress = if (pilot.cooldownTotal > 0.0) 1.0 - pilot.cooldown / pilot.cooldownTotal else 1.0
            if (shownScore != practice.score) {
                shownScore = practice.score
                score.text = "score: $shownScore"
            }
            updateNext()
        }
        fun update() {
            val (heading, instructions) = pages[page]
            title.text = heading
            message.text = instructions
            progress.text = "${page + 1} / ${pages.size}"
            next.text = if (page == pages.lastIndex) "DONE" else "NEXT"
            arena.resetControls()
            practice.fireLesson = page > 0
            arena.showFireControl = practice.fireLesson
            arena.contentDescription = "Practice arena. $instructions"
            if (page == pages.lastIndex) {
                practice.startTargetLesson()
                score.visibility = View.VISIBLE
            }
            updateNext()
            layoutPractice()
            scroll.scrollTo(0, 0)
        }
        next.setOnClickListener {
            if (!canAdvance()) return@setOnClickListener
            if (page == pages.lastIndex) cancel()
            else {
                page++
                update()
            }
        }
        update()
        setContentView(panel)
        window?.apply {
            setTitle("Quick tour")
            setBackgroundDrawable(background(context, surface, 13))
            setDimAmount(.8f)
        }
    }

    override fun onStart() {
        super.onStart()
        resumePractice()
    }

    override fun onStop() {
        arena.release()
        super.onStop()
    }

    fun resumePractice() {
        applyRefreshRate()
        arena.start()
    }

    fun pausePractice() {
        lastFrame = null
        arena.pause()
    }

    fun resize() {
        window?.setLayout(dialogWidth(), ViewGroup.LayoutParams.WRAP_CONTENT)
        layoutPractice()
        applyRefreshRate()
    }

    private fun applyRefreshRate() {
        val shown = window ?: return
        @Suppress("DEPRECATION")
        val display = arena.display ?: shown.windowManager.defaultDisplay
        shown.applyArenaRefreshRate(arena, display, interactive = true, highRefresh = highRefresh)
    }

    private fun dialogWidth() = minOf(context.resources.displayMetrics.widthPixels - context.dp(24), context.dp(650))

    private fun layoutPractice() {
        val metrics = context.resources.displayMetrics
        val landscape = metrics.widthPixels > metrics.heightPixels
        lesson.orientation = if (landscape) LinearLayout.HORIZONTAL else LinearLayout.VERTICAL
        instructions.layoutParams = if (landscape) LinearLayout.LayoutParams(0, -2, 1f).apply {
            marginEnd = context.dp(18)
        } else LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = context.dp(12) }
        arenaPanel.layoutParams = if (landscape) LinearLayout.LayoutParams(0, -2, 1.5f) else LinearLayout.LayoutParams(-1, -2)
        val height = if (landscape) context.dp(174) else minOf(context.dp(228), dialogWidth() - context.dp(48))
        arena.layoutParams = LinearLayout.LayoutParams(-1, height)
    }
}
