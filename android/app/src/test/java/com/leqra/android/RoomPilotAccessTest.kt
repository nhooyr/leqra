package com.leqra.android

import com.leqra.core.RoomRules
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class RoomPilotAccessTest {
    @Test
    fun rosterControlsFollowOwnershipBattleModeAndRoomPhase() {
        val remote = JSONObject().put("kind", "human").put("id", 3)
        val bot = JSONObject().put("kind", "bot").put("id", 4)
        val local = JSONObject().put("kind", "local").put("id", 5).put("owner", 1)
        fun controls(member: JSONObject, host: Boolean, editable: Boolean, rules: RoomRules) =
            roomPilotAccess(
                member,
                controller = 1,
                host = host,
                setupOpen = editable,
                matchmaking = false,
                rules = rules,
            )

        val ctf = RoomRules(mode = "ctf", teamMode = "teams")
        val hostRemote = controls(remote, true, true, ctf)
        assertEquals(2, hostRemote.teamCount)
        assertFalse(hostRemote.canToggleSpectating)
        assertFalse(hostRemote.canPaint)
        assertTrue(hostRemote.canRemove)
        assertEquals(1, controls(remote, true, true, ctf.copy(mode = "survival")).teamCount)
        assertEquals(0, controls(remote, false, true, ctf).teamCount)

        val ffa = RoomRules(teamMode = "ffa")
        val hostBot = controls(bot, true, true, ffa)
        assertTrue(hostBot.canRenameBot)
        assertTrue(hostBot.canPaint)
        assertFalse(controls(bot, true, false, ffa).canRenameBot)
        assertFalse(controls(bot, true, false, ffa).canPaint)
        assertFalse(controls(bot, false, true, ffa).canPaint)
        val localPilot = controls(local, true, true, ffa)
        assertEquals(2, localPilot.localSeat)
        assertTrue(localPilot.canToggleSpectating)
        assertTrue(localPilot.canPaint)
        assertFalse(controls(local.put("spectating", true), true, true, ffa).canPaint)
    }
}
