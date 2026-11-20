package com.leqra.core

import java.security.MessageDigest
import org.junit.Assert.assertEquals
import org.junit.Test

class CallsignCaseFoldTest {
    @Test
    fun everyUnicodeScalarMatchesTheGoGeneratedFixture() {
        val digest = MessageDigest.getInstance("SHA-256")
        val pair = ByteArray(8)
        for (point in 0..0x10ffff) {
            if (point in 0xd800..0xdfff) continue
            val folded = CallsignCaseFold.fold(String(Character.toChars(point))).codePointAt(0)
            for (offset in 0..3) {
                pair[offset] = (point ushr (24 - offset * 8)).toByte()
                pair[offset + 4] = (folded ushr (24 - offset * 8)).toByte()
            }
            digest.update(pair)
        }
        // scalarSHA256 in src/tests/fixtures/callsign-fold.json; generated from Go's
        // complete scalar mapping, independently of this Kotlin lookup implementation.
        assertEquals(
            "9f7a70a69a10727f79cff9a16879a85220f0416e129aea1b218f2ce69a78f907",
            digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) },
        )
    }
}
