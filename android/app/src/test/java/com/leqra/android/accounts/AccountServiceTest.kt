package com.leqra.android.accounts

import com.leqra.android.network.NetworkFailure
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.Assert.*
import org.junit.Test

class AccountServiceTest {
    private class Store : AccountStore {
        val selected = mutableMapOf<Int, AccountCredential>()
        val backups = mutableListOf<PendingAccount>()
        var intent: PublicIntent? = null

        override fun selected(origin: String, seat: Int) = selected[seat]

        override fun select(origin: String, seat: Int, key: String, registrationPending: Boolean) {
            selected[seat] = AccountCredential(key, registrationPending)
        }

        override fun clearIfMatching(origin: String, seat: Int, key: String) {
            if (selected[seat]?.key == key) selected.remove(seat)
        }

        override fun pending(origin: String, seat: Int) = backups.filter { it.seat == seat }

        override fun savePending(origin: String, pending: PendingAccount) {
            backups.add(pending)
        }

        override fun removePending(origin: String, id: String) {
            backups.removeAll { it.id == id }
        }

        override fun activeIntent() = intent

        override fun setActiveIntent(intent: PublicIntent?) {
            this.intent = intent
        }

        override fun prepareRegistration(origin: String, seat: Int): AccountCredential =
            selected[seat]
                ?: AccountCredential(AccountKeys.create(), true).also {
                    selected[seat] = it
                    backups.add(AccountKeys.pending(seat, it.key))
                }
    }

    private fun <T> awaitOperation(start: ((Result<T>) -> Unit) -> Unit): Result<T> {
        val latch = CountDownLatch(1)
        var value: Result<T>? = null
        start {
            value = it
            latch.countDown()
        }
        assertTrue("No API callback", latch.await(10, TimeUnit.SECONDS))
        return value!!
    }

    @Test
    fun keysHaveCanonicalCryptographic32ByteFormat() {
        val keys = (0 until 128).map { AccountKeys.create() }
        assertEquals(128, keys.toSet().size)
        assertTrue(keys.all { it.length == 45 && AccountKeys.valid(it) })
        assertFalse(AccountKeys.valid("p_" + "x".repeat(43))) // noncanonical terminal base64 bits
        assertFalse(AccountKeys.valid("not-an-account"))
    }

    @Test
    fun secretPostDoesNotFollowRedirects() {
        MockWebServer().use { source ->
            MockWebServer().use { target ->
                source.start()
                target.start()
                source.enqueue(
                    MockResponse()
                        .setResponseCode(307)
                        .setHeader("Location", target.url("/stolen"))
                        .setBody("{}"),
                )
                val service = AccountService(Store()) { it() }
                val result =
                    awaitOperation<CheckedAccount> {
                        service.inspect(source.url("/").toString(), AccountKeys.create(), it)
                    }
                assertTrue(result.isFailure)
                assertEquals(0, target.requestCount)
                val request = source.takeRequest()
                assertEquals("/api/account", request.path)
                assertEquals("POST", request.method)
                assertFalse(request.path!!.contains("p_"))
            }
        }
    }

    @Test
    fun rotationCandidateIsSavedBeforeRequestAndSuccessfulResetPreservesOtherSeat() {
        MockWebServer().use { server ->
            server.start()
            val store = Store()
            val old = AccountKeys.create()
            val other = AccountKeys.create()
            store.select("", 0, old)
            store.select("", 1, other)
            server.dispatcher =
                object : Dispatcher() {
                    override fun dispatch(request: RecordedRequest): MockResponse {
                        val backup = store.backups.single()
                        val body = org.json.JSONObject(request.body.readUtf8())
                        assertEquals(old, body.getString("publicToken"))
                        assertEquals(backup.key, body.getString("newPublicToken"))
                        assertEquals(old, store.selected[0]!!.key)
                        return MockResponse()
                            .setBody(
                                """{"publicToken":"${backup.key}","names":["Pilot"],"totalNames":1,"publicProfile":{"name":"Pilot","score":321}}""",
                            )
                    }
                }
            val service = AccountService(store) { it() }
            val result =
                awaitOperation<RecoveredAccount> {
                        service.rotate(server.url("/").toString(), 0, it)
                    }
                    .getOrThrow()
            assertTrue(result.promoted)
            assertNotEquals(old, store.selected[0]!!.key)
            assertEquals(other, store.selected[1]!!.key)
            assertEquals(321, result.checked.info.publicProfile!!.score)
            assertTrue(store.backups.isEmpty())
        }
    }

