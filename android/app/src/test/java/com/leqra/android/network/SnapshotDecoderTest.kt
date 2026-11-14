package com.leqra.android.network

import com.leqra.core.RoomRules
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class SnapshotDecoderTest {
    @Test
    fun completedProjectilePathsDecodeForFixedAndInfinityWithoutChangingAuthority() {
        val descriptor = """{"id":17,"owner":0,"colorIndex":3,"startTick":1,"endTick":1.25,"kind":"cannon","radius":18,"points":[{"x":10,"y":20,"tick":1},{"x":13,"y":20,"tick":1.25}]}"""
        for (fixed in listOf(false, true)) {
            val packet = JSONObject("""{"type":"state","tick":2,"tanks":[],"bullets":[],"leaderboard":[],"players":0,"tankCount":0,"effects":[{"id":1,"kind":"impact","flight":$descriptor}]}""")
            if (fixed) { packet.put("phase", "playing"); packet.put("events", org.json.JSONArray().put(JSONObject().put("id", 1).put("type", "impact").put("flight", JSONObject(descriptor)))) }
            val state = SnapshotDecoder().decode(packet)
            assertTrue(state.bullets.isEmpty())
            assertEquals(17, state.effects.single().flight!!.id)
            assertEquals(0, state.effects.single().flight!!.owner)
            assertEquals(1.25, state.effects.single().flight!!.points.last().tick, 0.0)
        }
        val bad = JSONObject().put("id", 1).put("flight", JSONObject(descriptor).put("points", org.json.JSONArray()))
        assertNull(ProtocolJson.arenaEffect(bad).flight)
        val legacy = JSONObject(descriptor).apply { remove("kind"); remove("radius") }
        assertEquals("cannon", ProtocolJson.arenaEffect(JSONObject().put("flight", legacy)).flight!!.kind)
        assertEquals(2.0, ProtocolJson.roomRules(JSONObject()).infinityBotSpawnRate, 0.0)
        assertEquals(.5, ProtocolJson.roomRules(JSONObject().put("infinityBotSpawnRate", .5)).infinityBotSpawnRate, 0.0)
        assertEquals(4.0, ProtocolJson.rules(com.leqra.core.RoomRules(infinityBotSpawnRate = 4.0)).getDouble("infinityBotSpawnRate"), 0.0)
    }
    @Test
    fun spectatorPacketsKeepFullRankingFollowTargetAndDeadDistantTank() {
        val packet = JSONObject("""{"type":"state","tick":24,"spectating":true,"following":81,"tanks":[{"id":81,"name":"Far Tank","x":240000,"y":-300000,"hp":0}],"bullets":[],"leaderboard":[],"players":2,"tankCount":24}""")
        repeat(24) { packet.getJSONArray("leaderboard").put(JSONObject().put("id", it + 81).put("name", "Tank $it").put("score", 24 - it).put("bot", it > 1)) }
        val state = SnapshotDecoder().decode(packet)
        assertTrue(state.spectating)
        assertEquals(81, state.following)
        assertEquals(24, state.leaderboard.size)
        assertEquals(0, state.tanks.single().hp)
        assertEquals(240000.0, state.tanks.single().x, 0.0)
        packet.remove("spectating")
        packet.remove("following")
        val legacy = SnapshotDecoder().decode(packet)
        assertFalse(legacy.spectating)
        assertEquals(0, legacy.following)
        val welcome = NetworkWelcome.parse(JSONObject().put("id", 0).put("seed", 123).put("spectating", true).put("following", 81))
        assertEquals(0, welcome.id)
        assertTrue(welcome.spectating)
        assertEquals(81, welcome.following)
        assertNull(welcome.localId)
        assertNull(welcome.publicToken)
        val roleChange = NetworkWelcome.parse(JSONObject().put("id", 3).put("localId", -1).put("localMember", 0))
        assertNull("The room identity sentinel means no P2", roleChange.localId)
        assertNull(roleChange.localMember)
        assertEquals(0, NetworkWelcome.parse(JSONObject().put("id", 3).put("localId", 0).put("localMember", 21)).localId)
    }

    @Test
    fun authoritativeLongGodlikeNamesRemainWholeAcrossTankLeaderboardAndNotice() {
        val name = "Bot 1234567890 - Godlike"
        assertTrue(name.length > 16)
        val packet = JSONObject("""{"type":"state","tick":1,"tanks":[{"id":7,"name":"$name","bot":true,"difficulty":"godlike"}],"bullets":[],"leaderboard":[{"id":7,"name":"$name","score":1,"bot":true}],"godlikeSpawns":[{"id":7,"spawnSerial":2,"name":"$name"}],"players":0,"tankCount":1}""")
        val state = SnapshotDecoder().decode(packet)
        assertEquals(name, state.tanks.single().name)
        assertEquals(name, state.leaderboard.single().name)
        assertEquals(name, state.godlikeSpawns.single().name)
        assertTrue(state.tanks.single().isGodlikeBot)
    }

    @Test
    fun optionalGodlikeSpawnEventsRemainBoundedAndOldPacketsNeedNoNewFields() {
        val packet = JSONObject("""{"type":"state","tick":1,"tanks":[],"bullets":[],"leaderboard":[],"players":0,"tankCount":0}""")
        assertTrue(SnapshotDecoder().decode(packet).godlikeSpawns.isEmpty())
        packet.put("godlikeSpawns", org.json.JSONArray().apply {
            repeat(200) { put(JSONObject().put("id", it).put("spawnSerial", 3).put("name", "Bot $it - Godlike")) }
        })
        val events = SnapshotDecoder().decode(packet).godlikeSpawns
        assertEquals(128, events.size)
        assertEquals(3, events[0].spawnSerial)
        assertEquals("Bot 0 - Godlike", events[0].name)
        packet.put("phase", "playing")
        assertTrue(SnapshotDecoder().decode(packet).godlikeSpawns.isEmpty())
    }

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
    fun infinityRetainsActualBotDifficultyAndOnlyThatTierCreatesGodlikeWarning() {
        val state =
            SnapshotDecoder()
                .decode(
                    JSONObject(
                        """{"type":"state","tick":1,"tanks":[{"id":2,"name":"Bot 2 - Godlike","bot":true,"difficulty":"godlike"},{"id":3,"name":"Bot 3 - Godlike","bot":true,"difficulty":"dumb"},{"id":4,"name":"Godlike Bot 4","bot":false,"difficulty":"godlike"},{"id":5,"name":"Old server bot","bot":true}],"bullets":[],"leaderboard":[],"players":1,"tankCount":4}"""
                    )
                )
        assertEquals(
            listOf("godlike", "dumb", "godlike", "normal"),
            state.tanks.map { it.difficulty },
        )
        assertEquals(listOf(true, false, false, false), state.tanks.map { it.isGodlikeBot })
        val rules = RoomRules(infinityBotDifficulty = "dumb")
        assertEquals(rules, ProtocolJson.roomRules(ProtocolJson.rules(rules)))
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
