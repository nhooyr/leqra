package com.leqra.android

import android.app.Dialog
import android.content.Context
import android.os.Build
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

internal const val QUICK_TOUR_SEEN = "quickTourSeen"

internal class QuickTour(context: Context, objective: String) : Dialog(context) {
    private val pages = listOf(
        "Drive and aim" to
            "Drag the left stick to drive. Touch near your tank to aim without moving.",
        "Fire" to
            ("Hold the right Fire button to shoot. After throwing a grenade, release Fire, then tap to detonate. " +
                "Release again before throwing another grenade."),
        "Play the objective" to
            ("$objective Open the sidebar for the current room’s weapon and power-up guide. " +
                "Pause to review controls or return to the ready room."),
    )
    private var page = 0

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
        val body = column(context).apply {
            add(title, gap = 18)
            add(message, gap = 18)
            add(progress, gap = 0)
        }
        val scroll = ScrollView(context).apply { addView(body) }
        panel.addView(scroll, LinearLayout.LayoutParams(-1, -2, 1f).apply { bottomMargin = context.dp(18) })

        val next = button(context, "NEXT", {}, role = "primary")
        panel.add(next, gap = 0)
        fun update() {
            val (heading, instructions) = pages[page]
            title.text = heading
            message.text = instructions
            progress.text = "${page + 1} / ${pages.size}"
            next.text = if (page == pages.lastIndex) "DONE" else "NEXT"
            scroll.scrollTo(0, 0)
        }
        next.setOnClickListener {
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

    fun resize() {
        val width = minOf(context.resources.displayMetrics.widthPixels - context.dp(24), context.dp(650))
        window?.setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT)
    }
}