    @Test
    fun delayedRecoveryDoesNotOverwriteAChangedSelection() {
        MockWebServer().use { server ->
            server.start()
            val store = Store()
            val old = AccountKeys.create()
            val replacement = AccountKeys.create()
            val imported = AccountKeys.create()
            val pending = AccountKeys.pending(0, replacement, old, "rotation")
            store.select("", 0, old)
            store.savePending("", pending)
            val service = AccountService(store) { it() }
            server.dispatcher =
                object : Dispatcher() {
                    override fun dispatch(request: RecordedRequest): MockResponse {
                        service.useChecked(
                            CheckedAccount(
                                server.url("/").toString().removeSuffix("/"),
                                imported,
                                AccountInfo(listOf("New"), 1, null),
                            ),
                            0,
                        )
                        return MockResponse().setBody("""{"names":["Old"],"totalNames":1}""")
                    }
                }
            val result =
                awaitOperation<RecoveredAccount> {
                        service.recover(server.url("/").toString(), pending, it)
                    }
                    .getOrThrow()
            assertFalse(result.promoted)
            assertEquals(imported, store.selected[0]!!.key)
            assertEquals(replacement, store.backups.single().key)
        }
    }

    @Test
    fun earlyReplacement401AndOld200RetainBothKeysForAmbiguousReset() {
        MockWebServer().use { server ->
            server.start()
            val store = Store()
            val old = AccountKeys.create()
            val pending = AccountKeys.pending(0, AccountKeys.create(), old, "rotation")
            store.select("", 0, old)
            store.savePending("", pending)
            server.enqueue(
                MockResponse().setResponseCode(401).setBody("""{"code":"invalid_account_key"}"""),
            )
            server.enqueue(MockResponse().setBody("""{"names":["Pilot"],"totalNames":1}"""))
            val service = AccountService(store) { it() }
            val result =
                awaitOperation<RecoveredAccount> {
                    service.recover(server.url("/").toString(), pending, it)
                }
            assertEquals("recovery_pending", (result.exceptionOrNull() as NetworkFailure).code)
            assertEquals(old, store.selected[0]!!.key)
            assertEquals(pending.key, store.backups.single().key)
        }
    }

