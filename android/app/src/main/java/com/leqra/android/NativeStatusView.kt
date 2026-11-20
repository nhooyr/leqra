package com.leqra.android

import android.content.Context
import android.graphics.Typeface
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextUtils
import android.text.style.ForegroundColorSpan
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.leqra.android.NativeStyle.dp
import com.leqra.core.ArenaSnapshot
import com.leqra.core.PilotIdentity
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.roundToInt

internal fun performanceReadout(
    preview: Boolean,
    online: Boolean,
    fps: Int,
    ping: Double?,
): String {
    val fpsValue = if (preview) "—" else fps.toString()
    val pingValue =
        ping?.takeIf { it.isFinite() && it >= 0.0 }?.let { "${it.roundToInt()} ms" } ?: "—"
    return "fps: $fpsValue" + if (preview || online) ", ping: $pingValue" else ""
}

/** Stable three-column arena chrome matching the native iOS status bar. */
internal class NativeStatusView(context: Context, openScores: () -> Unit) : LinearLayout(context) {
    private val title = NativeStyle.label(context, "INFINITY", 10f, NativeStyle.text, mono = true)
    private val count = NativeStyle.label(context, "", 10f, NativeStyle.muted, mono = true)
    private val score = NativeStyle.label(context, "", 10f, NativeStyle.accent, mono = true)
    private val finitePerformance =
        NativeStyle.label(context, "", 10f, NativeStyle.accent, mono = true)
    private val infinityPerformance =
        NativeStyle.label(context, "", 10f, NativeStyle.accent, mono = true)
    private val round = NativeStyle.label(context, "", 10f, NativeStyle.text, mono = true)
    private val clock = NativeStyle.label(context, "", 10f, NativeStyle.accent, mono = true)
    private val scores =
        Button(context).apply {
            text = "LEADERBOARD"
            textSize = 10f
            isAllCaps = false
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(NativeStyle.accent)
            minimumWidth = 0
            minWidth = 0
            minHeight = context.dp(30)
            minimumHeight = context.dp(30)
            setPadding(context.dp(7), 0, context.dp(7), 0)
            background = NativeStyle.background(context, NativeStyle.sunken, 4, 0xff34434a.toInt())
            setOnClickListener { openScores() }
        }
    var textUpdates = 0L
        private set

    private var scoreKey: String? = null

    fun showShowcase(snapshot: ArenaSnapshot, localID: Int, fps: Int, ping: Int, showFPS: Boolean) {
        showTitle("● PUBLIC INFINITY")
        count.value("${snapshot.players} online")
        count.visibility = View.VISIBLE
        val pilot = snapshot.tanks.firstOrNull { it.id == localID }
        score.value("score: ${pilot?.score ?: 0}, rank: #${pilot?.rank ?: 0}")
        score.setTextColor(NativeStyle.paint(pilot?.colorIndex ?: 0))
        displayPerformance(
            infinity = true,
            if (showFPS) performanceReadout(false, true, fps, ping.toDouble()) else "",
        )
        showMode(infinity = true, preview = false)
    }

