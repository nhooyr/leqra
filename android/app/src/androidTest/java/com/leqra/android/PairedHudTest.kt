package com.leqra.android

import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.text.StaticLayout
import android.view.View
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.leqra.core.ArenaSnapshot
import com.leqra.core.ArenaTank
import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PairedHudTest {
    @Test
    fun splitReadoutsKeepEachSeatWithItsOwnLoadout() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val state =
                ArenaSnapshot(
                    phase = "playing",
                    tanks =
                        listOf(
                            ArenaTank(
                                id = 1,
                                name = "Rust",
                                power = "cannon",
                                powerTime = 15.0,
                                charges = 3,
                            ),
                            ArenaTank(
                                id = 2,
                                name = "Vapor",
                                power = "rapid",
                                powerTime = 15.0,
                                machineRounds = 125,
                            ),
                        ),
                )
            for (seat in 0..1) {
                val hud = NativeHudView(instrumentation.targetContext)
                hud.update(state, 1, 2, true, false, false, onlySeat = seat)
                val description = hud.contentDescription.toString()
                if (seat == 0) {
                    assertTrue(description.contains("Rust (P1)"))
                    assertTrue(description.contains("CANNON"))
                    assertFalse(description.contains("Vapor"))
                } else {
                    assertTrue(description.contains("Vapor (P2)"))
                    assertTrue(description.contains("MACHINE GUN"))
                    assertFalse(description.contains("Rust"))
                }
            }
        }
    }

    @Test
    fun bothPilotsKeepWrappedNamesEquipmentAndReadableType() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val p1 = "ABCDEFGHIJKLMNOP"
            val p2 = "Wide界界界界界界界界界界界界"
            val state =
                ArenaSnapshot(
                    phase = "playing",
                    tanks =
                        listOf(
                            ArenaTank(
                                id = 1,
                                name = p1,
                                colorIndex = 0,
                                power = "rapid",
                                powerTime = 15.0,
                                machineRounds = 125,
                                shield = 10.0,
                                shieldCharges = 5,
                                speedTime = 15.0,
                                speedStacks = 5,
                                ghostTime = 10.0,
                            ),
                            ArenaTank(
                                id = 2,
                                name = p2,
                                colorIndex = 1,
                                power = "cannon",
                                powerTime = 15.0,
                                charges = 3,
                                shield = 10.0,
                                shieldCharges = 5,
                                speedTime = 15.0,
                                speedStacks = 5,
                                starmanTime = 10.0,
                            ),
                        ),
                )
            val output = File(instrumentation.targetContext.cacheDir, "p2-hud").apply { mkdirs() }
            for (scale in listOf(1f, 1.5f)) for ((widthDp, compact) in
                listOf(360 to false, 640 to true, 800 to false, 1280 to true)) {
                val config =
                    Configuration(instrumentation.targetContext.resources.configuration).apply {
                        fontScale = scale
                    }
                val context = instrumentation.targetContext.createConfigurationContext(config)
                val hud = NativeHudView(context).apply { this.compact = compact }
                val width = (widthDp * context.resources.displayMetrics.density).toInt()
                hud.update(
                    ArenaSnapshot(
                        phase = "playing",
                        tanks = listOf(ArenaTank(id = 1, name = p1), ArenaTank(id = 2, name = p2)),
                    ),
                    1,
                    2,
                    true,
                    false,
                    false,
                )
                hud.measure(
                    View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
                )
                hud.layout(0, 0, width, hud.measuredHeight)
                hud.update(state, 1, 2, true, false, false)
                assertTrue("New equipment can grow its wrapped layout", hud.isLayoutRequested)
                hud.measure(
                    View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
                )
                hud.layout(0, 0, width, hud.measuredHeight)
                val bitmap = Bitmap.createBitmap(width, hud.measuredHeight, Bitmap.Config.ARGB_8888)
                try {
                    hud.draw(Canvas(bitmap))
                    val description = hud.contentDescription.toString()
                    assertTrue(description.contains("$p1 (P1)"))
                    assertTrue(description.contains("$p2 (P2)"))
                    assertTrue(description.contains("MACHINE GUN"))
                    assertTrue(description.contains("CANNON"))
                    assertTrue(description.contains("SHD"))
                    assertTrue(description.contains("ammunition slots"))
                    val slots =
                        NativeHudView::class.java.getDeclaredField("slots").run {
                            isAccessible = true
                            get(hud) as List<*>
                        }
                    for (slot in slots) for (name in
                        listOf("identity", "weapon", "buffs", "readiness", "ammunition")) {
                        val block =
                            slot!!.javaClass.getDeclaredField(name).run {
                                isAccessible = true
                                get(slot)
                            }
                        val layout =
                            block.javaClass.getDeclaredField("layout").run {
                                isAccessible = true
                                get(block) as? StaticLayout
                            } ?: continue
                        assertTrue(
                            "$name has readable type",
                            layout.paint.textSize * context.resources.displayMetrics.density >= 10,
                        )
                        assertEquals(
                            "$name is not truncated",
                            layout.text.length,
                            layout.getLineEnd(layout.lineCount - 1),
                        )
                        if (compact && name in listOf("buffs", "readiness")) {
                            val secondY =
                                NativeHudView::class.java.getDeclaredField("compactSecondY").run {
                                    isAccessible = true
                                    getFloat(hud)
                                }
                            assertTrue(
                                "$name clears bottom edge at $widthDp dp, scale $scale",
                                secondY + layout.height <=
                                    hud.height / context.resources.displayMetrics.density - 5f,
                            )
                        }
                    }
                    File(output, "$widthDp-$compact-$scale.png").outputStream().use {
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                    }
                } finally {
                    bitmap.recycle()
                }
            }
        }
    }
}
