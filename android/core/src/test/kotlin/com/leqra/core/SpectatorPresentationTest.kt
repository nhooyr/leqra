package com.leqra.core

import org.junit.Assert.*
import org.junit.Test

class SpectatorPresentationTest {
    private fun view(tick: Long, following: Int, x: Double, hp: Int = 1, spawn: Int = 1) =
        ArenaSnapshot(
            tick = tick,
            generation = 4,
            spectating = true,
            following = following,
            tanks =
                listOf(ArenaTank(id = following, x = x, y = 200.0, hp = hp, spawnSerial = spawn)),
            leaderboard = (1..24).map { LeaderboardEntry(it, "Tank $it", 25 - it, bot = it > 2) },
        )

    @Test
    fun watchingInterpolatesAllTanksWithoutPredictingOrSendingInputs() {
        val timeline = OnlinePresentation(localID = -1)
        timeline.accept(view(100, 1, 100.0), 0.0)
        timeline.accept(view(102, 1, 102.0), 2.0 / 60)
        var sent = 0
        var frame = view(100, 1, 0.0)
        repeat(24) { index ->
            frame =
                timeline.render(
                    1.0 / 120,
                    GameInput(forward = true, fire = true),
                    index / 120.0,
                    send = { sent++ },
                )!!
        }
        assertEquals(0, sent)
        assertEquals(0, timeline.bufferedAcknowledgementCount)
        assertEquals(0, timeline.bufferedFrameCount)
        assertTrue(frame.spectating)
        assertEquals(24, frame.leaderboard.size)
        assertEquals(1, frame.following)
        assertTrue(frame.tanks.single().x >= 100.0)
    }

    @Test
    fun switchingFrozenViewAtTheSameTickReplacesCachedGeometryAndEmptyViewIsStable() {
        val timeline = OnlinePresentation(localID = -1)
        timeline.accept(view(100, 1, 100.0), 0.0)
        timeline.render(0.0, GameInput(), 0.0, send = {})
        timeline.accept(view(100, 19, 19000.0), .1)
        val selected = timeline.render(0.0, GameInput(), .1, send = {})!!
        assertEquals(19, selected.following)
        assertEquals(19, selected.tanks.single().id)
        assertEquals(19000.0, selected.tanks.single().x, 0.0)
        timeline.accept(view(100, 0, 0.0).copy(tanks = emptyList(), leaderboard = emptyList()), .2)
        val empty =
            timeline.render(
                .01,
                GameInput(fire = true),
                .2,
                send = { fail("Viewer input escaped") },
            )!!
        assertEquals(0, empty.following)
        assertTrue(empty.tanks.isEmpty())
        assertTrue(empty.leaderboard.isEmpty())
    }

    @Test
    fun deathKeepsFollowingAndRespawnNeverInterpolatesTheOldLife() {
        val timeline = OnlinePresentation(localID = -1)
        timeline.accept(view(100, 7, 100.0), 0.0)
        timeline.accept(view(102, 7, 100.0, hp = 0), .033)
        val dead = timeline.render(.01, GameInput(), .04, send = {})!!
        assertEquals(7, dead.following)
        assertEquals(0, dead.tanks.single().hp)
        timeline.accept(view(104, 7, 9000.0, spawn = 2), .067)
        val revived = timeline.render(.01, GameInput(), .08, send = {})!!
        assertEquals(7, revived.following)
        assertEquals(9000.0, revived.tanks.single().x, 0.0)
    }
}
