package com.leqra.android

import android.content.Context
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import com.leqra.android.NativeStyle.dp
import com.leqra.core.ArenaObjectives
import com.leqra.core.RoomRules

internal data class ObjectiveMessage(
    val text: String,
    val paintIndex: Int? = null,
    val urgent: Boolean = false,
)

internal fun objectiveMessages(
    objectives: ArenaObjectives?,
    rules: RoomRules,
): List<ObjectiveMessage> =
    when (objectives?.mode) {
        "survival" ->
            objectives.survival
                ?.let {
                    listOf(
                        ObjectiveMessage("WAVE ${it.wave}"),
                        ObjectiveMessage("${it.enemiesRemaining} ENEMIES"),
                    )
                }
                .orEmpty()
        "ctf" ->
            objectives.flags.take(2).map { flag ->
                val status =
                    when {
                        flag.home -> "FLAG HOME"
                        flag.carrier >= 0 -> "FLAG CARRIED"
                        else -> "FLAG DROPPED"
                    }
                ObjectiveMessage(
                    "TEAM ${flag.team}: $status",
                    rules.teamColors.getOrElse(flag.team - 1) { flag.team - 1 },
                )
            }
        "koth" ->
            buildList {
                add(
                    ObjectiveMessage(
                        when {
                            objectives.contested -> "HILL CONTESTED"
                            objectives.owner == 0 -> "HILL NEUTRAL"
                            else -> "HILL CONTROLLED"
                        },
                    ),
                )
                if (objectives.suddenDeath) add(ObjectiveMessage("SUDDEN DEATH", urgent = true))
            }
        else -> emptyList()
    }

internal class NativeObjectiveView(context: Context) : LinearLayout(context) {
    private val labels =
        List(2) { NativeStyle.label(context, "", 10f, NativeStyle.soft, mono = true) }
    private var current: List<ObjectiveMessage> = emptyList()

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        visibility = View.GONE
        setPadding(context.dp(12), context.dp(5), context.dp(12), context.dp(5))
        setBackgroundColor(NativeStyle.surface)
        labels.forEachIndexed { index, label ->
            label.gravity = if (index == 0) Gravity.START else Gravity.END
            addView(
                label,
                LayoutParams(0, -2, 1f).apply { if (index == 0) marginEnd = context.dp(8) },
            )
        }
    }

    fun update(objectives: ArenaObjectives?, rules: RoomRules) {
        val messages = objectiveMessages(objectives, rules)
        if (current == messages) return
        current = messages
        visibility = if (messages.isEmpty()) View.GONE else View.VISIBLE
        labels.forEachIndexed { index, label ->
            val message = messages.getOrNull(index)
            label.visibility = if (message == null) View.GONE else View.VISIBLE
            if (message != null) {
                label.text = message.text
                label.setTextColor(
                    if (message.urgent) NativeStyle.danger
                    else message.paintIndex?.let(NativeStyle::paint) ?: NativeStyle.soft,
                )
            }
        }
    }
}
