package com.leqra.android.render

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.leqra.core.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TerrainCacheTest {
    @Test
    fun firstFrameHasWallsBeforeRasterWorkerFinishes() {
        val gate = CountDownLatch(1)
        val world =
            ArenaWorld(336.0, 336.0, 4, 4, listOf(MazeWall(80.0, 40.0, 8.0, 80.0, "v", 84.0)))
        val cache = TerrainCache(beforeRaster = { gate.await(5, TimeUnit.SECONDS) }) {}
        val image = Bitmap.createBitmap(336, 336, Bitmap.Config.ARGB_8888)
        try {
            cache.configure(InfiniteMaze(world), world)
            cache.draw(Canvas(image), 0f, 0f, 336f, 336f)
            assertEquals(
                "Walls must be visible while the texture is still pending",
                0xff35434b.toInt(),
                image.getPixel(84, 80),
            )
            assertTrue(cache.fallbackDraws > 0)
        } finally {
            gate.countDown()
            cache.release()
            image.recycle()
        }
    }

    @Test
    fun everyFiniteSizeUsesOneBoundedRasterWithoutPrefetchThrashing() {
        val image = Bitmap.createBitmap(800, 600, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(image)
        try {
            for (size in
                listOf(
                    "compact",
                    "standard",
                    "large",
                    "huge",
                    "giant",
                    "ultrawide",
                )) for (portrait in listOf(false, true)) {
                val rules =
                    RoomRules.localDefaults("elimination").apply {
                        mapSize = size
                        portraitMaze = portrait
                    }
                val arena =
                    FixedArena(
                        rules = rules,
                        name = "Cache",
                        colorIndex = 0,
                        botCount = 0,
                        seed = 137,
                    )
                val world = arena.world
                val cache = TerrainCache {}
                try {
                    cache.configure(arena.maze, world)
                    val deadline = SystemClock.elapsedRealtime() + 5000
                    while (
                        cache.tilesBuilt == 0L && SystemClock.elapsedRealtime() < deadline
                    ) SystemClock.sleep(10)
                    assertEquals(
                        "$size/$portrait should install one complete map",
                        1L,
                        cache.tilesBuilt,
                    )
                    assertTrue(
                        "Finite artwork stays within iOS's 5MP budget",
                        cache.cachedBytes <= 20_050_000,
                    )
                    repeat(20) {
                        cache.draw(canvas, 0f, 0f, world.width.toFloat(), world.height.toFloat())
                    }
                    assertEquals("No recurring tile builds for large maps", 1L, cache.tilesBuilt)
                    assertEquals(0, cache.pendingRasters)
                } finally {
                    cache.release()
                }
            }
        } finally {
            image.recycle()
        }
    }
}
