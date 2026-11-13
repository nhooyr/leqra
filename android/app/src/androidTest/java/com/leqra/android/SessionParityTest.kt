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

    private fun eventually(message: String, condition: () -> Boolean) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(20)
        while (System.nanoTime() < deadline) {
            if (main(condition)) return
            Thread.sleep(30)
        }
        throw AssertionError(message)
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
            eventually("Custom roster did not publish") {
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
}
