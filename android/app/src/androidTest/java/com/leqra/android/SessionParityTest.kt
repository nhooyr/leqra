package com.leqra.android

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.leqra.android.accounts.isolatedAccountContext
import com.leqra.android.network.NetworkEvent
import com.leqra.android.network.NetworkWelcome
import com.leqra.core.*
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SessionParityTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val testWorld = ArenaWorld(8400.0, 8400.0, 100, 100)

    @Test
    fun fixedRoomWatchingPrimaryKeepsSecondaryControlsAndAudio() {
        val context = context()
        val session = main { GameSession(context) }
        try {
            main {
                val joined = NetworkWelcome.parse(JSONObject().put("id", 1).put("member", 10)
                    .put("spectating", true).put("localId", 2).put("localMember", 20))
                set(session, "online", true)
                set(session, "infinity", false)
                set(session.network, "connected", true)
                set(session.network, "welcome", joined)
                event(session, NetworkEvent.Welcome(joined))
                event(session, NetworkEvent.State(snapshot(1).apply { tanks = tanks.filter { it.id == 2 } }))
                assertTrue(session.spectating)
                assertEquals(2, session.localID2)
                assertTrue(session.canControlSecondary)
                assertTrue(session.hasLocalPlayer)
                assertTrue(session.audioGameplayActive)
                val p1 = session.network.lastInputSequence
                val p2 = session.network.lastLocalInputSequence
                session.input2 = GameInput(fire = true)
                session.input2 = GameInput()
                assertEquals("P2 press and release are sent while P1 watches", p2 + 2, session.network.lastLocalInputSequence)
                assertEquals(p1, session.network.lastInputSequence)
                session.input2 = GameInput(forward = true)
                session.frame(System.nanoTime())
                session.neutral()
                assertTrue(session.network.lastLocalInputSequence > p2 + 2)
                assertEquals("Spectating P1 never sends movement or neutral packets", p1, session.network.lastInputSequence)
                val hud = NativeHudView(context)
                hud.update(session.snapshot, session.localID, session.localID2, false, false, true)
                assertTrue(hud.contentDescription.toString().contains("Secondary (P2)"))
                val view = com.leqra.android.render.NativeArenaView(context)
                try {
                    view.showControls = false
                    view.mouseInputEnabled = true
                    val mouse = android.view.MotionEvent.obtain(0, 0, android.view.MotionEvent.ACTION_HOVER_MOVE, 80f, 80f, 0)
                    mouse.source = android.view.InputDevice.SOURCE_MOUSE
                    try { assertTrue(view.onGenericMotionEvent(mouse)); assertTrue(view.hasMouseInput) }
                    finally { mouse.recycle() }
                } finally { view.release() }
                set(session, "arenaActive", true)
                set(session.arenaNetwork, "welcome", joined)
                assertFalse("Infinity spectators cannot retain a playing P2", session.canControlSecondary)
                assertFalse(session.hasLocalPlayer)
                set(session.network, "welcome", welcome(local = true))
                set(session.arenaNetwork, "welcome", welcome(local = true))
                assertTrue("An active Infinity primary retains P2 controls", session.canControlSecondary)
                assertTrue(session.hasLocalPlayer)
            }
        } finally { main { session.release() }; context.noBackupFilesDir.deleteRecursively() }
    }

    @Test
    fun unchangedPendingCallsignBlurCannotInterruptOfflinePlay() {
        val context = context()
        context.getSharedPreferences("leqra-settings", 0).edit()
            .putString("server", "http://127.0.0.1:1").putString("callsign", "OFFLINE")
            .putString("localCallsign", "SECOND").putBoolean("autoPending0", false)
            .putBoolean("autoPending1", false).putBoolean("publicSelected", false).commit()
        val session = main { GameSession(context) }
        try {
            main {
                session.store.prepareRegistration(session.server, 0)
                session.botCount = 0
                session.play()
                assertEquals(Screen.PLAYING, session.screen)
                session.renameCallsign(session.callsign)
                assertEquals("Focus changes keep the current offline match", Screen.PLAYING, session.screen)
                assertEquals(false, field(session, "switchingCallsign"))
                assertTrue(session.store.selected(session.server, 0)!!.registrationPending)
            }
        } finally { main { session.release() }; context.noBackupFilesDir.deleteRecursively() }
    }

    @Test
    fun customCallsignCanBeStagedInOfflineReadyRoomAndSurvivesColdLoad() {
        val context = context()
        val origin = "http://127.0.0.1:1"
        context.getSharedPreferences("leqra-settings", 0).edit()
            .putString("server", origin).putString("callsign", "ORIGINAL")
            .putString("localCallsign", "SECOND").putBoolean("autoPending0", false)
            .putBoolean("autoPending1", false).putBoolean("publicSelected", false).commit()
        var session = main { GameSession(context) }
        val old = com.leqra.android.accounts.AccountKeys.create()
        try {
            main { session.store.select(origin, 0, old); session.renameCallsign("CUSTOM") }
            eventually("Offline custom callsign was not staged") { field(session, "switchingCallsign") == false && session.callsign == "CUSTOM" }
            val key = main {
                val credential = session.store.selected(origin, 0)!!
                assertTrue(credential.registrationPending)
                assertNotEquals(old, credential.key)
                assertTrue(session.accounts.savedCallsigns(origin).any { it.name == "ORIGINAL" && it.key == old })
                session.release()
                session = GameSession(context)
                assertEquals("CUSTOM", session.callsign)
                assertEquals(credential.key, session.store.selected(origin, 0)!!.key)
                session.botCount = 0; session.play()
                assertEquals(Screen.PLAYING, session.screen)
                credential.key
            }
            assertNotEquals(old, key)
        } finally { main { session.release() }; context.noBackupFilesDir.deleteRecursively() }
    }

    @Test
    fun pendingReleaseHoldsGameStartAndAlwaysUnblocksIt() {
        for (succeeds in listOf(true, false)) {
            val context = context()
            val server = java.net.ServerSocket(0).apply { soTimeout = 5000 }
            val requested = java.util.concurrent.CountDownLatch(1)
            val respond = java.util.concurrent.CountDownLatch(1)
            val origin = "http://127.0.0.1:${server.localPort}"
            context.getSharedPreferences("leqra-settings", 0).edit().putString("server", origin)
                .putString("callsign", "ORIGINAL").putString("localCallsign", "SECOND")
                .putBoolean("autoPending0", false).putBoolean("autoPending1", false).putBoolean("publicSelected", false).commit()
            val worker = Thread {
                server.accept().use { socket ->
                    val input = socket.getInputStream().bufferedReader(); var length = 0
                    while (true) { val line = input.readLine(); if (line.isEmpty()) break; if (line.startsWith("Content-Length:", true)) length = line.substringAfter(':').trim().toInt() }
                    repeat(length) { input.read() }; requested.countDown(); check(respond.await(5, TimeUnit.SECONDS))
                    val body = if (succeeds) """{"released":true}""" else """{"code":"server_busy","message":"Try again"}"""
                    val status = if (succeeds) "200 OK" else "503 Busy"
                    socket.getOutputStream().write("HTTP/1.1 $status\r\nContent-Length: ${body.length}\r\nConnection: close\r\n\r\n$body".toByteArray())
                }
            }.apply { start() }
            val session = main { GameSession(context) }
            val old = com.leqra.android.accounts.AccountKeys.create()
            var completed: Result<Unit>? = null
            try {
                main { session.store.select(origin, 0, old); session.releaseCallsign(old) { completed = it } }
                assertTrue(requested.await(5, TimeUnit.SECONDS))
                main {
                    assertTrue(session.releasingCallsign); assertFalse(session.canImportAccount)
                    session.callsign = "CHANGED"; session.localCallsign = "CHANGED TWO"
                    session.renameCallsign("RENAMED"); session.generateCallsign(1)
                    assertEquals("ORIGINAL", session.callsign); assertEquals("SECOND", session.localCallsign)
                    session.play(); session.share(); session.join("ANY"); session.findMatch()
                    assertEquals("No arena starts with an account being released", Screen.READY, session.screen)
                }
                respond.countDown()
                eventually("Release did not finish") { completed != null }
                main {
                    assertEquals(succeeds, completed!!.isSuccess)
                    assertFalse(session.releasingCallsign)
                    if (succeeds) assertNotEquals(old, session.store.selected(origin, 0)!!.key)
                    else { assertEquals(old, session.store.selected(origin, 0)!!.key); assertEquals("ORIGINAL", session.callsign) }
                    session.botCount = 0; session.play()
                    assertEquals("Release completion unblocks Play", Screen.PLAYING, session.screen)
                    assertEquals(session.callsign, session.snapshot.tanks.first().name)
                }
            } finally { respond.countDown(); worker.join(6000); server.close(); main { session.release() }; context.noBackupFilesDir.deleteRecursively() }
        }
    }

    @Test
    fun delayedNameGenerationFailureCannotInterruptAnAlreadyStartedGame() {
        val context = context()
        val server = java.net.ServerSocket(0).apply { soTimeout = 5000 }
        val requested = java.util.concurrent.CountDownLatch(1)
        val respond = java.util.concurrent.CountDownLatch(1)
        val origin = "http://127.0.0.1:${server.localPort}"
        context.getSharedPreferences("leqra-settings", 0).edit().putString("server", origin)
            .putString("callsign", "ORIGINAL").putString("localCallsign", "SECOND")
            .putBoolean("autoPending0", false).putBoolean("autoPending1", false).putBoolean("publicSelected", false).commit()
        val worker = Thread {
            server.accept().use { socket ->
                val input = socket.getInputStream().bufferedReader(); var length = 0
                while (true) { val line = input.readLine(); if (line.isEmpty()) break; if (line.startsWith("Content-Length:", true)) length = line.substringAfter(':').trim().toInt() }
                repeat(length) { input.read() }; requested.countDown(); check(respond.await(5, TimeUnit.SECONDS))
                val body = """{"code":"server_busy","message":"DELAYED FAILURE"}"""
                socket.getOutputStream().write("HTTP/1.1 503 Busy\r\nContent-Type: application/json\r\nContent-Length: ${body.length}\r\nConnection: close\r\n\r\n$body".toByteArray())
            }
        }.apply { start() }
        val session = main { GameSession(context) }
        val old = com.leqra.android.accounts.AccountKeys.create()
        val errors = mutableListOf<String>()
        try {
            main { session.store.select(origin, 0, old); session.notifyError = { errors += it }; session.generateCallsign(0) }
            assertTrue(requested.await(5, TimeUnit.SECONDS))
            main { session.botCount = 0; session.play(); assertEquals(Screen.PLAYING, session.screen) }
            respond.countDown()
            eventually("Generation request did not finish") { field(session, "switchingCallsign") == false }
            main {
                assertEquals(Screen.PLAYING, session.screen); assertEquals(old, session.store.selected(origin, 0)!!.key)
                assertEquals("ORIGINAL", session.callsign); assertTrue("A stale failure cannot show an error dialog", errors.isEmpty())
            }
        } finally { respond.countDown(); worker.join(6000); server.close(); main { session.release() }; context.noBackupFilesDir.deleteRecursively() }
    }

    @Test
    fun delayedRenameCannotReplaceTheAccountOrLeaveAnAlreadyStartedGame() {
        val context = context()
        val server = java.net.ServerSocket(0).apply { soTimeout = 5000 }
        val requested = java.util.concurrent.CountDownLatch(1)
        val respond = java.util.concurrent.CountDownLatch(1)
        val origin = "http://127.0.0.1:${server.localPort}"
        context.getSharedPreferences("leqra-settings", 0).edit().putString("server",origin)
            .putString("callsign","ORIGINAL").putString("localCallsign","SECOND")
            .putBoolean("autoPending0",false).putBoolean("autoPending1",false).putBoolean("publicSelected",false).commit()
        val worker = Thread {
            server.accept().use { socket ->
                val input=socket.getInputStream().bufferedReader();var length=0
                while(true){val line=input.readLine();if(line.isEmpty())break;if(line.startsWith("Content-Length:",true))length=line.substringAfter(':').trim().toInt()}
                repeat(length){input.read()};requested.countDown();check(respond.await(5,TimeUnit.SECONDS))
                val body="""{"names":["NEW"],"totalNames":1}"""
                socket.getOutputStream().write("HTTP/1.1 200 OK\r\nContent-Length: ${body.length}\r\nConnection: close\r\n\r\n$body".toByteArray())
            }
        }.apply{start()}
        val session=main{GameSession(context)}
        val old=com.leqra.android.accounts.AccountKeys.create()
        try {
            main {session.store.select(origin,0,old);session.renameCallsign("NEW")}
            assertTrue(requested.await(5,TimeUnit.SECONDS))
            main {session.botCount=0;session.play();assertEquals(Screen.PLAYING,session.screen)}
            respond.countDown()
            eventually("Rename request did not finish"){field(session,"switchingCallsign")==false}
            main {assertEquals(Screen.PLAYING,session.screen);assertEquals(old,session.store.selected(origin,0)!!.key)}
        } finally {respond.countDown();worker.join(6000);server.close();main{session.release()};context.noBackupFilesDir.deleteRecursively()}
    }

    @Test
    fun delayedExplicitRandomNameNeverOverwritesANewerDraftOrSelectsItsAccount() {
        val context = context()
        val server = java.net.ServerSocket(0).apply { soTimeout = 5000 }
        val requested = java.util.concurrent.CountDownLatch(1)
        val respond = java.util.concurrent.CountDownLatch(1)
        val origin = "http://127.0.0.1:${server.localPort}"
        context.getSharedPreferences("leqra-settings", 0).edit()
            .putString("server", origin).putString("callsign", "ORIGINAL")
            .putString("localCallsign", "SECOND").putBoolean("autoPending0", false)
            .putBoolean("autoPending1", false).putBoolean("publicSelected", false).commit()
        val worker = Thread {
            server.accept().use { socket ->
                val input = socket.getInputStream().bufferedReader()
                var length = 0
                while (true) {
                    val line = input.readLine()
                    if (line.isEmpty()) break
                    if (line.startsWith("Content-Length:", ignoreCase = true)) length = line.substringAfter(':').trim().toInt()
                }
                repeat(length) { input.read() }
                requested.countDown()
                check(respond.await(5, TimeUnit.SECONDS))
                val body = """{"names":[{"seat":0,"name":"pilot#ABC234"}]}"""
                socket.getOutputStream().write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${body.length}\r\nConnection: close\r\n\r\n$body".toByteArray())
            }
        }.apply { start() }
        val session = main { GameSession(context) }
        val previous = com.leqra.android.accounts.AccountKeys.create()
        try {
            main {
                session.store.select(origin, 0, previous)
                session.generateCallsign(0)
            }
            assertTrue(requested.await(5, TimeUnit.SECONDS))
            main { session.callsign = "NEW DRAFT"; session.callsign = "ORIGINAL" }
            respond.countDown()
            eventually("Generation response did not finish") { field(session, "switchingCallsign") == false }
            main {
                assertEquals("ORIGINAL", session.callsign)
                assertEquals(previous, session.store.selected(origin, 0)!!.key)
                assertTrue(session.store.pending(origin, 0).any { it.purpose.startsWith("generate:") && it.key != previous })
            }
        } finally {
            respond.countDown(); worker.join(6000); server.close()
            main { session.release() }; context.noBackupFilesDir.deleteRecursively()
        }
    }

    @Test
    fun publicInfinityRoomUpdatesKeepArenaModeUntilItEnds() {
        val context = context()
        val session = main { GameSession(context) }
        try {
            main {
                set(session, "online", true)
                set(session, "arenaActive", true)
                val arenaWelcome = NetworkWelcome.parse(JSONObject().put("id", 9).put("localId", 10).put("seed", 42))
                event(session, NetworkEvent.Welcome(arenaWelcome), arena = true)
                val room = JSONObject().put("type", "room").put("code", "ROOM").put("phase", "lobby")
                    .put("infinityPublic", true).put("infinityActive", true)
                    .put("rules", GameSession.rulesJson(RoomRules.localDefaults("koth")))

                event(session, NetworkEvent.Packet(room))
                assertEquals("koth", session.mode)
                assertFalse(session.rules.infinity)
                assertEquals(Screen.PLAYING, session.screen)
                assertTrue("The retained room cannot put a running Infinity arena into fixed match mode", session.infinity)
                assertEquals(10, session.localID2)

                event(session, NetworkEvent.Packet(room.put("infinityActive", false)))
                assertEquals(Screen.READY, session.screen)
                assertFalse("Returning to the retained room restores its finite mode", session.infinity)
            }
        } finally { main { session.release() }; context.noBackupFilesDir.deleteRecursively() }
    }

    @Test
    fun onlineModeAndRulesWaitForTheServerToAcceptThem() {
        val server = InstrumentationRegistry.getArguments().getString("server")
        assumeTrue("A disposable current Go backend is required", server != null)
        val context = context()
        val suffix = UUID.randomUUID().toString().take(8)
        context.getSharedPreferences("leqra-settings", 0).edit()
            .putString("server", server).putString("callsign", "Rules $suffix").putBoolean("autoPending0", false)
            .putBoolean("publicSelected", false).commit()
        val session = main { GameSession(context) }
        val errors = mutableListOf<String>()
        try {
            main {
                session.notifyError = { errors += it }
                session.botCount = 4
                session.share()
            }
            eventually("Five pilots did not enter the Elimination room") {
                session.room?.optJSONArray("players")?.length() == 5 && session.mode == "elimination"
            }
            main {
                session.selectMode("survival")
                assertEquals("elimination", session.mode)
            }
            eventually("The server did not reject a five-tank Survival squad") {
                errors.any { it.contains("Survival supports up to four allied tanks") }
            }
            main {
                assertEquals("elimination", session.mode)
                assertEquals("elimination", session.rules.mode)
                session.selectMode("koth")
                assertEquals("elimination", session.mode)
            }
            eventually("The accepted King of the Hill mode did not update the lobby") { session.mode == "koth" }
            main {
                val previous = session.rules
                session.changeRules(previous.copy(scoreTarget = 17, friendlyFire = true))
                assertEquals(previous, session.rules)
            }
            eventually("The accepted rules did not update the lobby") {
                session.rules.scoreTarget == 17 && session.rules.friendlyFire
            }
        } finally { main { session.leave(); session.release() }; context.noBackupFilesDir.deleteRecursively() }
    }

    @Test
    fun publicInfinityLeavesPrivateRulesAndRosterIntact() {
        val context = context()
        var session = main { GameSession(context) }
        try {
            main {
                assertTrue(session.publicSelected)
                assertEquals("elimination", session.mode)
                assertTrue(session.localBots.isEmpty())
                assertEquals(7319, session.maze?.seed)
                assertEquals(listOf(session.callsign), session.snapshot.tanks.map { it.name })
                assertEquals(listOf("cannon", "shield"), session.snapshot.pickups.map { it.type })
                session.togglePublic(false)
                assertEquals(listOf("Rust", "Vapor", "Ember"), session.localBots.map { it.name })
                session.selectMode("koth")
                session.changeRules(session.rules.copy(teamMode = "teams", scoreTarget = 18))
                session.botCount = 0
                repeat(3) { session.addLocalBot() }
                val bots = session.localBots.toList()
                assertEquals(listOf(2, 1, 2), bots.map { it.team })
                session.togglePublic(true)
                assertEquals("koth", session.mode)
                assertEquals(18, session.rules.scoreTarget)
                session.release()
                session = GameSession(context)
                assertTrue(session.publicSelected)
                session.togglePublic(false)
                assertEquals("koth", session.mode)
                assertEquals(18, session.rules.scoreTarget)
                assertEquals(bots, session.localBots)
            }
        } finally { main { session.release() }; context.noBackupFilesDir.deleteRecursively() }
    }

    @Test
    fun namedPresetsRestoreAPairedSquadWhileKeepingLegacyRulesPresets() {
        val context = context()
        val prefs = context.getSharedPreferences("leqra-settings", 0)
        prefs.edit().putBoolean("publicSelected", false).putString(
            "preset", GameSession.rulesJson(RoomRules.localDefaults("koth")).toString(),
        ).commit()
        var session = main { GameSession(context) }
        try {
            main {
                assertEquals("Saved preset", session.presets.single().name)
                session.botCount = 2
                session.localSelected = true
                session.localColorIndex = 5
                session.selectMode("survival")
                session.changeRules(session.rules.copy(scoreTarget = 7))
                val guard = session.localBots.first()
                session.updateLocalBot(guard.id, name = "Veteran", difficulty = "hard")
                val squad = session.localBots.toList()
                assertTrue(session.savePreset("A-team"))
                session.selectMode("elimination")
                session.localSelected = false
                session.botCount = 7
                session.save()
                session.release()
                session = GameSession(context)
                assertEquals(listOf("Saved preset", "A-team"), session.presets.map { it.name })
                assertTrue(session.loadPreset(session.presets.last()))
                assertEquals("survival", session.mode)
                assertEquals(7, session.rules.scoreTarget)
                assertEquals(squad, session.localBots)
                assertTrue(session.localSelected)
                assertEquals(5, session.localColorIndex)
                assertTrue(session.loadPreset(session.presets.first()))
                assertEquals("koth", session.mode)
                assertEquals(squad, session.localBots)
                assertTrue(session.localSelected)
            }
        } finally { main { session.release() }; context.noBackupFilesDir.deleteRecursively() }
    }

    @Test
    fun incompatibleSurvivalChangesNeverDeleteTheRosterOrChangePublicSelection() {
        val context = context()
        context.getSharedPreferences("leqra-settings", 0).edit().putString("server", "http://127.0.0.1:1")
            .putString("callsign", "Audit Pilot").putString("localCallsign", "Audit Wing")
            .putBoolean("autoPending0", false).putBoolean("autoPending1", false).putBoolean("publicSelected", false).commit()
        var session = main { GameSession(context) }
        try {
            main {
                session.localSelected = false
                session.selectMode("elimination")
                session.botCount = 6
                session.localBots.forEachIndexed { i, bot -> session.updateLocalBot(bot.id,
                    name = "Custom $i", colorIndex = i + 1, difficulty = if (i % 2 == 0) "hard" else "easy", team = i % 2 + 1) }
                session.togglePublic(true)
                val roster = session.localBots.toList()
                val rules = session.rules.copy()
                session.selectMode("survival")
                assertEquals("elimination", session.mode)
                assertTrue(session.publicSelected)
                assertEquals(rules, session.rules)
                assertEquals(roster, session.localBots)
                assertTrue(session.configurationError?.contains("four squad tanks") == true)
                session.changeRules(RoomRules.localDefaults("survival"))
                assertEquals(rules, session.rules)
                assertEquals(roster, session.localBots)
                session.save()
                session.release()
                session = GameSession(context)
                assertEquals(roster, session.localBots)
                assertTrue(session.publicSelected)
                session.selectMode("elimination")
                assertEquals(roster, session.localBots)
                assertFalse(session.publicSelected)
                session.botCount = 3
                session.selectMode("survival")
                val squad = session.localBots.toList()
                session.localSelected = true
                session.save()
                assertFalse("P2 cannot silently replace a configured squad bot", session.localSelected)
                assertEquals(squad, session.localBots)
                assertNotNull(session.configurationError)
                set(session, "online", true)
                session.localSelected = true
                session.save()
                assertTrue("Online P2 stays enabled until an actual Leave", session.localSelected)
                session.leave()
                assertFalse("Leave restores the earlier personal P2 preference", session.localSelected)
                assertEquals(squad, session.localBots)
                session.save()
                assertEquals("Saving after Leave cannot delete a squad bot", squad, session.localBots)
                session.removeLocalBot(squad.last().id)
                session.localSelected = true
                assertTrue(session.localSelected)
                assertNull(session.configurationError)
                session.togglePublic(true)
                session.selectMode("infinity")
                assertFalse("Explicit room Infinity is local", session.publicSelected)
                session.togglePublic(true)
                session.changeRules(RoomRules.localDefaults("elimination"))
                assertFalse("Applying a local preset is local", session.publicSelected)
                session.save()
            }
        } finally { main { session.release() }; context.noBackupFilesDir.deleteRecursively() }
    }

    @Test
    fun subphysicsFireEdgesRearmBothSeatsAndReachOnlineSequenceChronology() {
        for (finite in listOf(false, true)) for (power in listOf("rapid", "scatter", "homing", "grenade", "laser", "cannon")) {
            val context = context()
            val session = main { GameSession(context) }
            try {
                main {
                    val arena = PracticeArena(42, "P1", 0, 0, world = if (finite) ArenaWorld(10000.0, 10000.0, 120, 120) else null)
                    arena.configureLocal("P2", 1)
                    arena.snapshot.tanks.forEachIndexed { index, tank ->
                        tank.x = 42.0 + index * 24 * 84; tank.y = tank.x; tank.angle = 0.0
                        tank.invulnerable = 0.0; tank.spawnProtected = false
                        PracticeArena.applyPower(tank, power)
                        if (power == "rapid") tank.machineRounds = 1 else tank.charges = 1
                    }
                    set(session, "practice", arena); set(session, "fixed", null)
                    set(session, "online", false); set(session, "screen", Screen.PLAYING)
                    set(session, "infinity", !finite); set(session, "localID", 1); set(session, "localID2", 2)
                    set(session, "snapshot", arena.snapshot)
                    val clicks = mutableListOf<com.leqra.android.audio.AudioCue>()
                    session.muted = false; session.volume = .5f; session.emitAudioCue = { clicks += it }
                    session.input = GameInput(fire = true); session.input2 = GameInput(fire = true)
                    arena.step(mapOf(1 to session.input, 2 to session.input2), 1.0 / 60)
                    assertTrue(arena.snapshot.tanks.all { it.power.isEmpty() })
                    for (seat in 0..1) {
                        if (seat == 0) {
                            session.input = GameInput(); session.input = GameInput(fire = true); session.input = GameInput()
                        } else {
                            session.input2 = GameInput(); session.input2 = GameInput(fire = true); session.input2 = GameInput()
                        }
                    }
                    arena.step(mapOf(1 to session.input, 2 to session.input2), 1.0 / 60)
                    if (power == "grenade") {
                        assertTrue(arena.snapshot.bullets.isEmpty())
                        session.input = GameInput(fire = true); session.input = GameInput()
                        session.input2 = GameInput(fire = true); session.input2 = GameInput()
                        arena.step(mapOf(1 to session.input, 2 to session.input2), 1.0 / 60)
                    }
                    for (id in 1..2) assertEquals("A captured $power repress fires one standard shot for P$id", 1, arena.snapshot.bullets.count { it.owner == id && it.kind.isEmpty() })
                    repeat(8) { arena.step(GameInput(), 1.0 / 60) }
                    assertEquals(2, arena.snapshot.bullets.count { it.kind.isEmpty() })
                    assertTrue("Available ammo never generates a dry click", clicks.isEmpty())
                    session.input = GameInput(fire = true); session.input2 = GameInput(fire = true)
                    session.neutral()
                    arena.step(GameInput(), 1.0 / 60)
                    assertEquals("Neutral discards queued taps", 2, arena.snapshot.bullets.count { it.kind.isEmpty() })
                }
            } finally { main { session.release() }; context.noBackupFilesDir.deleteRecursively() }
        }
        val context = context()
        val session = main { GameSession(context) }
        try {
            main {
                set(session, "online", true); set(session, "screen", Screen.PLAYING)
                set(session.network, "connected", true)
                event(session, NetworkEvent.Welcome(welcome(local = true)))
                event(session, NetworkEvent.State(ArenaSnapshot(tanks = listOf(ArenaTank(id = 1), ArenaTank(id = 2)))))
                val before = session.authoritativeSnapshot.tanks.map { it.copy() }
                val primary = session.network.lastInputSequence
                val secondary = session.network.lastLocalInputSequence
                session.input = GameInput(fire = true); session.input = GameInput()
                session.input2 = GameInput(fire = true); session.input2 = GameInput()
                assertEquals(primary + 2, session.network.lastInputSequence)
                assertEquals(secondary + 2, session.network.lastLocalInputSequence)
                assertEquals(before, session.authoritativeSnapshot.tanks)
            }
        } finally { main { session.release() }; context.noBackupFilesDir.deleteRecursively() }
    }

    @Test
    fun emptyQuickPressesAnimateBothSeatsInEveryModeWithoutInventingShotsOrMutatingAuthority() {
        for (online in listOf(false, true)) for (finite in listOf(false, true)) {
            val context = context()
            val session = main { GameSession(context) }
            try {
                main {
                    val arena = PracticeArena(42, "P1", 0, 0, world = if (finite) ArenaWorld(10000.0, 10000.0, 120, 120) else null)
                    arena.configureLocal("P2", 1)
                    arena.snapshot.tanks[1].apply { x = 9000.0; y = 9000.0 }
                    arena.snapshot.tanks.forEach { it.invulnerable = 0.0; it.spawnProtected = false }
                    for (id in 1..2) repeat(5) {
                        arena.snapshot.tanks[id - 1].cooldown = 0.0
                        arena.step(mapOf(id to GameInput(fire = true)), 1.0 / 60)
                    }
                    arena.snapshot.tanks.forEach { it.cooldown = 0.0; it.cooldownTotal = 0.0; it.recoil = 0.0 }
                    assertTrue(arena.snapshot.tanks.all { it.ammoUsed == 5 && it.hp > 0 })
                    set(session, "online", online)
                    set(session, "screen", Screen.PLAYING)
                    set(session, "infinity", !finite)
                    set(session, "localID", 1); set(session, "localID2", 2)
                    if (online) {
                        set(session.network, "connected", true)
                        event(session, NetworkEvent.Welcome(welcome(local = true)))
                        event(session, NetworkEvent.State(arena.snapshot))
                    } else {
                        set(session, "practice", arena); set(session, "fixed", null)
                        set(session, "snapshot", arena.snapshot)
                    }
                    assertTrue(session.audioGameplayActive)
                    val before = session.authoritativeSnapshot.tanks.map { it.copy() }
                    val bullets = session.authoritativeSnapshot.bullets.map { it.copy() }
                    val clicks = mutableListOf<com.leqra.android.audio.AudioCue>()
                    session.muted = false; session.volume = .5f
                    session.emitAudioCue = { clicks += it }
                    session.input = GameInput(fire = true)
                    session.input = GameInput()
                    session.input2 = GameInput(fire = true)
                    session.input2 = GameInput()
                    val now = System.nanoTime()
                    session.frame(now)
                    assertTrue("P1 quick tap survives until draw", session.previewRecoil > .8)
                    assertTrue("P2 quick tap survives until draw", session.localPreviewRecoil > .8)
                    assertEquals(before, session.authoritativeSnapshot.tanks)
                    assertEquals(bullets, session.authoritativeSnapshot.bullets)
                    assertTrue(session.snapshot.tanks.all { it.recoil == 0.0 })
                    assertEquals(listOf(com.leqra.android.audio.AudioCue.DRY_FIRE, com.leqra.android.audio.AudioCue.DRY_FIRE), clicks)
                    session.cancelFireFeedback()
                    session.muted = true
                    session.input = GameInput(fire = true); session.input = GameInput()
                    assertEquals(2, clicks.size)
                    session.cancelFireFeedback()
                    session.muted = false; session.volume = 0f
                    session.input = GameInput(fire = true); session.input = GameInput()
                    assertEquals(2, clicks.size)
                    session.cancelFireFeedback()
                    session.volume = .5f
                    session.authoritativeSnapshot.tanks.first().starmanTime = 1.0
                    session.input = GameInput(fire = true); session.input = GameInput()
                    assertEquals(2, clicks.size)
                    session.cancelFireFeedback()
                    session.authoritativeSnapshot.tanks.first().starmanTime = 0.0
                    AmmoEpoch.refill(session.authoritativeSnapshot.tanks.first())
                    session.input = GameInput(fire = true); session.input = GameInput()
                    assertEquals("Available ammo must use normal shot audio only", 2, clicks.size)
                    session.cancelFireFeedback()
                    session.fireFeedbackAllowed = { false }
                    session.input = GameInput(fire = true)
                    session.input = GameInput()
                    session.frame(System.nanoTime())
                    assertEquals(0.0, session.previewRecoil, 0.0)
                    assertEquals(2, clicks.size)
                    session.fireFeedbackAllowed = { true }
                    session.neutral()
                    assertEquals(0.0, session.localPreviewRecoil, 0.0)
                }
            } finally { main { session.release() }; context.noBackupFilesDir.deleteRecursively() }
        }
    }

    @Test
    fun eitherAmmoEpochRefreshesHudImmediatelyWithoutWaitingForTheTenHzTicker() {
        val context = context()
        val session = main { GameSession(context) }
        try {
            main {
                val arena = PracticeArena(42, "P1", 0, 0, world = testWorld)
                arena.configureLocal("P2", 1)
                arena.snapshot.tanks.forEach { it.invulnerable = 0.0; it.spawnProtected = false }
                set(session, "practice", arena); set(session, "fixed", null)
                set(session, "online", false); set(session, "screen", Screen.PLAYING)
                set(session, "localID", 1); set(session, "localID2", 2)
                var updates = 0
                session.changed = { updates++ }
                val start = System.nanoTime()
                session.frame(start)
                updates = 0
                session.frame(start + 1_000_000_000L / 120)
                assertEquals(0, updates)
                PracticeArena.applyPower(arena.snapshot.tanks.first(), "speed")
                session.frame(start + 2_000_000_000L / 120)
                assertEquals(1, updates)
                PracticeArena.applyPower(arena.snapshot.tanks[1], "shield")
                session.frame(start + 3_000_000_000L / 120)
                assertEquals(2, updates)
            }
        } finally { main { session.release() }; context.noBackupFilesDir.deleteRecursively() }
    }

    @Test
    fun targetedOfflineInfinityNeedsAnOpponentWhenEveryRoamingTierIsOff() {
        val context = context()
        context.getSharedPreferences("leqra-settings", 0).edit().putString("server", "http://127.0.0.1:1").putString("callsign", "Rate Pilot").putBoolean("autoPending0", false).putBoolean("publicSelected", false).commit()
        val session = main { GameSession(context) }
        try {
            main {
                session.botCount = 0; session.localSelected = false
                session.changeRules(RoomRules.localDefaults("infinity").copy(infinityTarget = 3, infinityRandomBots = true, infinityBotSpawnRates = emptyMap()))
                val errors = mutableListOf<String>(); session.notifyError = { errors.add(it) }
                assertNotNull(session.localStartError)
                session.play(); assertEquals(Screen.READY, session.screen)
                assertEquals(1, errors.size)
                session.botCount = 1
                assertNull(session.localStartError)
                session.play(); assertEquals(Screen.PLAYING, session.screen)
            }
        } finally { main { session.leave(); session.release() }; context.noBackupFilesDir.deleteRecursively() }
    }

    @Test
    fun roomTierMapsPublishAndAcknowledgeExactRatesAndAllOffReadiness() {
        val server = InstrumentationRegistry.getArguments().getString("server")
        assumeTrue("A disposable current Go backend is required", server != null)
        val context = context()
        context.getSharedPreferences("leqra-settings", 0).edit().putString("server", server).putString("callsign", "rates-${UUID.randomUUID().toString().take(8)}").putBoolean("autoPending0", false).putBoolean("publicSelected", false).commit()
        val session = main { GameSession(context) }
        val configured = mapOf("dumb" to 2.0 / 3, "normal" to 1.5, "godlike" to 4.0)
        try {
            main {
                session.botCount = 0; session.localSelected = false
                session.changeRules(RoomRules.localDefaults("infinity").copy(infinityRandomBots = true, infinityBotSpawnRates = configured))
                session.share()
            }
            eventually("Per-tier room did not publish") { session.network.connected && session.room != null }
            main { assertEquals(configured.withDefault { 0.0 }.let { r -> BotDifficulty.names.associateWith { r.getValue(it) } }, com.leqra.android.network.ProtocolJson.roomRules(session.room!!.getJSONObject("rules")).roamingBotSpawnRates()) }
            main { session.changeRules(session.rules.copy(infinityTarget = 3, infinityBotSpawnRates = emptyMap())) }
            eventually("All-Off target room still allowed a single-side start") {
                val room = session.room
                room != null && room.getJSONObject("rules").optInt("infinityTarget") == 3 &&
                    com.leqra.android.network.ProtocolJson.roomRules(room.getJSONObject("rules")).roamingBotSpawnRates().values.all { it == 0.0 } && !room.optBoolean("canStart")
            }
            main {
                assertEquals("Add an opposing tank or enable a roaming bot spawn rate to play to a score target.", session.room!!.optString("startError"))
                session.command("add", "kind" to "bot", "name" to "Rate Bot", "difficulty" to "hard")
            }
            eventually("An authored opposing bot did not make the target room playable") { session.room?.optBoolean("canStart") == true }
        } finally { main { session.leave(); session.release() }; context.noBackupFilesDir.deleteRecursively() }
    }

    @Test
    fun onlineHostAddsRemovesAndRestoresIndependentSecondPilot() {
        val server = InstrumentationRegistry.getArguments().getString("server")
        assumeTrue("A disposable current Go backend is required", server != null)
        val context = context()
        val suffix = UUID.randomUUID().toString().take(8)
        val secondary = "Wing $suffix"
        context.getSharedPreferences("leqra-settings", 0).edit()
            .putString("server", server).putString("callsign", "One $suffix").putString("localCallsign", secondary)
            .putBoolean("autoPending0", false).putBoolean("autoPending1", false)
            .putBoolean("publicSelected", false).putBoolean("localSelected", false).commit()
        val session = main { GameSession(context) }
        try {
            main { session.share() }
            eventually("Room did not accept a second pilot") { session.canAddRoomLocalPilot }
            main {
                assertNull(session.store.selected(session.server, 1))
                session.addRoomLocalPilot()
            }
            eventually("Separate P2 credential was not acknowledged") {
                session.roomLocalPilot?.optString("name") == secondary &&
                    session.store.selected(session.server, 1)?.registrationPending == false
            }
            val key = main {
                val credential = session.store.selected(session.server, 1)!!
                assertNotEquals(session.store.selected(session.server, 0)?.key, credential.key)
                assertFalse("Online roster changes should leave offline P2 preference alone", session.localSelected)
                val pilot = session.roomLocalPilot!!
                session.command("kick", "target" to pilot.getInt("id"), "member" to pilot.getLong("member"))
                credential.key
            }
            eventually("P2 remove did not clear the roster seat") { session.roomLocalPilot == null && session.canAddRoomLocalPilot }
            main { session.addRoomLocalPilot() }
            eventually("Saved P2 account did not rejoin the roster") { session.roomLocalPilot?.optString("name") == secondary }
            main { assertEquals(key, session.store.selected(session.server, 1)?.key) }
        } finally { main { session.leave(); session.release() }; context.noBackupFilesDir.deleteRecursively() }
    }

    @Test
    fun privateRoomJoinCarriesP2WhenHostingAndIgnoresP2WhenWatching() {
        val server = InstrumentationRegistry.getArguments().getString("server")
        assumeTrue("A disposable current Go backend is required", server != null)
        val playerContext = context()
        val spectatorContext = context()
        val suffix = UUID.randomUUID().toString().take(8)
        val firstRoom = "First $suffix"
        val secondRoom = "Second $suffix"
        val secondary = "Wing $suffix"
        playerContext.getSharedPreferences("leqra-settings", 0).edit()
            .putString("server", server).putString("callsign", "One $suffix").putString("localCallsign", secondary)
            .putBoolean("autoPending0", false).putBoolean("autoPending1", false)
            .putBoolean("publicSelected", false).putBoolean("localSelected", true).commit()
        spectatorContext.getSharedPreferences("leqra-settings", 0).edit()
            .putString("server", server).putString("callsign", "View $suffix").putString("localCallsign", "Bot Reserved")
            .putBoolean("autoPending0", false).putBoolean("autoPending1", false)
            .putBoolean("publicSelected", false).putBoolean("localSelected", true).commit()
        val player = main { GameSession(playerContext) }
        val spectator = main { GameSession(spectatorContext) }
        try {
            main { player.join(firstRoom) }
            eventually("P2 was not added after joining as host") {
                player.roomCode == firstRoom && player.roomLocalPilot?.optString("name") == secondary
            }
            val secondaryKey = main {
                val key = player.store.selected(player.server, 1)!!.key
                assertNotEquals(player.store.selected(player.server, 0)?.key, key)
                // The current online party, not the offline roster, determines who joins the next room.
                player.localSelected = false
                player.join(secondRoom)
                key
            }
            eventually("P2 did not move to the next room with P1") {
                player.roomCode == secondRoom && player.roomLocalPilot?.optString("name") == secondary
            }
            main {
                assertEquals(secondaryKey, player.store.selected(player.server, 1)?.key)
                spectator.join(secondRoom, spectator = true)
            }
            eventually("Spectating incorrectly required the configured P2 callsign") {
                spectator.roomCode == secondRoom && spectator.roomSpectating
            }
            main {
                assertNull(spectator.roomLocalPilot)
                assertNull(spectator.store.selected(spectator.server, 1))
            }
        } finally {
            main { spectator.leave(); spectator.release(); player.leave(); player.release() }
            playerContext.noBackupFilesDir.deleteRecursively()
            spectatorContext.noBackupFilesDir.deleteRecursively()
        }
    }

    @Test
    fun pairedRoomJoinOnlyRegistersP2OnceAfterTheInitialLobbyPacket() {
        val context = context()
        val session = main { GameSession(context) }
        try {
            main {
                session.localCallsign = "Second pilot"
                set(session, "online", true)
                set(session, "pendingLocalJoin", true)
                set(session.network, "origin", session.server)
                val joined = NetworkWelcome.parse(JSONObject().put("id", 1).put("member", 20))
                set(session.network, "welcome", joined)
                event(session, NetworkEvent.Welcome(joined))
                assertNull(session.store.selected(session.server, 1))
                val room = NetworkEvent.Packet(JSONObject().put("type", "room").put("phase", "lobby")
                    .put("code", "Test room").put("host", 1).put("players", JSONArray().put(JSONObject().put("id", 1))))
                event(session, room)
                val registration = session.store.selected(session.server, 1)!!
                assertTrue(registration.registrationPending)

                session.store.forgetAccount(session.server, registration.key)
                event(session, room)
                assertNull("Roster refreshes must not re-register P2", session.store.selected(session.server, 1))
            }
        } finally { main { session.release() }; context.noBackupFilesDir.deleteRecursively() }
    }

    @Test
    fun unsharedRoomDropsTheStaleLobbyAndRestoresTheLocalRules() {
        val context = context()
        val session = main { GameSession(context) }
        try {
            main {
                for (publicArena in listOf(false, true)) {
                    session.selectMode("survival")
                    val joined = NetworkWelcome.parse(JSONObject().put("id", 1).put("member", 20))
                    set(session, "online", true)
                    set(session.network, "welcome", joined)
                    event(session, NetworkEvent.Welcome(joined))
                    event(session, NetworkEvent.Packet(JSONObject().put("type", "room").put("phase", "lobby")
                        .put("code", "Test room").put("host", 2).put("rules", GameSession.rulesJson(RoomRules.localDefaults("ctf")))))
                    assertEquals("ctf", session.mode)
                    if (publicArena) {
                        set(session, "arenaActive", true)
                        set(session.arenaNetwork, "infinity", true)
                        event(session, NetworkEvent.Welcome(NetworkWelcome.parse(
                            JSONObject().put("id", 9).put("seed", 42).put("public", true),
                        )), arena = true)
                        assertEquals(Screen.PLAYING, session.screen)
                    }

                    var notice: String? = null
                    session.notifyError = { notice = it }
                    event(session, NetworkEvent.Packet(JSONObject().put("type", "unshared").put("message", "Room unshared.")))
                    assertEquals("Room unshared.", notice)
                    assertFalse(session.online)
                    assertNull(session.roomCode)
                    assertEquals(Screen.READY, session.screen)
                    assertEquals("survival", session.mode)
                }
            }
        } finally { main { session.release() }; context.noBackupFilesDir.deleteRecursively() }
    }

    @Test
    fun pausedResultOverlayFinishesOnlyTheProjectilePresentation() {
        val context = context()
        val session = main { GameSession(context) }
        try {
            main {
                set(session, "online", true)
                event(session, NetworkEvent.Welcome(welcome()))
                event(session, NetworkEvent.State(snapshot(0)))
                val flight = ProjectileFlight(17, 1, 0, 0.0, .2, listOf(ProjectileFlightPoint(4200.0, 4200.0, 0.0), ProjectileFlightPoint(4210.0, 4200.0, .2)))
                val victim = ArenaTank(id=8,name="Target",x=4245.0,y=4200.0,hp=0,spawnSerial=2)
                val terminal = snapshot(1).copy(result = ArenaResult(id = 1, score = 1), tanks=snapshot(1).tanks+victim, effects = listOf(ArenaEffect(id = 1, kind = "impact", flight = flight),
                    ArenaEffect(id=2,kind="hit",tick=1,contact=CombatContact(17,"cannon",.2,8,2,ContactTankState(4245.0,4200.0,0.0)))))
                event(session, NetworkEvent.State(terminal))
                set(session, "paused", true)
                assertTrue(session.finishingProjectilePresentation)
                session.input = GameInput(forward = true, fire = true)
                val beforeSequence = session.network.lastInputSequence
                val start = System.nanoTime()
                var visible = false; var contacted=false; var exploded=false
                session.present = { image, _, _, _, _ ->
                    val shell=image.bullets.firstOrNull { it.id == 17 }
                    visible = visible || shell!=null
                    if(shell?.x==4210.0) { assertEquals(1,image.tanks.first { it.id==8 }.hp); contacted=true; assertNull(image.result) }
                    if(image.effects.any { it.id==2 }) { assertTrue(contacted); assertEquals(0,image.tanks.first { it.id==8 }.hp); exploded=true }
                }
                repeat(40) { session.frame(start + it * 1_000_000_000L / 120) }
                assertTrue(visible)
                assertTrue(contacted && exploded)
                assertFalse(session.finishingProjectilePresentation)
                assertEquals(4200.0, session.snapshot.tanks.first().x, 0.0)
                assertEquals(1, session.snapshot.result!!.score)
                assertEquals(beforeSequence, session.network.lastInputSequence)
                assertTrue(session.snapshot.bullets.isEmpty())
            }
        } finally { main { session.release() }; context.noBackupFilesDir.deleteRecursively() }
    }

    @Test
    fun spacedLegacyPlayerDefaultsUpgradeWithoutKeysAndBothCurrentKeysProtectThem() {
        for (protected in listOf(false, true)) {
            val context = context()
            val first = " pLaYeR   1 "
            val second = "Player  2"
            context.getSharedPreferences("leqra-settings", 0).edit().putString("callsign", first).putString("localCallsign", second).putBoolean("autoPending0", false).putBoolean("autoPending1", false).commit()
            val keys = (0..1).map { com.leqra.android.accounts.AccountKeys.create() }
            if (protected) {
                val store = com.leqra.android.accounts.EncryptedAccountStore(context)
                for (seat in 0..1) store.select("https://leqra.com", seat, keys[seat])
            }
            val session = main { GameSession(context) }
            try {
                if (protected) {
                    assertEquals(first, session.callsign)
                    assertEquals(second, session.localCallsign)
                    for (seat in 0..1) {
                        assertFalse(session.automaticNamePending(seat))
                        assertEquals(keys[seat], session.store.selected(session.server, seat)?.key)
                    }
                } else {
                    assertTrue(session.callsign.startsWith("pilot#"))
                    assertTrue(session.localCallsign.startsWith("pilot#"))
                    assertNotEquals(session.callsign, session.localCallsign)
                    assertTrue(session.automaticNamePending(0))
                    assertTrue(session.automaticNamePending(1))
                }
            } finally {
                main { session.release() }
                context.noBackupFilesDir.deleteRecursively()
            }
        }
    }

    @Test
    fun roomDemotionStopsInputAndPowerAudioBeforeTheArenaSocketIsReplaced() {
        val context = context()
        val session = main { GameSession(context) }
        try {
            main {
                val pilot = welcome()
                val viewer = NetworkWelcome.parse(JSONObject().put("id", 9).put("spectating", true))
                set(session, "online", true)
                set(session, "arenaActive", true)
                set(session.arenaNetwork, "welcome", pilot)
                set(session.arenaNetwork, "connected", true)
                event(session, NetworkEvent.Welcome(pilot), arena = true)
                val state = snapshot(1).apply { tanks[0].starmanTime = 5.0 }
                event(session, NetworkEvent.State(state), arena = true)
                assertTrue(session.audioGameplayActive)
                // Reliable control identity precedes its roster and arena invalidation.
                set(session.network, "welcome", viewer)
                event(session, NetworkEvent.Welcome(viewer))
                assertTrue(session.spectating)
                assertTrue("The watched scene still has ordinary audio", session.audioSceneActive)
                assertFalse(session.audioGameplayActive)
                session.input = GameInput(forward = true, fire = true)
                val sequence = session.arenaNetwork.lastInputSequence
                val start = System.nanoTime()
                repeat(12) { session.frame(start + it * 1_000_000_000L / 120) }
                assertEquals("The old actor receives no controls after its room role changes", sequence, session.arenaNetwork.lastInputSequence)
            }
        } finally {
            main { session.release() }
            context.noBackupFilesDir.deleteRecursively()
        }
    }

    @Test
    fun legacyNoKeyDefaultsUpgradeBeforeRegistrationAndStaleIntentCannotRestoreThem() {
        val context = context()
        context.getSharedPreferences("leqra-settings", 0).edit().putString("callsign", "PILOT").putString("localCallsign", "CO-PILOT").putBoolean("autoPending0", false).putBoolean("autoPending1", false).commit()
        val store = com.leqra.android.accounts.EncryptedAccountStore(context)
        store.setActiveIntent(com.leqra.android.accounts.PublicIntent("https://leqra.com", "PILOT", 3, "CO-PILOT", 4))
        var session = main { GameSession(context) }
        try {
            main {
                assertTrue(session.callsign.startsWith("pilot#"))
                assertTrue(session.localCallsign.startsWith("pilot#"))
                assertNotEquals(session.callsign, session.localCallsign)
                assertTrue(session.automaticNamePending(0))
                assertTrue(session.automaticNamePending(1))
                val first = session.callsign
                val second = session.localCallsign
                session.foreground()
                assertFalse(session.online)
                assertEquals(Screen.READY, session.screen)
                assertEquals(first, session.callsign)
                assertEquals(second, session.localCallsign)
                assertNull(session.store.activeIntent())
                session.release()
                session = GameSession(context)
                assertEquals(first, session.callsign)
                assertEquals(second, session.localCallsign)
            }
        } finally {
            main { session.release() }
            context.noBackupFilesDir.deleteRecursively()
        }
    }

    @Test
    fun accountBackedLegacyDefaultsAndCustomNamesStayUntouched() {
        val context = context()
        val key = com.leqra.android.accounts.AccountKeys.create()
        val store = com.leqra.android.accounts.EncryptedAccountStore(context)
        store.select("https://leqra.com", 0, key)
        context.getSharedPreferences("leqra-settings", 0).edit().putString("callsign", "PILOT").putString("localCallsign", "My custom name").commit()
        val session = main { GameSession(context) }
        try {
            assertEquals("PILOT", session.callsign)
            assertEquals("My custom name", session.localCallsign)
            assertFalse(session.automaticNamePending(0))
            assertFalse(session.automaticNamePending(1))
            assertEquals(key, session.store.selected(session.server, 0)?.key)
        } finally {
            main { session.release() }
            context.noBackupFilesDir.deleteRecursively()
        }
    }

    private fun <T> main(block: () -> T): T {
        var result: Result<T>? = null
        instrumentation.runOnMainSync { result = runCatching(block) }
        return result!!.getOrThrow()
    }

    private fun context(): Context {
        val base = isolatedAccountContext()
        val prefix = "session-parity-${UUID.randomUUID()}-"
        return object : ContextWrapper(base) {
            override fun getNoBackupFilesDir(): File = base.noBackupFilesDir

            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
                super.getSharedPreferences(prefix + name, mode)
        }
    }

    private fun field(instance: Any, name: String): Any? =
        instance.javaClass.getDeclaredField(name).run {
            isAccessible = true
            get(instance)
        }

    private fun set(instance: Any, name: String, value: Any?) =
        instance.javaClass.getDeclaredField(name).run {
            isAccessible = true
            set(instance, value)
        }

    private fun event(session: GameSession, value: NetworkEvent, arena: Boolean = false) {
        GameSession::class
            .java
            .getDeclaredMethod(
                "networkEvent",
                NetworkEvent::class.java,
                Boolean::class.javaPrimitiveType,
            )
            .run {
                isAccessible = true
                invoke(session, value, arena)
            }
    }

    private fun eventually(message: String, diagnostic: (() -> String)? = null, condition: () -> Boolean) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(20)
        while (System.nanoTime() < deadline) {
            if (main(condition)) return
            Thread.sleep(30)
        }
        throw AssertionError(message + (diagnostic?.let { ": " + main(it) } ?: ""))
    }

    private fun welcome(local: Boolean = false) =
        NetworkWelcome.parse(
            JSONObject().put("id", 1).put("member", 10).apply {
                if (local) put("localId", 2).put("localMember", 20)
            },
        )

    private fun snapshot(tick: Long) =
        ArenaSnapshot(
            tick = tick,
            generation = 1,
            world = testWorld,
            tanks =
                listOf(
                    ArenaTank(id = 1, name = "Primary", x = 4200.0, y = 4200.0, spawnSerial = 1),
                    ArenaTank(id = 2, name = "Secondary", x = 4700.0, y = 4200.0, spawnSerial = 1),
                ),
        )

    @Test
    fun serverSnapshotsNeverAddHudRefreshesBetweenDisplayCadenceUpdates() {
        val context = context()
        val session = main { GameSession(context) }
        try {
            main {
                val updates = mutableListOf<Boolean>()
                session.changed = { updates.add(it) }
                event(session, NetworkEvent.Welcome(welcome()))
                set(session, "online", true)
                event(session, NetworkEvent.State(snapshot(0)))
                updates.clear()
                repeat(120) { event(session, NetworkEvent.State(snapshot((it + 1).toLong()))) }
                assertTrue(
                    "Server snapshots must not trigger per-packet hierarchy updates",
                    updates.isEmpty(),
                )
                val base = System.nanoTime()
                var presents = 0
                session.present = { _, _, _, _, _ -> presents++ }
                repeat(121) { session.frame(base + it * 1_000_000_000L / 120) }
                assertEquals(121, presents)
                assertTrue("HUD cadence should remain10Hz: ${updates.size}", updates.size in 9..10)
                assertTrue(updates.none { it })
            }
        } finally {
            main { session.release() }
            context.noBackupFilesDir.deleteRecursively()
        }
    }

    @Test
    fun reconnectAndIdentityUpdatesPreserveAnExplicitPause() {
        val context = context()
        val session = main { GameSession(context) }
        val publicWelcome = NetworkWelcome.parse(JSONObject().put("id", 1).put("public", true))
        try {
            main {
                event(session, NetworkEvent.Welcome(publicWelcome))
                assertEquals(Screen.PLAYING, session.screen)
                assertFalse(session.paused)
                session.pause(true)
                event(session, NetworkEvent.Welcome(publicWelcome))
                assertTrue("Same-socket identity updates must keep the menu paused", session.paused)
                set(session, "timelineConnection", -1L)
                event(session, NetworkEvent.Reconnecting(1))
                event(session, NetworkEvent.Welcome(publicWelcome))
                assertEquals(Screen.PLAYING, session.screen)
                assertTrue("A reconnect must preserve an explicit pause", session.paused)
                session.pause(false)
                event(session, NetworkEvent.Welcome(publicWelcome))
                assertFalse("An active game should remain active", session.paused)
            }
        } finally {
            main { session.release() }
            context.noBackupFilesDir.deleteRecursively()
        }
    }

    @Test
    fun sameSocketP2WelcomeKeepsPrimaryPredictionAndImmediatelyPredictsP2() {
        val context = context()
        val session = main { GameSession(context) }
        try {
            main {
                event(session, NetworkEvent.Welcome(welcome()))
                set(session, "online", true)
                event(session, NetworkEvent.State(snapshot(0)))
                session.input = GameInput(forward = true)
                val base = System.nanoTime()
                repeat(6) { session.frame(base + it * 1_000_000_000L / 60) }
                val timeline = field(session, "timeline")!!
                val primary = field(timeline, "primary")!!
                val history = (field(primary, "frames") as Collection<*>).size
                val sequence = field(primary, "sequence") as Long
                val position = session.snapshot.tanks.first { it.id == 1 }.x
                assertTrue(history > 0)
                event(session, NetworkEvent.Welcome(welcome(local = true)))
                assertSame(timeline, field(session, "timeline"))
                assertEquals(history, (field(primary, "frames") as Collection<*>).size)
                assertEquals(sequence, field(primary, "sequence"))
                assertEquals(Screen.PLAYING, session.screen)
                session.input2 = GameInput(reverse = true)
                session.frame(base + 6 * 1_000_000_000L / 60)
                assertTrue(session.snapshot.tanks.first { it.id == 1 }.x > position)
                assertTrue(
                    "P2 must be predicted rather than delayed like a remote tank",
                    session.snapshot.tanks.first { it.id == 2 }.x < 4700,
                )
            }
        } finally {
            main { session.release() }
            context.noBackupFilesDir.deleteRecursively()
        }
    }

    @Test
    fun customRosterAndPaintPersistAndPublishExactlyTheOfflineIdentities() {
        val server = InstrumentationRegistry.getArguments().getString("server")
        assumeTrue("Local server argument was not supplied", server != null)
        val context = context()
        var session: GameSession? = null
        val tag = (System.nanoTime() % 1_000_000_000).toString()
        data class Identity(val bot: Boolean, val color: Int, val team: Int, val difficulty: String)
        var expected = emptyMap<String, Identity>()
        try {
            main {
                session = GameSession(context)
                session!!.setServer(server!!)
                session!!.callsign = "P$tag"
                session!!.localCallsign = "W$tag"
                session!!.localSelected = true
                session!!.togglePublic(false)
                session!!.selectMode("koth")
                session!!.changeRules(
                    session!!.rules.copy(teamMode = "teams", teamColors = listOf(4, 5, 6, 7)),
                )
                session!!.localTeam = 3
                session!!.secondLocalTeam = 4
                session!!.botCount = 2
                val bots = session!!.localBots.toList()
                session!!.updateLocalBot(
                    bots[0].id,
                    "A$tag",
                    colorIndex = 3,
                    difficulty = "hard",
                    team = 1,
                )
                session!!.updateLocalBot(
                    bots[1].id,
                    "B$tag",
                    colorIndex = 7,
                    difficulty = "godlike",
                    team = 2,
                )
                val saved = session!!.localBots.toList()
                session!!.save()
                session!!.release()
                session = GameSession(context)
                assertEquals(saved, session!!.localBots)
                assertEquals(3, session!!.localTeam)
                assertEquals(4, session!!.secondLocalTeam)
                session!!.play()
                session!!.renameCallsign("N$tag", 1)
                session!!.frame(System.nanoTime())
                session!!.restartMatch()
                val actors = session!!.snapshot.tanks
                assertTrue(
                    actors.any { it.name == "N$tag" && !it.bot && it.id == session!!.localID2 },
                )
                assertTrue(actors.none { it.bot && it.name == "N$tag" })
                expected = actors.associate {
                    it.name to Identity(it.bot, it.colorIndex, it.team, it.difficulty)
                }
                session!!.lobby()
                session!!.roomName = "Parity $tag"
                session!!.togglePublic(true)
                session!!.findMatch()
            }
            eventually("Matchmaking did not publish the current room and load its queues", { session!!.status }) {
                session!!.room?.optJSONArray("players")?.length() == 4 &&
                    session!!.room?.optBoolean("infinityPublic") == true &&
                    session!!.queuePacket?.optString("type") == "queue_catalog"
            }
            main {
                assertEquals("Parity $tag", session!!.roomCode)
                assertEquals("koth", session!!.rules.mode)
                val rows = session!!.room!!.getJSONArray("players")
                assertEquals(
                    expected.keys,
                    (0 until rows.length())
                        .map { rows.getJSONObject(it).getString("name") }
                        .toSet(),
                )
                repeat(rows.length()) { index ->
                    val player = rows.getJSONObject(index)
                    val value = expected.getValue(player.getString("name"))
                    assertEquals(value.bot, player.getString("kind") == "bot")
                    assertEquals(value.color, GamePalette.colors.indexOf(player.getString("color")))
                    assertEquals(value.team, player.getInt("team"))
                    if (value.bot) assertEquals(value.difficulty, player.getString("difficulty"))
                }
            }
        } finally {
            main {
                session?.let {
                    it.leave()
                    it.release()
                }
            }
            context.noBackupFilesDir.deleteRecursively()
        }
    }

    @Test
    fun callsignChangesSelectSeparateAccountsAndReturnToReadyRoom() {
        val server = InstrumentationRegistry.getArguments().getString("server")
        assumeTrue("Local server argument was not supplied", server != null)
        val context = context()
        val session = main { GameSession(context) }
        val tag = (System.nanoTime() % 1_000_000_000).toString()
        val primary = "RP$tag"
        val secondary = "RW$tag"
        val renamedLocal = "RN$tag"
        val renamedPrimary = "RX$tag"
        try {
            main {
                session.setServer(server!!)
                session.callsign = primary
                session.localCallsign = secondary
                session.localSelected = true
                session.botCount = 0
                session.togglePublic(false)
                session.selectMode("infinity")
                session.share()
            }
            eventually("Private paired room did not publish") {
                session.network.connected && session.network.welcome?.localId != null && session.room != null
            }
            val originalKeys = main { (0..1).map { session.store.selected(server!!, it)!!.key } }
            main { session.renameCallsign(renamedLocal, 1) }
            eventually("P2 account change did not return to the room") {
                session.screen == Screen.READY && session.room == null && session.localCallsign == renamedLocal
            }
            main {
                assertEquals(primary, session.callsign)
                assertEquals(originalKeys[0], session.store.selected(server!!, 0)!!.key)
                assertNotEquals(originalKeys[1], session.store.selected(server, 1)!!.key)
                assertTrue(session.accounts.savedCallsigns(server).any { it.name == secondary && it.key == originalKeys[1] })
                session.togglePublic(true)
                session.play()
            }
            eventually("Public paired arena did not start") {
                session.arenaNetwork.connected && session.arenaNetwork.isPublic && session.localID2 != null
            }
            val localKey = main { session.store.selected(server!!, 1)!!.key }
            main { session.renameCallsign(renamedPrimary, 0) }
            eventually("P1 account change did not return to the room") {
                session.screen == Screen.READY && !session.online && session.callsign == renamedPrimary
            }
            main {
                assertEquals(renamedLocal, session.localCallsign)
                assertEquals(localKey, session.store.selected(server!!, 1)!!.key)
                assertNotEquals(originalKeys[0], session.store.selected(server, 0)!!.key)
                assertTrue(session.accounts.savedCallsigns(server).any { it.name == primary && it.key == originalKeys[0] })
                session.renameCallsign(primary, 0)
            }
            eventually("Saved account could not be selected again") {
                session.callsign == primary && session.store.selected(server!!, 0)?.key == originalKeys[0]
            }
        } finally {
            main { session.leave(); session.release() }
            context.noBackupFilesDir.deleteRecursively()
        }
    }
    @Test
    fun freshPairedEntryWaitsForAtomicNamesAndKeepsThemAcrossColdLoad() {
        val server = InstrumentationRegistry.getArguments().getString("server")
        assumeTrue("Local server argument was not supplied", server != null)
        val context = context()
        var session: GameSession? = null
        try {
            main {
                session = GameSession(context)
                assertTrue(session!!.automaticNamePending(0))
                assertTrue(session!!.automaticNamePending(1))
                assertTrue(Regex("pilot#[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}").matches(session!!.callsign))
                assertNotEquals(session!!.callsign, session!!.localCallsign)
                session!!.setServer(server!!)
                session!!.localSelected = true
                session!!.publicSelected = true
                session!!.play()
                assertEquals(Screen.CONNECTING, session!!.screen)
                assertTrue(session!!.store.selected(server, 0)!!.registrationPending)
                assertTrue(session!!.store.selected(server, 1)!!.registrationPending)
                assertNotEquals(session!!.store.selected(server, 0)!!.key, session!!.store.selected(server, 1)!!.key)
            }
            eventually("Fresh P1/P2 automatic names should enter Public Infinity") {
                session!!.screen == Screen.PLAYING && session!!.localID2 != null &&
                    session!!.snapshot.tanks.any { it.id == session!!.localID2 }
            }
            main {
                val first = session!!.callsign
                val second = session!!.localCallsign
                assertFalse(session!!.automaticNamePending(0))
                assertFalse(session!!.automaticNamePending(1))
                assertFalse(session!!.store.selected(server!!, 1)!!.registrationPending)
                session!!.leave()
                session!!.release()
                session = GameSession(context)
                assertEquals(first, session!!.callsign)
                assertEquals(second, session!!.localCallsign)
                assertFalse(session!!.automaticNamePending(0))
                assertFalse(session!!.automaticNamePending(1))
                session!!.callsign = "Bot RUST"
                val errors = mutableListOf<String>()
                session!!.notifyError = { errors.add(it) }
                session!!.publicSelected = false
                session!!.play()
                assertEquals(Screen.READY, session!!.screen)
                assertEquals("Bot RUST", session!!.callsign)
                assertTrue(errors.single().contains("reserved"))
                val offline = "http://10.0.2.2:1"
                session!!.setServer(offline)
                session!!.generateCallsign(0)
            }
            eventually("Offline generation must select a local pending account") {
                val current = session!!
                Regex("pilot#[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}").matches(current.callsign) &&
                    current.store.selected("http://10.0.2.2:1", 0)?.registrationPending == true
            }
            main {
                val offline = "http://10.0.2.2:1"
                val fallback = session!!.callsign
                val key = session!!.store.selected(offline, 0)!!.key
                assertTrue("Unconfirmed server generation stays recoverable", session!!.store.pending(offline, 0).any { it.purpose.startsWith("generate:") })
                session!!.save()
                session!!.release()
                session = GameSession(context)
                assertEquals(fallback, session!!.callsign)
                assertEquals(key, session!!.store.selected(offline, 0)!!.key)
                session!!.publicSelected = false
                session!!.localSelected = false
                session!!.play()
                assertEquals("Offline play remains available after failed server generation", Screen.PLAYING, session!!.screen)
            }
        } finally {
            main { session?.leave(); session?.release() }
            context.noBackupFilesDir.deleteRecursively()
        }
    }

    @Test
    fun onlinePowerAudioRequiresFreshStateForTheCurrentTransport() {
        val context = context()
        lateinit var session: GameSession
        try {
            main {
                session = GameSession(context)
                set(session, "screen", Screen.PLAYING)
                assertTrue(session.audioGameplayActive)
                session.pause(true)
                assertFalse(session.audioGameplayActive)
                session.pause(false)
                set(session, "online", true)
                set(session, "arenaActive", true)
                set(session.arenaNetwork, "connected", true)
                assertFalse("A connected Welcome must not replay a stale pre-background power", session.audioGameplayActive)
                event(session, NetworkEvent.State(ArenaSnapshot(tick = 1, tanks = listOf(ArenaTank(id = 1, starmanTime = 8.0)))), true)
                assertTrue(session.audioGameplayActive)
                set(session.arenaNetwork, "epoch", session.arenaNetwork.connectionGeneration + 1)
                assertFalse(session.audioGameplayActive)
                event(session, NetworkEvent.State(ArenaSnapshot(tick = 2, tanks = listOf(ArenaTank(id = 1)))), true)
                assertTrue(session.audioGameplayActive)
                set(session.arenaNetwork, "welcome", NetworkWelcome.parse(JSONObject().put("id", 1).put("spectating", true)))
                assertFalse("Spectators cannot activate a local power-up loop", session.audioGameplayActive)
                set(session.arenaNetwork, "connected", false)
                assertFalse(session.audioGameplayActive)
                session.background()
                assertFalse(session.audioGameplayActive)
            }
        } finally {
            main { session.leave(); session.release() }
            context.noBackupFilesDir.deleteRecursively()
        }
    }

}
