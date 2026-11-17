package com.leqra.core

data class MatchReport(
    val mode: String,
    val duration: Double,
    val rounds: Int,
    val players: List<MatchPlayer>,
)

/** Match statistics use persistent room members because tank seats can be reused. */
data class MatchPlayer(
    val member: Long,
    val controllerMember: Long?,
    val name: String,
    val color: String,
    val team: Int,
    val score: Int,
    val kind: String,
    val eliminations: Int,
    val deaths: Int,
    val selfDestructs: Int,
    val captures: Int,
    val flagReturns: Int,
    val hillSeconds: Double,
    val winner: Boolean,
) {
    val bot: Boolean get() = kind == "bot"

    fun localSeat(ownMember: Long?): Int {
        if (bot || ownMember == null || (member != ownMember && controllerMember != ownMember)) return 0
        return if (kind == "local") 2 else 1
    }
}
