package com.leqra.android.network

import com.leqra.core.*
import org.json.JSONArray
import org.json.JSONObject

/** Explicit native DTO decoding; no reflection or script engine on the render path. */
object ProtocolJson {
    fun mazeWall(json: JSONObject) =
        MazeWall(
            x = json.number("x", 0.0),
            y = json.number("y", 0.0),
            w = json.number("w", 0.0),
            h = json.number("h", 0.0),
            axis = json.optString("axis", ""),
            line = json.number("line", 0.0),
        )

    fun beamPoint(json: JSONObject) =
        BeamPoint(
            x = json.number("x", 0.0),
            y = json.number("y", 0.0),
        )

    fun arenaTank(json: JSONObject) =
        ArenaTank(
            survivalEnemy = json.optBoolean("survivalEnemy", false),
            survivalBoss = json.optBoolean("survivalBoss", false),
            difficulty = json.optString("difficulty", "normal"),
            id = json.optInt("id", 0),
            name = json.optString("name", ""),
            x = json.number("x", 0.0),
            y = json.number("y", 0.0),
            angle = json.number("angle", 0.0),
            hp = json.optInt("hp", 1),
            colorIndex = json.optInt("colorIndex", 0),
            score = json.optInt("score", 0),
            rank = json.optInt("rank", 0),
            team = json.optInt("team", 0),
            bot = json.optBoolean("bot", false),
            protectedState = json.optBoolean("protected", false),
            spawnProtected = json.optBoolean("spawnProtected", false),
            ack = json.optLong("ack", 0L),
            ackSteps = json.optInt("ackSteps", 0),
            spawnSerial = json.optInt("spawnSerial", 0),
            track = json.number("track", 0.0),
            recoil = json.number("recoil", 0.0),
            cooldown = json.number("cooldown", 0.0),
            cooldownTotal = json.number("cooldownTotal", 0.0),
            invulnerable = json.number("invulnerable", 0.0),
            powerTime = json.number("powerTime", 0.0),
            shield = json.number("shield", 0.0),
            speedTime = json.number("speedTime", 0.0),
            ghostTime = json.number("ghostTime", 0.0),
            starmanTime = json.number("starmanTime", 0.0),
            respawnTime = json.number("respawnTime", 0.0),
            grenadeLife = json.number("grenadeLife", 0.0),
            power = json.optString("power", ""),
            charges = json.optInt("charges", 0),
            machineRounds = json.optInt("machineRounds", 0),
            shieldCharges = json.optInt("shieldCharges", 0),
            speedStacks = json.optInt("speedStacks", 0),
            ammoUsed = json.optInt("ammoUsed", 0),
            grenades = json.optInt("grenades", 0),
            locked = json.optBoolean("locked", false),
            killedBy = json.optString("killedBy", ""),
            killedByColor = json.optString("killedByColor", ""),
        )

    fun arenaBullet(json: JSONObject) =
        ArenaBullet(
            id = json.optInt("id", 0),
            x = json.number("x", 0.0),
            y = json.number("y", 0.0),
            vx = json.number("vx", 0.0),
            vy = json.number("vy", 0.0),
            owner = json.optInt("owner", 0),
            kind = json.optString("kind", ""),
            colorIndex = json.optInt("colorIndex", 0),
            life = json.number("life", 0.0),
            bounces = json.optInt("bounces", 0),
            target = json.optInt("target", 0),
        )

    fun arenaPickup(json: JSONObject) =
        ArenaPickup(
            id = json.optInt("id", 0),
            x = json.number("x", 0.0),
            y = json.number("y", 0.0),
            type = json.optString("type", ""),
            age = json.number("age", 0.0),
            life = json.number("life", 30.0),
        )

    fun arenaEffect(json: JSONObject) =
        ArenaEffect(
            id = json.optInt("id", 0),
            kind = json.optString("kind", ""),
            x = json.number("x", 0.0),
            y = json.number("y", 0.0),
            owner = json.optInt("owner", 0),
            points = json.optJSONArray("points")?.objects { beamPoint(it) } ?: emptyList(),
            player = json.intOrNull("player"),
            tick = json.intOrNull("tick"),
            spawnSerial = json.intOrNull("spawnSerial"),
            shotSerial = json.longOrNull("shotSerial"),
            flight = json.optJSONObject("flight")?.let { runCatching { projectileFlight(it) }.getOrNull() },
        )

    private fun projectileFlight(json: JSONObject): ProjectileFlight {
        require(json.has("startTick") && json.has("endTick"))
        val points = json.getJSONArray("points")
        require(points.length() in 2..32)
        val id = json.getInt("id")
        val owner = json.getInt("owner")
        val color = json.getInt("colorIndex")
        require(json.getDouble("id") == id.toDouble() && json.getDouble("owner") == owner.toDouble() && json.getDouble("colorIndex") == color.toDouble())
        return ProjectileFlight(id, owner, color, json.number("startTick"), json.number("endTick"),
            points.objects { require(it.has("x") && it.has("y") && it.has("tick")); ProjectileFlightPoint(it.number("x"), it.number("y"), it.number("tick")) },
            json.optString("kind", "cannon"), json.number("radius", 18.0))
    }

    fun leaderboardEntry(json: JSONObject) =
        LeaderboardEntry(
            id = json.optInt("id", 0),
            name = json.optString("name", ""),
            score = json.optInt("score", 0),
            colorIndex = json.optInt("colorIndex", 0),
            bot = json.optBoolean("bot", false),
            team = json.optInt("team", 0),
        )

