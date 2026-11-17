package com.leqra.android

import com.leqra.core.ArenaSnapshot
import com.leqra.core.ArenaTank
import com.leqra.core.GamePalette
import com.leqra.core.RoomRules
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RoundAnnouncementTest {
    @Test
    fun roundsShowCountdownBriefGoAndWrapUpAfterTheFinalProjectile() {
        val sequence = RoundAnnouncementSequence()
        val countdown = ArenaSnapshot(phase = "countdown", phaseTime = 2.1, round = 4)
        fun update(snapshot: ArenaSnapshot?, now: Long, holding: Boolean = false) =
            sequence.update(snapshot, RoomRules(), primaryID = 1, secondaryID = 2, finishingProjectile = holding, nowMillis = now)

        assertEquals(RoundAnnouncement("ROUND 04", "3", "Bounce. Dodge. Outlast."), update(countdown, 0))
        val playing = countdown.copy(phase = "playing")
        assertEquals(RoundAnnouncement("WEAPONS LIVE", "GO", ""), update(playing, 100))
        assertEquals("GO", update(playing, 899)?.title)
        assertNull(update(playing, 900))

        val roundOver = playing.copy(phase = "roundOver", phaseTime = 1.1, winner = 2,
            tanks = listOf(ArenaTank(id = 2, name = "Wing", colorIndex = 5)))
        assertNull(update(roundOver, 1000, holding = true))
        assertEquals(RoundAnnouncement("", "Wing (P2) WINS", "NEW MAZE IN 2", GamePalette.colors[5], result = true), update(roundOver, 1100))
        assertEquals("ROUND DRAW", update(roundOver.copy(winner = -1), 1200)?.title)
        assertNull(update(null, 1300))
        assertNull(update(playing, 1400))
    }
}
