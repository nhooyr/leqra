package com.leqra.android.accounts

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.leqra.android.network.NetworkFailure
import com.leqra.android.network.ServerAddress
import java.io.IOException
import java.util.concurrent.TimeUnit
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONArray
import org.json.JSONObject

data class PublicProfile(
    val name: String,
    val score: Int,
    val localName: String? = null,
    val localScore: Int? = null,
)

data class AccountInfo(
    val names: List<String>,
    val totalNames: Int,
    val publicProfile: PublicProfile?,
) {
    val preferredCallsign: String?
        get() = publicProfile?.name ?: names.firstOrNull()

    fun scoreForCallsign(name: String): Int? = if (publicProfile != null) {
        publicProfile.takeIf { com.leqra.core.Callsigns.canonical(it.name) == com.leqra.core.Callsigns.canonical(name) }?.score
    } else if (names.size == 1 && com.leqra.core.Callsigns.canonical(names[0]) == com.leqra.core.Callsigns.canonical(name)) 0 else null
}

class CheckedAccount(val origin: String, val key: String, val info: AccountInfo)

data class CallsignAvailability(val seat: Int, val name: String, val available: Boolean, val reason: String = "")

class GeneratedCallsign(val seat: Int, val name: String, val key: String, val selected: Boolean)

data class PublicStatus(
    val players: Int,
    val tankCount: Int,
    val capacity: Int,
    val leaders: List<PublicLeader>,
    val latencyMilliseconds: Double,
)

data class PublicLeader(
    val id: Int,
    val name: String,
    val score: Int,
    val colorIndex: Int,
    val rank: Int,
    val bot: Boolean,
    val difficulty: String = "",
)

class RecoveredAccount(
    val checked: CheckedAccount,
    val promoted: Boolean,
    val pending: PendingAccount,
)

fun interface CancelRequest {
    fun cancel()
}

/**
 * No keys in URLs, redirect bodies, caches, loggers, or analytics. Callbacks run on the main
 * thread.
 */
