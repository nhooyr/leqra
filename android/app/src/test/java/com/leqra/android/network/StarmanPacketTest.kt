package com.leqra.android.network

import com.leqra.core.GamePalette
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class StarmanPacketTest {
    private fun packet(): JSONObject {
        val tanks = JSONArray()
        val packed = JSONArray()
        val boosted = JSONArray()
        val shots = JSONArray()
        repeat(12) { owner ->
            tanks.put(
                JSONObject()
                    .put("id", owner)
                    .put("alive", owner != 11)
                    .put("color", GamePalette.colors[owner % 8])
                    .put("team", if (owner == 4) 0 else owner % 4 + 1)
                    .put(
                        "power",
                        when (owner) {
                            1 -> "laser"
                            2 -> "grenade"
                            3 -> "homing"
                            else -> "rapid"
                        },
                    )
                    .put("charges", 1)
                    .put("ammoUsed", 999)
                    .put("grenades", 9)
                    .put("grenadeLife", 99)
                    .put("locked", true),
            )
            repeat(48) { index ->
                val id = 1000 + owner * 48 + index
                packed.put(
                    JSONArray(listOf(id, owner, 0, 0, 44, 56, 100, -50, .1, 4, 2, owner % 8)),
                )
                if (index % 2 == 0) boosted.put(id)
            }
        }
        // Ally0/1/5 use team1; hostile grenade2 uses team2.
        tanks.getJSONObject(1).put("team", 1)
        tanks.getJSONObject(2).put("team", 2)
        tanks.getJSONObject(5).put("team", 1)
        fun shot(
            id: Int,
            owner: Int,
            kind: String,
            target: Int,
            life: Double,
            star: Boolean = false,
        ) {
            shots.put(
                JSONObject()
                    .put("id", id)
                    .put("owner", owner)
                    .put("kind", kind)
                    .put("target", target)
                    .put("life", life),
            )
            if (star) boosted.put(id)
        }
        shot(10, 2, "grenade", 1, 2.0, star = true)
        shot(11, 2, "grenade", 1, 8.0)
        shot(12, 2, "grenade", 2, 3.0)
        shot(13, 3, "grenade", 4, 6.0, star = true)
        shot(20, 0, "homing", 5, 2.0)
        shot(21, 4, "homing", 7, 2.0)
        shot(22, 5, "homing", 5, 2.0)
        shot(23, 99, "homing", 6, 2.0)
        return JSONObject()
            .put("type", "state")
            .put("phase", "playing")
            .put("tick", 17)
            .put("rules", JSONObject().put("friendlyFire", false))
            .put("scores", JSONArray((0..11).map { it * 3 }))
            .put("tanks", tanks)
            .put("bullets", shots)
            .put("machineBullets", packed)
            .put("boostedBulletIds", boosted)
    }

    @Test
    fun denseStarmanPacketsRetainAmmoGrenadesAndHostileLocksWithOnePassNormalization() {
        val source = packet()
        val decoder = SnapshotDecoder()
        val state = decoder.decode(source)
        assertEquals(584, state.bullets.size)
        assertEquals(290, state.boostedBulletIds.size)
        assertEquals(25, state.tanks[0].ammoUsed)
        assertEquals(2, state.tanks[1].ammoUsed)
        assertEquals(26, state.tanks[2].ammoUsed)
        assertEquals(3, state.tanks[2].grenades)
        assertEquals(8.0, state.tanks[2].grenadeLife, 0.0)
        assertEquals(24, state.tanks[3].ammoUsed)
        assertEquals(1, state.tanks[3].grenades)
        assertEquals(6.0, state.tanks[3].grenadeLife, 0.0)
        assertEquals(25, state.tanks[4].ammoUsed)
        assertEquals(25, state.tanks[5].ammoUsed)
        assertFalse(state.tanks[0].locked)
        assertEquals(0, state.tanks[0].grenades)
        assertEquals(0.0, state.tanks[0].grenadeLife, 0.0)
        assertTrue(state.tanks[1].locked)
        assertFalse(state.tanks[2].locked)
        assertFalse(state.tanks[5].locked)
        assertTrue(state.tanks[4].locked)
        assertTrue(state.tanks[6].locked)
        assertTrue(state.tanks[7].locked)
        assertEquals(0, state.tanks[11].hp)
        assertEquals(33, state.tanks[11].score)
        source.getJSONObject("rules").put("friendlyFire", true)
        assertTrue(decoder.decode(source).tanks[5].locked)
    }

    @Test
    fun packedRapidRowsRejectFractionalIdentityAndNonFiniteMotion() {
        for (column in listOf(0, 1, 10, 11)) {
            val source = packet()
            source.getJSONArray("machineBullets").getJSONArray(0).put(column, 1.25)
            try {
                SnapshotDecoder().decode(source)
                fail("Fractional machine field$column accepted")
            } catch (_: IllegalArgumentException) {}
        }
        val source = packet()
        source.getJSONArray("machineBullets").getJSONArray(0).put(4, "NaN")
        try {
            SnapshotDecoder().decode(source)
            fail("Nonfinite packed coordinate accepted")
        } catch (_: IllegalArgumentException) {}
    }
}
