package com.leqra.core

import kotlin.math.hypot
import org.junit.Assert.*
import org.junit.Test

class CombatContactPresentationTest {
    private val ballistics = listOf("regular", "rapid", "scatter", "homing", "grenade", "cannon")
    private fun body(hp: Int = 0, life: Int = 2) = ArenaTank(id = 8, x = 160.0, y = 42.0, hp = hp,
        spawnSerial = life, score = 41, power = "rapid", powerTime = 10.0, machineRounds = 179,
        speedTime = 10.0, speedStacks = 5, ghostTime = 5.0, starmanTime = 5.0)
    private fun contact(kind: String, projectile: Int = 7, shield: Boolean = false) = ArenaEffect(
        id = 2, kind = if (shield) "shield" else "hit", owner = 1, tick = 6,
        contact = CombatContact(projectile, kind, 6.0, 8, 2,
            ContactTankState(140.0, 42.0, .4, hp = 1, shield = if (shield) 3.0 else 0.0,
                shieldCharges = if (shield) 2 else 0)))
    private fun terminal(kind: String) = ArenaEffect(id = 1,
        kind = if (kind == "grenade") "blast" else "impact", tick = 6,
        flight = ProjectileFlight(7, 1, 0, 0.0, 6.0,
            listOf(ProjectileFlightPoint(40.0, 42.0, 0.0), ProjectileFlightPoint(140.0 - 17 - if (kind == "cannon") 18.0 else 4.5, 42.0, 6.0)),
            kind, if (kind == "cannon") 18.0 else 4.5))

    @Test fun retainedTerminalCapacityCoversEightStarmanShotgunActors() {
        val flights = ProjectileFlightPresentation(); val contacts = CombatContactPresentation()
        val tanks = (1..8).map { body().copy(id = it) }
        val effects = (1..864).flatMap { id ->
            val path = terminal("scatter").let { it.copy(id = id * 2, flight = it.flight!!.copy(id = id)) }
            val hit = contact("scatter").let { it.copy(id = id * 2 + 1, contact = it.contact!!.copy(projectileId = id, target = 1 + id % 8)) }
            if (id > 856) listOf(path, hit) else listOf(path)
        }
        flights.accept(effects, 0.0, tanks.size); contacts.accept(effects, tanks, 0.0, 6.0)
        val endpoint = flights.render(emptyList(), effects, .11, contacts::canCompleteProjectile)
        val intact = contacts.render(tanks, endpoint.effects, .11, flights)
        assertEquals(864, endpoint.bullets.size)
        assertTrue(intact.tanks.all { it.hp == 1 })
        assertTrue(intact.effects.isEmpty())
        val terminal = flights.render(emptyList(), effects, .12, contacts::canCompleteProjectile)
        val damaged = contacts.render(tanks, terminal.effects, .12, flights)
        assertEquals(872, damaged.effects.size)
        assertTrue(damaged.tanks.all { it.hp == 0 })
        assertFalse(contacts.hasPending)
    }

