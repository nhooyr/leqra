package com.leqra.android.audio

import com.leqra.core.*
import kotlin.math.hypot
import org.junit.Assert.*
import org.junit.Test

class CombatContactAudioTest {
    @Test fun allBallisticsFinishContactBeforeVictimExplosionOrShieldAudioAtEveryLatency() {
        for (kind in listOf("regular", "rapid", "scatter", "homing", "grenade", "cannon"))
        for (shield in listOf(false, true)) for (fixed in listOf(false, true)) for (boosted in listOf(false,true))
        for (role in listOf("attacker", "victim", "spectator")) for (ping in listOf(.001, .05, .2, .4)) {
            val victim = ArenaTank(id = 8, name = "Target", x = 140.0, y = 42.0, spawnSerial = 2,
                hp = 1, shield = if (shield) 3.0 else 0.0, shieldCharges = if (shield) 2 else 0,
                speedTime = 10.0, speedStacks = 5, ghostTime = 5.0)
            val baseline = ArenaSnapshot(tick = 0, generation = 1,
                tanks = listOf(ArenaTank(id = 1, x = 42.0, y = 42.0, power=kind, powerTime=10.0,
                    starmanTime=if(boosted)5.0 else 0.0, speedTime=10.0, speedStacks=5, ghostTime=5.0), victim),
                boostedBulletIds=if(boosted)listOf(7) else emptyList(),
                world = if (fixed) ArenaWorld(1000.0, 1000.0) else null,
                spectating = role == "spectator", following = if (role == "spectator") 8 else 0)
            val radius = PracticeArena.spec(kind).radius
            val flight = ProjectileFlight(7, 1, 0, 0.0, 2.0,
                listOf(ProjectileFlightPoint(70.0, 42.0, 0.0), ProjectileFlightPoint(140 - 17 - radius, 42.0, 2.0)), kind, radius)
            val effects = listOf(
                ArenaEffect(id = 1, kind = if (kind == "grenade") "blast" else "projectileFlight", tick = 2, owner = 1, flight = flight),
                ArenaEffect(id = 2, kind = if (shield) "shield" else "hit", tick = 2, owner = 1,
                    contact = CombatContact(7, kind, 2.0, 8, 2, ContactTankState(140.0, 42.0, 0.0, hp = 1, shield = victim.shield, shieldCharges = victim.shieldCharges))))
            val killed = baseline.copy(tick = 2, tanks = listOf(baseline.tanks[0].copy(score = 1), victim.copy(hp = if (shield) 1 else 0, shield = 0.0, shieldCharges = 0)), effects = effects)
            val local = if (role == "victim") 8 else 1
            val timeline = OnlinePresentation(localID = local)
            val router = AudioEventRouter()
            timeline.accept(baseline, 0.0)
            router.consume(timeline.render(0.0, GameInput(), 0.0) {}!!, local, !fixed, true, 0.0)
            timeline.accept(killed, ping / 2 + 2.0 / 60)
            assertEquals(if (shield) 1 else 0, timeline.authoritativeSnapshot!!.tanks[1].hp)
            var endpoint = false; var damage = false; var sound = false
            repeat(90) { frame ->
                val now = ping / 2 + 2.0 / 60 + frame / 120.0
                if (frame > 0 && frame % 4 == 0) timeline.accept(killed.copy(tick = 2L + frame / 2), now)
                val image = timeline.render(1.0 / 120, GameInput(), now) {}!!
                val visible = image.tanks.first { it.id == 8 }
                val bullet = image.bullets.firstOrNull { it.id == 7 }
                val cues = router.consume(image, local, !fixed, true, now)
                val hitShown = image.effects.any { it.id == 2 }
                if (!damage && (hitShown || visible.hp == 0 || visible.shieldCharges == 0 && shield)) {
                    assertTrue("$kind/$shield/$fixed/$role/ping$ping must draw contact before damage", endpoint)
                    damage = true
                }
                if (bullet != null && kotlin.math.abs(bullet.x - flight.points.last().x) < 1e-7) {
                    assertEquals(1, visible.hp)
                    assertEquals(17 + radius, hypot(visible.x - bullet.x, visible.y - bullet.y), 1e-6)
                    assertFalse(hitShown)
                    endpoint = true
                }
                if (cues.any { it.cue in listOf(AudioCue.EXPLOSION, AudioCue.GRENADE_EXPLOSION, AudioCue.SHIELD) }) {
                    assertTrue("Damage sound must follow the visible contact", endpoint && damage)
                    sound = true
                }
            }
            assertTrue("$kind/$shield/$fixed/$role/ping$ping endpoint=$endpoint damage=$damage sound=$sound", endpoint && damage && sound)
        }
    }
}