    @Test
    fun recoveryRechecksReplacementAfterOldRevocation() {
        MockWebServer().use { server ->
            server.start()
            val store = Store()
            val old = AccountKeys.create()
            val pending = AccountKeys.pending(1, AccountKeys.create(), old, "rotation")
            store.select("", 1, old)
            store.savePending("", pending)
            server.enqueue(
                MockResponse().setResponseCode(401).setBody("""{"code":"invalid_account_key"}"""),
            )
            server.enqueue(
                MockResponse().setResponseCode(401).setBody("""{"code":"account_key_revoked"}"""),
            )
            server.enqueue(MockResponse().setBody("""{"names":["Wing"],"totalNames":1}"""))
            val result =
                awaitOperation<RecoveredAccount> {
                        AccountService(store) { task -> task() }
                            .recover(server.url("/").toString(), pending, it)
                    }
                    .getOrThrow()
            assertTrue(result.promoted)
            assertEquals(pending.key, store.selected[1]!!.key)
            assertEquals(3, server.requestCount)
        }
    }
    @Test
    fun generationPersistsBothIndependentBearersBeforeSendingAndKeepsRetryId() {
        MockWebServer().use { server ->
            val store = Store()
            var persistedBeforeRequest = false
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    persistedBeforeRequest = store.selected.size == 2 && store.backups.size == 2
                    return MockResponse().setBody("""{"names":[{"seat":0,"name":"pilot#ABC234"},{"seat":1,"name":"pilot-klmnopqrst"}]}""")
                }
            }
            server.start()
            val origin = server.url("/").toString()
            val service = AccountService(store) { it() }
            val id = java.util.UUID.randomUUID().toString()
            val result = awaitOperation<List<GeneratedCallsign>> { service.generate(origin, listOf(1, 0), id, it) }.getOrThrow()
            assertTrue(persistedBeforeRequest)
            assertNotEquals(result[0].key, result[1].key)
            assertTrue(result.all { it.selected })
            val first = server.takeRequest()
            assertEquals("/api/callsigns/generate", first.path)
            assertEquals("POST", first.method)
            val body = org.json.JSONObject(first.body.readUtf8())
            assertEquals(id, body.getString("requestId"))
            for (seat in 0..1) {
                assertEquals(seat, body.getJSONArray("accounts").getJSONObject(seat).getInt("seat"))
                assertEquals(store.selected[seat]!!.key, body.getJSONArray("accounts").getJSONObject(seat).getString("publicToken"))
                assertEquals(seat == 1, store.selected[seat]!!.registrationPending)
            }
            assertEquals(2, store.backups.size)
            awaitOperation<List<GeneratedCallsign>> { service.generate(origin, listOf(0, 1), id, it) }.getOrThrow()
            assertEquals(id, org.json.JSONObject(server.takeRequest().body.readUtf8()).getString("requestId"))
            service.close()
        }
    }

    @Test
    fun reservedAvailabilityHasItsOwnReasonAndNeverAnImportHint() {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse().setBody("""{"names":[{"seat":0,"name":"Bot RUST","available":false,"reason":"reserved"}]}"""))
            val service = AccountService(Store()) { it() }
            val rows = awaitOperation<List<CallsignAvailability>> { service.availability(server.url("/").toString(), listOf("Bot RUST"), it) }.getOrThrow()
            assertEquals("reserved", rows.single().reason)
            assertFalse(rows.single().available)
            service.close()
        }
    }

    @Test
    fun liveGenerationIsAtomicIdempotentAndFreshAttemptsKeepIndependentKeys() {
        val configured = System.getenv("LEQRA_TEST_SERVER")
        org.junit.Assume.assumeTrue("Set LEQRA_TEST_SERVER for the isolated Go integration", configured != null)
        val origin = requireNotNull(configured)
        val store = Store()
        val service = AccountService(store) { it() }
        try {
            val requestID = java.util.UUID.randomUUID().toString()
            val first = awaitOperation<List<GeneratedCallsign>> { service.generate(origin, listOf(0, 1), requestID, it) }.getOrThrow()
            assertNotEquals(first[0].name, first[1].name)
            assertNotEquals(first[0].key, first[1].key)
            val repeated = awaitOperation<List<GeneratedCallsign>> { service.generate(origin, listOf(0, 1), requestID, it) }.getOrThrow()
            assertEquals(first.map { it.name }, repeated.map { it.name })
            val alone = awaitOperation<List<GeneratedCallsign>> { service.generate(origin, listOf(1), requestID, it) }.getOrThrow()
            assertEquals(first[1].name, alone.single().name)
            val fresh = awaitOperation<List<GeneratedCallsign>> { service.generate(origin, listOf(0), java.util.UUID.randomUUID().toString(), it) }.getOrThrow().single()
            assertNotEquals(first[0].name, fresh.name)
            assertEquals(first[0].key, fresh.key)
            val info = awaitOperation<CheckedAccount> { service.inspect(origin, fresh.key, it) }.getOrThrow().info
            assertTrue(info.names.containsAll(listOf(first[0].name, fresh.name)))
            assertFalse(store.selected[0]!!.registrationPending)
            assertTrue(store.selected[1]!!.registrationPending)
            val reserved = awaitOperation<List<CallsignAvailability>> { service.availability(origin, listOf("Bot RUST"), it) }.getOrThrow().single()
            assertFalse(reserved.available)
            assertEquals("reserved", reserved.reason)
        } finally { service.close() }
    }

}
