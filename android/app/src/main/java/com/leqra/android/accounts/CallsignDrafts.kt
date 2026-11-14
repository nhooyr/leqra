package com.leqra.android.accounts

import java.security.SecureRandom
import java.util.UUID

/** A generated alias can only replace the exact unchanged draft which requested it. */
class CallsignDrafts(saved: List<String?>, pending: List<Boolean?>, requestIDs: List<String?>) {
    private class Draft(
        var name: String,
        var pending: Boolean,
        var requestID: String,
        var revision: Long = 0,
    )

    private val initialRequest = UUID.randomUUID().toString()
    private val seats =
        Array(2) { seat ->
            Draft(
                saved[seat] ?: randomName(),
                pending[seat] ?: (saved[seat] == null),
                requestIDs[seat] ?: initialRequest,
            )
        }

    init {
        for (seat in 0..1) if (saved[seat] == null) {
            while (seats[seat].name == seats[1 - seat].name) seats[seat].name = randomName()
        }
    }

    class Request(
        val seat: Int,
        val origin: String,
        val key: String,
        val name: String,
        val requestID: String,
        val revision: Long,
    )

    fun name(seat: Int) = seats[seat].name

    fun pending(seat: Int) = seats[seat].pending

    fun requestID(seat: Int) = seats[seat].requestID

    fun edit(seat: Int, value: String) {
        if (seats[seat].name == value) return
        cancel(seat)
        seats[seat].name = value
    }

    fun cancel(seat: Int) {
        seats[seat].pending = false
        seats[seat].revision++
    }

    fun generate(seat: Int) {
        seats[seat].name = randomName()
        while (seats[seat].name == seats[1 - seat].name) seats[seat].name = randomName()
        seats[seat].pending = true
        seats[seat].requestID = UUID.randomUUID().toString()
        seats[seat].revision++
    }

    fun request(seat: Int, origin: String, key: String) =
        seats[seat].let { Request(seat, origin, key, it.name, it.requestID, it.revision) }

    fun complete(request: Request, origin: String, key: String?, name: String): Boolean {
        val draft = seats[request.seat]
        if (
            !draft.pending ||
                request.origin != origin ||
                request.key != key ||
                request.revision != draft.revision ||
                request.requestID != draft.requestID ||
                request.name != draft.name
        )
            return false
        draft.name = name
        cancel(request.seat)
        return true
    }

    companion object {
        private val random = SecureRandom()
        private const val alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

        fun randomName() =
            "pilot#" +
                ByteArray(6)
                    .also(random::nextBytes)
                    .map { alphabet[it.toInt() and 31] }
                    .joinToString("")
    }
}
