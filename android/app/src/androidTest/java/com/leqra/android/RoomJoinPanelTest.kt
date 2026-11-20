package com.leqra.android

import android.net.Uri
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.Switch
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RoomJoinPanelTest {
    @Test
    fun fullLengthUnicodeInvitesRetainNameAndSpectatorIntent() {
        val code = "💥".repeat(roomNameLimit)
        val link =
            Uri.parse("https://leqra.com/")
                .buildUpon()
                .appendQueryParameter("room", code)
                .appendQueryParameter("spectate", "1")
                .build()
        assertEquals(RoomJoinRequest(code, true), RoomJoinRequest.fromInvite(link))
        assertEquals(RoomJoinRequest(code, true), RoomJoinRequest.fromInput(link.toString(), false))
        assertEquals(RoomJoinRequest(code, false), RoomJoinRequest.fromInput(code, false))
        assertNull(RoomJoinRequest.fromInput(code + "X", false))
    }

    @Test
    fun spectateSwitchChangesTheActionAndSendsSpectatorIntent() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            var joined: RoomJoinRequest? = null
            var activatedCallsign: String? = null
            var accountDraft: RoomJoinDraft? = null
            val panel =
                roomJoinPanel(
                    instrumentation.targetContext,
                    "Pilot",
                    RoomJoinDraft(),
                    { true },
                    { accountDraft = it },
                ) { callsign, request ->
                    activatedCallsign = callsign
                    joined = request
                }
            val views = (0 until panel.childCount).map(panel::getChildAt)
            val identity = views.filterIsInstance<LinearLayout>().single()
            val accountViews = (0 until identity.childCount).map(identity::getChildAt)
            val pilot = accountViews.filterIsInstance<EditText>().single()
            val code = views.filterIsInstance<EditText>().single()
            val spectate = views.filterIsInstance<Switch>().single()
            val action = views.filterIsInstance<Button>().single { it !is Switch }
            assertFalse(action.isEnabled)
            code.setText("Friday battle")
            assertTrue(action.isEnabled)
            assertEquals("JOIN →", action.text)
            spectate.isChecked = true
            assertEquals("WATCH →", action.text)
            accountViews.filterIsInstance<Button>().single().performClick()
            assertEquals(RoomJoinDraft("Friday battle", true), accountDraft)
            pilot.setText("")
            assertFalse(action.isEnabled)
            pilot.setText("Friday Pilot")
            action.performClick()
            assertEquals(RoomJoinRequest("Friday battle", true), joined)
            assertEquals("Friday Pilot", activatedCallsign)
        }
    }
}
