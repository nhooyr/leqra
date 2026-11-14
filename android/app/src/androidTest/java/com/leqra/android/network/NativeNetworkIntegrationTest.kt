package com.leqra.android.network

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.leqra.android.accounts.*
import com.leqra.core.GameInput
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Runs against the actual Go server, never the production service. Pass -e server
 * http://10.0.2.2:PORT.
 */
@RunWith(AndroidJUnit4::class)
class NativeNetworkIntegrationTest {
    private fun main(block: () -> Unit) =
        InstrumentationRegistry.getInstrumentation().runOnMainSync(block)

    private fun next(
        queue: LinkedBlockingQueue<NetworkEvent>,
        predicate: (NetworkEvent) -> Boolean,
    ): NetworkEvent {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(20)
        while (System.nanoTime() < deadline) {
            val event = queue.poll(1, TimeUnit.SECONDS) ?: continue
            if (event is NetworkEvent.Error && event.terminal && !predicate(event))
                fail("Native connection failed: ${event.code}: ${event.message}")
            if (predicate(event)) return event
        }
        throw AssertionError("Timed out waiting for native protocol event")
    }

    private fun server(): String {
        val value = InstrumentationRegistry.getArguments().getString("server")
        assumeTrue("Local server argument was not supplied", value != null)
        return value!!
    }

    @Test
    fun pendingPrimaryRegistrationRecoversCommittedKeysAndReplacesOnlyUnknownCandidates() {
        val origin = server()
        for (route in listOf("public", "create", "publish")) for (registered in listOf(false,true)) {
            val context = isolatedAccountContext()
            val store = EncryptedAccountStore(context)
            val candidate = store.prepareRegistration(origin, 0)
            assertTrue(candidate.registrationPending)
            val events = LinkedBlockingQueue<NetworkEvent>()
            var client: NativeNetworkClient? = null
            var service: AccountService? = null
            var name = "C${System.nanoTime() % 1_000_000_000}"
            try {
                if (registered) {
                    service = AccountService(store)
                    val generated = LinkedBlockingQueue<Result<List<GeneratedCallsign>>>()
                    service.generate(origin,listOf(0),java.util.UUID.randomUUID().toString()) { generated.offer(it) }
                    name = (generated.poll(20,TimeUnit.SECONDS) ?: throw AssertionError("Registration timed out")).getOrThrow().single().name
                    // Recreate the durable state after the server commits but its reply is lost.
                    store.select(origin,0,candidate.key,registrationPending=true)
                }
                main {
                    client = NativeNetworkClient(store, events::offer)
                    when (route) {
                        "public" -> client!!.connectPublic(origin, name, 0)
                        "create" -> client!!.connectRoom(origin, name)
                        "publish" -> client!!.connectPublishedRoom(origin, name, ProtocolJson.rules(com.leqra.core.RoomRules.localDefaults()),
                            org.json.JSONArray().put(org.json.JSONObject().put("kind", "human").put("name", name)))
                    }
                }
                val welcome = (next(events) { it is NetworkEvent.Welcome } as NetworkEvent.Welcome).welcome
                assertNotNull(welcome.publicToken)
                if(registered) assertEquals(candidate.key,welcome.publicToken) else assertNotEquals(candidate.key, welcome.publicToken)
                assertEquals(welcome.publicToken, store.selected(origin, 0)!!.key)
                assertFalse(store.selected(origin, 0)!!.registrationPending)
                if (!registered) assertTrue(store.pending(origin,0).any { it.key==candidate.key })
            } finally { main { client?.disconnect(false); service?.close() }; context.noBackupFilesDir.deleteRecursively() }
        }
    }

