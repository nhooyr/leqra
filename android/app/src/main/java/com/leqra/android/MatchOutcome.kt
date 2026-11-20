package com.leqra.android

import com.leqra.core.ArenaSnapshot
import com.leqra.core.GamePalette
import com.leqra.core.PilotIdentity
import com.leqra.core.RoomRules
import com.leqra.core.isWinningSide

internal data class MatchOutcome(
    val title: String,
    val detail: String = "",
    val winnerColor: String? = null,
    val boldTitle: Boolean = true,
)

internal data class WinnerPresentation(val label: String, val color: String?, val bold: Boolean)

internal fun winnerPresentation(
    snapshot: ArenaSnapshot,
    rules: RoomRules,
    primaryID: Int,
    secondaryID: Int?,
    member: Long?,
): WinnerPresentation {
    val result = snapshot.result
    val report = snapshot.matchStats
    val reportedWinner = if (result == null) report?.players?.firstOrNull { it.winner } else null
    val winnerID = result?.id ?: snapshot.winner
    val tank = snapshot.tanks.firstOrNull { it.id == winnerID }
    val archived = snapshot.leaderboard.firstOrNull { it.id == winnerID }
    val team = result?.team ?: reportedWinner?.team ?: tank?.team ?: 0
    val color: String?
    val label: String
    val boldWinner: Boolean
    if (team > 0) {
        label = rules.teamNames.getOrElse(team - 1) { "Team $team" }
        color =
            GamePalette.colors[GamePalette.index(rules.teamColors.getOrElse(team - 1) { team - 1 })]
        boldWinner = true
    } else {
        val name =
            result?.name?.takeIf(String::isNotBlank)
                ?: reportedWinner?.name
                ?: tank?.name
                ?: archived?.name
        val bot = reportedWinner?.bot ?: tank?.bot ?: archived?.bot ?: false
        val seat =
            reportedWinner?.localSeat(member)
                ?: when {
                    bot || winnerID < 0 -> 0
                    winnerID == primaryID -> 1
                    winnerID == secondaryID -> 2
                    else -> 0
                }
        label = name?.let { PilotIdentity.label(it, bot, seat) } ?: "TANK"
        color =
            reportedWinner?.color
                ?: if (name != null)
                    GamePalette.colors[
                            GamePalette.index(tank?.colorIndex ?: archived?.colorIndex ?: 0)]
                else null
        boldWinner = seat > 0 || name == null
    }
    return WinnerPresentation(label, color, boldWinner)
}

internal fun matchOutcome(
    snapshot: ArenaSnapshot,
    rules: RoomRules,
    primaryID: Int,
    secondaryID: Int?,
    member: Long?,
    online: Boolean,
): MatchOutcome {
    val report = snapshot.matchStats
    val winner = winnerPresentation(snapshot, rules, primaryID, secondaryID, member)
    val win = "${winner.label} WINS"
    if (snapshot.result != null)
        return MatchOutcome(win, winnerColor = winner.color, boldTitle = winner.bold)
    snapshot.objectives?.survival?.let {
        return MatchOutcome(
            if (it.status == "won") "SURVIVAL COMPLETE" else "SQUAD DOWN.",
            "Wave ${it.wave}, ${it.wavesCleared} cleared",
            winner.color,
        )
    }
    if (snapshot.winner < 0 && report?.players?.any { it.winner } != true)
        return MatchOutcome("MATCH DRAW")
    val localParticipants = report?.players.orEmpty().filter { it.localSeat(member) != 0 }
    val lost =
        if (online) localParticipants.isNotEmpty() && localParticipants.none { it.winner }
        else snapshot.isWinningSide(primaryID) == false
    return if (lost) MatchOutcome("DEFEAT", win, winner.color)
    else MatchOutcome(win, winnerColor = winner.color, boldTitle = winner.bold)
}
