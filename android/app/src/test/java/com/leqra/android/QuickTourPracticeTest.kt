package com.leqra.android

import com.leqra.android.audio.AudioCue
import com.leqra.android.audio.AudioEventRouter
import com.leqra.core.GameInput
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class QuickTourPracticeTest {
    @Test
    fun movementAdvancesOnSubTickFramesAtHighRefresh() {
        val practice = QuickTourPractice()
        val drive = GameInput(stickX = 1.0)
        val frame = 1.0 / 120
        var previousX = practice.advance(drive, 0.0, nowSeconds = 0.0).tanks.first().x
        for (index in 1..12) {
            val rendered = practice.advance(drive, frame, nowSeconds = index * frame).tanks.first()
            assertTrue("Movement advances between physics ticks", rendered.x > previousX)
            previousX = rendered.x
        }
    }

    @Test
    fun aimingInPlaceDoesNotUnlockDrivingAndFiringRequiresALiveProjectile() {
        val practice = QuickTourPractice()
        val initial = practice.advance(GameInput(), 0.0)
        val pilot = initial.tanks.single()
        assertTrue(initial.world!!.walls.isNotEmpty())
        assertTrue(pilot.name.isEmpty())

        val aimed = practice.advance(GameInput(stickY = 1.0, aimOnly = true, snapAim = true, fire = true), 1.0 / 60)
        assertEquals(pilot.x, aimed.tanks.single().x, 0.0)
        assertEquals(pilot.y, aimed.tanks.single().y, 0.0)
        assertTrue(aimed.tanks.single().angle > 1.0)
        assertTrue(aimed.bullets.isEmpty())
        assertFalse(practice.moved)
        assertFalse(practice.fired)

        repeat(12) { practice.advance(GameInput(stickY = 1.0), 1.0 / 60) }
        assertTrue(practice.moved)
        practice.fireLesson = true
        val ready = practice.advance(GameInput(), 1.0 / 60)
        assertTrue(ready.bullets.isEmpty())
        assertFalse(practice.fired)
        val audio = AudioEventRouter()
        audio.consume(ready, practice.tankID, infinity = false, online = false, now = 0.0)

        practice.captureFire(true)
        practice.captureFire(false)
        val fired = practice.advance(GameInput(), 1.0 / 60)
        assertEquals(practice.tankID, fired.bullets.single().owner)
        assertTrue(practice.fired)
        val shot = audio.consume(fired, practice.tankID, infinity = false, online = false, now = 1.0 / 60)
        assertTrue(shot.any { it.cue == AudioCue.REGULAR })

        var ricochet = false
        for (tick in 2..61) {
            val state = practice.advance(GameInput(), 1.0 / 60)
            val cues = audio.consume(state, practice.tankID, infinity = false, online = false, now = tick / 60.0)
            if (cues.any { it.cue == AudioCue.RICOCHET }) ricochet = true
        }
        assertTrue("A wall contact produces the ordinary ricochet cue", ricochet)
    }

    @Test
    fun targetLessonClearsOldShotsAndScoresOnceOnAnActualKill() {
        val practice = QuickTourPractice().apply { fireLesson = true }
        val step = 1.0 / 60
        val firstShot = practice.advance(GameInput(fire = true), step)
        assertTrue(firstShot.bullets.isNotEmpty())
        practice.resetFire()
        practice.startTargetLesson()
        val targetLesson = practice.advance(GameInput(), step)
        val pilot = targetLesson.tanks.first()
        val target = targetLesson.tanks.last()
        assertTrue(targetLesson.bullets.isEmpty())
        assertEquals(0, practice.score)
        repeat(30) {
            val idle = practice.advance(GameInput(), step).tanks.last()
            assertEquals(target.x, idle.x, 0.0)
            assertEquals(target.y, idle.y, 0.0)
            assertEquals(1, idle.hp)
        }
        val aim = GameInput(stickX = target.x - pilot.x, stickY = target.y - pilot.y, aimOnly = true, snapAim = true)
        practice.advance(aim, step)
        assertEquals(0, practice.score)
        val firing = practice.advance(aim.copy(fire = true), step)
        assertTrue(firing.bullets.isNotEmpty())
        assertEquals("Shooting alone does not score", 0, practice.score)
        repeat(120) { practice.advance(aim, step) }
        assertEquals(1, practice.score)
        assertEquals(0, practice.advance(aim, step).tanks.last().hp)
    }
}
