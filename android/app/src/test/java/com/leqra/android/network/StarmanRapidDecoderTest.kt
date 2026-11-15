package com.leqra.android.network

import com.leqra.core.*
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class StarmanRapidDecoderTest {
    @Test fun fixedTuplesAndInfinityObjectsKeepEachRoundsCapturedSpeedAndLifetime() {
        for (fixed in listOf(false, true)) {
            val regularLife = if (fixed) (840.0 - 28) / 846 else 1512.0 / 846
            val starLife = if (fixed) (1680.0 - 28) / 1692 else (3024.0 + 28) / 1692
            val tank = JSONObject().put("id", 1).put("hp", 1).put("alive", true).put("power", "rapid").put("machineRounds", 180)
                .put("starmanTime", 8).put("ammoEpoch", 7)
            val packet = JSONObject().put("type", "state").put("tick", 10).put("tanks", JSONArray().put(tank))
                .put("bullets", JSONArray()).put("leaderboard", JSONArray()).put("players", 1).put("tankCount", 1)
                .put("boostedBulletIds", JSONArray().put(2))
            if (fixed) {
                packet.put("phase", "playing").put("world", JSONObject().put("width", 1008).put("height", 672).put("cols", 12).put("rows", 8).put("walls", JSONArray()))
                val rows = JSONArray()
                for ((id, speed, life) in listOf(Triple(1, 846.0, regularLife), Triple(2, 1692.0, starLife)))
                    rows.put(JSONArray(listOf(id, 1, 0, 0, 100, 210, speed, 0, 3.5 / 3, life, 0, 0)))
                packet.put("machineBullets", rows).put("machineAmmoEpochs", JSONArray(listOf(7, 7)))
            } else {
                for ((id, speed, life) in listOf(Triple(1, 846.0, regularLife), Triple(2, 1692.0, starLife)))
                    packet.getJSONArray("bullets").put(JSONObject().put("id", id).put("owner", 1).put("kind", "rapid")
                        .put("x", 100).put("y", 210).put("vx", speed).put("vy", 0).put("life", life).put("ammoEpoch", 7))
            }
            val state = SnapshotDecoder().decode(packet)
            assertEquals(listOf(846.0, 1692.0), state.bullets.map { it.vx })
            assertEquals(listOf(regularLife, starLife), state.bullets.map { it.life })
            assertTrue(state.bullets.all { it.kind == "rapid" && it.ammoEpoch == 7L && it.vy == 0.0 })
            if (fixed) assertEquals("Only the captured ordinary round occupies standard ammo", 1, state.tanks.single().ammoUsed)
            assertEquals("Machine-gun capacity remains unchanged", 115, PracticeArena.spec("rapid").capacity)
        }
    }
}
