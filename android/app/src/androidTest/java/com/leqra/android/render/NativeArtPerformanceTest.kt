package com.leqra.android.render

import android.os.Debug
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.leqra.core.PracticeArena
import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Measures the first draw's raster work separately from already cached artwork. */
@RunWith(AndroidJUnit4::class)
class NativeArtPerformanceTest {
    @Test
    fun preparedArtworkMatchesEveryLazyPixelAndNeverRasterizesOnFirstUse() {
        val prepared = NativeArt()
        assertTrue(prepared.prepare())
        val before = prepared.bitmapCount
        for (color in 0..7) {
            val lazy = NativeArt()
            for (phase in 0..3) assertTrue(
                "Hull $color/$phase pixels",
                lazy.hull(color, phase).sameAs(prepared.hull(color, phase)),
            )
            assertTrue("Barrel $color pixels", lazy.barrel(color).sameAs(prepared.barrel(color)))
            assertTrue("Turret $color pixels", lazy.turret(color).sameAs(prepared.turret(color)))
        }
        for (kind in PracticeArena.pickupKinds) {
            val lazy = NativeArt()
            assertTrue("$kind pickup pixels", lazy.pickup(kind).sameAs(prepared.pickup(kind)))
            assertTrue("$kind badge pixels", lazy.badge(kind).sameAs(prepared.badge(kind)))
        }
        val lazy = NativeArt()
        assertTrue(lazy.wreck().sameAs(prepared.wreck()))
        assertTrue(lazy.stickBase().sameAs(prepared.stickBase()))
        assertTrue(lazy.stickKnob().sameAs(prepared.stickKnob()))
        for (held in listOf(false, true)) for (detonate in listOf(false, true)) assertTrue(
            lazy.fireButton(held, detonate).sameAs(prepared.fireButton(held, detonate)),
        )
        assertEquals("All first-use bitmap work is already complete", before, prepared.bitmapCount)
        assertEquals(75, before)
        val reports = ArrayList<String>()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            for (kind in PracticeArena.pickupKinds) {
                val samples = LongArray(20)
                repeat(samples.size) { index ->
                    val start = Debug.threadCpuTimeNanos()
                    prepared.pickup(kind)
                    prepared.badge(kind)
                    prepared.hull(index % 8, index % 4)
                    prepared.barrel(index % 8)
                    prepared.turret(index % 8)
                    samples[index] = Debug.threadCpuTimeNanos() - start
                }
                samples.sort()
                reports += "$kind preparedCpuMs p50=${samples[10]/1e6} p95=${samples[19]/1e6}"
            }
        }
        assertEquals(before, prepared.bitmapCount)
        File(instrumentation.targetContext.cacheDir, "native-art-prepared.txt")
            .writeText(
                "bitmapCount=$before; all lazy/prepared pixels identical\n" +
                    reports.joinToString("\n", postfix = "\n"),
            )
        prepared.clear()
        lazy.clear()
    }

    @Test
    fun firstPickupAndTankArtworkReportsColdAndCachedCosts() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val reports = ArrayList<String>()
        instrumentation.runOnMainSync {
            for (kind in PracticeArena.pickupKinds) {
                val cold = LongArray(20)
                val warm = LongArray(20)
                repeat(cold.size) { index ->
                    val art = NativeArt()
                    var start = Debug.threadCpuTimeNanos()
                    val pickup = art.pickup(kind)
                    val badge = art.badge(kind)
                    art.hull(index % 8, index % 4)
                    art.barrel(index % 8)
                    art.turret(index % 8)
                    cold[index] = Debug.threadCpuTimeNanos() - start
                    start = Debug.threadCpuTimeNanos()
                    assertSame(pickup, art.pickup(kind))
                    assertSame(badge, art.badge(kind))
                    art.hull(index % 8, index % 4)
                    art.barrel(index % 8)
                    art.turret(index % 8)
                    warm[index] = Debug.threadCpuTimeNanos() - start
                    art.clear()
                }
                cold.sort()
                warm.sort()
                reports +=
                    "$kind coldCpuMs p50=${cold[10]/1e6} p95=${cold[19]/1e6}; cachedCpuMs p50=${warm[10]/1e6} p95=${warm[19]/1e6}"
            }
        }
        File(instrumentation.targetContext.cacheDir, "native-art-first-use.txt")
            .writeText(reports.joinToString("\n", postfix = "\n"))
    }
}
