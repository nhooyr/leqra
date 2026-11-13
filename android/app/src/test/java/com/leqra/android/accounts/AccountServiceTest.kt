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
}
