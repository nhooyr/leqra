package com.leqra.android.network

import com.leqra.core.RoomRules
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class SnapshotDecoderTest {
    @Test
    fun fixedWorldSurvivesOmittedUpdatesAndPackedRapidBulletsAreDecoded() {
        val decoder = SnapshotDecoder()
        val packet =
            JSONObject(
                """{"type":"state","tick":1,"phase":"playing","scores":[7,3],"tanks":[{"id":0,"name":"Pilot","alive":true,"color":"#73cee4","power":"rapid"},{"id":1,"alive":false}],"bullets":[],"machineBullets":[[12,0,0,0,44,56,100,-50,0.1,4,2,2]],"boostedBulletIds":[12],"events":[{"id":4,"type":"shot","text":"rapid"}],"world":{"width":700,"height":500,"cols":10,"rows":7,"walls":[{"x":10,"y":10,"w":6,"h":70}]}}""",
            )
        val first = decoder.decode(packet)
        assertEquals(700.0, first.world!!.width, 0.0)
        assertEquals(7, first.tanks[0].score)
        assertEquals(2, first.tanks[0].colorIndex)
        assertEquals(0, first.tanks[1].hp)
        assertEquals(1, first.bullets.size)
        assertEquals("rapid", first.bullets.single().kind)
        assertEquals(0, first.tanks[0].ammoUsed)
        assertEquals("shot:rapid", first.effects.single().kind)
        packet.remove("world")
        packet.put("tick", 2)
        assertSame(first.world, decoder.decode(packet).world)
    }

    @Test
    fun infinityUsesAuthoritativeIdentityScoreAndStatus() {
        val state =
            SnapshotDecoder()
                .decode(
                    JSONObject(
                        """{"type":"state","tick":456,"tanks":[{"id":23,"name":"PILOT","hp":1,"score":88,"protected":true,"ack":71,"ackSteps":3,"speedStacks":2,"starmanTime":8.5}],"bullets":[],"players":1,"tankCount":4,"leaderboard":[{"id":23,"name":"PILOT","score":88,"colorIndex":4}],"effects":[{"id":3,"kind":"pickup:speed"}]}""",
                    ),
                )
        assertEquals(88, state.tanks.single().score)
        assertTrue(state.tanks.single().protectedState)
        assertEquals(71L, state.tanks.single().ack)
        assertEquals(2, state.tanks.single().speedStacks)
        assertEquals("pickup:speed", state.effects.single().kind)
        assertEquals(4, state.tankCount)
        assertNull(state.world)
    }

    @Test
    fun fixedLockedStatusRespectsTeamsAndFriendlyFire() {
        val packet =
            JSONObject(
                """{"type":"state","tick":1,"phase":"playing","rules":{"friendlyFire":false},"tanks":[{"id":0,"alive":true,"team":1},{"id":1,"alive":true,"team":1}],"bullets":[{"id":5,"kind":"homing","owner":0,"target":1}]}""",
            )
        assertFalse(SnapshotDecoder().decode(packet).tanks[1].locked)
        packet.getJSONObject("rules").put("friendlyFire", true)
        assertTrue(SnapshotDecoder().decode(packet).tanks[1].locked)
    }

    @Test
    fun rulesRoundTripPreservesEveryModePowerAndTeamSetting() {
        val rules =
            RoomRules(
                mode = "ctf",
                teamMode = "teams",
                friendlyFire = true,
                teamNames = listOf("A", "B", "C", "D"),
                portraitMaze = true,
            )
        assertEquals(rules, ProtocolJson.roomRules(ProtocolJson.rules(rules)))
    }

    @Test
    fun nonFiniteCoordinatesAreRejected() {
        val tank = JSONObject().put("x", "NaN")
        try {
            ProtocolJson.arenaTank(tank)
            fail("Nonfinite coordinate accepted")
        } catch (_: IllegalArgumentException) {}
    }

    @Test
    fun originNormalizationNeverIncludesCredentialsPathsOrTokens() {
        assertEquals(
            "https://example.com",
            ServerAddress.origin("https://EXAMPLE.com:443/room?token=secret#x"),
        )
        assertEquals("http://localhost:8080", ServerAddress.origin("ws://localhost:8080/ws"))
        try {
            ServerAddress.origin("https://user:secret@example.com/")
            fail("URL credentials accepted")
        } catch (_: IllegalArgumentException) {}
    }
}
