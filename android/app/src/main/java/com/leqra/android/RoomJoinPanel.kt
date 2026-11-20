package com.leqra.android

import android.content.Context
import android.graphics.Typeface
import android.net.Uri
import android.text.Editable
import android.text.TextWatcher
import com.leqra.android.NativeStyle.add
import com.leqra.android.NativeStyle.button
import com.leqra.android.NativeStyle.column
import com.leqra.android.NativeStyle.dp
import com.leqra.android.NativeStyle.field
import com.leqra.android.NativeStyle.label
import com.leqra.android.NativeStyle.row
import com.leqra.android.NativeStyle.weighted
import com.leqra.core.Callsigns

internal const val roomNameLimit = 128

internal data class RoomJoinDraft(val code: String = "", val spectating: Boolean = false)

internal data class RoomJoinRequest(val code: String, val spectate: Boolean) {
    companion object {
        fun fromInput(value: String, spectate: Boolean): RoomJoinRequest? {
            val input = value.trim()
            val uri =
                Uri.parse(input).takeIf {
                    it.isHierarchical && it.scheme in listOf("http", "https")
                }
            return if (uri?.getQueryParameter("room") != null) fromInvite(uri, spectate)
            else request(input, spectate)
        }

        fun fromInvite(uri: Uri, spectate: Boolean = false): RoomJoinRequest? {
            if (!uri.isHierarchical) return null
            val code = uri.getQueryParameter("room") ?: return null
            return request(code.trim(), spectate || uri.getQueryParameter("spectate") == "1")
        }

        private fun request(code: String, spectate: Boolean): RoomJoinRequest? =
            if (code.isEmpty() || code.codePointCount(0, code.length) > roomNameLimit) null
            else RoomJoinRequest(code, spectate)
    }
}

internal fun roomJoinPanel(
    context: Context,
    callsign: String,
    draft: RoomJoinDraft,
    canJoin: () -> Boolean,
    openAccount: (RoomJoinDraft) -> Unit,
    joinRoom: (String, RoomJoinRequest) -> Unit,
) =
    column(context, 16).apply {
        add(label(context, "Find a room.", 24f, NativeStyle.accent, bold = true))
        val pilot =
            field(context, callsign, "Callsign").apply { contentDescription = "P1 callsign" }
        val code =
            field(context, draft.code, "Room name or invite link", 2048).apply {
                contentDescription = "Room name or code"
            }
        val spectator =
            NativeStyle.toggle(context).apply {
                text = "Spectate"
                textSize = 13f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(NativeStyle.text)
                isChecked = draft.spectating
            }
        add(label(context, "CALLSIGN", 10f, NativeStyle.muted, mono = true))
        add(
            row(context).apply {
                weighted(pilot)
                add(
                    button(
                            context,
                            "Account",
                            {
                                openAccount(
                                    RoomJoinDraft(code.text.toString(), spectator.isChecked),
                                )
                            },
                        )
                        .apply { contentDescription = "P1 account key" },
                    width = -2,
                    gap = 0,
                )
            },
        )
        val feedback =
            label(context, "", 11f, NativeStyle.danger).apply {
                minHeight = context.dp(14)
            }
        add(feedback)
        add(label(context, "ROOM NAME OR CODE", 10f, NativeStyle.muted, mono = true))
        add(code)
        add(spectator)
        val action =
            button(
                context,
                "JOIN →",
                {
                    val name = pilot.text.toString().trim()
                    if (canJoin() && name.isNotEmpty() && !Callsigns.botReserved(name))
                        RoomJoinRequest.fromInput(code.text.toString(), spectator.isChecked)?.let {
                            joinRoom(name, it)
                        }
                },
                role = "primary",
            )
        add(action)
        val help = label(context, "", 11f, NativeStyle.soft)
        add(help, gap = 0)
        fun update() {
            val name = pilot.text.toString().trim()
            val reserved = Callsigns.botReserved(name)
            val request = RoomJoinRequest.fromInput(code.text.toString(), spectator.isChecked)
            val watching = request?.spectate ?: spectator.isChecked
            action.text = if (watching) "WATCH →" else "JOIN →"
            action.isEnabled = request != null && name.isNotEmpty() && !reserved && canJoin()
            action.alpha = if (action.isEnabled) 1f else .45f
            feedback.text = if (reserved) Callsigns.botNamespaceMessage else ""
            help.text =
                if (watching) "Join as a spectator without a tank."
                else "Missing rooms are created with the joining pilot as host."
        }
        val updateInput =
            object : TextWatcher {
                override fun beforeTextChanged(
                    value: CharSequence?,
                    start: Int,
                    count: Int,
                    after: Int,
                ) = Unit

                override fun onTextChanged(
                    value: CharSequence?,
                    start: Int,
                    before: Int,
                    count: Int,
                ) = update()

                override fun afterTextChanged(value: Editable?) = Unit
            }
        code.addTextChangedListener(updateInput)
        pilot.addTextChangedListener(updateInput)
        spectator.setOnCheckedChangeListener { _, _ -> update() }
        update()
    }
