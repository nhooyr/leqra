package com.leqra.android.network

import com.leqra.android.accounts.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ReconnectExpiryTest {
    private class Store : AccountStore {
        val credential = AccountCredential(AccountKeys.create())
        var intent: PublicIntent? = PublicIntent("https://example.test", "Pilot", 0)

        override fun selected(origin: String, seat: Int) = if (seat == 0) credential else null

        override fun select(origin: String, seat: Int, key: String, registrationPending: Boolean) =
            error("Unexpected credential mutation")

        override fun clearIfMatching(origin: String, seat: Int, key: String) =
            error("Unexpected credential deletion")

        override fun pending(origin: String, seat: Int) = emptyList<PendingAccount>()

        override fun savePending(origin: String, pending: PendingAccount) =
            error("Unexpected registration")

        override fun removePending(origin: String, id: String) = Unit

        override fun activeIntent() = intent

        override fun setActiveIntent(intent: PublicIntent?) {
            this.intent = intent
        }

        override fun prepareRegistration(origin: String, seat: Int): AccountCredential =
            error("Unexpected registration")
    }

    private fun field(client: NativeNetworkClient, name: String): Any? =
        client.javaClass.getDeclaredField(name).run {
            isAccessible = true
            get(client)
        }

    private fun set(client: NativeNetworkClient, name: String, value: Any?) =
        client.javaClass.getDeclaredField(name).run {
            isAccessible = true
            set(client, value)
        }

    private fun expiredRoute(
        client: NativeNetworkClient,
        infinity: Boolean,
        public: Boolean = false,
    ) {
        val route = JSONObject().put("type", "join").put("name", "Pilot")
        if (!public) route.put("code", "ROOM").put("token", "test-room-token")
        set(client, "origin", "https://example.test")
        set(client, "infinity", infinity)
        set(client, "resumeJoin", route)
        set(client, "pendingJoin", JSONObject(route.toString()))
        set(client, "deadline", -1L)
        set(client, "suspended", true)
    }

    @Test
    fun expiredPrivateForegroundResumeReportsTerminalErrorAndRetainsCredentials() {
        for (infinity in listOf(false, true)) {
            val store = Store()
            val events = mutableListOf<NetworkEvent>()
            val client = NativeNetworkClient(store, { events.add(it) })
            try {
                expiredRoute(client, infinity)
                assertFalse(client.resume())
                val error = events.filterIsInstance<NetworkEvent.Error>().single()
                assertTrue(error.terminal)
                assertEquals("The reconnect window expired. Join the room again.", error.message)
                assertTrue(events.any { it is NetworkEvent.Disconnected })
                assertNull(field(client, "resumeJoin"))
                assertNull(field(client, "retry"))
                assertSame(store.credential, store.selected("https://example.test", 0))
                assertFalse(client.connected)
            } finally {
                client.close()
            }
        }
    }

    @Test
    fun explicitPrivateReconnectAfterExpiryCannotSilentlyFail() {
        val events = mutableListOf<NetworkEvent>()
        val client = NativeNetworkClient(Store(), { events.add(it) })
        try {
            expiredRoute(client, false)
            assertFalse(client.reconnect())
            assertTrue(
                events
                    .single { it is NetworkEvent.Error }
                    .let { it as NetworkEvent.Error }
                    .terminal,
            )
            assertNull(field(client, "resumeJoin"))
        } finally {
            client.close()
        }
    }

    @Test
    fun publicResumeHasNoPrivateDeadlineAndKeepsItsAccountIntent() {
        val store = Store()
        val events = mutableListOf<NetworkEvent>()
        val client = NativeNetworkClient(store, { events.add(it) })
        try {
            expiredRoute(client, true, public = true)
            assertTrue(client.resume())
            assertNull(field(client, "deadline"))
            assertNotNull(field(client, "resumeJoin"))
            assertNotNull(field(client, "retry"))
            assertTrue(events.any { it is NetworkEvent.Reconnecting })
            assertTrue(events.none { it is NetworkEvent.Error })
            assertNotNull(store.activeIntent())
            assertSame(store.credential, store.selected("https://example.test", 0))
        } finally {
            client.close()
        }
    }
}
