package com.leqra.android

import java.io.File
import org.junit.Assert.*
import org.junit.Test

class BuildVersionTest {
    @Test
    fun nativeBuildConfigUsesTheVersionScriptAndServerSource() {
        val root =
            generateSequence(File(System.getProperty("user.dir"))) { it.parentFile }
                .first { File(it, "scripts/version.sh").isFile }
        val process = ProcessBuilder("sh", "scripts/version.sh").directory(root).start()
        val version = process.inputStream.bufferedReader().readText().trim()
        assertEquals(0, process.waitFor())
        assertEquals(version, BuildConfig.VERSION_NAME)
        val parts = version.split('.').map(String::toInt)
        assertEquals(parts[0] * 1000000 + parts[1] * 10000 + parts[2], BuildConfig.VERSION_CODE)
        assertTrue(
            Regex("(?m)^\\s*version\\s*=\\s*\"${Regex.escape(version)}\"")
                .containsMatchIn(File(root, "src/main.go").readText())
        )
    }
}