    @Test fun coalescedShieldThenKillEachDrawTheirOwnMovingVictimAtContact() {
        for (firstKind in ballistics) for (lastKind in ballistics) {
            val flights = ProjectileFlightPresentation(); val contacts = CombatContactPresentation()
            val firstPath = terminal(firstKind).let { it.copy(flight=it.flight!!.copy(startTick=0.0,endTick=1.0,
                points=listOf(ProjectileFlightPoint(40.0,42.0,0.0),ProjectileFlightPoint(140-17-it.flight!!.radius,42.0,1.0)))) }
            val firstHit=contact(firstKind,shield=true).let { it.copy(contact=it.contact!!.copy(tick=1.0)) }
            val lastPath=terminal(lastKind).let { it.copy(id=3,flight=it.flight!!.copy(id=9,startTick=21.0,endTick=22.0,
                points=listOf(ProjectileFlightPoint(140.0,42.0,21.0),ProjectileFlightPoint(200-17-it.flight!!.radius,42.0,22.0)))) }
            val lastHit=contact(lastKind,projectile=9).let { it.copy(id=4,contact=it.contact!!.copy(tick=22.0,before=it.contact!!.before.copy(x=200.0))) }
            val effects=listOf(firstPath,firstHit,lastPath,lastHit)
            flights.accept(effects,.5); contacts.accept(effects,listOf(body()),.5,30.0)
            fun render(t: Double): Pair<ProjectileFlightPresentation.Image,CombatContactPresentation.Image> {
                val image=flights.render(emptyList(),effects,t,contacts::canCompleteProjectile)
                return image to contacts.render(listOf(body()),image.effects,t,flights)
            }
            val (first,shield)=render(.56)
            assertEquals(140.0,shield.tanks.single().x,0.0)
            assertEquals(2,shield.tanks.single().shieldCharges)
            assertEquals(17+firstPath.flight!!.radius,140-first.bullets.first { it.id==7 }.x,1e-9)
            assertTrue(shield.effects.isEmpty())
            val (last,alive)=render(.57)
            assertEquals(200.0,alive.tanks.single().x,0.0)
            assertEquals(1,alive.tanks.single().hp)
            assertEquals(0,alive.tanks.single().shieldCharges)
            assertEquals(17+lastPath.flight!!.radius,200-last.bullets.single().x,1e-9)
            assertTrue(alive.effects.any { it.id==2 })
            assertFalse(alive.effects.any { it.id==4 })
            val (_,dead)=render(.58)
            assertEquals(0,dead.tanks.single().hp)
            assertTrue(dead.effects.any { it.id==4 })
        }
    }

    @Test fun retiredSameLifeVictimUsesKnownIdentityUntilContactAndUnknownTargetsStayUnknown() {
        for (known in listOf(false, true)) {
            val flights = ProjectileFlightPresentation(); val contacts = CombatContactPresentation()
            if (known) contacts.render(listOf(body(1).copy(name = "Known pilot", colorIndex = 5)), emptyList(), 0.0, flights)
            val effects = listOf(terminal("cannon"), contact("cannon"))
            flights.accept(effects, .2); contacts.accept(effects, emptyList(), .2, 12.0)
            val endpoint = flights.render(emptyList(), effects, .26)
            val intact = contacts.render(emptyList(), endpoint.effects, .26, flights)
            if (known) {
                assertEquals("Known pilot", intact.tanks.single().name)
                assertEquals(5, intact.tanks.single().colorIndex)
                assertEquals(1, intact.tanks.single().hp)
                assertEquals(140.0, intact.tanks.single().x, 0.0)
            } else assertTrue(intact.tanks.isEmpty())
            assertTrue(intact.effects.isEmpty())
            val terminal = flights.render(emptyList(), effects, .27)
            val damaged = contacts.render(emptyList(), terminal.effects, .27, flights)
            assertTrue(damaged.tanks.isEmpty())
            assertTrue(damaged.effects.any { it.id == 2 })
            contacts.reset(effects); flights.reset(effects)
            assertTrue(contacts.render(emptyList(), effects, 1.0, flights).effects.isEmpty())
        }
    }

    @Test fun everyBallisticDrawsLiveVictimAndExactContactBeforeDestructionOrHitEffects() {
        for (kind in ballistics) for (shield in listOf(false, true)) {
            val flights = ProjectileFlightPresentation(); val contacts = CombatContactPresentation()
            val authority = body(if (shield) 1 else 0)
            val hit = contact(kind, shield = shield); val effects = listOf(terminal(kind), hit)
            flights.accept(effects, 0.0); contacts.accept(effects, listOf(authority), 0.0, 6.0)
            fun render(t: Double): Pair<ProjectileFlightPresentation.Image, CombatContactPresentation.Image> {
                val f = flights.render(emptyList(), effects, t)
                return f to contacts.render(listOf(authority), f.effects, t, flights)
            }
            val (_, traveling) = render(.05)
            assertEquals("$kind victim stays visible during flight", 1, traveling.tanks.single().hp)
            assertEquals(if (shield) 2 else 0, traveling.tanks.single().shieldCharges)
            assertEquals(41, traveling.tanks.single().score)
            assertTrue(traveling.effects.isEmpty())
            val (endpoint, touching) = render(.11)
            assertEquals(1, touching.tanks.single().hp)
            assertEquals(140.0, touching.tanks.single().x, 0.0)
            assertEquals(17 + terminal(kind).flight!!.radius,
                hypot(touching.tanks.single().x - endpoint.bullets.single().x, touching.tanks.single().y - endpoint.bullets.single().y), 1e-9)
            assertTrue("No blast/shield/hit/audio event before the contact frame", touching.effects.isEmpty())
            val (gone, damaged) = render(.12)
            assertTrue(gone.bullets.isEmpty())
            assertEquals(authority.hp, damaged.tanks.single().hp)
            assertEquals(0, damaged.tanks.single().shieldCharges)
            assertEquals(setOf(1, 2), damaged.effects.map { it.id }.toSet())
            assertEquals("Authority is never held back", if (shield) 1 else 0, authority.hp)
        }
    }

