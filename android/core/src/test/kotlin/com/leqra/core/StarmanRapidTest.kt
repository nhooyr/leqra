package com.leqra.core

import kotlin.math.*
import org.junit.Assert.*
import org.junit.Test

class StarmanRapidTest {
    private val dt = 1.0 / 60

    private fun arena(
        star: Boolean,
        world: ArenaWorld? = ArenaWorld(2016.0, 1176.0, 24, 14),
    ): PracticeArena =
        PracticeArena(42, "Pilot", 0, 0, world = world).apply {
            PracticeArena::class
                .java
                .getDeclaredField("pickupRate")
                .apply { isAccessible = true }
                .set(this, "off")
            snapshot.tanks.single().apply {
                x = if (world == null) 42.0 else 100.0
                y = if (world == null) 42.0 else world.height / 2
                angle = 0.0
                invulnerable = 0.0
                spawnProtected = false
                if (star) PracticeArena.applyPower(this, "starman", 30.0, 30.0)
                PracticeArena.applyPower(this, "rapid", 30.0)
            }
        }

    @Test
    fun onlyTheActualMachineGunAndStarmanCombinationChangesProjectileSpeed() {
        val regular = PracticeArena.spec("rapid")
        val star = PracticeArena.spec("rapid", true)
        assertEquals(846.0, regular.speed, 0.0)
        assertEquals(1692.0, star.speed, 0.0)
        assertEquals(regular.radius, star.radius, 0.0)
        assertEquals(regular.capacity, star.capacity)
        assertEquals(regular.cooldown, star.cooldown, 0.0)
        assertEquals(2 * (regular.speed * regular.life + 28), star.speed * star.life + 28, 1e-9)
        assertSame("Cached specs do not allocate per shot", star, PracticeArena.spec("rapid", true))
        for (kind in listOf("") + PracticeArena.pickupKinds.filter { it != "rapid" }) assertSame(
            "Starman alone and other weapons retain their current tuning",
            PracticeArena.spec(kind),
            PracticeArena.spec(kind, true),
        )
    }

    @Test
    fun fixedAndInfinityKeepSixtyAccurateShotsWhileDoublingTheFullTravelBudget() {
        for (world in listOf(null, ArenaWorld(2016.0, 1176.0, 24, 14))) {
            val normal = arena(false, world)
            val star = arena(true, world)
            val seen = listOf(HashSet<Int>(), HashSet<Int>())
            for (tick in 1..60) {
                for ((index, model) in listOf(normal, star).withIndex()) {
                    model.step(GameInput(fire = true), dt)
                    val fresh = model.snapshot.bullets.filter { seen[index].add(it.id) }
                    assertEquals("Exactly one rapid round per physics tick", 1, fresh.size)
                    val bullet = fresh.single()
                    val speed = hypot(bullet.vx, bullet.vy)
                    assertEquals(if (index == 0) 846.0 else 1692.0, speed, 1e-7)
                    val normalBudget =
                        if (world == null) 18 * 84.0 + 28 else (world.width + world.height) / 2
                    val totalBudget = if (index == 0) normalBudget else normalBudget * 2
                    assertEquals(
                        "Double the total range includes the unchanged muzzle travel exactly once",
                        totalBudget,
                        (bullet.life + dt) * speed + 28,
                        1e-6,
                    )
                    if (world != null) {
                        assertEquals("Zero spread", 0.0, bullet.vy, 0.0)
                        assertEquals(100.0 + 28 + speed * dt, bullet.x, 1e-7)
                    }
                }
            }
            assertEquals(60, seen[0].size)
            assertEquals(60, seen[1].size)
            assertEquals(120, normal.snapshot.tanks.single().machineRounds)
            assertEquals(180, star.snapshot.tanks.single().machineRounds)
        }
    }

    @Test
    fun fixedRapidRangeSubtractsTheActualHiddenLaunchPathInsideAWall() {
        val world =
            ArenaWorld(1008.0, 672.0, 12, 8, listOf(MazeWall(148.0, 0.0, 32.0, 672.0, "v", 164.0)))
        val model = arena(true, world)
        val tank =
            model.snapshot.tanks.single().apply {
                x = 175.8
                y = 210.0
                angle = 0.0
            }
        val launch =
            model.maze.launchRay(
                tank.x,
                tank.y,
                tank.angle,
                "rapid",
                PracticeArena.spec("rapid").radius,
            )!!
        assertTrue(
            "This clear-face relocation is longer than the usual muzzle path",
            launch.distance > 28,
        )
        val hidden = launch.distance + max(0.0, 28 - launch.distance)
        model.step(GameInput(fire = true), dt)
        val bullet = model.snapshot.bullets.single()
        assertEquals(
            "The full doubled map budget includes the actual relocation",
            world.width + world.height,
            hidden + (bullet.life + dt) * hypot(bullet.vx, bullet.vy),
            1e-6,
        )
    }

