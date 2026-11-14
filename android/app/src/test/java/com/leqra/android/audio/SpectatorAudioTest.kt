package com.leqra.android.audio

import com.leqra.core.*
import org.junit.Assert.*
import org.junit.Test

class SpectatorAudioTest {
    @Test
    fun observerHearsWatchedShotsExplosionsAndRicochetsWithoutOwningTheTank() {
        val router = AudioEventRouter()
        val tank = ArenaTank(id = 7, x = 1000.0, y = 2000.0, starmanTime = 5.0, locked = true)
        val baseline =
            ArenaSnapshot(
                tick = 1,
                generation = 1,
                spectating = true,
                following = 7,
                tanks = listOf(tank),
                bullets =
                    listOf(ArenaBullet(id = 8, owner = 7, x = 1000.0, y = 2000.0, bounces = 0)),
            )
        assertTrue(router.consume(baseline, -1, true, true, 1.0).isEmpty())
        val next =
            baseline.copy(
                tick = 2,
                bullets = listOf(baseline.bullets.single().copy(bounces = 1)),
                effects =
                    listOf(
                        ArenaEffect(
                            id = 1,
                            kind = "shot:regular",
                            owner = 7,
                            x = 1000.0,
                            y = 2000.0,
                        ),
                        ArenaEffect(id = 2, kind = "hit", owner = 7, x = 1000.0, y = 2000.0),
                        ArenaEffect(id = 3, kind = "pickup", owner = 7, x = 1000.0, y = 2000.0),
                        ArenaEffect(id = 4, kind = "shot:cannon", owner = 9, x = 9000.0, y = 2000.0),
                    ),
            )
        val sounds = router.consume(next, -1, true, true, 1.1)
        assertEquals(
            setOf(AudioCue.REGULAR, AudioCue.EXPLOSION, AudioCue.RICOCHET, AudioCue.PICKUP),
            sounds.map { it.cue }.toSet(),
        )
        assertTrue(
            sounds
                .filter { it.cue == AudioCue.REGULAR || it.cue == AudioCue.PICKUP }
                .none { it.local }
        )
        assertFalse(sounds.any { it.cue == AudioCue.HOMING_WARNING || it.cue == AudioCue.CANNON })
        assertFalse(StarmanLoopState.active(next, -1, null, true))
        assertTrue(router.consume(next, -1, true, true, 1.2).isEmpty())
    }
}
