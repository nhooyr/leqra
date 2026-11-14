package com.leqra.core

import org.junit.Assert.*
import org.junit.Test

class ProjectileFlightPresentationTest {
    private fun effect(
        kind: String = "cannon",
        start: Double = 0.0,
        end: Double = 6.0,
        id: Int = 1,
    ) =
        ArenaEffect(
            id = id,
            kind =
                if (kind == "grenade") "blast"
                else if (kind == "cannon" || kind == "homing") "impact" else "projectileFlight",
            flight =
                ProjectileFlight(
                    id,
                    0,
                    2,
                    start,
                    end,
                    listOf(
                        ProjectileFlightPoint(0.0, 42.0, start),
                        ProjectileFlightPoint(100.0, 42.0, end),
                    ),
                    kind,
                    if (kind == "cannon") 18.0 else 4.5,
                ),
        )

    @Test
    fun allBallisticsMissedBetweenSnapshotsAreVisibleAndReleaseTheImpactAtTheEndpoint() {
        for (kind in listOf("regular", "rapid", "scatter", "homing", "grenade", "cannon")) {
            val cache = ProjectileFlightPresentation()
            val hit = effect(kind)
            cache.accept(listOf(hit), 0.0)
            val first = cache.render(emptyList(), listOf(hit), .025)
            assertEquals(kind, first.bullets.single().kind)
            assertEquals(25.0, first.bullets.single().x, 1e-9)
            assertTrue(first.effects.isEmpty())
            val second = cache.render(emptyList(), listOf(hit), .075)
            assertEquals(75.0, second.bullets.single().x, 1e-9)
            val end = cache.render(emptyList(), emptyList(), .11)
            assertTrue(end.bullets.isEmpty())
            assertEquals(listOf(hit), end.effects)
            assertTrue(cache.render(emptyList(), emptyList(), .12).effects.isEmpty())
        }
    }

    @Test
    fun shortAndAlreadyPassedFlightsGetBoundedGraceWithoutOvershootOrDuplicateBodies() {
        for (arrival in listOf(0.0, .05, .2, .4)) {
            val cache = ProjectileFlightPresentation()
            val hit = effect(end = .2)
            cache.accept(listOf(hit), arrival)
            val initial =
                cache.render(
                    listOf(ArenaBullet(id = 1, kind = "cannon", x = -100.0)),
                    listOf(hit),
                    arrival,
                )
            assertEquals(1, initial.bullets.size)
            assertEquals(0.0, initial.bullets.single().x, 1e-9)
            val middle = cache.render(emptyList(), emptyList(), arrival + .025)
            assertEquals(50.0, middle.bullets.single().x, 1e-7)
            val finished =
                cache.render(
                    listOf(ArenaBullet(id = 1, kind = "cannon")),
                    emptyList(),
                    arrival + .06,
                )
            assertTrue(finished.bullets.isEmpty())
            assertEquals(listOf(hit), finished.effects)
            assertTrue(
                cache
                    .render(
                        listOf(ArenaBullet(id = 1, kind = "cannon")),
                        emptyList(),
                        arrival + .08,
                    )
                    .bullets
                    .isEmpty()
            )
            cache.accept(listOf(hit), arrival + .1)
            assertTrue(cache.render(emptyList(), emptyList(), arrival + .1).bullets.isEmpty())
        }
    }

    @Test
    fun baselineRecoveryInvalidPathsAndObservedCompletedFlightsNeverReplay() {
        val cache = ProjectileFlightPresentation()
        val hit = effect()
        cache.reset(listOf(hit))
        cache.accept(listOf(hit), .4)
        assertTrue(cache.render(emptyList(), emptyList(), .4).bullets.isEmpty())
        cache.reset()
        cache.render(listOf(ArenaBullet(id = 1, kind = "cannon")), emptyList(), 0.0)
        cache.accept(listOf(hit), .4)
        assertTrue(cache.render(emptyList(), listOf(hit), .4).bullets.isEmpty())
        assertEquals(listOf(hit), cache.render(emptyList(), listOf(hit), .4).effects)
        cache.reset()
        val invalid =
            hit.copy(
                id = 2,
                flight =
                    hit.flight!!.copy(
                        points =
                            listOf(
                                ProjectileFlightPoint(Double.NaN, 1.0, 0.0),
                                ProjectileFlightPoint(1.0, 1.0, 6.0),
                            )
                    ),
            )
        cache.accept(listOf(invalid), 0.0)
        assertTrue(cache.render(emptyList(), listOf(invalid), .025).bullets.isEmpty())
    }

    @Test
    fun authoritativelyRecordedRimBouncesUseTheirActualTimes() {
        val cache = ProjectileFlightPresentation()
        val hit =
            effect().let {
                it.copy(
                    flight =
                        it.flight!!.copy(
                            points =
                                listOf(
                                    ProjectileFlightPoint(0.0, 42.0, 0.0),
                                    ProjectileFlightPoint(80.0, 42.0, 2.0),
                                    ProjectileFlightPoint(0.0, 42.0, 6.0),
                                )
                        )
                )
            }
        cache.accept(listOf(hit), 0.0)
        assertEquals(
            40.0,
            cache.render(emptyList(), emptyList(), 1.0 / 60).bullets.single().x,
            1e-9,
        )
        assertEquals(
            40.0,
            cache.render(emptyList(), emptyList(), 4.0 / 60).bullets.single().x,
            1e-9,
        )
    }
}