    @Test
    fun projectilesKeepTheirBirthVelocityAcrossPickupsAndStarmanExpiry() {
        val model = arena(false)
        val tank = model.snapshot.tanks.single()
        model.step(GameInput(fire = true), dt)
        val ordinary = model.snapshot.bullets.single().id
        PracticeArena.applyPower(tank, "starman")
        model.step(GameInput(fire = true), dt)
        val fast = model.snapshot.bullets.last().id
        assertEquals(846.0, model.snapshot.bullets.first { it.id == ordinary }.vx, 0.0)
        assertEquals(1692.0, model.snapshot.bullets.first { it.id == fast }.vx, 0.0)
        PracticeArena.applyPower(tank, "shield")
        tank.starmanTime = dt / 2
        model.step(GameInput(fire = true), dt)
        assertEquals(0.0, tank.starmanTime, 0.0)
        assertEquals(846.0, model.snapshot.bullets.first { it.id == ordinary }.vx, 0.0)
        assertEquals(1692.0, model.snapshot.bullets.first { it.id == fast }.vx, 0.0)
        assertEquals(
            "The first post-Star round returns to normal speed",
            846.0,
            model.snapshot.bullets.last().vx,
            0.0,
        )
    }

    @Test
    fun doubledSpeedAndRangeKeepTheNaturalLifetimeAndOriginalProjectileCap() {
        for (world in listOf(null, ArenaWorld(2016.0, 1176.0, 24, 14))) {
            fun lifetime(star: Boolean): Int {
                val model = arena(star, world)
                model.step(GameInput(fire = true), dt)
                val id = model.snapshot.bullets.single().id
                var ticks = 1
                while (model.snapshot.bullets.any { it.id == id } && ticks < 200) {
                    model.step(GameInput(), dt)
                    ticks++
                }
                assertTrue(ticks < 200)
                return ticks
            }
            val normal = lifetime(false)
            val fast = lifetime(true)
            assertEquals(
                "The extra doubled muzzle allowance is at most one physics tick",
                normal.toDouble(),
                fast.toDouble(),
                1.0,
            )
        }
    }

    @Test
    fun everyFixedMapAndInfinityFitTheOriginalCapWithoutPrematureRecycling() {
        val worlds =
            listOf(null) +
                listOf(7 to 7, 9 to 7, 12 to 10, 14 to 12, 16 to 14, 24 to 14).map { (cols, rows) ->
                    ArenaWorld(cols * 84.0, rows * 84.0, cols, rows)
                }
        for (world in worlds) {
            val model = arena(true, world)
            val births = HashSet<Int>()
            repeat(180) {
                val before = model.snapshot.bullets.associate { it.id to it.life }
                model.step(GameInput(fire = true), dt)
                val live = model.snapshot.bullets.map { it.id }.toSet()
                for ((id, life) in before) if (id !in live)
                    assertTrue(
                        "The115 cap must not truncate a naturally valid boosted round",
                        life <= dt + 1e-9,
                    )
                assertEquals(1, model.snapshot.bullets.count { births.add(it.id) })
                assertTrue(model.snapshot.bullets.size <= 115)
            }
            assertEquals(180, births.size)
        }
    }

    @Test
    fun onlineFastRicochetsKeepTheirActualVelocityAndTheThinWallContact() {
        val world = ArenaWorld(300.0, 200.0, walls = listOf(MazeWall(100.0, 0.0, 8.0, 200.0)))
        val maze = InfiniteMaze(world)
        val radius = PracticeArena.spec("rapid").radius
        val contact = 100 - radius
        val duration = 1.0 / 30
        val first = ArenaBullet(id = 1, kind = "rapid", x = 80.0, y = 50.0, vx = 1692.0, life = 1.8)
        val second =
            first.copy(
                x = contact - .08 - (1692 * duration - (contact - first.x)),
                vx = -1692.0,
                bounces = 1,
                life = first.life - duration,
            )
        val path = RicochetPath.between(first, second, duration, maze)!!
        val before = path.sample(second, first, .1)
        val after = path.sample(second, first, .8)
        assertEquals(1692.0, before.vx, 0.0)
        assertEquals(-1692.0, after.vx, 0.0)
        assertTrue(before.x > first.x)
        assertTrue(after.x > second.x)
        assertTrue(listOf(before, after).all { it.x <= contact })
        val timeline = OnlinePresentation(localID = 99, maze = maze)
        timeline.accept(ArenaSnapshot(tick = 0, world = world, bullets = listOf(first)), 0.0)
        timeline.accept(ArenaSnapshot(tick = 2, world = world, bullets = listOf(second)), duration)
        val image = timeline.render(.1, GameInput(), .1) {}!!.bullets.single()
        assertEquals(1692.0, abs(image.vx), 0.0)
        assertTrue(image.x <= contact)
    }

