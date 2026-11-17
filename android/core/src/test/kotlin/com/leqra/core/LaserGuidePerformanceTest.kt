package com.leqra.core

import kotlin.math.*
import org.junit.Assert.*
import org.junit.Test

class LaserGuidePerformanceTest {
    private fun original(maze: InfiniteMaze, x: Double, y: Double, angle: Double): List<BeamPoint> {
        val launch = maze.launchRay(x, y, angle, "laser", 3.0) ?: return emptyList()
        var xx=launch.x;var yy=launch.y;var ux=launch.ux;var uy=launch.uy
        var remaining=max(0.0,36*84.0-launch.distance)
        val points=mutableListOf<BeamPoint>()
        repeat(256) { i ->
            val wall=maze.rayHit(xx,yy,ux*remaining,uy*remaining,3.0)
            val length=remaining*(wall?.fraction?:1.0)
            if(i==0) { val crop=if(launch.bounced)0.0 else 28.0;points+=BeamPoint(xx+ux*min(crop,length),yy+uy*min(crop,length)) }
            xx+=ux*length;yy+=uy*length;remaining-=length;points+=BeamPoint(xx,yy)
            if(wall==null||remaining<=1e-7)return points
            if(wall.nx!=0.0)ux = -ux
            if(wall.ny!=0.0)uy = -uy
            val nudge=min(.001,remaining);xx+=ux*nudge;yy+=uy*nudge;remaining-=nudge
        }
        return points
    }

    @Test
    fun laserGuideMatchesFullRangeReferenceAndReportsCost() {
        val maze=InfiniteMaze(123)
        val rays=(0 until 180).map { i-> Triple(42.0+(i%9-4)*84,42.0+(i%7-3)*84,i*PI/90) }
        for((x,y,angle) in rays) {
            val old=original(maze,x,y,angle);val actual=maze.laserGuide(x,y,angle)
            assertEquals(old.size,actual.size)
            for(i in old.indices) {assertEquals(old[i].x,actual[i].x,1e-5);assertEquals(old[i].y,actual[i].y,1e-5)}
        }
        repeat(2){for((x,y,angle)in rays){original(maze,x,y,angle);maze.laserGuide(x,y,angle)}}
        val times=LongArray(9);val referenceTimes=LongArray(9)
        fun measure(reference: Boolean): Long {
            val start=System.nanoTime()
            for((x,y,angle)in rays)if(reference)original(maze,x,y,angle)else maze.laserGuide(x,y,angle)
            return System.nanoTime()-start
        }
        repeat(times.size) { sample ->
            if(sample%2==0){referenceTimes[sample]=measure(true);times[sample]=measure(false)}
            else{times[sample]=measure(false);referenceTimes[sample]=measure(true)}
        }
        times.sort();referenceTimes.sort()
        println("180 infinite laser previews medianMs=${times[4]/1e6} fullRangeReferenceMs=${referenceTimes[4]/1e6}")
    }

    @Test
    fun chunkedLaserGuideKeepsBoundaryAndDistantCoordinateBounces() {
        for (seed in listOf(1, 42, 123, -123, Int.MAX_VALUE)) {
            val maze = InfiniteMaze(seed)
            for (i in 0 until 60) {
                val x = (i % 11 - 5) * 84.0 + if (i % 2 == 0) 1e-7 else 83.9999999
                val y = (i % 13 - 6) * 84.0 + if (i % 3 == 0) 1e-7 else 42.0
                val angle = i * PI / 30 + if (i % 4 == 0) 1e-9 else 0.0
                val expected = original(maze, x, y, angle)
                val actual = maze.laserGuide(x, y, angle)
                assertEquals("seed=$seed ray=$i", expected.size, actual.size)
                for (p in expected.indices) {
                    assertEquals(expected[p].x, actual[p].x, 1e-5)
                    assertEquals(expected[p].y, actual[p].y, 1e-5)
                }
            }
        }
    }
}
