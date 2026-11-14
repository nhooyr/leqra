package com.leqra.android.network

import com.leqra.core.ArenaSnapshot
import org.json.JSONObject

/** Room credentials remain in memory; never persist a private room token. */
class NetworkWelcome(
    val id: Int,
    val seed: Int?,
    var room: String?,
    val token: String?,
    val publicToken: String?,
    val localPublicToken: String?,
    val isPublic: Boolean,
    val spectating: Boolean,
    val localId: Int?,
    val generation: Long?,
    val member: Long?,
    val localMember: Long?,
    val resumed: Boolean,
    val created: Boolean,
    val full: Boolean,
    val busy: Boolean,
    val following: Int = 0,
) {
    fun withLocal(id: Int?, member: Long?, spectating: Boolean = this.spectating) =
        NetworkWelcome(
            this.id,
            seed,
            room,
            token,
            publicToken,
            localPublicToken,
            isPublic,
            spectating,
            id,
            generation,
            this.member,
            member,
            resumed,
            created,
            full,
            busy,
            following,
        )

    companion object {
        fun parse(json: JSONObject) =
            NetworkWelcome(
                json.getInt("id"),
                json.intOrNull("seed"),
                json.stringOrNull("room"),
                json.stringOrNull("token"),
                json.stringOrNull("publicToken"),
                json.stringOrNull("localPublicToken"),
                json.optBoolean("public"),
                json.optBoolean("spectating"),
                json.intOrNull("localId")?.takeIf { it >= 0 },
                json.longOrNull("generation"),
                json.longOrNull("member"),
                json.longOrNull("localMember")?.takeIf { it > 0 },
                json.optBoolean("resumed"),
                json.optBoolean("created"),
                json.optBoolean("full"),
                json.optBoolean("busy"),
                json.optInt("following"),
            )
    }
}

sealed interface NetworkEvent {
    data class Status(val message: String) : NetworkEvent

    class Welcome(val welcome: NetworkWelcome) : NetworkEvent

    data class State(val snapshot: ArenaSnapshot) : NetworkEvent

    /**
     * Full protocol room, chat, queue, identity notices and rename acknowledgements. Never log
     * packets.
     */
    class Packet(val packet: JSONObject) : NetworkEvent

    data class InfinityStarted(val isPublic: Boolean) : NetworkEvent

    data class Latency(val milliseconds: Double) : NetworkEvent

    data class Reconnecting(val attempt: Int) : NetworkEvent

    data class Error(
        val message: String,
        val code: String? = null,
        val seat: Int? = null,
        val terminal: Boolean = false,
    ) : NetworkEvent

    data class Disconnected(val message: String?) : NetworkEvent
}

internal fun JSONObject.stringOrNull(key: String): String? =
    if (isNull(key)) null else optString(key).takeIf(String::isNotEmpty)

internal fun JSONObject.intOrNull(key: String): Int? = if (isNull(key)) null else optInt(key)

internal fun JSONObject.longOrNull(key: String): Long? = if (isNull(key)) null else optLong(key)

/** Private rooms identify renamed P2 by its seat ID; Infinity includes an explicit seat. */
internal fun JSONObject.renamedSeat(primary: Int, secondary: Int?): Int? {
    if (has("seat"))
        return optInt("seat", -1).takeIf { it in 0..1 && (it == 0 || secondary != null) }
    if (has("id"))
        return when (optInt("id", -1)) {
            primary -> 0
            secondary -> 1
            else -> null
        }
    return 0
}
