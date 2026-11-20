package com.leqra.android

import com.leqra.core.RoomRules
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class RoomPresetTest {
    @Test
    fun rulesAndAllLocalSeatsRoundTrip() {
        val original =
            RoomPreset(
                "Arena for two",
                RoomRules.localDefaults("survival")
                    .copy(scoreTarget = 9, teamColors = listOf(5, 3, 2, 1)),
                listOf(
                    PresetSeat("human", "Pilot", 0, 1),
                    PresetSeat("local", "Wing", 7, 1),
                    PresetSeat("bot", "Rook", 5, 1, "godlike"),
                ),
            )
        assertEquals(original, RoomPreset.fromJson(JSONObject(original.toJson().toString())))
    }

    @Test
    fun serializedRosterContainsOnlySetupFields() {
        val seat =
            PresetSeat.fromJson(
                JSONObject()
                    .put("kind", "local")
                    .put("name", "Wing")
                    .put("colorIndex", 7)
                    .put("team", 2)
                    .put("publicToken", "unused")
                    .put("member", 50)
                    .put("score", 42),
            )
        assertEquals(PresetSeat("local", "Wing", 7, 2), seat)
        for (field in listOf("publicToken", "member", "score")) assertFalse(
            seat.toJson().has(field),
        )
    }
}
