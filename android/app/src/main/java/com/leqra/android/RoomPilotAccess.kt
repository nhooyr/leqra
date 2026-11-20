package com.leqra.android

import com.leqra.core.RoomRules
import org.json.JSONObject

internal fun JSONObject.roomRosterMembers(): List<JSONObject> =
    optJSONArray("players")?.objects().orEmpty() + optJSONArray("spectators")?.objects().orEmpty()

internal data class RoomPilotAccess(
    val localSeat: Int,
    val bot: Boolean,
    val canRenameBot: Boolean,
    val canPaint: Boolean,
    val teamCount: Int,
    val canToggleSpectating: Boolean,
    val canRemove: Boolean,
)

internal fun roomPilotAccess(
    member: JSONObject,
    controller: Int?,
    host: Boolean,
    setupOpen: Boolean,
    matchmaking: Boolean,
    rules: RoomRules,
): RoomPilotAccess {
    val kind = member.optString("kind")
    val bot = kind == "bot" || member.optBoolean("bot")
    val id = member.optInt("id", -1)
    val spectating = member.optBoolean("spectating")
    val seat =
        when {
            controller == null || bot -> 0
            id == controller -> 1
            kind == "local" && member.optInt("owner", -1) == controller -> 2
            else -> 0
        }
    val canConfigure = host && setupOpen
    val teamCount =
        if (!canConfigure || spectating || rules.teamMode != "teams") 0
        else if (!rules.infinity && rules.mode == "survival") 1
        else if (!rules.infinity && rules.mode == "ctf") 2 else 4
    return RoomPilotAccess(
        localSeat = seat,
        bot = bot,
        canRenameBot = canConfigure && bot,
        canPaint = setupOpen && !spectating && rules.teamMode == "ffa" && (seat > 0 || host && bot),
        teamCount = teamCount,
        canToggleSpectating = seat > 0,
        canRemove = host && !matchmaking && seat != 1,
    )
}
