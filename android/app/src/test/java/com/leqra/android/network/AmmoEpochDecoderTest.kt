package com.leqra.android.network

import com.leqra.core.*
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AmmoEpochDecoderTest {
    @Test fun finalGrenadeRemoteBankIncludesExplicitZeroWithoutUsingNewAmmoSlots() {
        for (bank in listOf(0L, 7L, AmmoEpoch.maximum)) {
            val packet = JSONObject("""{"type":"state","tick":1,"phase":"playing","tanks":[{"id":1,"alive":true,"ammoEpoch":8}],"bullets":[{"id":91,"owner":1,"kind":"grenade","life":5,"ammoEpoch":$bank}]}""")
            packet.getJSONArray("tanks").getJSONObject(0).put("grenadeEpoch", bank)
            val state = SnapshotDecoder().decode(packet)
            val tank = state.tanks.single()
            assertEquals(bank, tank.grenadeEpoch)
            assertEquals(0, tank.ammoUsed)
            assertEquals(1, tank.grenades)
            assertEquals(5.0, tank.grenadeLife, 0.0)
            assertEquals("DETONATE READY", PilotReadout(tank, state, false).readiness)
            assertEquals(5, PilotReadout(tank, state, false).available)
        }
        assertNull(ProtocolJson.arenaTank(JSONObject()).grenadeEpoch)
        assertNull(ProtocolJson.arenaTank(JSONObject().put("grenadeEpoch", JSONObject.NULL)).grenadeEpoch)
        for (value in listOf(-1, 1.5, "7", AmmoEpoch.maximum + 1))
            assertThrows(IllegalArgumentException::class.java) { ProtocolJson.arenaTank(JSONObject().put("grenadeEpoch", value)) }
    }

    @Test fun fixedRapidTuplesStayTwelveColumnsWhileOptionalParallelEpochsSelectCurrentAmmo() {
        val packet = JSONObject("""{"type":"state","tick":1,"phase":"playing","tanks":[{"id":1,"alive":true,"ammoEpoch":7}],"bullets":[{"id":90,"owner":1,"ammoEpoch":6},{"id":91,"owner":1,"ammoEpoch":7},{"id":92,"owner":1,"kind":"grenade","life":5,"ammoEpoch":6},{"id":93,"owner":1,"kind":"grenade","life":3,"ammoEpoch":7}],"machineBullets":[[100,1,0,0,100,100,846,0,1,1,0,0],[101,1,0,0,100,100,846,0,1,1,0,0],[102,1,0,0,100,100,846,0,1,1,0,0]],"machineAmmoEpochs":[7,6]}""")
        val state = SnapshotDecoder().decode(packet)
        val tank = state.tanks.single()
        assertEquals(7L, tank.ammoEpoch)
        assertEquals(listOf(7L, 6L, 0L), state.bullets.filter { it.kind == "rapid" }.map { it.ammoEpoch })
        assertEquals(3, tank.ammoUsed)
        assertEquals(1, tank.grenades); assertEquals(3.0, tank.grenadeLife, 0.0)
        assertEquals(7, state.bullets.size)
        assertEquals(2, PilotReadout(tank, state, false).available)
        repeat(packet.getJSONArray("machineBullets").length()) { assertEquals(12, packet.getJSONArray("machineBullets").getJSONArray(it).length()) }
        packet.remove("machineAmmoEpochs")
        assertTrue(SnapshotDecoder().decode(packet).bullets.filter { it.kind == "rapid" }.all { it.ammoEpoch == 0L })
    }

    @Test fun legacyEpochZeroRemainsCompatibleAndInvalidEpochsCannotEnterTheQuota() {
        assertEquals(0L, ProtocolJson.arenaTank(JSONObject()).ammoEpoch)
        assertEquals(0L, ProtocolJson.arenaBullet(JSONObject()).ammoEpoch)
        assertEquals(AmmoEpoch.maximum, ProtocolJson.arenaTank(JSONObject().put("ammoEpoch", AmmoEpoch.maximum)).ammoEpoch)
        for (value in listOf(-1, 1.5, "7", AmmoEpoch.maximum + 1)) {
            assertThrows(IllegalArgumentException::class.java) { ProtocolJson.arenaTank(JSONObject().put("ammoEpoch", value)) }
            assertThrows(IllegalArgumentException::class.java) { JSONArray().put(value).ammoEpoch(0) }
        }
        val legacy = SnapshotDecoder().decode(JSONObject("""{"type":"state","tick":1,"phase":"playing","tanks":[{"id":1,"alive":true}],"bullets":[{"id":1,"owner":1}],"machineBullets":[[2,1,0,0,100,100,846,0,1,1,0,0]]}"""))
        assertEquals(2, legacy.tanks.single().ammoUsed)
        assertEquals(3, PilotReadout(legacy.tanks.single(), legacy, false).available)
    }
}