class AccountService(
    private val store: AccountStore,
    private val dispatch: ((() -> Unit) -> Unit) = { task ->
        Handler(Looper.getMainLooper()).post(task)
    },
) {
    private val http =
        OkHttpClient.Builder()
            .followRedirects(false)
            .followSslRedirects(false)
            .retryOnConnectionFailure(false)
            .callTimeout(6, TimeUnit.SECONDS)
            .build()
    private val epochs = mutableMapOf<String, Long>()

    private fun slot(origin: String, seat: Int) = ServerAddress.origin(origin) + ":" + seat

    @Synchronized
    private fun next(origin: String, seat: Int): Long =
        slot(origin, seat).let { key ->
            ((epochs[key] ?: 0) + 1).also { epochs[key] = it }
        }

    @Synchronized
    private fun current(origin: String, seat: Int, epoch: Long) =
        epochs[slot(origin, seat)] == epoch

    fun invalidate(origin: String, seat: Int) {
        next(origin, seat)
    }

    fun inspect(
        origin: String,
        key: String,
        signIn: Boolean,
        callback: (Result<CheckedAccount>) -> Unit,
    ): CancelRequest {
        if (!AccountKeys.valid(key)) {
            dispatch { callback(Result.failure(invalidKey())) }
            return CancelRequest {}
        }
        val normalized = ServerAddress.origin(origin)
        return request(normalized, "/api/account", JSONObject().put("publicToken", key).apply { if (signIn) put("signIn", true) }) { result ->
            callback(result.mapCatching { CheckedAccount(normalized, key, parseInfo(it)) })
        }
    }

    fun inspect(origin: String, key: String, callback: (Result<CheckedAccount>) -> Unit): CancelRequest = inspect(origin, key, false, callback)

    /**
     * Called only after the user has reviewed the authenticated preview and explicitly chosen Use
     * key.
     */
    fun useChecked(checked: CheckedAccount, seat: Int) {
        require(seat in 0..1)
        require(store.selected(checked.origin, 1 - seat)?.key != checked.key) {
            "P1 and P2 need independent account keys."
        }
        next(checked.origin, seat)
        store.select(checked.origin, seat, checked.key)
        store.setActiveIntent(null)
        // Pending requests remain backed up: a canceled HTTP mutation can still commit on the
        // server.
    }

    /** A successful response is required before deleting local credentials. */
    fun release(origin: String, key: String, callback: (Result<Unit>) -> Unit): CancelRequest {
        require(AccountKeys.valid(key))
        return request(origin, "/api/account/release", JSONObject().put("publicToken", key)) { result ->
            callback(result.mapCatching { response ->
                check(response.optBoolean("released")) { "The callsign release could not be confirmed." }
                for (seat in 0..1) next(origin,seat)
                store.forgetAccount(origin,key)
            })
        }
    }

    fun signInChecked(checked: CheckedAccount, seat: Int, previousName: String, canCommit: () -> Boolean = { true }, callback: (Result<CheckedAccount>) -> Unit) {
        require(seat in 0..1)
        val selected = store.selected(checked.origin, seat)?.key
        val epoch = next(checked.origin, seat)
        inspect(checked.origin, checked.key, signIn = true) { result ->
            callback(result.mapCatching { refreshed ->
                check(canCommit() && current(checked.origin, seat, epoch) && store.selected(checked.origin, seat)?.key == selected) {
                    "Account changed while the request was pending."
                }
                store.selected(checked.origin,seat)?.let { rememberCallsign(checked.origin,seat,previousName,it.key) }
                useChecked(refreshed,seat)
                refreshed.info.preferredCallsign?.let { rememberCallsign(refreshed.origin,seat,it,refreshed.key) }
                refreshed
            })
        }
    }

    class SavedCallsign(val name: String, val key: String)

    fun savedCallsigns(origin: String): List<SavedCallsign> = (0..1)
        .flatMap { store.pending(origin, it) }.filter { it.purpose.startsWith("saved:") }
        .map { SavedCallsign(it.purpose.removePrefix("saved:"), it.key) }
        .distinctBy { canonical(it.name) }

    private fun canonical(name: String) = com.leqra.core.Callsigns.canonical(name)

    fun rememberCallsign(origin: String, seat: Int, name: String, key: String) {
        if (savedCallsigns(origin).any { it.name == name && it.key == key }) return
        val old = (0..1).flatMap { store.pending(origin, it) }.filter { it.purpose.startsWith("saved:") && (canonical(it.purpose.removePrefix("saved:")) == canonical(name) || it.key == key) }
        store.savePending(origin, AccountKeys.pending(seat, key, purpose = "saved:$name"))
        old.forEach { store.removePending(origin, it.id) }
    }

    /** The candidate is durable before HTTP; the selected credential changes only after success. */
    fun switchCallsign(origin: String, seat: Int, name: String, previousName: String, localOnly: Boolean = false,
                       canCommit: () -> Boolean = { true },
                       callback: (Result<CheckedAccount>) -> Unit) {
        val previous = store.selected(origin, seat)
        if (previous != null && previousName.isNotBlank()) rememberCallsign(origin, seat, previousName, previous.key)
        val same = canonical(name) == canonical(previousName)
        val saved = savedCallsigns(origin).firstOrNull { canonical(it.name) == canonical(name) }
        val retry = store.pending(origin, seat).lastOrNull { it.purpose == "callsign:${canonical(name)}" && it.previousKey == previous?.key }
        val key = retry?.key ?: if (same && previous != null) previous.key else saved?.key
        if (key != null && key == store.selected(origin, 1-seat)?.key) {
            callback(Result.failure(IllegalStateException("P1 and P2 need independent accounts."))); return
        }
        val pending = retry != null || key == null || same && previous?.registrationPending == true
        var candidate = key ?: store.pending(origin, seat).firstOrNull { it.purpose == "callsign:${canonical(name)}" && it.previousKey == previous?.key }?.key
            ?: AccountKeys.create().also { store.savePending(origin, AccountKeys.pending(seat, it, previous?.key, "callsign:${canonical(name)}")) }
        val epoch = next(origin, seat)
        fun finish(info: AccountInfo, fresh: Boolean) {
            callback(runCatching {
                check(canCommit() && current(origin, seat, epoch) && store.selected(origin, seat)?.key == previous?.key) { "Account changed while the request was pending." }
                check(store.selected(origin, 1 - seat)?.key != candidate) { "P1 and P2 need independent accounts." }
                check(info.preferredCallsign?.let(::canonical) == canonical(name)) { "The saved account no longer owns that callsign." }
                rememberCallsign(origin, seat, info.preferredCallsign!!, candidate)
                store.select(origin, seat, candidate, fresh)
                if (!fresh) store.pending(origin, seat).filter { it.purpose == "callsign:${canonical(name)}" }.forEach { store.removePending(origin, it.id) }
                CheckedAccount(ServerAddress.origin(origin), candidate, info)
            })
        }
        fun create() {
            request(origin, "/api/account/create", JSONObject().put("publicToken", candidate).put("name", name)) { response ->
                response.fold({ json -> runCatching { parseInfo(json) }.fold({ finish(it, false) }, { callback(Result.failure(it)) }) }, { callback(Result.failure(it)) })
            }
        }
        if (localOnly) { finish(AccountInfo(listOf(name), 1, null), pending); return }
        if (pending) create()
        else inspect(origin, candidate, signIn = true) { result ->
            result.fold({ finish(it.info, false) }, { error ->
                if ((error as? NetworkFailure)?.code in setOf("invalid_account_key", "account_key_invalid", "account_expired")) {
                    candidate = AccountKeys.create()
                    store.savePending(origin, AccountKeys.pending(seat, candidate, previous?.key, "callsign:${canonical(name)}"))
                    create()
                }
                else callback(Result.failure(error))
            })
        }
    }

    fun availability(
        origin: String,
        names: List<String>,
        callback: (Result<List<CallsignAvailability>>) -> Unit,
    ): CancelRequest {
        require(names.size in 1..2)
        val saved = savedCallsigns(origin)
        val first = saved.firstOrNull { canonical(it.name) == canonical(names[0]) }?.let { AccountCredential(it.key) } ?: store.selected(origin, 0)
        val second = names.getOrNull(1)?.let { name -> saved.firstOrNull { canonical(it.name) == canonical(name) } }?.let { AccountCredential(it.key) } ?: store.selected(origin, 1)
        val body = JSONObject().put("names", JSONArray(names)).put("publicToken", first?.key)
        if (names.size == 2)
            body
                .put("independentAccounts", true)
                .put("localPublicToken", second?.key)
                .put("localNewAccount", second?.registrationPending == true)
        return request(origin, "/api/callsigns", body) { response ->
            callback(
                response.mapCatching { json ->
                    val rows = json.getJSONArray("names")
                    require(rows.length() == names.size)
                    (0 until rows.length()).map { index ->
                        rows.getJSONObject(index).let {
                            require(it.getInt("seat") == index && it.getString("name").length <= 64)
                            CallsignAvailability(
                                index,
                                it.getString("name"),
                                it.getBoolean("available"),
                                it.optString("reason"),
                            )
                        }
                    }
                },
            )
        }
    }

    /** Both selected bearer and backup reach durable storage before the HTTP request exists. */
    fun generate(
        origin: String,
        seats: List<Int>,
        requestID: String,
        freshAccount: Boolean,
        canCommit: () -> Boolean = { true },
        callback: (Result<List<GeneratedCallsign>>) -> Unit,
    ): CancelRequest {
        require(
            seats.size in 1..2 && seats.distinct().size == seats.size && seats.all { it in 0..1 }
        )
        require(java.util.UUID.fromString(requestID).toString() == requestID)
        val normalized = ServerAddress.origin(origin)
        val ordered = seats.sorted()
        val previous = ordered.associateWith { store.selected(normalized, it) }
        val credentials = ordered.associateWith { seat ->
            if (!freshAccount) store.selected(normalized, seat) ?: store.prepareRegistration(normalized, seat)
            else {
                val pending = store.pending(normalized, seat).firstOrNull { it.purpose == "generate:$requestID" }
                    ?: AccountKeys.pending(seat, AccountKeys.create(), previous[seat]?.key, "generate:$requestID").also { store.savePending(normalized, it) }
                AccountCredential(pending.key, true)
            }
        }
        val epochs = ordered.associateWith { next(normalized, it) }
        val body =
            JSONObject()
                .put("requestId", requestID)
                .put(
                    "accounts",
                    JSONArray().apply {
                        ordered.forEach {
                            put(
                                JSONObject()
                                    .put("seat", it)
                                    .put("publicToken", credentials.getValue(it).key)
                            )
                        }
                    },
                )
        return request(normalized, "/api/callsigns/generate", body) { result ->
            callback(
                result.mapCatching { json ->
                    val rows = json.getJSONArray("names")
                    require(rows.length() == ordered.size)
                    val names =
                        ordered.mapIndexed { index, seat ->
                            val row = rows.getJSONObject(index)
                            require(row.getInt("seat") == seat)
                            row.getString("name").also {
                            require(Regex("(?:pilot#[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}|pilot-[a-z2-7]{10})").matches(it))
                            }
                        }
                    ordered.mapIndexed { index, seat ->
                        val key = credentials.getValue(seat).key
                        val selected =
                            canCommit() && current(normalized, seat, epochs.getValue(seat)) &&
                                store.selected(normalized, 1 - seat)?.key != key &&
                                store.selected(normalized, seat)?.key == (if (freshAccount) previous[seat]?.key else key)
                        // The HTTP response proves P1's candidate is registered. A canceled
                        // request leaves it pending so a later custom-name join can start fresh.
                        if (selected && (freshAccount || seat == 0 && credentials.getValue(seat).registrationPending)) {
                            store.select(normalized, seat, key)
                            rememberCallsign(normalized, seat, names[index], key)
                        }
                        // Name generation is not the first gameplay acknowledgement.
                        // Preserve fresh-P2 legacy migration intent until Welcome confirms the key.
                        GeneratedCallsign(seat, names[index], key, selected)
                    }
                }
            )
        }
    }

    fun generate(origin: String, seats: List<Int>, requestID: String, callback: (Result<List<GeneratedCallsign>>) -> Unit): CancelRequest =
        generate(origin, seats, requestID, false, callback = callback)

    fun publicStatus(origin: String, callback: (Result<PublicStatus>) -> Unit): CancelRequest {
        val started = SystemClock.elapsedRealtimeNanos()
        return request(origin, "/api/infinity", null, 65_536) { result ->
            callback(
                result.mapCatching { json ->
                    val rows = json.optJSONArray("leaders") ?: JSONArray()
                    require(rows.length() <= 128)
                    val leaders =
                        (0 until rows.length()).map {
                            rows.getJSONObject(it).run {
                                PublicLeader(
                                    getInt("id"),
                                    getString("name"),
                                    getInt("score"),
                                    optInt("colorIndex"),
                                    optInt("rank"),
                                    optBoolean("bot"),
                                    optString("difficulty", ""),
                                )
                            }
                        }
                    PublicStatus(
                        json.getInt("players"),
                        json.getInt("tankCount"),
                        json.getInt("capacity"),
                        leaders,
                        (SystemClock.elapsedRealtimeNanos() - started) / 1_000_000.0,
                    )
                },
            )
        }
    }

    /** Candidate is persisted before the request; retry always reuses that same candidate. */
    fun rotate(
        origin: String,
        seat: Int,
        callback: (Result<RecoveredAccount>) -> Unit,
    ): CancelRequest {
        val selected = store.selected(origin, seat) ?: throw invalidKey()
        require(!selected.registrationPending) {
            "Finish creating this account before resetting its key."
        }
        val pending =
            store.pending(origin, seat).lastOrNull {
                it.purpose == "rotation" && it.previousKey == selected.key
            }
                ?: AccountKeys.pending(seat, AccountKeys.create(), selected.key, "rotation").also {
                    store.savePending(origin, it)
                }
        val epoch = next(origin, seat)
        return request(
            origin,
            "/api/account/rotate",
            JSONObject().put("publicToken", selected.key).put("newPublicToken", pending.key),
        ) { result ->
            if (result.isSuccess) {
                val validated = result.mapCatching { json ->
                    require(json.getString("publicToken") == pending.key)
                    complete(origin, pending, parseInfo(json), epoch)
                }
                callback(validated)
            } else {
                // A lost response can follow a committed rotation. Validate the saved replacement
                // first.
                recoverInternal(origin, pending, epoch, callback)
            }
        }
    }

    fun recover(
        origin: String,
        pending: PendingAccount,
        callback: (Result<RecoveredAccount>) -> Unit,
    ): CancelRequest = recoverInternal(origin, pending, next(origin, pending.seat), callback)

    private fun recoverInternal(
        origin: String,
        pending: PendingAccount,
        epoch: Long,
        callback: (Result<RecoveredAccount>) -> Unit,
    ): CancelRequest =
        inspect(origin, pending.key) { replacement ->
            if (replacement.isSuccess) {
                callback(
                    runCatching { complete(origin, pending, replacement.getOrThrow().info, epoch) },
                )
            } else if (
                (replacement.exceptionOrNull() as? NetworkFailure)?.code == "invalid_account_key" &&
                    pending.previousKey != null
            ) {
                inspect(origin, pending.previousKey) { previous ->
                    if (
                        (previous.exceptionOrNull() as? NetworkFailure)?.code ==
                            "account_key_revoked"
                    ) {
                        // Recheck AFTER observing old-key revocation. Earlier 401 is not proof of
                        // rollback.
                        inspect(origin, pending.key) { finalCheck ->
                            if (finalCheck.isSuccess)
                                callback(
                                    runCatching {
                                        complete(
                                            origin,
                                            pending,
                                            finalCheck.getOrThrow().info,
                                            epoch,
                                        )
                                    },
                                )
                            else
                                callback(
                                    Result.failure(finalCheck.exceptionOrNull() ?: invalidKey()),
                                )
                        }
                    } else
                        callback(
                            Result.failure(
                                NetworkFailure(
                                    "recovery_pending",
                                    "The replacement is saved safely. Retry the reset to finish it; keep both keys until it is confirmed.",
                                    terminal = false,
                                ),
                            ),
                        )
                }
            } else callback(Result.failure(replacement.exceptionOrNull() ?: invalidKey()))
        }

    private fun complete(
        origin: String,
        pending: PendingAccount,
        info: AccountInfo,
        epoch: Long,
    ): RecoveredAccount {
        val selected = store.selected(origin, pending.seat)?.key
        val promote =
            current(origin, pending.seat, epoch) &&
                store.selected(origin, 1 - pending.seat)?.key != pending.key &&
                (selected == pending.previousKey ||
                    selected == pending.key ||
                    selected == null && pending.previousKey == null)
        if (promote) {
            store.select(origin, pending.seat, pending.key)
            info.preferredCallsign?.let { rememberCallsign(origin, pending.seat, it, pending.key) }
            store.removePending(origin, pending.id)
        }
        return RecoveredAccount(
            CheckedAccount(ServerAddress.origin(origin), pending.key, info),
            promote,
            pending,
        )
    }

    private fun request(
        origin: String,
        path: String,
        json: JSONObject?,
        limit: Long = 16_384,
        callback: (Result<JSONObject>) -> Unit,
    ): CancelRequest {
        val request =
            Request.Builder()
                .url(ServerAddress.endpoint(origin, path))
                .header("Origin", ServerAddress.origin(origin))
                .header("Cache-Control", "no-store")
                .apply {
                    if (json != null)
                        post(json.toString().toRequestBody("application/json".toMediaType()))
                }
                .build()
        val call = http.newCall(request)
        call.enqueue(
            object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if (!call.isCanceled())
                        dispatch {
                            callback(
                                Result.failure(
                                    NetworkFailure(
                                        "network",
                                        "The server could not be reached. Try again.",
                                        terminal = false,
                                    ),
                                ),
                            )
                        }
                }

                override fun onResponse(call: Call, response: Response) {
                    val result = runCatching {
                        response.use {
                            val body =
                                it.body
                                    ?: throw NetworkFailure(
                                        "invalid_response",
                                        "The server sent an invalid response.",
                                    )
                            val source = body.source()
                            if (source.request(limit + 1) && source.buffer.size > limit)
                                throw NetworkFailure(
                                    "invalid_response",
                                    "The server sent an oversized response.",
                                )
                            val value = JSONObject(source.readUtf8())
                            if (!it.isSuccessful) {
                                val code =
                                    value.optString(
                                        "code",
                                        if (it.code == 401) "invalid_account_key"
                                        else "server_error",
                                    )
                                val message =
                                    when (code) {
                                        "callsign_reserved" -> com.leqra.core.Callsigns.botNamespaceMessage
                                        "account_key_revoked" ->
                                            "This account key was reset. Import its new key to sign in again."
                                        "invalid_account_key",
                                        "account_invalid",
                                        "invalid_key" ->
                                            "That account key is invalid or unavailable."
                                        else ->
                                            value.optString(
                                                "message",
                                                "The server could not complete this action. Try again.",
                                            )
                                    }
                                throw NetworkFailure(
                                    if (it.code == 401 && code != "account_key_revoked")
                                        "invalid_account_key"
                                    else code,
                                    message,
                                    terminal = it.code < 500,
                                )
                            }
                            value
                        }
                    }
                    if (!call.isCanceled()) dispatch { callback(result) }
                }
            },
        )
        return CancelRequest { call.cancel() }
    }

    fun close() {
        http.dispatcher.cancelAll()
        http.dispatcher.executorService.shutdown()
        http.connectionPool.evictAll()
    }

    companion object {
        fun parseInfo(json: JSONObject): AccountInfo {
            val rows = json.getJSONArray("names")
            require(rows.length() <= 128)
            val names =
                (0 until rows.length()).map {
                    rows.getString(it).also { name ->
                        require(name.isNotBlank() && name.codePointCount(0, name.length) <= 16)
                    }
                }
            val total = json.optInt("totalNames", names.size)
            require(total >= names.size)
            val profile =
                json.optJSONObject("publicProfile")?.let {
                    val name = it.getString("name")
                    require(name.isNotEmpty() && name.codePointCount(0, name.length) <= 16)
                    PublicProfile(
                        name,
                        it.getInt("score"),
                        it.optString("localName").takeIf(String::isNotEmpty),
                        if (it.has("localScore")) it.getInt("localScore") else null,
                    )
                }
            return AccountInfo(names, total, profile)
        }

        private fun invalidKey() =
            NetworkFailure("invalid_account_key", "That account key is invalid or unavailable.")
    }
}
