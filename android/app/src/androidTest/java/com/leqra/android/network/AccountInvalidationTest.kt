package com.leqra.android.network

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.leqra.android.accounts.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AccountInvalidationTest {
    @Test
    fun chatPacketsAreIgnoredWithoutInterruptingRoomEvents() {
        val context = isolatedAccountContext()
        val events = mutableListOf<NetworkEvent>()
        try {
            InstrumentationRegistry.getInstrumentation().runOnMainSync {
                val client = NativeNetworkClient(EncryptedAccountStore(context), events::add)
                val receive = NativeNetworkClient::class.java.getDeclaredMethod("receive", JSONObject::class.java).apply { isAccessible = true }
                for (type in listOf("chat", "chat_history")) receive.invoke(client, JSONObject().put("type", type).put("text", "Ignored message"))
                assertTrue(events.isEmpty())
                receive.invoke(client, JSONObject().put("type", "queue_info"))
                assertEquals("queue_info", (events.single() as NetworkEvent.Packet).packet.optString("type"))
                client.disconnect(false)
            }
        } finally { context.noBackupFilesDir.deleteRecursively() }
    }

    @Test
    fun expiredOrReleasedP2StopsRetryAndForgetsOnlyItsOwnCredential() {
        for (code in listOf("account_key_invalid", "account_key_revoked")) {
            val context = isolatedAccountContext()
            val store = EncryptedAccountStore(context)
            val origin = "https://example.test"
            val p1 = AccountKeys.create(); val p2 = AccountKeys.create(); val newer = AccountKeys.create()
            val events = mutableListOf<NetworkEvent>()
            var client: NativeNetworkClient? = null
            try {
                InstrumentationRegistry.getInstrumentation().runOnMainSync {
                    store.select(origin, 0, p1); store.select(origin, 1, p2)
                    store.savePending(origin, AccountKeys.pending(1, p2, purpose = "saved:OLD"))
                    store.select(origin, 1, newer)
                    store.savePending(origin, AccountKeys.pending(1, newer, purpose = "saved:NEW"))
                    client = NativeNetworkClient(store, events::add)
                    fun field(name: String, value: Any?) = NativeNetworkClient::class.java.getDeclaredField(name).run {
                        isAccessible = true; set(client, value)
                    }
                    field("origin", origin); field("infinity", true); field("connected", true)
                    field("selectionAtJoin", arrayOf(p1, p2))
                    field("resumeJoin", JSONObject().put("publicToken", p1).put("localPublicToken", p2))
                    NativeNetworkClient::class.java.getDeclaredMethod("receive", JSONObject::class.java).run {
                        isAccessible = true
                        invoke(client, JSONObject().put("type", "error").put("code", code).put("seat", 1))
                    }
                    assertEquals(p1, store.selected(origin, 0)!!.key)
                    assertEquals("A newer P2 selection survives an old socket error", newer, store.selected(origin, 1)!!.key)
                    assertFalse(store.pending(origin, 1).any { it.key == p2 })
                    assertTrue(store.pending(origin, 1).any { it.key == newer })
                    assertFalse(client!!.connected)
                    assertTrue(events.filterIsInstance<NetworkEvent.Error>().single().terminal)
                    assertFalse(events.any { it is NetworkEvent.Reconnecting })
                    client!!.disconnect(false)
                }
            } finally { context.noBackupFilesDir.deleteRecursively() }
        }
    }
}
