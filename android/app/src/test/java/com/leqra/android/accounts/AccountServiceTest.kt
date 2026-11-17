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
    @Test
    fun scoreForCallsignUsesOnlyThatAccountsAuthoritativeProfile() {
        val info = AccountInfo(listOf("CURRENT"), 1, PublicProfile("CURRENT", -7))
        assertEquals(-7, info.scoreForCallsign("current"))
        assertNull(info.scoreForCallsign("OTHER"))
        assertEquals(0, AccountInfo(listOf("NEW"), 1, null).scoreForCallsign("NEW"))
        assertNull(AccountInfo(listOf("NEW"), 1, null).scoreForCallsign("OTHER"))
        assertNull(AccountInfo(emptyList(), 0, null).scoreForCallsign("NEW"))
        assertEquals(17, AccountInfo(listOf("Σnow"), 1, PublicProfile("Σnow", 17)).scoreForCallsign("ςNOW"))
        assertNull(AccountInfo(listOf("ı"), 1, PublicProfile("ı", 17)).scoreForCallsign("i"))
    }

    @Test
    fun unicodeEquivalentSavedNameReusesItsAuthenticatedKey() {
        MockWebServer().use { server ->
            server.start()
            val store = Store(); val old = AccountKeys.create(); val saved = AccountKeys.create()
            store.select("", 0, old)
            val service = AccountService(store) { it() }; val origin = server.url("/").toString()
            service.rememberCallsign(origin, 0, "Σnow", saved)
            server.enqueue(MockResponse().setBody("""{"names":["Σnow"],"totalNames":1,"publicProfile":{"name":"Σnow","score":17}}"""))
            val checked = awaitOperation<CheckedAccount> { service.switchCallsign(origin, 0, "ςNOW", "OLD", callback = it) }.getOrThrow()
            val request = server.takeRequest()
            assertEquals("/api/account", request.path)
            val body = org.json.JSONObject(request.body.readUtf8())
            assertEquals(saved, body.getString("publicToken")); assertTrue(body.getBoolean("signIn"))
            assertEquals(saved, checked.key); assertEquals(saved, store.selected[0]!!.key)
            assertEquals(17, checked.info.scoreForCallsign("ςNOW"))
            service.rememberCallsign(origin, 0, "i", AccountKeys.create())
            service.rememberCallsign(origin, 0, "ı", AccountKeys.create())
            assertTrue(service.savedCallsigns(origin).any { it.name == "i" })
            assertTrue(service.savedCallsigns(origin).any { it.name == "ı" })
            service.close()
        }
    }

    @Test
    fun scorePreviewDoesNotSignInOrSelectTheSavedAccount() {
        MockWebServer().use { server ->
            server.start()
            val store = Store(); val selected = AccountKeys.create(); val saved = AccountKeys.create()
            store.select("", 0, selected)
            val service = AccountService(store) { it() }; val origin = server.url("/").toString()
            server.enqueue(MockResponse().setBody("""{"names":["SAVED"],"totalNames":1,"publicProfile":{"name":"SAVED","score":42}}"""))
            val checked = awaitOperation<CheckedAccount> { service.inspect(origin, saved, it) }.getOrThrow()
            val request = server.takeRequest()
            assertEquals("/api/account", request.path)
            val body = org.json.JSONObject(request.body.readUtf8())
            assertEquals(setOf("publicToken"), body.keys().asSequence().toSet())
            assertEquals(saved, body.getString("publicToken"))
            assertEquals(42, checked.info.scoreForCallsign("SAVED"))
            assertEquals(selected, store.selected[0]!!.key)
        }
    }

    @Test
    fun savedActivationReviewExcludesSelectedKnownAndResetKeys() {
        val store = Store()
        val service = AccountService(store) { it() }
        val origin = "https://leqra.com"
        val active = AccountKeys.create()
        val next = AccountKeys.create()
        val reset = AccountKeys.create()
        val saved = AccountKeys.create()
        val secondary = AccountKeys.create()
        store.select(origin, 0, active)
        store.select(origin, 1, secondary)
        store.savePending(origin, AccountKeys.pending(0, reset, active, "rotation"))
        store.savePending(origin, AccountKeys.pending(0, active, purpose = "generate:active"))
        store.savePending(origin, AccountKeys.pending(0, secondary, purpose = "generate:secondary"))
        store.savePending(origin, AccountKeys.pending(0, next, purpose = "generate:next"))
        store.savePending(origin, AccountKeys.pending(0, next, purpose = "callsign:next"))
        store.savePending(origin, AccountKeys.pending(0, saved, purpose = "generate:saved"))
        service.rememberCallsign(origin, 0, "SAVED", saved)
        assertEquals(listOf(next), service.savedActivations(origin, 0).map { it.key })
        assertEquals(reset, service.pendingRotation(origin, 0)?.key)
        val result = awaitOperation<CheckedAccount> { service.inspectForSeat(origin, secondary, 0, it) }
        assertEquals("P1 and P2 need independent account keys.", result.exceptionOrNull()?.message)
        assertEquals(active, store.selected[0]?.key)
        service.close()
    }

    @Test
    fun reviewingAnActivationOnlyChangesSelectionAfterExplicitUse() {
        MockWebServer().use { server ->
            server.start()
            val origin = server.url("/").toString()
            val store = Store()
            val service = AccountService(store) { it() }
            val previous = AccountKeys.create()
            val candidate = AccountKeys.create()
            store.select(origin, 0, previous)
            store.savePending(origin, AccountKeys.pending(0, candidate, previous, "generate:preview"))
            val response = """{"names":["NEXT"],"totalNames":1,"publicProfile":{"name":"NEXT","score":12}}"""
            server.enqueue(MockResponse().setBody(response))
            val pending = service.savedActivations(origin, 0).single()
            val checked = awaitOperation<CheckedAccount> { service.inspectForSeat(origin, pending.key, 0, it) }.getOrThrow()
            val previewRequest = org.json.JSONObject(server.takeRequest().body.readUtf8())
            assertFalse(previewRequest.has("signIn"))
            assertEquals(previous, store.selected[0]?.key)
            assertEquals(12, checked.info.scoreForCallsign("NEXT"))

            server.enqueue(MockResponse().setBody(response))
            awaitOperation<CheckedAccount> { service.signInChecked(checked, 0, "PREVIOUS", callback = it) }.getOrThrow()
            assertTrue(org.json.JSONObject(server.takeRequest().body.readUtf8()).getBoolean("signIn"))
            assertEquals(candidate, store.selected[0]?.key)
            assertTrue(service.savedCallsigns(origin).any { it.key == previous })
            service.close()
        }
    }

    @Test
    fun delayedImportSignInCannotReplaceANewerSelectedAccount() {
        MockWebServer().use { server ->
            server.start()
            val store = Store()
            val old = AccountKeys.create()
            val imported = AccountKeys.create()
            val newer = AccountKeys.create()
            store.select("", 0, old)
            val service = AccountService(store) { it() }
            val origin = server.url("/").toString()
            val requested = CountDownLatch(1)
            val reply = CountDownLatch(1)
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    requested.countDown()
                    check(reply.await(5, TimeUnit.SECONDS))
                    return MockResponse().setBody("""{"names":["IMPORTED"],"totalNames":1,"publicProfile":{"name":"IMPORTED","score":17}}""")
                }
            }
            val finished = CountDownLatch(1)
            var result: Result<CheckedAccount>? = null
            service.signInChecked(CheckedAccount(origin, imported, AccountInfo(listOf("IMPORTED"), 1, null)), 0, "OLD") {
                result = it; finished.countDown()
            }
            assertTrue(requested.await(5, TimeUnit.SECONDS))
            service.useChecked(CheckedAccount(origin, newer, AccountInfo(listOf("NEWER"), 1, null)), 0)
            reply.countDown()
            assertTrue(finished.await(5, TimeUnit.SECONDS))
            assertTrue("Stale import should fail", result!!.isFailure)
            assertEquals("Newer account stays selected", newer, store.selected[0]!!.key)
            assertFalse(service.savedCallsigns(origin).any { it.name == "IMPORTED" })
            service.close()
        }
    }

    @Test
    fun importSignInDoesNotCommitAfterLeavingTheAccountMenu() {
        MockWebServer().use { server ->
            server.start()
            val store = Store()
            val old = AccountKeys.create(); val imported = AccountKeys.create()
            store.select("", 0, old)
            val service = AccountService(store) { it() }
            val origin = server.url("/").toString()
            server.enqueue(MockResponse().setBody("""{"names":["IMPORTED"],"totalNames":1}"""))
            val result = awaitOperation<CheckedAccount> {
                service.signInChecked(CheckedAccount(origin, imported, AccountInfo(listOf("IMPORTED"), 1, null)), 0, "OLD", canCommit = { false }, callback = it)
            }
            assertTrue(result.isFailure)
            assertEquals(old, store.selected[0]!!.key)
            assertTrue(service.savedCallsigns(origin).isEmpty())
            service.close()
        }
    }

    @Test
    fun savedCallsignCannotBecomeBothSeatsWhileSignInIsPending() {
        MockWebServer().use { server ->
            server.start()
            val store = Store()
            val oldP1 = AccountKeys.create(); val oldP2 = AccountKeys.create(); val saved = AccountKeys.create()
            store.select("", 0, oldP1); store.select("", 1, oldP2)
            val service = AccountService(store) { it() }; val origin = server.url("/").toString()
            service.rememberCallsign(origin, 0, "SAVED", saved)
            val requested = CountDownLatch(1); val reply = CountDownLatch(1); val finished = CountDownLatch(1)
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    requested.countDown(); check(reply.await(5, TimeUnit.SECONDS))
                    return MockResponse().setBody("""{"names":["SAVED"],"totalNames":1}""")
                }
            }
            var result: Result<CheckedAccount>? = null
            service.switchCallsign(origin, 0, "SAVED", "OLD") { result = it; finished.countDown() }
            assertTrue(requested.await(5, TimeUnit.SECONDS))
            service.useChecked(CheckedAccount(origin, saved, AccountInfo(listOf("SAVED"), 1, null)), 1)
            reply.countDown(); assertTrue(finished.await(5, TimeUnit.SECONDS))
            assertTrue(result!!.isFailure)
            assertEquals(oldP1, store.selected[0]!!.key); assertEquals(saved, store.selected[1]!!.key)
            service.close()
        }
    }

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

        override fun forgetAccount(origin: String, key: String) {
            for (seat in 0..1) clearIfMatching(origin, seat, key)
            for (seat in 0..1) pending(origin, seat).filter { it.key == key || it.previousKey == key }.forEach {
                removePending(origin, it.id)
                if (it.key != key) savePending(origin, PendingAccount(it.id,it.seat,it.key,null,it.purpose))
            }
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
    fun newCallsignPersistsCandidateBeforeCreateAndKeepsOldAccountOnFailure() {
        MockWebServer().use { server ->
            server.start()
            val store = Store(); val old = AccountKeys.create(); store.select("",0,old)
            val service = AccountService(store) { it() }
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    assertEquals("/api/account/create", request.path)
                    val body = org.json.JSONObject(request.body.readUtf8())
                    assertEquals("NEW", body.getString("name")); assertFalse(body.has("score"))
                    assertNotEquals(old, body.getString("publicToken"))
                    assertEquals(old, store.selected[0]!!.key)
                    assertTrue(store.backups.any { it.key == body.getString("publicToken") })
                    return MockResponse().setResponseCode(409).setBody("""{"code":"callsign_taken","message":"Taken"}""")
                }
            }
            val result = awaitOperation<CheckedAccount> { service.switchCallsign(server.url("/").toString(),0,"NEW","OLD",callback=it) }
            assertTrue(result.isFailure); assertEquals(old,store.selected[0]!!.key)
            assertTrue(service.savedCallsigns(server.url("/").toString()).any { it.name == "OLD" && it.key == old })
        }
    }

    @Test
    fun failedCreateRetriesTheSameDurablySavedCandidate() {
        MockWebServer().use { server ->
            server.start(); val store=Store(); val old=AccountKeys.create(); store.select("",0,old)
            val service=AccountService(store) { it() }; val origin=server.url("/").toString()
            server.enqueue(MockResponse().setResponseCode(503).setBody("""{"code":"server_busy"}"""))
            server.enqueue(MockResponse().setBody("""{"names":["NEW"],"totalNames":1}"""))
            assertTrue(awaitOperation<CheckedAccount> { service.switchCallsign(origin,0,"NEW","OLD",callback=it) }.isFailure)
            val first=org.json.JSONObject(server.takeRequest().body.readUtf8()).getString("publicToken")
            val next=awaitOperation<CheckedAccount> { service.switchCallsign(origin,0,"NEW","OLD",callback=it) }.getOrThrow()
            val second=org.json.JSONObject(server.takeRequest().body.readUtf8()).getString("publicToken")
            assertEquals(first,second); assertEquals(first,next.key)
            assertTrue(store.backups.none { it.purpose.startsWith("callsign:") })
        }
    }

    @Test
    fun expiredSelectedAccountUsesNewKeyEvenForSameSpelling() {
        MockWebServer().use { server ->
            server.start(); val store=Store(); val old=AccountKeys.create(); store.select("",0,old)
            val service=AccountService(store) { it() }; val origin=server.url("/").toString()
            server.enqueue(MockResponse().setResponseCode(401).setBody("""{"code":"invalid_account_key"}"""))
            server.enqueue(MockResponse().setBody("""{"names":["SAME"],"totalNames":1}"""))
            val result=awaitOperation<CheckedAccount> { service.switchCallsign(origin,0,"SAME","SAME",callback=it) }.getOrThrow()
            server.takeRequest()
            val create=org.json.JSONObject(server.takeRequest().body.readUtf8())
            assertNotEquals(old,create.getString("publicToken")); assertEquals(result.key,store.selected[0]!!.key)
        }
    }

    @Test
    fun savedCallsignSwitchSignsInWithItsOwnKeyAndScore() {
        MockWebServer().use { server ->
            server.start()
            val store=Store(); val old=AccountKeys.create(); val saved=AccountKeys.create(); store.select("",0,old)
            val service=AccountService(store) { it() }; val origin=server.url("/").toString()
            service.rememberCallsign(origin,0,"SAVED",saved)
            server.enqueue(MockResponse().setBody("""{"names":["SAVED"],"totalNames":1,"publicProfile":{"name":"SAVED","score":37}}"""))
            val checked=awaitOperation<CheckedAccount> { service.switchCallsign(origin,0,"SAVED","OLD",callback=it) }.getOrThrow()
            val request=server.takeRequest(); assertEquals("/api/account",request.path)
            val body=org.json.JSONObject(request.body.readUtf8()); assertTrue(body.getBoolean("signIn")); assertEquals(saved,body.getString("publicToken"))
            assertEquals(37,checked.info.publicProfile!!.score); assertEquals(saved,store.selected[0]!!.key)
            assertEquals(setOf("OLD","SAVED"),service.savedCallsigns(origin).map { it.name }.toSet())
        }
    }

    @Test
    fun expiredSavedCallsignCreatesNewKeyWithoutResurrectingItsScore() {
        MockWebServer().use { server ->
            server.start()
            val store=Store(); val old=AccountKeys.create(); val expired=AccountKeys.create(); store.select("",0,old)
            val service=AccountService(store) { it() }; val origin=server.url("/").toString()
            service.rememberCallsign(origin,0,"EXPIRED",expired)
            server.enqueue(MockResponse().setResponseCode(401).setBody("""{"code":"invalid_account_key"}"""))
            server.enqueue(MockResponse().setBody("""{"names":["EXPIRED"],"totalNames":1,"publicProfile":{"name":"EXPIRED","score":0}}"""))
            val checked=awaitOperation<CheckedAccount> { service.switchCallsign(origin,0,"EXPIRED","OLD",callback=it) }.getOrThrow()
            server.takeRequest(); val create=org.json.JSONObject(server.takeRequest().body.readUtf8())
            assertNotEquals(expired,create.getString("publicToken")); assertEquals(0,checked.info.publicProfile!!.score)
            assertEquals(checked.key,store.selected[0]!!.key)
        }
    }

    @Test
    fun releaseDeletesOnlyTheConfirmedAccountAndItsPendingReferences() {
        MockWebServer().use { server ->
            server.start(); val store=Store(); val old=AccountKeys.create(); val other=AccountKeys.create()
            store.select("",0,old); store.select("",1,other)
            val service=AccountService(store) { it() }; val origin=server.url("/").toString()
            service.rememberCallsign(origin,0,"OLD",old); service.rememberCallsign(origin,1,"OTHER",other)
            store.savePending(origin,AccountKeys.pending(0,AccountKeys.create(),old,"rotation"))
            server.enqueue(MockResponse().setResponseCode(503).setBody("""{"code":"server_busy"}"""))
            assertTrue(awaitOperation<Unit> { service.release(origin,old,it) }.isFailure)
            assertEquals(old,store.selected[0]!!.key); assertEquals(3,store.backups.size)
            server.enqueue(MockResponse().setBody("""{"released":true}"""))
            awaitOperation<Unit> { service.release(origin,old,it) }.getOrThrow()
            val request=server.takeRequest(); assertEquals("/api/account/release",request.path)
            val body=org.json.JSONObject(request.body.readUtf8()); assertEquals(setOf("publicToken"),body.keys().asSequence().toSet())
            assertEquals(old,body.getString("publicToken")); assertNull(store.selected[0]); assertEquals(other,store.selected[1]!!.key)
            assertTrue(store.backups.all { it.key != old && it.previousKey != old })
            assertTrue(store.backups.any { it.purpose == "rotation" })
            assertEquals(listOf("OTHER"),service.savedCallsigns(origin).map { it.name })
        }
    }

    @Test
    fun releasedSelectedAccountCanRegisterItsNewLocalNameOnNextPlay() {
        MockWebServer().use { server ->
            server.start(); val store=Store(); val old=AccountKeys.create(); store.select("",0,old)
            val service=AccountService(store) { it() }; val origin=server.url("/").toString()
            server.enqueue(MockResponse().setBody("""{"released":true}"""))
            awaitOperation<Unit> { service.release(origin,old,it) }.getOrThrow()
            val replacement=AccountKeys.create(); store.select(origin,0,replacement,true)
            server.enqueue(MockResponse().setBody("""{"names":["pilot#ABCDEF"],"totalNames":1}"""))
            val registered=awaitOperation<CheckedAccount> { service.switchCallsign(origin,0,"pilot#ABCDEF","pilot#ABCDEF",callback=it) }.getOrThrow()
            server.takeRequest(); val request=server.takeRequest()
            assertEquals("/api/account/create",request.path)
            val body=org.json.JSONObject(request.body.readUtf8())
            assertEquals(replacement,body.getString("publicToken")); assertEquals("pilot#ABCDEF",body.getString("name"))
            assertEquals(replacement,registered.key); assertFalse(store.selected[0]!!.registrationPending)
        }
    }

    @Test
    fun publicPreviewCarriesBotDifficultyAndKeepsLegacyFieldsOptional() {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse().setBody("""{"players":1,"tankCount":4,"capacity":32,"leaders":[{"id":1,"name":"Pilot","score":9},{"id":2,"name":"Bot 2 - Normal","score":8,"bot":true,"difficulty":"normal"},{"id":3,"name":"Bot 3 - Dumb","score":7,"bot":true,"difficulty":"dumb"},{"id":4,"name":"Bot 4 - Godlike","score":6,"bot":true,"difficulty":"godlike"}]}"""))
            val result = awaitOperation<PublicStatus> { AccountService(Store()) { it() }.publicStatus(server.url("/").toString(), it) }.getOrThrow()
            assertEquals(listOf("", "normal", "dumb", "godlike"), result.leaders.map { it.difficulty })
            assertEquals("Bot 2 - Normal", result.leaders[1].name)
            assertEquals("GET", server.takeRequest().method)
        }
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
            assertTrue(store.backups.none { it.purpose == "rotation" })
            assertTrue(service.savedCallsigns(server.url("/").toString()).any {
                it.name == "Pilot" && it.key == result.checked.key
            })
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
            assertEquals(2, store.backups.count { !it.purpose.startsWith("saved:") })
            assertTrue(service.savedCallsigns(origin).any {
                it.name == "pilot#ABC234" && it.key == store.selected[0]!!.key
            })
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
    fun staleExplicitGenerationRetainsRecoveryWithoutSelectingTheNewAccount() {
        MockWebServer().use { server ->
            server.start()
            val store = Store()
            val previous = AccountKeys.create()
            store.select("", 0, previous)
            val service = AccountService(store) { it() }
            val origin = server.url("/").toString()
            val id = java.util.UUID.randomUUID().toString()
            server.enqueue(MockResponse().setBody("""{"names":[{"seat":0,"name":"pilot#ABC234"}]}"""))
            val result = awaitOperation<List<GeneratedCallsign>> {
                service.generate(origin, listOf(0), id, freshAccount = true, canCommit = { false }, callback = it)
            }.getOrThrow().single()
            assertFalse(result.selected)
            assertNotEquals(previous, result.key)
            assertEquals(previous, store.selected[0]!!.key)
            assertTrue(store.backups.any { it.key == result.key && it.purpose == "generate:$id" })
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
            assertEquals(listOf(fresh.name), info.names)
            assertFalse(store.selected[0]!!.registrationPending)
            assertTrue(store.selected[1]!!.registrationPending)
            val reserved = awaitOperation<List<CallsignAvailability>> { service.availability(origin, listOf("Bot RUST"), it) }.getOrThrow().single()
            assertFalse(reserved.available)
            assertEquals("reserved", reserved.reason)
        } finally { service.close() }
    }

}
