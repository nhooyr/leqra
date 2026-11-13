package com.leqra.android.network

import android.content.ContextWrapper
import android.content.SharedPreferences
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.leqra.android.GameSession
import com.leqra.android.Screen
import com.leqra.android.accounts.isolatedAccountContext
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GameSessionNetworkIntegrationTest {
    private fun main(block: () -> Unit) =
        InstrumentationRegistry.getInstrumentation().runOnMainSync(block)

    private fun eventually(message: String, condition: () -> Boolean) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(20)
        while (System.nanoTime() < deadline) {
            var done = false
            main { done = condition() }
            if (done) return
            Thread.sleep(50)
        }
        throw AssertionError(message)
    }

    @Test
    fun sessionKeepsRoomSocketDuringPrivateInfinityAndColdResumesPublicPair() {
        val server = InstrumentationRegistry.getArguments().getString("server")
        assumeTrue("Local server argument was not supplied", server != null)
        val base = isolatedAccountContext()
        val suffix = UUID.randomUUID().toString()
        val context =
            object : ContextWrapper(base) {
                override fun getNoBackupFilesDir(): File = base.noBackupFilesDir

                override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
                    super.getSharedPreferences("test-$suffix-$name", mode)
            }
        var first: GameSession? = null
        var restored: GameSession? = null
        try {
            val names = (System.nanoTime() % 1_000_000_000).toString()
            main {
                first = GameSession(context)
                first!!.setServer(server!!)
                first!!.callsign = "SP$names"
                first!!.localCallsign = "SW$names"
                first!!.localSelected = true
                first!!.botCount = 0
                first!!.togglePublic(false)
                first!!.selectMode("infinity")
                first!!.share()
            }
            eventually("Room did not publish") { first!!.network.connected && first!!.room != null }
            main { first!!.play() }
            eventually("Private Infinity did not connect with separate room transport") {
                first!!.arenaNetwork.connected &&
                    first!!.network.connected &&
                    first!!.screen == Screen.PLAYING
            }
            main {
                assertNotNull(first!!.localID2)
                assertFalse(first!!.arenaNetwork.isPublic)
                assertEquals(first!!.network.welcome!!.room, first!!.arenaNetwork.welcome!!.room)
                first!!.background()
                first!!.foreground()
            }
            eventually("Private Infinity did not resume both transports") {
                first!!.arenaNetwork.connected &&
                    first!!.network.connected &&
                    first!!.localID2 != null
            }
            main {
                first!!.lobby()
            }
            eventually("Private Infinity did not return to its live room") {
                first!!.network.connected &&
                    !first!!.arenaNetwork.connected &&
                    first!!.screen == Screen.READY &&
                    first!!.room?.optBoolean("infinityActive") != true
            }
            main {
                first!!.togglePublic(true)
                first!!.play()
            }
            eventually("Public party did not connect") {
                first!!.arenaNetwork.connected &&
                    first!!.arenaNetwork.isPublic &&
                    first!!.localID2 != null
            }
            var id = 0
            var localId: Int? = null
            var key: String? = null
            var localKey: String? = null
            main {
                id = first!!.localID
                localId = first!!.localID2
                key = first!!.store.selected(server!!, 0)!!.key
                localKey = first!!.store.selected(server, 1)!!.key
                first!!.release()
                restored = GameSession(context)
                restored!!.foreground()
            }
            eventually("Public party did not automatically cold-resume") {
                restored!!.arenaNetwork.connected && restored!!.screen == Screen.PLAYING
            }
            main {
                assertEquals(id, restored!!.localID)
                assertEquals(localId, restored!!.localID2)
                assertEquals(key, restored!!.store.selected(server!!, 0)!!.key)
                assertEquals(localKey, restored!!.store.selected(server, 1)!!.key)
                assertNull(restored!!.room)
                restored!!.leave()
                assertNull(restored!!.store.activeIntent())
                assertEquals(key, restored!!.store.selected(server, 0)!!.key)
            }
        } finally {
            main {
                restored?.let {
                    it.leave()
                    it.release()
                }
                first?.let {
                    if (restored == null) {
                        it.leave()
                        it.release()
                    }
                }
            }
            context.noBackupFilesDir.deleteRecursively()
        }
    }
}
