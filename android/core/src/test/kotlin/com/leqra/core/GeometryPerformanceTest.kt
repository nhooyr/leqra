package com.leqra.core

import org.junit.Assume.assumeTrue
import org.junit.Test

/** Opt-in JVM CPU evidence, not a physical Android frame-rate claim. */
class GeometryPerformanceTest {
    @Test
    fun reportGeometryWorkloads() {
        assumeTrue(System.getenv("LEQRA_PROFILE_GEOMETRY") == "1")
        val fixed =
            InfiniteMaze(
                FixedArena(RoomRules(mapSize = "ultrawide"), "PERF", 0, 0, seed = 42).world,
            )
        for ((name, maze) in listOf("fixed" to fixed, "infinity" to InfiniteMaze(42))) {
            val queries =
                Array(1024) { index ->
                    doubleArrayOf(
                        42 + index % 21 * 83.25,
                        42 + index % 11 * 83.5,
                        (index % 19 - 9) * 15.25,
                        (index % 17 - 8) * 13.75,
                    )
                }
            for (operation in listOf("ray", "launch", "muzzle")) {
                val samples = ArrayList<Double>()
                var checksum = 0L
                repeat(9) { sample ->
                    val start = System.nanoTime()
                    repeat(16384) { index ->
                        val q = queries[index % queries.size]
                        val value =
                            when (operation) {
                                "ray" -> maze.rayHit(q[0], q[1], q[2], q[3], 3.5)?.fraction ?: -1.0
                                "launch" ->
                                    maze.launchRay(q[0], q[1], q[2] / 40, "regular", 3.5)?.x ?: -1.0
                                else ->
                                    MuzzlePresentation.retraction(
                                        ArenaTank(
                                            id = 1,
                                            x = q[0],
                                            y = q[1],
                                            angle = q[2] / 40,
                                            ghostTime = 10.0,
                                        ),
                                        maze,
                                    )
                            }
                        checksum = checksum * 31 + java.lang.Double.doubleToRawLongBits(value)
                    }
                    if (sample >= 2) samples.add((System.nanoTime() - start).toDouble() / 16384)
                }
                samples.sort()
                println(
                    "GEOMETRY $name $operation ns/query p50=${samples[3]} p95=${samples[6]} checksum=${java.lang.Long.toUnsignedString(checksum)}",
                )
            }
        }
        val samples = ArrayList<Double>()
        var checksum = 0
        repeat(9) { sample ->
            val maze = InfiniteMaze(42)
            val start = System.nanoTime()
            repeat(1024) { index ->
                checksum += maze.walls(index * 672.0, 0.0, index * 672.0 + 84, 84.0).size
            }
            if (sample >= 2) samples.add((System.nanoTime() - start).toDouble() / 1024)
        }
        samples.sort()
        println(
            "GEOMETRY cold-chunks ns/query p50=${samples[3]} p95=${samples[6]} checksum=$checksum",
        )
    }
}