    @Test
    fun publicColdResumePreservesBothAccountsAndNewestDeviceTakesOver() {
        val origin = server()
        val context = isolatedAccountContext()
        val store = EncryptedAccountStore(context)
        val suffix = (System.nanoTime() % 1_000_000_000).toString()
        val firstEvents = LinkedBlockingQueue<NetworkEvent>()
        val secondEvents = LinkedBlockingQueue<NetworkEvent>()
        val thirdEvents = LinkedBlockingQueue<NetworkEvent>()
        var first: NativeNetworkClient? = null
        var second: NativeNetworkClient? = null
        var third: NativeNetworkClient? = null
        try {
            main {
                first = NativeNetworkClient(store, { firstEvents.offer(it) })
                first!!.connectPublic(origin, "AP$suffix", 0, "AW$suffix", 1, true)
            }
            val welcome =
                (next(firstEvents) { it is NetworkEvent.Welcome } as NetworkEvent.Welcome).welcome
            assertTrue(welcome.isPublic)
            assertNotNull(welcome.localId)
            assertNotEquals(welcome.publicToken, welcome.localPublicToken)
            val before =
                (next(firstEvents) { it is NetworkEvent.State } as NetworkEvent.State).snapshot
            val score = before.tanks.first { it.id == welcome.id }.score
            main {
                first!!.sendInput(GameInput(fire = true))
                first!!.suspend()
            }
            store.select(origin,0,welcome.publicToken!!,registrationPending=true)
            val restored = EncryptedAccountStore(context)
            assertNotNull(restored.activeIntent())
            assertEquals(welcome.localPublicToken, restored.selected(origin, 1)!!.key)
            main {
                second = NativeNetworkClient(restored, { secondEvents.offer(it) })
                assertTrue(second!!.restorePublicIntent())
            }
            val resumed =
                (next(secondEvents) { it is NetworkEvent.Welcome } as NetworkEvent.Welcome).welcome
            assertEquals(welcome.id, resumed.id)
            assertEquals(welcome.localId, resumed.localId)
            val after =
                (next(secondEvents) { it is NetworkEvent.State } as NetworkEvent.State).snapshot
            assertTrue(after.tanks.first { it.id == welcome.id }.score >= score)
            main {
                third = NativeNetworkClient(restored, { thirdEvents.offer(it) })
                third!!.connectPublic(origin, "ignored", 0, "ignored2", 1)
            }
            val takeover =
                (next(thirdEvents) { it is NetworkEvent.Welcome } as NetworkEvent.Welcome).welcome
            assertEquals(welcome.id, takeover.id)
            val error =
                next(secondEvents) { it is NetworkEvent.Error && it.code == "session_replaced" }
                    as NetworkEvent.Error
            assertTrue(error.terminal)
            assertTrue(error.message.contains("taken over"))
            assertEquals(welcome.publicToken, restored.selected(origin, 0)!!.key)
            assertEquals(welcome.localPublicToken, restored.selected(origin, 1)!!.key)
            main { third!!.disconnect() }
            assertNull(restored.activeIntent())
            assertEquals(
                welcome.publicToken,
                EncryptedAccountStore(context).selected(origin, 0)!!.key,
            )
        } finally {
            main {
                first?.disconnect(false)
                second?.disconnect(false)
                third?.disconnect(false)
            }
            context.noBackupFilesDir.deleteRecursively()
        }
    }

    @Test
    fun privateRoomReconnectRetainsMemberAndIndependentP2() {
        val origin = server()
        val context = isolatedAccountContext()
        val store = EncryptedAccountStore(context)
        val events = LinkedBlockingQueue<NetworkEvent>()
        var client: NativeNetworkClient? = null
        val suffix = (System.nanoTime() % 1_000_000_000).toString()
        try {
            main {
                client = NativeNetworkClient(store, { events.offer(it) })
                client!!.connectRoom(origin, "RP$suffix")
            }
            val original =
                (next(events) { it is NetworkEvent.Welcome } as NetworkEvent.Welcome).welcome
            assertNotNull(original.room)
            assertNotNull(original.token)
            assertNotNull(original.member)
            main {
                client!!.send(
                    JSONObject().put("type", "add").put("kind", "local").put("name", "RW$suffix"),
                )
            }
            val paired =
                (next(events) { it is NetworkEvent.Welcome && it.welcome.localId != null }
                        as NetworkEvent.Welcome)
                    .welcome
            assertNotEquals(paired.publicToken, paired.localPublicToken)
            assertFalse(store.selected(origin, 1)!!.registrationPending)
            main {
                client!!.suspend()
                assertTrue(client!!.resume())
            }
            val resumed =
                (next(events) {
                        it is NetworkEvent.Welcome &&
                            it.welcome.resumed &&
                            it.welcome.localId != null
                    }
                        as NetworkEvent.Welcome)
                    .welcome
            assertEquals(original.member, resumed.member)
            assertEquals(paired.localMember, resumed.localMember)
            assertEquals(paired.localPublicToken, resumed.localPublicToken)
            assertNull(store.activeIntent())
        } finally {
            main { client?.disconnect() }
            context.noBackupFilesDir.deleteRecursively()
        }
    }
}
