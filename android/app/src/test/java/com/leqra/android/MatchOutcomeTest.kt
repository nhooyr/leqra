package com.leqra.android

import com.leqra.core.ArenaObjectives
import com.leqra.core.ArenaSnapshot
import com.leqra.core.ArenaSurvival
import com.leqra.core.ArenaTank
import com.leqra.core.GamePalette
import com.leqra.core.MatchPlayer
import com.leqra.core.MatchReport
import com.leqra.core.RoomRules
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class MatchOutcomeTest {
    @Test
    fun resultsDistinguishDrawDefeatAndSurvivalOutcome() {
        val rules = RoomRules()
        val tanks = listOf(ArenaTank(id = 1, name = "Pilot"), ArenaTank(id = 2, name = "RUST", bot = true, colorIndex = 2))
        val match = ArenaSnapshot(tanks = tanks)
        assertEquals("MATCH DRAW", matchOutcome(match, rules, 1, null, null, false).title)
        val loss = matchOutcome(match.copy(winner = 2), rules, 1, null, null, false)
        assertEquals(MatchOutcome("DEFEAT", "Bot Rust WINS", GamePalette.colors[2]), loss)
        val survival = match.copy(objectives = ArenaObjectives(survival = ArenaSurvival(wave = 4, wavesCleared = 3)))
        assertEquals(MatchOutcome("SQUAD DOWN.", "Wave 4, 3 cleared"), matchOutcome(survival, rules, 1, null, null, false))
        survival.objectives!!.survival!!.status = "won"
        assertEquals("SURVIVAL COMPLETE", matchOutcome(survival, rules, 1, null, null, false).title)
    }

    @Test
    fun reportWinnerUsesStableMemberIdentityInsteadOfAnActiveSeat() {
        val player = MatchPlayer(34, 30, "Wing", GamePalette.colors[5], 0, 5, "local", 4, 1, 0, 0, 0, 0.0, true)
        val match = ArenaSnapshot(matchStats = MatchReport("elimination", 61.0, 5, listOf(player)))
        val own = matchOutcome(match, RoomRules(), 1, null, 30, true)
        assertEquals(MatchOutcome("Wing (P2) WINS", winnerColor = GamePalette.colors[5]), own)
        val remote = matchOutcome(match, RoomRules(), 1, 2, 31, true)
        assertEquals("Wing WINS", remote.title)
        assertFalse(remote.boldTitle)
    }
}
