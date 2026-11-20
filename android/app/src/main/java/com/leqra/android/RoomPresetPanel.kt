package com.leqra.android

import android.content.Context
import android.text.Editable
import android.text.TextWatcher
import com.leqra.android.NativeStyle.add
import com.leqra.android.NativeStyle.button
import com.leqra.android.NativeStyle.column
import com.leqra.android.NativeStyle.field
import com.leqra.android.NativeStyle.label
import com.leqra.android.NativeStyle.row
import com.leqra.android.NativeStyle.weighted

internal fun roomPresetPanel(context: Context, session: GameSession, onLoaded: () -> Unit) =
    column(context, 16).apply {
        add(label(context, "ROOM PRESETS.", 24f, NativeStyle.accent, bold = true))
        add(
            label(
                context,
                "Save this room's rules and bots for another battle.",
                12f,
                NativeStyle.soft,
            ),
        )
        val name = field(context, "", "Preset name", RoomPreset.maxNameLength)
        add(name)
        val saved = column(context)
        fun showSavedPresets() {
            saved.removeAllViews()
            session.presets.forEach { preset ->
                saved.add(
                    row(context).apply {
                        weighted(label(context, preset.name, 13f))
                        add(
                            button(
                                    context,
                                    "LOAD",
                                    {
                                        if (session.loadPreset(preset)) onLoaded()
                                    },
                                )
                                .apply {
                                    isEnabled = session.canLoadPreset
                                    alpha = if (isEnabled) 1f else .45f
                                    contentDescription = "Load ${preset.name}"
                                },
                            width = 70,
                            gap = 0,
                        )
                    },
                )
            }
        }
        val save =
            button(
                    context,
                    "SAVE ROOM",
                    {
                        if (session.savePreset(name.text.toString())) {
                            name.text.clear()
                            showSavedPresets()
                        }
                    },
                )
                .apply {
                    background =
                        NativeStyle.background(context, NativeStyle.accent, 6, NativeStyle.accent)
                    setTextColor(NativeStyle.page)
                }
        fun updateSave() {
            save.isEnabled = session.isHost && !session.releasingCallsign && name.text.isNotBlank()
            save.alpha = if (save.isEnabled) 1f else .45f
        }
        name.addTextChangedListener(
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
                ) = updateSave()

                override fun afterTextChanged(value: Editable?) = Unit
            },
        )
        updateSave()
        add(save)
        add(saved, gap = 0)
        showSavedPresets()
    }
