package com.leqra.android.network

import com.leqra.core.*
import org.json.JSONArray
import org.json.JSONObject

/**
 * A decoder belongs to one socket; reliable world updates survive intervening small state packets.
 */
class SnapshotDecoder {
    private var lastWorld: ArenaWorld? = null

    fun decode(json: JSONObject): ArenaSnapshot {
        require(json.getString("type") == "state")
        val fixed = json.has("phase")
        val scores = json.optJSONArray("scores")?.ints() ?: emptyList()
        val tanks =
            json.getJSONArray("tanks").objects { raw ->
                ProtocolJson.arenaTank(raw).also { tank ->
                    if (fixed) {
                        tank.hp = if (raw.optBoolean("alive")) 1 else 0
                        tank.score = scores.getOrElse(tank.id) { 0 }
                        tank.colorIndex = colorIndex(raw.optString("color"))
                    }
                }
            }
        val bullets =
            json
                .getJSONArray("bullets")
                .objects { raw ->
                    ProtocolJson.arenaBullet(raw).also {
                        if (fixed) it.colorIndex = colorIndex(raw.optString("color"))
                    }
                }
                .toMutableList()
        if (fixed)
            json.optJSONArray("machineBullets")?.let { packed ->
                for (index in 0 until packed.length()) {
                    val row = packed.getJSONArray(index)
                    require(row.length() == 12)
                    for (column in 0 until 12) require(row.getDouble(column).isFinite())
                    require(
                        row.getDouble(0) == row.getInt(0).toDouble() &&
                            row.getDouble(1) == row.getInt(1).toDouble() &&
                            row.getDouble(10) == row.getInt(10).toDouble() &&
                            row.getDouble(11) == row.getInt(11).toDouble(),
                    )
                    bullets.add(
                        ArenaBullet(
                            id = row.getInt(0),
                            owner = row.getInt(1),
                            kind = "rapid",
                            x = row.getDouble(4),
                            y = row.getDouble(5),
                            vx = row.getDouble(6),
                            vy = row.getDouble(7),
                            life = row.getDouble(9),
                            bounces = row.getInt(10),
                            colorIndex = row.getInt(11),
                        ),
                    )
                }
            }
        val boosted = json.optJSONArray("boostedBulletIds")?.ints() ?: emptyList()
        val rules = json.optJSONObject("rules")?.let(ProtocolJson::roomRules)
        if (!fixed) rules?.infinity = true
        if (fixed) {
            // Normalize every projectile in one pass. Per-projectile temporary
            // sets, grouped lists and grenade filters are expensive during Starman.
            val byId = tanks.associateBy { it.id }
            val boostedSet = boosted.toHashSet()
            for (tank in tanks) {
                tank.ammoUsed =
                    if (tank.power == "laser") (3 - tank.charges).coerceAtLeast(0) else 0
                tank.grenades = 0
                tank.grenadeLife = 0.0
                tank.locked = false
            }
            for (bullet in bullets) {
                val shooter = byId[bullet.owner]
                if (shooter != null) {
                    if (shooter.power != "laser" && bullet.id !in boostedSet) shooter.ammoUsed++
                    if (bullet.kind == "grenade") {
                        shooter.grenades++
                        shooter.grenadeLife = maxOf(shooter.grenadeLife, bullet.life)
                    }
                }
                if (
                    (bullet.kind == "homing" || bullet.kind == "grenade") &&
                        bullet.owner != bullet.target
                ) {
                    val target = byId[bullet.target]
                    if (
                        target != null &&
                            (rules?.friendlyFire == true ||
                                shooter == null ||
                                shooter.team == 0 ||
                                shooter.team != target.team)
                    )
                        target.locked = true
                }
            }
        }
        val leaderboard =
            if (fixed)
                tanks.sortedWith(compareByDescending<ArenaTank> { it.score }.thenBy { it.id }).map {
                    LeaderboardEntry(it.id, it.name, it.score, it.colorIndex, it.bot, it.team)
                }
            else json.getJSONArray("leaderboard").objects(ProtocolJson::leaderboardEntry)
        val effects =
            (json.optJSONArray(if (fixed) "events" else "effects") ?: JSONArray()).objects { raw ->
                ProtocolJson.arenaEffect(raw).also {
                    if (fixed)
                        it.kind =
                            if (raw.optString("type") == "shot") "shot:" + raw.optString("text")
                            else raw.optString("type")
                }
            }
        if (fixed) json.optJSONObject("world")?.let { lastWorld = ProtocolJson.arenaWorld(it) }
        else lastWorld = null
        val spawns = if (fixed) null else json.optJSONArray("godlikeSpawns")
        return ArenaSnapshot(
            rules = rules,
            boostedBulletIds = boosted,
            generation = json.optInt("generation"),
            objectives = json.optJSONObject("objectives")?.let(ProtocolJson::arenaObjectives),
            result = json.optJSONObject("result")?.let(ProtocolJson::arenaResult),
            teamScores = json.optJSONArray("teamScores")?.ints() ?: emptyList(),
            tick = json.getLong("tick"),
            tanks = tanks,
            bullets = bullets,
            pickups =
                (json.optJSONArray("pickups") ?: JSONArray()).objects(ProtocolJson::arenaPickup),
            effects = effects,
            godlikeSpawns =
                if (spawns == null) emptyList()
                else List(minOf(spawns.length(), 128)) { index ->
                    val event = spawns.getJSONObject(index)
                    val name = event.getString("name")
                    require(name.isNotBlank() && name.codePointCount(0, name.length) <= 64)
                    GodlikeSpawn(event.getInt("id"), event.getInt("spawnSerial"), name)
                },
            leaderboard = leaderboard,
            players = if (fixed) tanks.count { !it.bot } else json.getInt("players"),
            tankCount = if (fixed) tanks.size else json.getInt("tankCount"),
            world = lastWorld,
            phase = json.optString("phase", "playing"),
            phaseTime = json.number("phaseTime"),
            roundClock = json.number("roundClock"),
            round = json.optInt("round"),
            scores = scores,
            winner = json.optInt("winner", -1),
            spectating = json.optBoolean("spectating"),
            following = json.optInt("following"),
        )
    }

    private fun colorIndex(color: String) = GamePalette.colors.indexOf(color).coerceAtLeast(0)

    companion object {
        fun rules(json: JSONObject): RoomRules = ProtocolJson.roomRules(json)
    }
}
