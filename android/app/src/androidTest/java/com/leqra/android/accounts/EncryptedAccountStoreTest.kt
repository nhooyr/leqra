package com.leqra.android.accounts

import android.content.Context
import android.content.ContextWrapper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class EncryptedAccountStoreTest {
    @Test
    fun encryptedDurableKeysCandidatesAndIntentSurviveColdLoad() {
        val context = isolatedAccountContext()
        try {
            val origin = "https://example.test"
            val store = EncryptedAccountStore(context)
            val p1 = AccountKeys.create()
            store.select(origin, 0, p1)
            val p2 = store.prepareRegistration(origin, 1)
            assertTrue(p2.registrationPending)
            assertNotEquals(p1, p2.key)
            val replacement = AccountKeys.pending(0, AccountKeys.create(), p1, "rotation")
            store.savePending(origin, replacement)
            store.setActiveIntent(PublicIntent(origin, "Pilot", 2, "Wing", 3))
            val restored = EncryptedAccountStore(context)
            assertEquals(p1, restored.selected("https://EXAMPLE.test:443/any/path?x=1", 0)!!.key)
            assertEquals(p2.key, restored.selected(origin, 1)!!.key)
            assertEquals(p2.key, restored.pending(origin, 1).single().key)
            assertEquals(replacement.key, restored.pending(origin, 0).single().key)
            assertEquals("Wing", restored.activeIntent()!!.localName)
            assertNull(restored.selected("https://different.test", 0))
            val bytes =
                File(context.noBackupFilesDir, "accounts.v1").readBytes().toString(Charsets.UTF_8)
            assertFalse(bytes.contains(p1))
            assertFalse(bytes.contains(p2.key))
            assertFalse(bytes.contains(replacement.key))
            restored.clearIfMatching(origin, 0, AccountKeys.create())
            assertEquals(p1, restored.selected(origin, 0)!!.key)
            restored.clearIfMatching(origin, 0, p1)
            assertNull(restored.selected(origin, 0))
            assertEquals(p2.key, restored.selected(origin, 1)!!.key)
        } finally {
            context.noBackupFilesDir.deleteRecursively()
        }
    }

    @Test
    fun authenticationFailureNeverSilentlyDiscardsStoredKeys() {
        val context = isolatedAccountContext()
        try {
            EncryptedAccountStore(context).select("https://example.test", 0, AccountKeys.create())
            val file = File(context.noBackupFilesDir, "accounts.v1")
            val bytes = file.readBytes()
            bytes[bytes.lastIndex] = (bytes.last().toInt() xor 1).toByte()
            file.writeBytes(bytes)
            try {
                EncryptedAccountStore(context)
                fail("Corrupt encrypted credentials were silently discarded")
            } catch (_: java.security.GeneralSecurityException) {}
            assertArrayEquals(bytes, file.readBytes())
        } finally {
            context.noBackupFilesDir.deleteRecursively()
        }
    }

    @Test
    fun importedAccountCannotOccupyBothLocalSeats() {
        val context = isolatedAccountContext()
        try {
            val store = EncryptedAccountStore(context)
            val key = AccountKeys.create()
            store.select("https://example.test", 0, key)
            try {
                store.select("https://example.test", 1, key)
                fail("Duplicate account accepted")
            } catch (_: IllegalArgumentException) {}
            assertNull(store.selected("https://example.test", 1))
            assertEquals(
                key,
                EncryptedAccountStore(context).selected("https://example.test", 0)!!.key,
            )
        } finally {
            context.noBackupFilesDir.deleteRecursively()
        }
    }
}

fun isolatedAccountContext(): Context {
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    val folder =
        File(context.noBackupFilesDir, "account-test-" + UUID.randomUUID()).apply { mkdirs() }
    return object : ContextWrapper(context) {
        override fun getNoBackupFilesDir(): File = folder
    }
}
