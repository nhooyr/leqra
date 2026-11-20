package com.leqra.android

import com.leqra.core.ArenaSnapshot
import com.leqra.core.ArenaTank
import com.leqra.core.ArenaWorld
import com.leqra.core.GameInput
import com.leqra.core.MazeWall
import com.leqra.core.PracticeArena
import com.leqra.core.RoomRules
import kotlin.math.hypot
import kotlin.math.max

/** An isolated arena for the Quick Tour, with the target added for the scoring lesson. */
internal class QuickTourPractice {
    private val spawnX = 210.0
    private val spawnY = 84.0
    private val world =
        ArenaWorld(
            420.0,
            252.0,
            5,
            3,
            listOf(
                MazeWall(-4.0, -4.0, 428.0, 8.0, "h", 0.0),
                MazeWall(-4.0, 248.0, 428.0, 8.0, "h", 252.0),
                MazeWall(-4.0, -4.0, 8.0, 260.0, "v", 0.0),
                MazeWall(416.0, -4.0, 8.0, 260.0, "v", 420.0),
                MazeWall(80.0, -4.0, 8.0, 92.0, "v", 84.0),
                MazeWall(248.0, 164.0, 92.0, 8.0, "h", 168.0),
                MazeWall(-4.0, 164.0, 92.0, 8.0, "h", 168.0),
            ),
        )
    private val arena =
        PracticeArena(name = "", colorIndex = 0, botCount = 0, world = world).apply {
            configure(RoomRules(pickupRate = "off"))
            respawnsEnabled = false
        }
    private val tank =
        arena.snapshot.tanks.single().apply {
            x = spawnX
            y = spawnY
            spawnProtected = false
            invulnerable = 0.0
        }
    private var accumulator = 0.0
    private var target: ArenaTank? = null
    private var targetX = 0.0
    val maze = arena.maze
    val tankID = arena.localID
    var moved = false
        private set

    var fireLesson = false
    var fired = false
        private set

    val score
        get() = tank.score

    fun startTargetLesson() {
        arena.clearProjectiles()
        tank.cooldown = 0.0
        targetX = if (tank.x <= spawnX) 336.0 else 126.0
        target =
            ArenaTank(id = 2, x = targetX, y = spawnY, colorIndex = 1, spawnSerial = 1).also {
                arena.snapshot.tanks += it
            }
    }

    fun captureFire(firing: Boolean) {
        if (fireLesson) arena.captureFire(tankID, firing)
    }

    fun resetFire() = arena.resetFire(tankID)

    fun advance(
        input: GameInput,
        elapsed: Double,
        nowSeconds: Double = System.nanoTime() / 1e9,
    ): ArenaSnapshot {
        val step = 1.0 / 60
        accumulator += elapsed.coerceIn(0.0, .08)
        val controls = if (!fireLesson && input.fire) input.copy(fire = false) else input
        while (accumulator + 1e-9 >= step) {
            arena.step(controls, step)
            target?.apply {
                x = targetX
                y = spawnY
            }
            if (!moved) moved = hypot(tank.x - spawnX, tank.y - spawnY) >= 12.0
            if (fireLesson && !fired) fired = arena.snapshot.bullets.any { it.owner == tankID }
            accumulator = max(0.0, accumulator - step)
        }
        return arena
            .presentationSnapshot(
                accumulator / step,
                localInput = controls,
                nowSeconds = nowSeconds,
            )
            .copy(world = world)
    }
}
