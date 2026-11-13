package com.leqra.android.network

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class RenameMetadataTest {
    @Test
    fun privateSecondSeatAcknowledgementNeverChangesThePrimaryName() {
        assertEquals(1, JSONObject().put("id", 2).put("member", 12).renamedSeat(0, 2))
        assertEquals(0, JSONObject().put("id", 0).renamedSeat(0, 2))
        assertNull(JSONObject().put("id", 2).renamedSeat(0, null))
        assertNull(JSONObject().put("id", 3).renamedSeat(0, 2))
    }

    @Test
    fun explicitInfinitySeatIsValidatedIndependentlyOfTankID() {
        assertEquals(1, JSONObject().put("seat", 1).renamedSeat(51, 76))
        assertEquals(0, JSONObject().put("seat", 0).renamedSeat(51, 76))
        assertNull(JSONObject().put("seat", 1).renamedSeat(51, null))
        assertNull(JSONObject().put("seat", 2).renamedSeat(51, 76))
    }
}
