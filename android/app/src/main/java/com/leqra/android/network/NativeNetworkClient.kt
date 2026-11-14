package com.leqra.android.network

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.leqra.android.BuildConfig
import com.leqra.android.accounts.AccountKeys
import com.leqra.android.accounts.AccountStore
import com.leqra.android.accounts.PublicIntent
import com.leqra.core.GameInput
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.math.min
import kotlin.math.pow
import okhttp3.Call
import okhttp3.Callback
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import org.json.JSONArray
import org.json.JSONObject

/** Native transport. Public mutations and event delivery belong to the main thread. */
class NativeNetworkClient(
    private val store: AccountStore,
    var onEvent: (NetworkEvent) -> Unit = {},
    private val main: Handler = Handler(Looper.getMainLooper()),
) {
    private val http =
        OkHttpClient.Builder()
            .followRedirects(false)
            .followSslRedirects(false)
            .connectTimeout(6, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.SECONDS)
            .build()
    private var socket: WebSocket? = null
    private var discovery: Call? = null
    private var epoch = 0L
    private var origin: String? = null
    private var infinity = false
    private var pendingJoin = JSONObject()
    private var resumeJoin: JSONObject? = null
    private var retryAttempt = 0
    private var deadline: Long? = null
    private var suspended = false
    private var lastReceived = 0L
    private var sequence = 0L
    private var localSequence = 0L
    private var renameSequence = 0L
    private var selectionAtJoin = arrayOfNulls<String>(2)
    private val pingTimes = LinkedHashSet<Long>()
    private var retry: Runnable? = null
    private var heartbeat: Runnable? = null
    var connected: Boolean = false
        private set

    var welcome: NetworkWelcome? = null
        private set

    internal val connectionGeneration: Long
        get() = epoch

    private sealed interface Incoming {
        class State(val snapshot: com.leqra.core.ArenaSnapshot) : Incoming

        class Packet(val json: JSONObject) : Incoming
    }

    var automaticallyReconnects = true
    val lastInputSequence: Long
        get() = sequence

    val lastLocalInputSequence: Long
        get() = localSequence

    val accountKey: String?
        get() = welcome?.publicToken ?: pendingJoin.stringOrNull("publicToken")

    val localAccountKey: String?
        get() = welcome?.localPublicToken ?: pendingJoin.stringOrNull("localPublicToken")

    val isPublic: Boolean
        get() = infinity && !pendingJoin.has("code")

    fun connectPublic(
        origin: String,
        name: String,
        colorIndex: Int,
        localName: String? = null,
        localColorIndex: Int = 1,
        updateNames: Boolean = false,
    ) {
        val normalized = ServerAddress.origin(origin)
        val first = store.selected(normalized, 0)
        val second = if (localName != null) store.prepareRegistration(normalized, 1) else null
        require(first == null || second?.key != first.key) {
            "P1 and P2 need independent account keys."
        }
        val join =
            JSONObject()
                .put("type", "join")
                .put("name", name)
                .put("colorIndex", colorIndex.coerceIn(0, 7))
                .put("publicToken", first?.key)
                .put("localName", localName)
        if (first != null) join.put("resume", true)
        if (localName != null)
            join
                .put("localColorIndex", localColorIndex.coerceIn(0, 7))
                .put("localPublicToken", second?.key)
                .put("localNewAccount", second?.registrationPending == true)
        if (updateNames) join.put("updateNames", true)
        store.setActiveIntent(
            PublicIntent(normalized, name, colorIndex, localName, localColorIndex),
        )
        begin(normalized, true, join, false)
    }

    /** Restores only deliberately active public play. Merely saving a P2 key never joins P2. */
    fun restorePublicIntent(): Boolean {
        val saved = store.activeIntent() ?: return false
        connectPublic(
            saved.origin,
            saved.name,
            saved.colorIndex,
            saved.localName,
            saved.localColorIndex,
        )
        return true
    }

    fun connectRoom(
        origin: String,
        name: String,
        code: String? = null,
        spectating: Boolean = false,
    ) {
        val join =
            JSONObject()
                .put("type", if (code.isNullOrBlank()) "create" else "join")
                .put("name", name)
                .put("spectating", spectating)
                .put("publicToken", store.selected(origin, 0)?.key)
        if (!code.isNullOrBlank()) join.put("code", code)
        begin(ServerAddress.origin(origin), false, join, false)
    }

    fun connectPublishedRoom(
        origin: String,
        name: String,
        rules: JSONObject,
        roster: JSONArray,
        code: String? = null,
    ) {
        val join =
            JSONObject()
                .put("type", "publish")
                .put("name", name)
                .put("rules", rules)
                .put("roster", roster)
                .put("code", code)
                .put("publicToken", store.selected(origin, 0)?.key)
        if ((0 until roster.length()).any { roster.getJSONObject(it).optString("kind") == "local" })
            attachLocalCredential(join, origin)
        begin(ServerAddress.origin(origin), false, join, false)
    }

    fun connectRoomInfinity(
        origin: String,
        code: String,
        token: String,
        resume: Boolean = false,
        generation: Long? = null,
        includeLocal: Boolean = false,
    ) {
        val join = JSONObject().put("type", "join").put("code", code).put("token", token)
        if (resume) join.put("resume", true).put("generation", generation)
        if (includeLocal)
            store.selected(origin, 1)?.let {
                join.put("localPublicToken", it.key).put("localNewAccount", it.registrationPending)
            }
        begin(ServerAddress.origin(origin), true, join, resume)
    }

    private fun attachLocalCredential(json: JSONObject, origin: String) {
        val second = store.prepareRegistration(origin, 1)
        require(second.key != store.selected(origin, 0)?.key) {
            "P1 and P2 need independent account keys."
        }
        json
            .put("independentAccounts", true)
            .put("localPublicToken", second.key)
            .put("localNewAccount", second.registrationPending)
    }

    fun send(command: JSONObject) {
        // These mutations can register/migrate P2, so its durable candidate must precede the send.
        val type = command.optString("type")
        val includesLocal =
            type == "add" && command.optString("kind") == "local" ||
                type == "preset" &&
                    command.optJSONArray("roster")?.let { rows ->
                        (0 until rows.length()).any {
                            rows.getJSONObject(it).optString("kind") == "local"
                        }
                    } == true
        val editsLocal =
            type in setOf("configure", "rename_local") &&
                welcome?.localId != null &&
                command.optInt("target", -1) == welcome?.localId
        if ((includesLocal || editsLocal) && origin != null)
            attachLocalCredential(command, origin!!)
        command.stringOrNull("localPublicToken")?.let {
            pendingJoin.put("localPublicToken", it)
            selectionAtJoin[1] = store.selected(origin!!, 1)?.key
        }
        val text = command.toString()
        if (text.toByteArray(Charsets.UTF_8).size > 8192) return
        val active = socket ?: return
        if (active.queueSize() > 128 * 1024 || !active.send(text))
            fail("The connection cannot keep up. Reconnecting…", false)
    }

    fun sendInput(
        input: GameInput,
        paused: Boolean = false,
        local: Boolean = false,
        player: Int? = null,
        member: Long? = null,
    ) {
        if (!connected) return
        val previous = if (local) localSequence else sequence
        val next = if (input.seq > 0) input.seq else previous + 1
        if (next <= previous) return
        if (local) localSequence = next else sequence = next
        val command =
            JSONObject()
                .put("type", "input")
                .put("seq", next)
                .put("forward", !paused && input.forward)
                .put("reverse", !paused && input.reverse)
                .put("left", !paused && input.left)
                .put("right", !paused && input.right)
                .put("fire", !paused && input.fire)
                .put("stickX", if (paused) 0.0 else input.stickX)
                .put("stickY", if (paused) 0.0 else input.stickY)
                .put("touchAim", input.touchAim)
                .put("aimOnly", input.aimOnly)
        if (infinity) {
            command.put("paused", paused)
            if (local) command.put("local", true)
        } else command.put("player", player).put("member", member)
        send(command)
    }

    fun renameInfinity(name: String, seat: Int = 0): Long {
        renameSequence++
        send(
            JSONObject()
                .put("type", "rename")
                .put("name", name)
                .put("seat", seat)
                .put("requestId", renameSequence),
        )
        return renameSequence
    }

    fun updateResumeRoomCode(code: String) {
        if (!isPublic) {
            resumeJoin?.put("code", code)
            welcome?.room = code
        }
    }

    fun reconnect(): Boolean {
        suspended = false
        return scheduleReconnect(true)
    }

    fun resume(): Boolean {
        suspended = false
        return if (resumeJoin != null) scheduleReconnect(true) else false
    }

    /**
     * Backgrounding sends neutral controls and closes transport, without leave or erasing public
     * intent.
     */
    fun suspend() {
        if (connected) {
            sendInput(GameInput(), paused = true, player = welcome?.id, member = welcome?.member)
            if (welcome?.localId != null)
                sendInput(
                    GameInput(),
                    paused = true,
                    local = true,
                    player = welcome?.localId,
                    member = welcome?.localMember,
                )
        }
        if (!isPublic && resumeJoin != null && deadline == null)
            deadline = SystemClock.elapsedRealtime() + 18_000
        suspended = true
        invalidate()
    }

    fun close() {
        suspend()
        http.dispatcher.cancelAll()
        http.dispatcher.executorService.shutdown()
        http.connectionPool.evictAll()
    }

    /** Explicit exit retires the tank; account credentials are retained. */
    fun disconnect(clearPublicIntent: Boolean = true) {
        if (connected) socket?.send("{\"type\":\"leave\"}")
        if (clearPublicIntent && isPublic) store.setActiveIntent(null)
        resumeJoin = null
        deadline = null
        retryAttempt = 0
        suspended = false
        invalidate()
        origin = null
    }

    private fun invalidate() {
        epoch++
        retry?.let(main::removeCallbacks)
        retry = null
        heartbeat?.let(main::removeCallbacks)
        heartbeat = null
        discovery?.cancel()
        discovery = null
        socket?.close(1001, null)
        socket = null
        connected = false
        welcome = null
        pingTimes.clear()
    }

    private fun begin(origin: String, infinity: Boolean, join: JSONObject, resuming: Boolean) {
        invalidate()
        this.origin = origin
        this.infinity = infinity
        this.pendingJoin = JSONObject(join.toString()).put("independentAccounts", true)
        this.suspended = false
        if (!resuming) {
            deadline = null
            retryAttempt = 0
            resumeJoin = null
        }
        if (infinity && !join.has("code")) resumeJoin = JSONObject(pendingJoin.toString())
        else if (infinity && join.has("token")) resumeJoin = JSONObject(pendingJoin.toString())
        selectionAtJoin = arrayOf(store.selected(origin, 0)?.key, store.selected(origin, 1)?.key)
        sequence = 0
        localSequence = 0
        lastReceived = SystemClock.elapsedRealtime()
        val current = epoch
        onEvent(NetworkEvent.Status(if (resuming) "Reconnecting…" else "Connecting…"))
        startHeartbeat(current)
        val call =
            http.newCall(
                Request.Builder()
                    .url(ServerAddress.endpoint(origin, "/api/build"))
                    .header("Cache-Control", "no-cache")
                    .build(),
            )
        discovery = call
        call.enqueue(
            object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    main.post {
                        if (epoch == current && !call.isCanceled())
                            fail("The server could not be reached. Reconnecting…", false)
                    }
                }

                override fun onResponse(call: Call, response: Response) {
                    val build = runCatching {
                        response.use {
                            if (it.code == 429 || it.code >= 500)
                                throw NetworkFailure(
                                    "server_busy",
                                    "The server is temporarily unavailable. Reconnecting…",
                                    terminal = false,
                                )
                            if (!it.isSuccessful)
                                throw NetworkFailure(
                                    "invalid_response",
                                    "The server sent an invalid response.",
                                )
                            val source = it.body?.source() ?: throw IOException()
                            if (source.request(8193) && source.buffer.size > 8192)
                                throw IOException()
                            val version = JSONObject(source.readUtf8()).getString("version")
                            if (version != BuildConfig.VERSION_NAME)
                                throw NetworkFailure(
                                    "version",
                                    "This server is running leqra $version. Update the app before joining.",
                                )
                            version
                        }
                    }
                    main.post {
                        if (epoch != current || call.isCanceled()) return@post
                        build.fold(
                            { version -> openSocket(current, version) },
                            { error ->
                                fail(
                                    error.message ?: "The server sent an invalid response.",
                                    (error as? NetworkFailure)?.terminal ?: true,
                                    (error as? NetworkFailure)?.code,
                                )
                            },
                        )
                    }
                }
            },
        )
    }

    private fun openSocket(current: Long, version: String) {
        val address = origin ?: return
        val decoder = SnapshotDecoder()
        val request =
            Request.Builder()
                .url(ServerAddress.endpoint(address, if (infinity) "/ws/infinite" else "/ws"))
                .header("Origin", address)
                .build()
        socket =
            http.newWebSocket(
                request,
                object : WebSocketListener() {
                    override fun onOpen(webSocket: WebSocket, response: Response) {
                        main.post {
                            if (epoch != current) {
                                webSocket.close(1001, null)
                                return@post
                            }
                            if (infinity)
                                send(JSONObject(pendingJoin.toString()).put("version", version))
                        }
                    }

                    override fun onMessage(webSocket: WebSocket, text: String) {
                        if (text.length > 2 * 1024 * 1024) {
                            main.post {
                                if (epoch == current)
                                    fail("The server sent an oversized message.", true)
                            }
                            return
                        }
                        val value = runCatching {
                            val json = JSONObject(text)
                            // A queued state needs its DTOs, not a second retained
                            // JSONObject tree containing every projectile as well.
                            if (json.optString("type") == "state")
                                Incoming.State(decoder.decode(json))
                            else Incoming.Packet(json)
                        }
                        main.post {
                            if (epoch != current) return@post
                            lastReceived = SystemClock.elapsedRealtime()
                            value.fold(
                                { incoming ->
                                    try {
                                        when (incoming) {
                                            is Incoming.State ->
                                                onEvent(NetworkEvent.State(incoming.snapshot))
                                            is Incoming.Packet -> receive(incoming.json)
                                        }
                                    } catch (error: Exception) {
                                        fail(
                                            error.message ?: "The server sent an invalid response.",
                                            true,
                                            (error as? NetworkFailure)?.code,
                                        )
                                    }
                                },
                                { fail("The server sent an invalid response.", true) },
                            )
                        }
                    }

                    override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                        onMessage(webSocket, bytes.utf8())
                    }

                    override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                        main.post {
                            if (epoch == current)
                                fail("The connection closed. Reconnecting…", false)
                        }
                    }

                    override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                        webSocket.close(code, null)
                    }

                    override fun onFailure(
                        webSocket: WebSocket,
                        t: Throwable,
                        response: Response?,
                    ) {
                        response?.close()
                        main.post {
                            if (epoch == current)
                                fail("The connection was interrupted. Reconnecting…", false)
                        }
                    }
                },
            )
    }

    private fun receive(json: JSONObject) {
        when (val type = json.getString("type")) {
            "server_hello" -> {
                if (infinity || json.optInt("protocol") != 1)
                    throw NetworkFailure(
                        "protocol",
                        "This server uses an unsupported game protocol.",
                    )
                if (json.optString("version") != BuildConfig.VERSION_NAME)
                    throw NetworkFailure("version", "Update leqra before joining this server.")
                send(
                    JSONObject()
                        .put("type", "client_hello")
                        .put("version", BuildConfig.VERSION_NAME)
                        .put("protocol", 1),
                )
                send(pendingJoin)
            }
            "welcome",
            "identity" -> acceptWelcome(json, type == "identity")
            "room" -> {
                if (!infinity) {
                    resumeJoin?.put("code", json.optString("code"))
                    welcome?.room = json.optString("code")
                    // Room welcomes carry credentials; the following roster supplies stable P2
                    // seat/member IDs.
                    welcome?.let { current ->
                        val players = json.optJSONArray("players") ?: JSONArray()
                        val local =
                            (0 until players.length())
                                .map { players.getJSONObject(it) }
                                .firstOrNull {
                                    it.optString("kind") == "local" &&
                                        it.optInt("owner", -1) == current.id
                                }
                        val localId = local?.getInt("id")
                        val localMember = local?.getLong("member")
                        if (localId != current.localId || localMember != current.localMember) {
                            welcome = current.withLocal(localId, localMember)
                            onEvent(NetworkEvent.Welcome(welcome!!))
                        }
                    }
                }
                onEvent(NetworkEvent.Packet(json))
            }
            "room_renamed" -> {
                updateResumeRoomCode(json.getString("room"))
                onEvent(NetworkEvent.Packet(json))
            }
            "renamed" -> {
                val seat = json.renamedSeat(welcome?.id ?: -1, welcome?.localId) ?: return
                if (seat == 0) resumeJoin?.put("name", json.optString("name"))
                else resumeJoin?.put("localName", json.optString("name"))
                onEvent(NetworkEvent.Packet(json))
            }
            "infinity_start" -> onEvent(NetworkEvent.InfinityStarted(json.optBoolean("public")))
            "pong" -> {
                val timestamp = json.optLong("t", -1)
                if (pingTimes.remove(timestamp)) {
                    val elapsed = SystemClock.elapsedRealtime() - timestamp
                    if (elapsed in 0..6000) onEvent(NetworkEvent.Latency(elapsed.toDouble()))
                }
            }
            "error" -> {
                val code = json.optString("code")
                val seat = json.intOrNull("seat")
                val message =
                    when (code) {
                        "callsign_reserved" -> com.leqra.core.Callsigns.botNamespaceMessage
                        "session_replaced" ->
                            "${if (seat == 1) "P2's tank" else "This tank"} was taken over on another device. Rejoin to take it back."
                        "account_key_revoked" ->
                            "${if (seat == 1) "P2's account key" else "This account key"} was reset. Import its new key to sign in again."
                        else -> json.optString("message", "The server rejected this action.")
                    }
                onEvent(NetworkEvent.Packet(json))
                if (code == "account_key_revoked") {
                    val slot = seat ?: 0
                    val old = selectionAtJoin[slot.coerceIn(0, 1)]
                    if (old != null)
                        origin?.let { store.clearIfMatching(it, slot.coerceIn(0, 1), old) }
                }
                val transient =
                    isPublic &&
                        code in
                            setOf(
                                "server_shutdown",
                                "server_busy",
                                "full",
                                "arena_full",
                                "busy",
                                "session_active",
                            )
                if (transient || code == "session_active" && deadline != null)
                    fail(message, false, code, seat)
                else if (
                    !connected ||
                        code in setOf("kicked", "session_replaced", "account_key_revoked") ||
                        json.optString("action") == "version"
                )
                    fail(message, true, code, seat)
                else onEvent(NetworkEvent.Error(message, code, seat))
            }
            "server_shutdown" ->
                if (isPublic) fail("Reconnecting after server restart…", false)
                else fail(json.optString("message", "The server is restarting."), true, type)
            "kicked",
            "room_offline" ->
                fail(json.optString("message", "The server closed this session."), true, type)
            "unshared" -> {
                onEvent(NetworkEvent.Packet(json))
                disconnect()
            }
            else -> onEvent(NetworkEvent.Packet(json))
        }
    }

    private fun acceptWelcome(json: JSONObject, identity: Boolean) {
        if (identity) {
            json.put("room", welcome?.room)
            json.put("token", welcome?.token)
        }
        if (infinity && !json.optBoolean("public") && pendingJoin.has("code")) {
            // Arena welcomes omit the private route already authenticated by the ready-room socket.
            json
                .put("room", pendingJoin.getString("code"))
                .put("token", pendingJoin.stringOrNull("token"))
        }
        val info = NetworkWelcome.parse(json)
        val address = origin ?: return
        val expectedLocal = pendingJoin.stringOrNull("localPublicToken")
        if (
            info.localId != null &&
                (info.localPublicToken == null || info.localPublicToken == info.publicToken)
        )
            throw NetworkFailure(
                "local_account_unconfirmed",
                "The server did not confirm P2's independent account. Update the server before adding P2.",
            )
        if (
            info.localId != null &&
                expectedLocal != null &&
                info.localPublicToken != expectedLocal &&
                !(pendingJoin.has("code") &&
                    pendingJoin.optBoolean("localNewAccount") &&
                    info.resumed)
        )
            throw NetworkFailure(
                "local_account_mismatch",
                "This private room uses a different P2 account. Leave and rejoin P2 to use the imported key.",
            )
        arrayOf(info.publicToken, info.localPublicToken).forEachIndexed { seat, key ->
            if (key != null) {
                require(AccountKeys.valid(key))
                val selected = store.selected(address, seat)?.key
                if (selected != key) {
                    store.savePending(
                        address,
                        AccountKeys.pending(seat, key, purpose = "activation"),
                    )
                    if (selected != selectionAtJoin[seat])
                        throw NetworkFailure(
                            "account_selection_changed",
                            "The selected account changed while joining. Join again to use it.",
                        )
                }
                store.select(address, seat, key)
                // A confirmed selected key no longer needs its registration backup; unrelated
                // candidates stay safe.
                store
                    .pending(address, seat)
                    .filter { it.key == key && it.purpose != "rotation" }
                    .forEach { store.removePending(address, it.id) }
                selectionAtJoin[seat] = key
            }
        }
        welcome = info
        connected = true
        if (infinity && info.isPublic) {
            val route = JSONObject(pendingJoin.toString())
            listOf("code", "token", "generation", "updateNames", "localNewAccount")
                .forEach(route::remove)
            route
                .put("publicToken", info.publicToken)
                .put("resume", true)
                .put("localPublicToken", info.localPublicToken)
            if (info.localId == null) {
                route.remove("localName")
                route.remove("localColorIndex")
            }
            resumeJoin = route
            pendingJoin = JSONObject(route.toString())
        } else if (info.room != null && info.token != null) {
            resumeJoin =
                JSONObject()
                    .put("type", "join")
                    .put("code", info.room)
                    .put("token", info.token)
                    .put("name", pendingJoin.optString("name"))
                    .put("localPublicToken", info.localPublicToken)
                    .put("independentAccounts", true)
            if (infinity) resumeJoin?.put("resume", true)?.put("generation", info.generation)
        }
        deadline = null
        retryAttempt = 0
        onEvent(NetworkEvent.Welcome(info))
        onEvent(NetworkEvent.Status("Connected"))
    }

    private fun fail(message: String, terminal: Boolean, code: String? = null, seat: Int? = null) {
        if (!terminal && scheduleReconnect()) return
        if (isPublic) store.setActiveIntent(null)
        resumeJoin = null
        deadline = null
        invalidate()
        onEvent(NetworkEvent.Error(message, code, seat, true))
        onEvent(NetworkEvent.Disconnected(message))
    }

    private fun scheduleReconnect(force: Boolean = false): Boolean {
        if (suspended || !automaticallyReconnects && !force) return false
        val route = resumeJoin ?: return false
        val address = origin ?: return false
        val public = infinity && !route.has("code")
        val now = SystemClock.elapsedRealtime()
        if (public) deadline = null else if (deadline == null) deadline = now + 18_000
        if (deadline?.let { now >= it } == true) {
            // Background suspension removes timers. An expired foreground
            // resume must still leave the session with an explicit error.
            if (force) fail("The reconnect window expired. Join the room again.", true)
            return false
        }
        retryAttempt++
        val attempt = retryAttempt
        invalidate()
        val current = epoch
        val delay =
            if (public) min(10_000.0, 300 * 1.6.pow(min(attempt - 1, 8))).toLong()
            else min(2000L, 300L * attempt)
        onEvent(NetworkEvent.Reconnecting(attempt))
        onEvent(NetworkEvent.Status("Reconnecting…"))
        retry =
            Runnable {
                if (epoch == current && !suspended) {
                    if (deadline?.let { SystemClock.elapsedRealtime() >= it } == true)
                        fail("The reconnect window expired. Join the room again.", true)
                    else begin(address, infinity, route, true)
                }
            }
                .also { main.postDelayed(it, delay) }
        return true
    }

    private fun startHeartbeat(current: Long) {
        heartbeat =
            object : Runnable {
                    override fun run() {
                        if (epoch != current || suspended) return
                        val now = SystemClock.elapsedRealtime()
                        if (deadline?.let { now >= it } == true && !connected) {
                            fail("The reconnect window expired. Join the room again.", true)
                            return
                        }
                        if (now - lastReceived > if (connected) 12_000 else 6500) {
                            fail("The server stopped responding. Reconnecting…", false)
                            return
                        }
                        if (connected) {
                            pingTimes.removeAll { now - it > 6000 }
                            while (pingTimes.size >= 8) pingTimes.remove(pingTimes.first())
                            pingTimes.add(now)
                            send(JSONObject().put("type", "ping").put("t", now))
                        }
                        main.postDelayed(this, 1000)
                    }
                }
                .also { main.postDelayed(it, 1000) }
    }
}
