package com.leqra.android.network

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.leqra.android.BuildConfig
import com.leqra.android.accounts.EncryptedAccountStore
import com.leqra.android.accounts.isolatedAccountContext
import java.net.ServerSocket
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HttpDiscoveryRecoveryTest {
    @Test fun truncatedBuildAndAccountBodiesKeepRetrying() = verify("truncated", true)
    @Test fun malformedBuildAndAccountBodiesAreTerminal() = verify("malformed", false)
    @Test fun oversizedBuildAndAccountBodiesAreTerminal() = verify("oversized", false)
    @Test fun unavailableAccountResponseRetriesWithoutRequiringJson() = verify("unavailable", true, accounts = listOf(true))
    @Test fun incompatibleBuildProtocolIsTerminalDespiteMatchingRelease() = verify("incompatible", false, accounts = listOf(false))

    private fun verify(kind: String, retries: Boolean, accounts: List<Boolean> = listOf(false, true)) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        for (account in accounts) {
            val context = isolatedAccountContext()
            val store = EncryptedAccountStore(context)
            val events = LinkedBlockingQueue<NetworkEvent>()
            val server = ServerSocket(0).apply { soTimeout = 6000 }
            val origin = "http://127.0.0.1:${server.localPort}"
            if (account) store.prepareRegistration(origin, 0)
            val worker = Thread {
                repeat(if (account) 2 else 1) { request ->
                    server.accept().use { socket ->
                        val reader = socket.getInputStream().bufferedReader()
                        var contentLength = 0
                        while (true) {
                            val line = reader.readLine() ?: break
                            if (line.isEmpty()) break
                            if (line.startsWith("Content-Length:", true)) contentLength = line.substringAfter(':').trim().toInt()
                        }
                        repeat(contentLength) { reader.read() }
                        val discovery = account && request == 0
                        val body = when {
                            discovery && kind == "unavailable" -> """{"version":"0.0.0","protocol":${GameWireProtocol.epoch}}"""
                            discovery -> """{"version":"0.0.0"}"""
                            kind == "incompatible" -> """{"version":"${BuildConfig.VERSION_NAME}","protocol":${GameWireProtocol.epoch + 1}}"""
                            kind == "oversized" -> " ".repeat(if (account) 65537 else 8193)
                            kind == "unavailable" -> "<html>Unavailable</html>"
                            else -> "{broken"
                        }
                        val declared = body.length + if (!discovery && kind == "truncated") 100 else 0
                        val status = if (!discovery && kind == "unavailable") "503 Unavailable" else "200 OK"
                        socket.getOutputStream().write("HTTP/1.1 $status\r\nContent-Length: $declared\r\nConnection: close\r\n\r\n$body".toByteArray())
                    }
                }
            }.apply { isDaemon = true; start() }
            var client: NativeNetworkClient? = null
            try {
                instrumentation.runOnMainSync { client = NativeNetworkClient(store, events::offer); client!!.connectPublic(origin, "HttpAudit", 0) }
                val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(6)
                var outcome: NetworkEvent? = null
                while (System.nanoTime() < deadline && outcome == null) {
                    val event = events.poll(100, TimeUnit.MILLISECONDS)
                    if (event is NetworkEvent.Error || event is NetworkEvent.Reconnecting) outcome = event
                }
                if (retries) assertTrue("$kind account=$account retries: $outcome", outcome is NetworkEvent.Reconnecting)
                else assertTrue("$kind account=$account is rejected: $outcome", outcome is NetworkEvent.Error && outcome.terminal)
                if (kind == "incompatible") assertEquals("version_mismatch", (outcome as NetworkEvent.Error).code)
            } finally {
                instrumentation.runOnMainSync { client?.close() }
                server.close(); worker.join(1000); context.noBackupFilesDir.deleteRecursively()
            }
        }
    }
}
