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
                assertEquals("infinity", session.mode)
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
                session!!.share()
            }
            eventually("Custom roster did not publish", { session!!.status }) {
                session!!.room?.optJSONArray("players")?.length() == 4
            }
            main {
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
    fun privateP2RenameAcknowledgementsAndPublicP1P2RenamesUseTheCorrectSeatAndSocket() {
        val server = InstrumentationRegistry.getArguments().getString("server")
        assumeTrue("Local server argument was not supplied", server != null)
        val context = context()
        val session = main { GameSession(context) }
        val tag = (System.nanoTime() % 1_000_000_000).toString()
        val primary = "RP$tag"
        val secondary = "RW$tag"
        val renamedLocal = "RN$tag"
        val renamedPrimary = "RX$tag"
        val renamedSecondary = "RY$tag"
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
                session.network.connected &&
                    session.network.welcome?.localId != null &&
                    session.room != null
            }
            main { session.renameCallsign(renamedLocal, 1) }
            eventually("Private P2 rename did not acknowledge the right seat") {
                val rows = session.room?.optJSONArray("players")
                val name = rows?.let {
                    (0 until it.length())
                        .map { index -> it.getJSONObject(index) }
                        .firstOrNull { it.optInt("id") == session.network.welcome?.localId }
                        ?.optString("name")
                }
                val pending = field(session, "renameNames") as Array<*>
                name == renamedLocal && pending[1] == null
            }
            main {
                assertEquals(primary, session.callsign)
                assertEquals(renamedLocal, session.localCallsign)
                session.togglePublic(true)
                session.play()
            }
            eventually("Public paired arena did not start") {
                session.arenaNetwork.connected &&
                    session.arenaNetwork.isPublic &&
                    session.localID2 != null
            }
            val startSequence = main { field(session.arenaNetwork, "renameSequence") as Long }
            main {
                session.renameCallsign(renamedPrimary, 0)
                session.renameCallsign(renamedSecondary, 1)
            }
            eventually("Public P1/P2 names were not both confirmed in the arena") {
                val first = session.snapshot.tanks.firstOrNull { it.id == session.localID }?.name
                val second = session.snapshot.tanks.firstOrNull { it.id == session.localID2 }?.name
                val pending = field(session, "renameNames") as Array<*>
                first == renamedPrimary && second == renamedSecondary && pending.all { it == null }
            }
            main {
                assertEquals(startSequence + 2, field(session.arenaNetwork, "renameSequence"))
                assertEquals(0L, field(session.network, "renameSequence"))
                assertEquals(renamedPrimary, session.callsign)
                assertEquals(renamedSecondary, session.localCallsign)
            }
        } finally {
            main {
                session.leave()
                session.release()
            }
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
                val fallback = session!!.callsign
                val draft = field(session!!, "nameDrafts") as com.leqra.android.accounts.CallsignDrafts
                val requestID = draft.requestID(0)
                val key = session!!.store.selected(offline, 0)!!.key
                assertTrue(Regex("pilot#[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}").matches(fallback))
                assertTrue(session!!.automaticNamePending(0))
                session!!.publicSelected = false
                session!!.localSelected = false
                session!!.play()
                assertEquals(Screen.PLAYING, session!!.screen)
                session!!.save()
                session!!.release()
                session = GameSession(context)
                assertEquals(fallback, session!!.callsign)
                assertEquals(requestID, (field(session!!, "nameDrafts") as com.leqra.android.accounts.CallsignDrafts).requestID(0))
                assertEquals(key, session!!.store.selected(offline, 0)!!.key)
                assertTrue(session!!.automaticNamePending(0))
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
