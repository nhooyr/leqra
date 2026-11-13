package com.leqra.android.accounts

import com.leqra.android.network.ServerAddress
import java.security.SecureRandom
import java.util.Base64
import java.util.UUID

/** These objects deliberately omit toString(): bearer secrets must never enter logs. */
class AccountCredential(val key: String, val registrationPending: Boolean = false)

class PendingAccount(
    val id: String,
    val seat: Int,
    val key: String,
    val previousKey: String?,
    val purpose: String,
)

data class PublicIntent(
    val origin: String,
    val name: String,
    val colorIndex: Int,
    val localName: String? = null,
    val localColorIndex: Int = 1,
)

interface AccountStore {
    fun selected(origin: String, seat: Int = 0): AccountCredential?

    fun select(origin: String, seat: Int, key: String, registrationPending: Boolean = false)

    fun clearIfMatching(origin: String, seat: Int, key: String)

    fun pending(origin: String, seat: Int): List<PendingAccount>

    fun savePending(origin: String, pending: PendingAccount)

    fun removePending(origin: String, id: String)

    fun activeIntent(): PublicIntent?

    fun setActiveIntent(intent: PublicIntent?)

    /**
     * Save backup and selected credential atomically before a registration can leave the device.
     */
    fun prepareRegistration(origin: String, seat: Int): AccountCredential
}

object AccountKeys {
    private val random = SecureRandom()

    fun create(): String =
        "p_" +
            Base64.getUrlEncoder()
                .withoutPadding()
                .encodeToString(ByteArray(32).also(random::nextBytes))

    fun valid(key: String): Boolean =
        try {
            key.length == 45 &&
                key.startsWith("p_") &&
                Base64.getUrlEncoder()
                    .withoutPadding()
                    .encodeToString(Base64.getUrlDecoder().decode(key.substring(2))) ==
                    key.substring(2) &&
                Base64.getUrlDecoder().decode(key.substring(2)).size == 32
        } catch (_: IllegalArgumentException) {
            false
        }

    fun pending(
        seat: Int,
        key: String,
        previous: String? = null,
        purpose: String = "registration",
    ) = PendingAccount(UUID.randomUUID().toString(), seat, key, previous, purpose)

    fun normalizedOrigin(origin: String) = ServerAddress.origin(origin)
}
