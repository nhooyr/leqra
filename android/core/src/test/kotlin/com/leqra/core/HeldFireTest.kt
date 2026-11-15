package com.leqra.core

import org.junit.Assert.*
import org.junit.Test

class HeldFireTest {
    private val dt = 1.0 / 60
    private fun arena(fixed: Boolean) = PracticeArena(42, "Pilot", 0, 0,
        world = if (fixed) ArenaWorld(10000.0,10000.0,120,120) else null).apply {
        snapshot.tanks.first().apply { x=if(fixed)5000.0 else 42.0;y=x;spawnProtected=false;invulnerable=0.0 }
    }
    @Test fun everyActualPickupRestartsHeldFireImmediatelyInBothWorlds() {
        for (fixed in listOf(false,true)) for (power in PracticeArena.pickupKinds) {
            val a=arena(fixed);val t=a.snapshot.tanks.first()
            a.step(GameInput(fire=true),dt)
            val old=a.snapshot.bullets.single().id
            t.cooldown=5.0
            a.snapshot.pickups=listOf(ArenaPickup(id=900,x=t.x,y=t.y,type=power))
            a.step(GameInput(fire=true),dt)
            assertTrue("$power collected",a.snapshot.effects.any {it.kind=="pickup"})
            assertTrue("Held $power fires on its pickup tick",a.snapshot.effects.any {it.kind=="laser"||it.kind=="shot:${t.power}"||it.kind=="shot:"})
            assertTrue("A refill preserves old flights",a.snapshot.bullets.any {it.id==old})
            if(power!="laser")assertTrue(a.snapshot.bullets.any {it.id!=old})
        }
    }
    @Test fun aFullProjectileBankAutomaticallyRetriesAfterItsFlightsExpire() {
        for (power in listOf("","rapid","scatter")) {
            val a=arena(true);val t=a.snapshot.tanks.first()
            if(power.isNotEmpty())PracticeArena.applyPower(t,power)
            val shots=if(power=="rapid")115 else if(power=="scatter")4 else 5
            repeat(shots){t.cooldown=0.0;a.step(GameInput(fire=true),dt)}
            val old=a.snapshot.bullets.map {it.id}.toSet()
            assertEquals(if(power=="scatter")12 else shots,old.size)
            t.cooldown=0.0;a.step(GameInput(fire=true),dt)
            assertEquals("Full $power bank does not invent shots",old,a.snapshot.bullets.map {it.id}.toSet())
            val projectiles=PracticeArena::class.java.getDeclaredField("projectiles").run {isAccessible=true;get(a) as List<*>}
            projectiles.forEach {p->p!!.javaClass.getDeclaredField("wire").run {isAccessible=true;get(p) as ArenaBullet}.life=.001}
            a.step(GameInput(fire=true),dt);a.step(GameInput(fire=true),dt)
            assertTrue("Held $power retries as capacity returns",a.snapshot.bullets.any {it.id !in old})
        }
    }
    @Test fun boostedGrenadePopRemovesTheWholeBankThenHeldThrowResumesNextTick() {
        for(fixed in listOf(false,true)) {
            val a=arena(fixed);val t=a.snapshot.tanks.first()
            PracticeArena.applyPower(t,"grenade");PracticeArena.applyPower(t,"starman")
            repeat(4){a.step(GameInput(fire=true),dt)}
            assertEquals(4,t.grenades)
            a.step(GameInput(),dt);a.step(GameInput(fire=true),dt)
            assertEquals(0,t.grenades)
            assertFalse("Pop tick cannot throw a new grenade",a.snapshot.bullets.any {it.kind=="grenade"})
            a.step(GameInput(fire=true),dt)
            assertEquals(1,t.grenades)
            assertEquals(1,a.snapshot.bullets.count {it.kind=="grenade"})
        }
    }
}