    fun arenaWorld(json: JSONObject) =
        ArenaWorld(
            width = json.number("width", 0.0),
            height = json.number("height", 0.0),
            cols = json.optInt("cols", 0),
            rows = json.optInt("rows", 0),
            walls = json.optJSONArray("walls")?.objects { mazeWall(it) } ?: emptyList(),
        )

    fun arenaFlag(json: JSONObject) =
        ArenaFlag(
            team = json.optInt("team", 0),
            homeX = json.number("homeX", 0.0),
            homeY = json.number("homeY", 0.0),
            x = json.number("x", 0.0),
            y = json.number("y", 0.0),
            carrier = json.optInt("carrier", -1),
            home = json.optBoolean("home", true),
            returnIn = json.number("returnIn", 0.0),
        )

    fun arenaSurvival(json: JSONObject) =
        ArenaSurvival(
            wave = json.optInt("wave", 0),
            wavesCleared = json.optInt("wavesCleared", 0),
            waveTarget = json.optInt("waveTarget", 0),
            enemiesRemaining = json.optInt("enemiesRemaining", 0),
            boss = json.optBoolean("boss", false),
            breakTime = json.number("breakTime", 0.0),
            status = json.optString("status", ""),
        )

    fun arenaObjectives(json: JSONObject) =
        ArenaObjectives(
            mode = json.optString("mode", ""),
            flags = json.optJSONArray("flags")?.objects { arenaFlag(it) } ?: emptyList(),
            hillX = json.number("hillX", 0.0),
            hillY = json.number("hillY", 0.0),
            radius = json.number("radius", 32.0),
            owner = json.optInt("owner", 0),
            contested = json.optBoolean("contested", false),
            hold = json.number("hold", 0.0),
            suddenDeath = json.optBoolean("suddenDeath", false),
            survival = json.optJSONObject("survival")?.let { arenaSurvival(it) },
        )

    fun arenaResult(json: JSONObject) =
        ArenaResult(
            id = json.optInt("id", 0),
            name = json.optString("name", ""),
            team = json.optInt("team", 0),
            score = json.optInt("score", 0),
        )

    fun roomRules(json: JSONObject) =
        RoomRules(
            mode = json.optString("mode", "elimination"),
            infinity = json.optBoolean("infinity", false),
            infinityTarget = json.optInt("infinityTarget", 0),
            infinityRandomBots = json.optBoolean("infinityRandomBots", false),
            infinityBotDifficulty = json.optString("infinityBotDifficulty", "normal"),
            infinityRandomDifficulty = json.optBoolean("infinityRandomDifficulty", false),
            infinityBotSpawnRate = json.number("infinityBotSpawnRate", 2.0),
            teamMode = json.optString("teamMode", "ffa"),
            mapSize = json.optString("mapSize", "large"),
            portraitMaze = json.optBoolean("portraitMaze", false),
            scoreTarget = json.optInt("scoreTarget", 5),
            timeLimit = json.optInt("timeLimit", 75),
            respawnSeconds = json.optInt("respawnSeconds", 3),
            pickupRate = json.optString("pickupRate", "superfast"),
            weapons =
                json.optJSONArray("weapons")?.strings()
                    ?: listOf(
                        "rapid",
                        "scatter",
                        "shield",
                        "homing",
                        "grenade",
                        "speed",
                        "laser",
                        "cannon",
                        "ghost",
                        "starman",
                    ),
            friendlyFire = json.optBoolean("friendlyFire", false),
            teamNames =
                json.optJSONArray("teamNames")?.strings()
                    ?: listOf("Team 1", "Team 2", "Team 3", "Team 4"),
            teamColors = json.optJSONArray("teamColors")?.ints() ?: listOf(0, 1, 2, 3),
        )

    fun rules(rules: RoomRules): JSONObject =
        JSONObject().apply {
            put("mode", rules.mode)
            put("infinity", rules.infinity)
            put("infinityTarget", rules.infinityTarget)
            put("infinityRandomBots", rules.infinityRandomBots)
            put("infinityBotDifficulty", rules.infinityBotDifficulty)
            put("infinityRandomDifficulty", rules.infinityRandomDifficulty)
            put("infinityBotSpawnRate", rules.infinityBotSpawnRate)
            put("teamMode", rules.teamMode)
            put("mapSize", rules.mapSize)
            put("portraitMaze", rules.portraitMaze)
            put("scoreTarget", rules.scoreTarget)
            put("timeLimit", rules.timeLimit)
            put("respawnSeconds", rules.respawnSeconds)
            put("pickupRate", rules.pickupRate)
            put("weapons", JSONArray(rules.weapons))
            put("friendlyFire", rules.friendlyFire)
            put("teamNames", JSONArray(rules.teamNames))
            put("teamColors", JSONArray(rules.teamColors))
        }
}

internal fun JSONObject.number(key: String, fallback: Double = 0.0): Double {
    if (isNull(key)) return fallback
    val value = get(key)
    require(value is Number) { "Invalid numeric field." }
    return value.toDouble().also { require(it.isFinite()) }
}

internal fun JSONArray.ints(): List<Int> = (0 until length()).map { getInt(it) }

internal fun JSONArray.strings(): List<String> = (0 until length()).map { getString(it) }

internal fun <T> JSONArray.objects(transform: (JSONObject) -> T): List<T> =
    (0 until length()).map { transform(getJSONObject(it)) }