    @Test fun firstSeenCorpseUsesPreContactStateAndOldLifeCannotCoverRespawn() {
        val flights = ProjectileFlightPresentation(); val contacts = CombatContactPresentation()
        val effects = listOf(terminal("cannon"), contact("cannon"))
        flights.accept(effects, .2); contacts.accept(effects, listOf(body()), .2, 12.0)
        val initial = flights.render(emptyList(), effects, .2)
        assertEquals(1, contacts.render(listOf(body()), initial.effects, .2, flights).tanks.single().hp)
        val respawn = body(1, 3).copy(x = 600.0)
        val image = contacts.render(listOf(respawn), effects, .21, flights)
        assertEquals(respawn, image.tanks.single())
        assertFalse(image.effects.any { it.id == 2 })
        contacts.reset(effects); flights.reset(effects)
        contacts.accept(effects, listOf(body()), 2.0, 120.0)
        assertFalse(contacts.hasPending)
    }

    @Test fun shieldCatchupKeepsAuthorityImmediateAndAvoidsASpeedFiveSnap() {
        val flights = ProjectileFlightPresentation(); val contacts = CombatContactPresentation()
        val authority = body(1).copy(x = 167.0)
        val effects = listOf(terminal("cannon"), contact("cannon", shield = true))
        flights.accept(effects, 0.0); contacts.accept(effects, listOf(authority), 0.0, 6.0)
        fun render(t: Double): ArenaTank {
            val f = flights.render(emptyList(), effects, t)
            return contacts.render(listOf(authority), f.effects, t, flights).tanks.single()
        }
        assertEquals(140.0, render(.11).x, 0.0)
        val released = render(.12)
        assertEquals(140.0, released.x, 0.0)
        assertEquals(0, released.shieldCharges)
        val next = render(.13)
        assertTrue(next.x in 140.0..167.0)
        assertTrue(next.x - released.x < 10)
        assertEquals(167.0, authority.x, 0.0)
    }

    @Test fun laserBeamAndStarmanContactGetABodyFrameBeforeHitAndLocalStarHasNoRemoteDelay() {
        for (kind in listOf("laser", "starman")) for (own in listOf(false, true)) {
            val contacts = CombatContactPresentation(); val flights = ProjectileFlightPresentation()
            val hit = contact(kind, projectile = 0)
            val beam = ArenaEffect(id = 1, kind = "laser", tick = 6, points = listOf(BeamPoint(20.0, 42.0), BeamPoint(140.0, 42.0)))
            val effects = if (kind == "laser") listOf(beam, hit) else listOf(hit)
            contacts.accept(effects, listOf(body()), .02, 6.0, if (own) setOf(1) else emptySet())
            val early = contacts.render(listOf(body()), effects, .02, flights)
            assertEquals(1, early.tanks.single().hp)
            assertFalse(early.effects.any { it.kind == "hit" })
            val instantOwnStar = kind == "starman" && own
            val endpoint = contacts.render(listOf(body()), effects, if (instantOwnStar) .03 else .1, flights)
            if (instantOwnStar) { assertEquals(0, endpoint.tanks.single().hp); assertEquals(listOf(hit), endpoint.effects) }
            else {
                assertEquals(1, endpoint.tanks.single().hp)
                if (kind == "laser") assertEquals(listOf(beam), endpoint.effects)
                val released = contacts.render(listOf(body()), effects, .11, flights)
                assertEquals(0, released.tanks.single().hp)
                assertTrue(released.effects.any { it.id == hit.id })
            }
        }
    }
}
