package com.leqra.core

import java.io.File
import org.junit.Assert.*
import org.junit.Test

class ArenaTypographyTest {
    @Test
    fun identityAndDeathNoticeSizesMatchSharedZoomFixtures() {
        val root = generateSequence(File(System.getProperty("user.dir"))) { it.parentFile }
            .first { File(it, "src/tests/arena-typography-fixtures.json").isFile }
        val fixtures = Regex("\\{[^}]+}").findAll(File(root, "src/tests/arena-typography-fixtures.json").readText()).toList()
        assertTrue(fixtures.isNotEmpty())
        for (row in fixtures) {
            fun value(name: String) = Regex("\"$name\"\\s*:\\s*([^,}]+)").find(row.value)!!.groupValues[1]
            assertEquals(value("size").toDouble(), ArenaTypography.labelSize(value("zoom").toDouble(), value("infinity").toBooleanStrict(), value("fontScale").toDouble()), .0001)
        }
    }

    @Test
    fun deathNoticeUsesOnlyTheVictimsRecordedKillerAndClearsOnRespawn() {
        val tank = ArenaTank(id = 1, hp = 0, killedBy = "Missing <pilot> 雪", killedByColor = "#ff83bd")
        val notice = DeathNotice.from(tank)
        assertEquals("Killed by Missing <pilot> 雪", notice?.text)
        assertEquals("#ff83bd", notice?.color)
        assertNull(DeathNotice.from(tank.copy(hp = 1)))
        assertNull(DeathNotice.from(tank.copy(killedBy = "")))
        assertNull(DeathNotice.from(null))
    }
}