    private fun showTitle(value: String) {
        title.visibility = if (value.isEmpty()) View.GONE else View.VISIBLE
        if (!TextUtils.equals(title.text, value)) {
            title.text =
                android.text.SpannableString(value).apply {
                    if (value.isNotEmpty())
                        setSpan(
                            ForegroundColorSpan(NativeStyle.accent),
                            0,
                            1,
                            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                        )
                }
            textUpdates++
        }
    }

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setBackgroundColor(NativeStyle.surface)
        setPadding(context.dp(12), context.dp(6), context.dp(12), context.dp(6))
        minimumHeight = context.dp(39)
        val left =
            LinearLayout(context).apply {
                orientation = VERTICAL
                addView(title, LayoutParams(-1, -2))
                addView(count, LayoutParams(-1, -2).apply { topMargin = context.dp(3) })
                addView(finitePerformance, LayoutParams(-1, -2).apply { topMargin = context.dp(3) })
            }
        val middle =
            LinearLayout(context).apply {
                orientation = VERTICAL
                gravity = Gravity.CENTER
                score.gravity = Gravity.CENTER
                infinityPerformance.gravity = Gravity.CENTER
                addView(
                    infinityPerformance,
                    LayoutParams(-1, -2).apply { bottomMargin = context.dp(2) },
                )
                addView(score, LayoutParams(-1, -2))
            }
        addView(left, LayoutParams(0, -2, 1f).apply { marginEnd = context.dp(6) })
        addView(middle, LayoutParams(0, -2, 1.2f).apply { marginEnd = context.dp(6) })
        addView(round, LayoutParams(-2, -2).apply { marginEnd = context.dp(6) })
        addView(clock, LayoutParams(-2, -2).apply { marginEnd = context.dp(6) })
        addView(scores, LayoutParams(-2, context.dp(30)))
    }

    private fun showMode(infinity: Boolean, preview: Boolean) {
        val height = context.dp(if (preview) 52 else 39)
        if (minimumHeight != height) minimumHeight = height
        val finiteVisibility = if (infinity) View.GONE else View.VISIBLE
        round.visibility = finiteVisibility
        clock.visibility = finiteVisibility
        scores.visibility = if (infinity) View.VISIBLE else View.GONE
        scores.contentDescription = "Leaderboard"
    }

    private fun displayPerformance(infinity: Boolean, performance: String) {
        finitePerformance.visibility =
            if (!infinity && performance.isNotEmpty()) View.VISIBLE else View.GONE
        infinityPerformance.visibility =
            if (infinity && performance.isNotEmpty()) View.VISIBLE else View.GONE
        if (infinity) infinityPerformance.value(performance)
        else finitePerformance.value(performance)
    }

    fun update(session: GameSession, fps: Int) {
        val preview = session.screen != Screen.PLAYING
        val public = session.room?.optBoolean("infinityPublic") ?: session.publicSelected
        val infinity = if (preview) public || session.rules.infinity else session.infinity
        val name =
            if (preview) {
                if (infinity) if (public) "PUBLIC INFINITY" else "INFINITY" else ""
            } else if (infinity) {
                if (session.online && (session.room == null || public)) "PUBLIC INFINITY"
                else "INFINITY"
            } else
                when (session.snapshot.phase) {
                    "playing" -> "LIVE ARENA"
                    "countdown" -> "GET READY"
                    "roundOver" -> "ROUND COMPLETE"
                    else -> "MATCH COMPLETE"
                }
        val titleText =
            if (name.isEmpty()) ""
            else "● ${if (infinity && session.spectating && !preview) "SPECTATING" else name}"
        showTitle(titleText)
        showMode(infinity, preview)
        val onlineCount =
            if (preview && public && infinity) session.publicStatus?.players
            else if (!preview && infinity && session.online) session.snapshot.players else null
        count.value(onlineCount?.let { "$it online" } ?: "")
        count.visibility = if (onlineCount == null) View.GONE else View.VISIBLE
        displayPerformance(
            infinity,
            if (session.showFPS) performanceReadout(preview, session.online, fps, session.latency)
            else "",
        )
        val pilot =
            session.snapshot.tanks.firstOrNull {
                it.id == if (session.spectating) session.followingID else session.localID
            }
        if (infinity) {
            scoreKey = null
            val following = session.spectating && !preview
            val followingName =
                session.snapshot.leaderboard
                    .firstOrNull { it.id == session.followingID }
                    ?.let { PilotIdentity.leaderboardLabel(it.name, it.bot) }
                    ?: pilot?.let { PilotIdentity.leaderboardLabel(it.name, it.bot) }
            score.value(
                if (following)
                    followingName?.let {
                        (if (pilot == null) "WAITING FOR " else "FOLLOWING ") + it
                    } ?: "WAITING FOR TANKS"
                else
                    "score: ${if(preview) 0 else pilot?.score ?: 0}, rank: #${if(preview) 0 else pilot?.rank ?: 0}",
            )
            score.setTextColor(
                if (following) NativeStyle.soft
                else
                    NativeStyle.paint(
                        if (preview) session.colorIndex
                        else pilot?.colorIndex ?: session.colorIndex,
                    ),
            )
        } else {
            val teams = session.rules.teamMode == "teams"
            val entries = session.snapshot.leaderboard
            val key =
                "$teams:" +
                    entries.joinToString { "${it.id}:${it.team}:${it.colorIndex}:${it.score}" }
            if (key != scoreKey) {
                scoreKey = key
                score.setTextColor(NativeStyle.text)
                val values = SpannableStringBuilder()
                val shownTeams = HashSet<Int>()
                var shown = 0
                for (entry in entries) {
                    if (teams && (entry.team <= 0 || !shownTeams.add(entry.team))) continue
                    if (values.isNotEmpty()) values.append(" ")
                    val start = values.length
                    values.append("▪${entry.score}")
                    values.setSpan(
                        ForegroundColorSpan(NativeStyle.paint(entry.colorIndex)),
                        start,
                        start + 1,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
                    if (++shown >= 8) break
                }
                score.text = values
                textUpdates++
            }
            val seconds =
                maxOf(
                    0,
                    ceil(
                            if (preview) session.rules.timeLimit.toDouble()
                            else session.snapshot.roundClock,
                        )
                        .toInt(),
                )
            round.value(String.format(Locale.ROOT, "ROUND %02d", maxOf(1, session.snapshot.round)))
            clock.value(String.format(Locale.ROOT, "%02d:%02d", seconds / 60, seconds % 60))
        }
    }

    private fun TextView.value(value: CharSequence) {
        if (!TextUtils.equals(text, value)) {
            text = value
            textUpdates++
        }
    }
}
