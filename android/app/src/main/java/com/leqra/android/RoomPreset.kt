package com.leqra.android

import com.leqra.android.network.ProtocolJson
import com.leqra.core.BotDifficulty
import com.leqra.core.GamePalette
import com.leqra.core.RoomRules
import org.json.JSONArray
import org.json.JSONObject

internal data class RoomPreset(
    val name: String,
    val rules: RoomRules,
    val roster: List<PresetSeat>?,
) {
    fun toJson() = JSONObject()
        .put("name", name)
        .put("rules", ProtocolJson.rules(rules))
        .put("roster", roster?.toRosterJson())

    companion object {
        const val maxCount = 12
        const val maxNameLength = 40

        fun fromJson(json: JSONObject) = RoomPreset(
            json.getString("name"),
            ProtocolJson.roomRules(json.getJSONObject("rules")),
            json.optJSONArray("roster")?.objects()?.map(PresetSeat::fromJson),
        )
    }
}

internal data class PresetSeat(
    val kind: String,
    val name: String,
    val color: Int,
    val team: Int,
    val difficulty: String = "normal",
) {
    fun toJson() = JSONObject()
        .put("kind", kind)
        .put("name", name)
        .put("colorIndex", color)
        .put("team", team)
        .put("difficulty", difficulty)

    companion object {
        fun fromJson(json: JSONObject) = PresetSeat(
            json.getString("kind"),
            json.getString("name"),
            GamePalette.index(json.optInt("colorIndex", GamePalette.colors.indexOf(json.optString("color")).coerceAtLeast(0))),
            json.optInt("team").coerceIn(0, 4),
            json.optString("difficulty").takeIf { it in BotDifficulty.names } ?: "normal",
        )
    }
}

internal fun List<PresetSeat>.toRosterJson() = JSONArray(map(PresetSeat::toJson))

internal fun JSONArray.objects() = (0 until length()).mapNotNull(::optJSONObject)