    @Test
    fun fastRicochetsUseSweptThinHitboxesAndExactContactPresentation() {
        val world =
            ArenaWorld(1008.0, 672.0, 12, 8, listOf(MazeWall(248.0, 0.0, 8.0, 672.0, "v", 252.0)))
        fun shot(star: Boolean): ProjectileFlight {
            val model = arena(star, world)
            model.configureLocal("Target", 1)
            model.snapshot.tanks.first().apply {
                x = 150.0
                y = 210.0
            }
            model.snapshot.tanks.last().apply {
                x = 70.0
                y = 210.0
                invulnerable = 0.0
                spawnProtected = false
            }
            model.step(GameInput(fire = true), dt)
            var bounced = false
            repeat(40) {
                bounced = bounced || model.snapshot.bullets.any { it.bounces > 0 }
                if (model.snapshot.tanks.last().hp > 0) model.step(GameInput(), dt)
            }
            assertTrue("The shot must ricochet before reaching the target", bounced)
            assertEquals(0, model.snapshot.tanks.last().hp)
            // Retained effects last150ms; find the exact flight on the hit tick instead.
            return model.snapshot.effects.firstOrNull { it.flight != null }?.flight
                ?: error("Missing retained flight")
        }
        val normal = shot(false)
        val fast = shot(true)
        assertEquals(normal.radius, fast.radius, 0.0)
        assertEquals(70 + 17 + 3.5 / 3, fast.points.last().x, 1e-6)
        assertEquals(210.0, fast.points.last().y, 1e-6)
        assertEquals(normal.endTick / 2, fast.endTick, .001)
    }

    @Test
    fun aSubTickFastContactStillDrawsTheProjectileAtTheLivingHullBeforeItsHit() {
        val radius = PracticeArena.spec("rapid", true).radius
        val endpoint = 180 - 17 - radius
        val endTick = (endpoint - 140) / 1692 * 60
        val path =
            ProjectileFlight(
                7,
                1,
                0,
                0.0,
                endTick,
                listOf(
                    ProjectileFlightPoint(140.0, 42.0, 0.0),
                    ProjectileFlightPoint(endpoint, 42.0, endTick),
                ),
                "rapid",
                radius,
            )
        val effects =
            listOf(
                ArenaEffect(id = 1, kind = "projectileFlight", flight = path),
                ArenaEffect(
                    id = 2,
                    kind = "hit",
                    owner = 1,
                    contact =
                        CombatContact(
                            7,
                            "rapid",
                            endTick,
                            2,
                            1,
                            ContactTankState(180.0, 42.0, 0.0),
                        ),
                ),
            )
        val tank = ArenaTank(id = 2, x = 180.0, y = 42.0, hp = 0, spawnSerial = 1)
        val flights = ProjectileFlightPresentation()
        val contacts = CombatContactPresentation()
        flights.accept(effects, 0.0)
        contacts.accept(effects, listOf(tank), 0.0, 1.0)
        fun draw(
            now: Double,
        ): Pair<ProjectileFlightPresentation.Image, CombatContactPresentation.Image> {
            val image = flights.render(emptyList(), effects, now, contacts::canCompleteProjectile)
            return image to contacts.render(listOf(tank), image.effects, now, flights)
        }
        assertEquals(1, draw(.04).second.tanks.single().hp)
        val (touching, alive) = draw(.05)
        assertEquals(1, alive.tanks.single().hp)
        assertEquals(endpoint, touching.bullets.single().x, 1e-9)
        assertEquals(1692.0, touching.bullets.single().vx, 1e-7)
        assertTrue(alive.effects.isEmpty())
        val (gone, dead) = draw(.06)
        assertTrue(gone.bullets.isEmpty())
        assertEquals(0, dead.tanks.single().hp)
        assertTrue(dead.effects.any { it.kind == "hit" })
    }
}
