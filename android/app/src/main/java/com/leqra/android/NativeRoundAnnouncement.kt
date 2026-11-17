package com.leqra.android

import android.content.Context
import android.content.res.Configuration
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import com.leqra.android.NativeStyle.add
import com.leqra.android.NativeStyle.dp
import com.leqra.core.ArenaSnapshot
import com.leqra.core.RoomRules
import java.util.Locale
import kotlin.math.ceil

internal data class RoundAnnouncement(
    val heading: String,
    val title: String,
    val detail: String,
    val winnerPaint: String? = null,
    val result: Boolean = false,
    val bold: Boolean = true,
)

internal class RoundAnnouncementSequence {
    private var previousPhase = ""
    private var weaponsLiveUntil = 0L

    fun update(
        snapshot: ArenaSnapshot?,
        rules: RoomRules,
        primaryID: Int,
        secondaryID: Int?,
        finishingProjectile: Boolean,
        nowMillis: Long,
    ): RoundAnnouncement? {
        val phase = snapshot?.phase.orEmpty()
        if (phase != "playing") weaponsLiveUntil = 0L
        else if (previousPhase == "countdown") weaponsLiveUntil = nowMillis + 800
        previousPhase = phase
        return when {
            snapshot == null -> null
            phase == "countdown" -> {
                val stage = if (rules.mode == "survival") "WAVE" else "ROUND"
                val round = String.format(Locale.ROOT, "%02d", snapshot.round)
                RoundAnnouncement("$stage $round", ceil(snapshot.phaseTime).toInt().coerceAtLeast(1).toString(), "Bounce. Dodge. Outlast.")
            }
            phase == "playing" && nowMillis < weaponsLiveUntil -> RoundAnnouncement("WEAPONS LIVE", "GO", "")
            phase == "roundOver" && !finishingProjectile -> {
                val winner = winnerPresentation(snapshot, rules, primaryID, secondaryID, member = null)
                val detail = "NEW MAZE IN ${ceil(snapshot.phaseTime).toInt().coerceAtLeast(0)}"
                if (snapshot.winner < 0) RoundAnnouncement("", "ROUND DRAW", detail, result = true)
                else RoundAnnouncement("", "${winner.label} WINS", detail, winner.color, result = true, bold = winner.bold)
            }
            else -> null
        }
    }
}

/** Readable, wrapping announcements centered in the playable portion of the arena. */
internal class NativeRoundAnnouncement(context: Context) : FrameLayout(context) {
    private val sequence = RoundAnnouncementSequence()
    private val card = NativeStyle.column(context, 10).apply { gravity = Gravity.CENTER }
    private val heading = NativeStyle.label(context, "", 10f, NativeStyle.soft, mono = true)
    private val title = NativeStyle.label(context, "", 72f, NativeStyle.accent, true).apply { gravity = Gravity.CENTER }
    private val detail = NativeStyle.label(context, "", 11f, NativeStyle.soft).apply { gravity = Gravity.CENTER }
    private val resultBackground = NativeStyle.background(context, 0xf2192127.toInt(), 6, 0xff34434a.toInt())
    private var current: RoundAnnouncement? = null

    init {
        addView(card, LayoutParams(-2, -2, Gravity.CENTER))
        card.add(heading, width = -2, gap = 5)
        card.add(title, width = -2, gap = 5)
        card.add(detail, width = -2, gap = 0)
        visibility = View.GONE
        isClickable = false
        isFocusable = false
    }

    fun update(session: GameSession, snapshot: ArenaSnapshot) {
        val active = session.screen == Screen.PLAYING && !session.infinity
        val shown = sequence.update(snapshot.takeIf { active }, session.rules, session.localID, session.localID2,
            active && session.finishingProjectilePresentation, android.os.SystemClock.uptimeMillis())
        if (shown == current) return
        current = shown
        visibility = if (shown == null) View.GONE else View.VISIBLE
        if (shown == null) return
        heading.text = shown.heading
        heading.visibility = if (shown.heading.isEmpty()) View.GONE else View.VISIBLE
        title.text = shown.title
        updateTitleSize(shown, resources.configuration)
        title.setTypeface(title.typeface, if (shown.bold) android.graphics.Typeface.BOLD else android.graphics.Typeface.NORMAL)
        title.setTextColor(shown.winnerPaint?.let(NativeStyle::mappedPaint) ?: NativeStyle.accent)
        detail.text = shown.detail
        detail.visibility = if (shown.detail.isEmpty()) View.GONE else View.VISIBLE
        card.background = if (shown.result) resultBackground else null
    }

    fun setSafeArea(left: Int, right: Int, bottom: Int) {
        setPadding(left + context.dp(12), 0, right + context.dp(12), bottom)
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        current?.let { updateTitleSize(it, newConfig) }
    }

    private fun updateTitleSize(shown: RoundAnnouncement, config: Configuration) {
        title.textSize = if (shown.result) 28f else if (config.orientation == Configuration.ORIENTATION_LANDSCAPE) 64f else 96f
    }
}
