package com.leqra.android.accounts

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONArray
import org.json.JSONObject

/**
 * Device-only AES/GCM key; encrypted AtomicFile lives in noBackupFilesDir. Writes fsync before
 * returning.
 */
class EncryptedAccountStore(context: Context) : AccountStore {
    private val file = AtomicFile(File(context.noBackupFilesDir, "accounts.v1"))
    private val key: SecretKey =
        KeyStore.getInstance("AndroidKeyStore").run {
            load(null)
            (getKey(ALIAS, null) as? SecretKey)
                ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
                    .run {
                        init(
                            KeyGenParameterSpec.Builder(
                                    ALIAS,
                                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                                )
                                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                                .setRandomizedEncryptionRequired(true)
                                .build(),
                        )
                        generateKey()
                    }
        }
    // Authentication/decryption failures are surfaced. Never silently overwrite recoverable
    // credentials.
    private var state: JSONObject =
        if (file.baseFile.exists() || File(file.baseFile.path + ".bak").exists()) {
            val bytes = file.openRead().use { it.readBytes() }
            require(bytes.size in 29..1_048_576 && bytes[0] == 1.toByte()) {
                "Account storage cannot be read."
            }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, bytes.copyOfRange(1, 13)))
            cipher.updateAAD("leqra accounts v1".toByteArray(Charsets.UTF_8))
            JSONObject(String(cipher.doFinal(bytes.copyOfRange(13, bytes.size)), Charsets.UTF_8))
        } else JSONObject().put("origins", JSONObject())

    @Synchronized
    private fun <T> mutate(block: (JSONObject) -> T): T {
        val next = JSONObject(state.toString())
        val result = block(next)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        cipher.updateAAD("leqra accounts v1".toByteArray(Charsets.UTF_8))
        val encrypted =
            byteArrayOf(1) + cipher.iv + cipher.doFinal(next.toString().toByteArray(Charsets.UTF_8))
        check(encrypted.size <= 1_048_576) {
            "Account backup storage is full. Save and review pending account keys before creating another."
        }
        val output = file.startWrite()
        try {
            output.write(encrypted)
            file.finishWrite(output)
        } catch (error: Exception) {
            file.failWrite(output)
            throw error
        }
        state = next
        return result
    }

    private fun origin(state: JSONObject, value: String): JSONObject {
        val origins =
            state.optJSONObject("origins") ?: JSONObject().also { state.put("origins", it) }
        val name = AccountKeys.normalizedOrigin(value)
        return origins.optJSONObject(name) ?: JSONObject().also { origins.put(name, it) }
    }

    @Synchronized
    override fun selected(origin: String, seat: Int): AccountCredential? {
        require(seat in 0..1)
        val row = origin(state, origin).optJSONObject("seat$seat") ?: return null
        val token = row.optString("key")
        check(AccountKeys.valid(token)) { "Saved account key is invalid." }
        return AccountCredential(token, row.optBoolean("fresh"))
    }

    override fun select(origin: String, seat: Int, key: String, registrationPending: Boolean) =
        mutate { next ->
            require(seat in 0..1 && AccountKeys.valid(key))
            val root = origin(next, origin)
            require(root.optJSONObject("seat${1 - seat}")?.optString("key") != key) {
                "P1 and P2 need independent account keys."
            }
            root.put("seat$seat", JSONObject().put("key", key).put("fresh", registrationPending))
            Unit
        }

    override fun clearIfMatching(origin: String, seat: Int, key: String) = mutate { next ->
        val root = origin(next, origin)
        if (root.optJSONObject("seat$seat")?.optString("key") == key) root.remove("seat$seat")
        Unit
    }

    @Synchronized
    override fun pending(origin: String, seat: Int): List<PendingAccount> {
        val rows = origin(state, origin).optJSONArray("pending") ?: return emptyList()
        return (0 until rows.length())
            .map { rows.getJSONObject(it) }
            .filter { it.getInt("seat") == seat }
            .map {
                PendingAccount(
                    it.getString("id"),
                    seat,
                    it.getString("key"),
                    it.optString("previous").takeIf(String::isNotEmpty),
                    it.getString("purpose"),
                )
            }
    }

    private fun append(root: JSONObject, item: PendingAccount) {
        require(
            item.seat in 0..1 &&
                AccountKeys.valid(item.key) &&
                (item.previousKey == null || AccountKeys.valid(item.previousKey)),
        )
        val rows = root.optJSONArray("pending") ?: JSONArray().also { root.put("pending", it) }
        for (i in 0 until rows.length()) if (rows.getJSONObject(i).getString("id") == item.id)
            return
        rows.put(
            JSONObject()
                .put("id", item.id)
                .put("seat", item.seat)
                .put("key", item.key)
                .put("previous", item.previousKey)
                .put("purpose", item.purpose),
        )
    }

    override fun savePending(origin: String, pending: PendingAccount) = mutate {
        append(origin(it, origin), pending)
    }

    override fun removePending(origin: String, id: String) = mutate { next ->
        val root = origin(next, origin)
        val rows = root.optJSONArray("pending") ?: JSONArray()
        root.put(
            "pending",
            JSONArray(
                (0 until rows.length())
                    .map { rows.getJSONObject(it) }
                    .filter { it.getString("id") != id },
            ),
        )
        Unit
    }

    override fun prepareRegistration(origin: String, seat: Int): AccountCredential =
        mutate { next ->
            require(seat in 0..1)
            val root = origin(next, origin)
            root.optJSONObject("seat$seat")?.let {
                return@mutate AccountCredential(it.getString("key"), it.optBoolean("fresh"))
            }
            val token = AccountKeys.create()
            append(root, AccountKeys.pending(seat, token))
            root.put("seat$seat", JSONObject().put("key", token).put("fresh", true))
            AccountCredential(token, true)
        }

    @Synchronized
    override fun activeIntent(): PublicIntent? =
        state.optJSONObject("active")?.let {
            PublicIntent(
                it.getString("origin"),
                it.getString("name"),
                it.getInt("color"),
                it.optString("localName").takeIf(String::isNotEmpty),
                it.optInt("localColor", 1),
            )
        }

    override fun setActiveIntent(intent: PublicIntent?) = mutate { next ->
        if (intent == null) next.remove("active")
        else
            next.put(
                "active",
                JSONObject()
                    .put("origin", AccountKeys.normalizedOrigin(intent.origin))
                    .put("name", intent.name)
                    .put("color", intent.colorIndex)
                    .put("localName", intent.localName)
                    .put("localColor", intent.localColorIndex),
            )
        Unit
    }

    companion object {
        private const val ALIAS = "leqra.accounts.v1"
    }
}
