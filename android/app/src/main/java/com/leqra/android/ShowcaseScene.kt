package com.leqra.android

import android.content.Context
import com.leqra.android.network.SnapshotDecoder
import com.leqra.core.ArenaSnapshot
import com.leqra.core.BeamPoint
import com.leqra.core.InfiniteMaze
import org.json.JSONArray
import org.json.JSONObject

internal class ShowcaseScene
private constructor(
    val snapshot: ArenaSnapshot,
    val maze: InfiniteMaze,
    val localID: Int,
    val time: Double,
    val effectAges: Map<Int, Double>,
    val outlines: Map<Int, List<BeamPoint>>,
    val trails: Map<Int, List<BeamPoint>>,
    val fps: Int,
    val ping: Int,
) {
    companion object {
        fun load(context: Context, portrait: Boolean = false): ShowcaseScene {
            val root =
                context.assets.open("showcase.json").bufferedReader().use {
                    JSONObject(it.readText())
                }
            val json = if (portrait) root.optJSONObject("portrait") ?: root else root
            require(json.getInt("showcaseVersion") == 1)
            fun points(array: JSONArray): List<BeamPoint> =
                List(array.length()) { index ->
                    array.getJSONObject(index).let {
                        BeamPoint(it.getDouble("x"), it.getDouble("y"))
                    }
                }
            val effects = json.getJSONArray("effects")
            val ages = mutableMapOf<Int, Double>()
            val outlines = mutableMapOf<Int, List<BeamPoint>>()
            repeat(effects.length()) { index ->
                val effect = effects.getJSONObject(index)
                val id = effect.getInt("id")
                ages[id] = effect.optDouble("showcaseAge", 0.0) / 1000
                effect.optJSONArray("outline")?.let { outlines[id] = points(it) }
            }
            val trails = mutableMapOf<Int, List<BeamPoint>>()
            val ranks = mutableMapOf<Int, Int>()
            json.optJSONArray("leaderboard")?.let { leaders ->
                repeat(leaders.length()) { index ->
                    val leader = leaders.getJSONObject(index)
                    ranks[leader.getInt("id")] = leader.optInt("rank", index + 1)
                }
            }
            val tanks = json.getJSONArray("tanks")
            repeat(tanks.length()) { index ->
                val tank = tanks.getJSONObject(index)
                if (!tank.has("rank")) tank.put("rank", ranks[tank.getInt("id")] ?: 0)
            }
            val bullets = json.getJSONArray("bullets")
            repeat(bullets.length()) { index ->
                val bullet = bullets.getJSONObject(index)
                if (bullet.isNull("target")) bullet.put("target", -1)
                bullet.optJSONArray("trail")?.let { trails[bullet.getInt("id")] = points(it) }
            }
            return ShowcaseScene(
                SnapshotDecoder().decode(json),
                InfiniteMaze(json.getInt("seed")),
                json.getInt("localID"),
                json.getDouble("time") / 1000,
                ages,
                outlines,
                trails,
                json.optInt("fps", 120),
                json.optInt("ping", 8),
            )
        }
    }
}
