package com.leqra.android.network

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class GameWireProtocolTest {
    @Test
    fun theSameEpochAllowsDifferentReleaseStrings() {
        for (release in listOf("0.0.0", "99.99.99")) {
            GameWireProtocol.check(
                JSONObject().put("version", release).put("protocol", GameWireProtocol.epoch),
            )
        }
    }

    @Test
    fun legacyMetadataWithoutProtocolMeansEpochOne() {
        GameWireProtocol.check(JSONObject("""{"version":"0.0.0"}"""))
        GameWireProtocol.check(JSONObject("""{"type":"welcome","id":1}"""))
    }

    @Test
    fun incompatibleEpochIsTerminalDespiteMatchingRelease() {
        val server =
            JSONObject()
                .put("version", com.leqra.android.BuildConfig.VERSION_NAME)
                .put("protocol", GameWireProtocol.epoch + 1)
        val error = assertThrows(NetworkFailure::class.java) { GameWireProtocol.check(server) }
        assertEquals("version_mismatch", error.code)
        assertTrue(error.terminal)
    }
}
