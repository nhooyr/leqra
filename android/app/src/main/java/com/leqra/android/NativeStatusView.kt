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
import kotlin.math.ceil

/** Stable three-column arena chrome matching the native iOS status bar. */
internal class NativeStatusView(context: Context, openScores: () -> Unit) : LinearLayout(context) {
    private val title = NativeStyle.label(context, "INFINITY", 10f, NativeStyle.text, mono = true)
    private val count = NativeStyle.label(context, "", 10f, NativeStyle.muted, mono = true)
    private val score = NativeStyle.label(context, "", 10f, NativeStyle.accent, mono = true)
    private val details = NativeStyle.label(context, "", 10f, NativeStyle.muted, mono = true)
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
            }
        val middle =
            LinearLayout(context).apply {
                orientation = VERTICAL
                gravity = Gravity.CENTER
                score.gravity = Gravity.CENTER
                details.gravity = Gravity.CENTER
                addView(score, LayoutParams(-1, -2))
                addView(details, LayoutParams(-1, -2).apply { topMargin = context.dp(3) })
            }
        addView(left, LayoutParams(0, -2, 1f).apply { marginEnd = context.dp(6) })
        addView(middle, LayoutParams(0, -2, 1.2f).apply { marginEnd = context.dp(6) })
        addView(scores, LayoutParams(-2, context.dp(30)))
    }

    fun update(session: GameSession, fps: Int) {
        val preview = session.screen != Screen.PLAYING
        val infinity =
            if (preview) session.publicSelected || session.rules.infinity else session.infinity
        val public = session.room?.optBoolean("infinityPublic") ?: session.publicSelected
        val name =
            if (preview) {
                if (infinity) if (public) "PUBLIC INFINITY" else "INFINITY" else "READY ROOM"
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
        val titleText = "● ${if (session.spectating && !preview) "SPECTATING" else name}"
        if (!TextUtils.equals(title.text, titleText)) {
            title.text =
                android.text.SpannableString(titleText).apply {
                    setSpan(
                        ForegroundColorSpan(NativeStyle.accent),
                        0,
                        1,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
                }
            textUpdates++
        }
        val onlineCount =
            if (preview && public && infinity) session.publicStatus?.players
            else if (!preview && infinity && session.online) session.snapshot.players else null
        count.value(onlineCount?.let { "$it online" } ?: "")
        count.visibility = if (onlineCount == null) View.GONE else View.VISIBLE
        val pilot = session.snapshot.tanks.firstOrNull { it.id == if (session.spectating) session.followingID else session.localID }
        if (infinity) {
            scoreKey = null
            score.value(
                if (session.spectating && !preview) session.snapshot.leaderboard.firstOrNull { it.id == session.followingID }?.let { "Following ${com.leqra.core.PilotIdentity.leaderboardLabel(it.name, it.bot)}" } ?: "Waiting for tanks"
                else "score: ${if(preview) 0 else pilot?.score ?: 0}, rank: #${if(preview) 0 else pilot?.rank ?: 0}",
            )
            score.setTextColor(NativeStyle.paint(pilot?.colorIndex ?: session.colorIndex))
            val performance =
                listOfNotNull(
                        if (session.showFPS && !preview) "$fps fps" else null,
                        if (
                            session.online && session.latency > 0 ||
                                preview && public && session.latency > 0
                        )
                            "${session.latency.toInt()} ms"
                        else null,
                    )
                    .joinToString(" · ")
            details.value(performance)
            details.visibility = if (performance.isBlank()) View.GONE else View.VISIBLE
            scores.value("LEADERBOARD")
            scores.contentDescription = "Leaderboard"
        } else {
            val tanks = session.snapshot.tanks
            val key = tanks.joinToString { "${it.id}:${it.team}:${it.colorIndex}:${it.score}" }
            if (key != scoreKey) {
                scoreKey = key
                val values = SpannableStringBuilder()
                val shownTeams = HashSet<Int>()
                var shown = 0
                for (tank in tanks) {
                    if (
                        session.rules.teamMode == "teams" &&
                            tank.team > 0 &&
                            !shownTeams.add(tank.team)
                    )
                        continue
                    if (values.isNotEmpty()) values.append("  ")
                    val start = values.length
                    values.append("▪ ${tank.score}")
                    values.setSpan(
                        ForegroundColorSpan(NativeStyle.paint(tank.colorIndex)),
                        start,
                        values.length,
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
            details.value(
                "ROUND ${maxOf(1,session.snapshot.round).toString().padStart(2,'0')} · ${seconds/60}:${(seconds%60).toString().padStart(2,'0')}",
            )
            details.visibility = View.VISIBLE
            scores.value("≡")
            scores.contentDescription = "Standings"
        }
    }

    private fun TextView.value(value: CharSequence) {
        if (!TextUtils.equals(text, value)) {
            text = value
            textUpdates++
        }
    }
}
