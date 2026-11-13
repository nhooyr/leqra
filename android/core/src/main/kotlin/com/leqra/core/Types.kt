package com.leqra.core

// Native protocol DTOs. Gameplay fields retain server defaults.
object GamePalette {
    val colors =
        listOf(
            "#d2f65a",
            "#ff9679",
            "#73cee4",
            "#c5a2ff",
            "#ffc46b",
            "#ff83bd",
            "#75f0cb",
            "#b7c6ee",
        )
    val displayColors =
        listOf(
            "#32c5ff",
            "#ff758f",
            "#3ee6c5",
            "#ba91ff",
            "#ffcb66",
            "#ff7bd5",
            "#79d878",
            "#91a9ff",
        )
    val names =
        listOf("Electric blue", "Coral", "Jade", "Amethyst", "Amber", "Orchid", "Leaf", "Iris")

    fun index(value: Int) = Math.floorMod(value, colors.size)
}

data class GameInput(
    var seq: Long = 0L,
    var forward: Boolean = false,
    var reverse: Boolean = false,
    var left: Boolean = false,
    var right: Boolean = false,
    var fire: Boolean = false,
    var stickX: Double = 0.0,
    var stickY: Double = 0.0,
    var touchAim: Boolean = true,
    var aimOnly: Boolean = false,
)

data class MazeWall(
    var x: Double = 0.0,
    var y: Double = 0.0,
    var w: Double = 0.0,
    var h: Double = 0.0,
    var axis: String = "",
    var line: Double = 0.0,
)

data class BeamPoint(
    var x: Double = 0.0,
    var y: Double = 0.0,
)

data class ArenaTank(
    var survivalEnemy: Boolean = false,
    var survivalBoss: Boolean = false,
    var difficulty: String = "normal",
    var id: Int = 0,
    var name: String = "",
    var x: Double = 0.0,
    var y: Double = 0.0,
    var angle: Double = 0.0,
    var hp: Int = 1,
    var colorIndex: Int = 0,
    var score: Int = 0,
    var rank: Int = 0,
    var team: Int = 0,
    var bot: Boolean = false,
    var protectedState: Boolean = false,
    var spawnProtected: Boolean = false,
    var ack: Long = 0L,
    var ackSteps: Int = 0,
    var spawnSerial: Int = 0,
    var track: Double = 0.0,
    var recoil: Double = 0.0,
    var cooldown: Double = 0.0,
    var cooldownTotal: Double = 0.0,
    var invulnerable: Double = 0.0,
    var powerTime: Double = 0.0,
    var shield: Double = 0.0,
    var speedTime: Double = 0.0,
    var ghostTime: Double = 0.0,
    var starmanTime: Double = 0.0,
    var respawnTime: Double = 0.0,
    var grenadeLife: Double = 0.0,
    var power: String = "",
    var charges: Int = 0,
    var machineRounds: Int = 0,
    var shieldCharges: Int = 0,
    var speedStacks: Int = 0,
    var ammoUsed: Int = 0,
    var grenades: Int = 0,
    var locked: Boolean = false,
    var killedBy: String = "",
    var killedByColor: String = "",
)

data class ArenaBullet(
    var id: Int = 0,
    var x: Double = 0.0,
    var y: Double = 0.0,
    var vx: Double = 0.0,
    var vy: Double = 0.0,
    var owner: Int = 0,
    var kind: String = "",
    var colorIndex: Int = 0,
    var life: Double = 0.0,
    var bounces: Int = 0,
    var target: Int = 0,
)

data class ArenaPickup(
    var id: Int = 0,
    var x: Double = 0.0,
    var y: Double = 0.0,
    var type: String = "",
    var age: Double = 0.0,
    var life: Double = 30.0,
)

data class ArenaEffect(
    var id: Int = 0,
    var kind: String = "",
    var x: Double = 0.0,
    var y: Double = 0.0,
    var owner: Int = 0,
    var points: List<BeamPoint> = emptyList(),
    var player: Int? = null,
    var tick: Int? = null,
    var spawnSerial: Int? = null,
    var shotSerial: Long? = null,
)

data class LeaderboardEntry(
    var id: Int = 0,
    var name: String = "",
    var score: Int = 0,
    var colorIndex: Int = 0,
    var bot: Boolean = false,
    var team: Int = 0,
)

data class ArenaWorld(
    var width: Double = 0.0,
    var height: Double = 0.0,
    var cols: Int = 0,
    var rows: Int = 0,
    var walls: List<MazeWall> = emptyList(),
)

data class ArenaSnapshot(
    var rules: RoomRules? = null,
    var boostedBulletIds: List<Int> = emptyList(),
    var generation: Int = 0,
    var objectives: ArenaObjectives? = null,
    var result: ArenaResult? = null,
    var teamScores: List<Int> = emptyList(),
    var type: String = "state",
    var tick: Long = 0L,
    var tanks: List<ArenaTank> = emptyList(),
    var bullets: List<ArenaBullet> = emptyList(),
    var pickups: List<ArenaPickup> = emptyList(),
    var effects: List<ArenaEffect> = emptyList(),
    var leaderboard: List<LeaderboardEntry> = emptyList(),
    var players: Int = 0,
    var tankCount: Int = 0,
    var world: ArenaWorld? = null,
    var phase: String = "playing",
    var phaseTime: Double = 0.0,
    var roundClock: Double = 0.0,
    var round: Int = 0,
    var scores: List<Int> = emptyList(),
    var winner: Int = -1,
)

data class ArenaFlag(
    var team: Int = 0,
    var homeX: Double = 0.0,
    var homeY: Double = 0.0,
    var x: Double = 0.0,
    var y: Double = 0.0,
    var carrier: Int = -1,
    var home: Boolean = true,
    var returnIn: Double = 0.0,
)

data class ArenaSurvival(
    var wave: Int = 0,
    var wavesCleared: Int = 0,
    var waveTarget: Int = 0,
    var enemiesRemaining: Int = 0,
    var boss: Boolean = false,
    var breakTime: Double = 0.0,
    var status: String = "",
)

data class ArenaObjectives(
    var mode: String = "",
    var flags: List<ArenaFlag> = emptyList(),
    var hillX: Double = 0.0,
    var hillY: Double = 0.0,
    var radius: Double = 32.0,
    var owner: Int = 0,
    var contested: Boolean = false,
    var hold: Double = 0.0,
    var suddenDeath: Boolean = false,
    var survival: ArenaSurvival? = null,
)

data class ArenaResult(
    var id: Int = 0,
    var name: String = "",
    var team: Int = 0,
    var score: Int = 0,
)

data class RoomRules(
    var mode: String = "elimination",
    var infinity: Boolean = false,
    var infinityTarget: Int = 0,
    var infinityRandomBots: Boolean = false,
    var infinityBotDifficulty: String = "normal",
    var infinityRandomDifficulty: Boolean = false,
    var teamMode: String = "ffa",
    var mapSize: String = "large",
    var portraitMaze: Boolean = false,
    var scoreTarget: Int = 5,
    var timeLimit: Int = 75,
    var respawnSeconds: Int = 3,
    var pickupRate: String = "superfast",
    var weapons: List<String> =
        listOf(
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
    var friendlyFire: Boolean = false,
    var teamNames: List<String> = listOf("Team 1", "Team 2", "Team 3", "Team 4"),
    var teamColors: List<Int> = listOf(0, 1, 2, 3),
) {
    companion object {
        fun modeDefaults(mode: String = "elimination") =
            RoomRules(
                infinity = mode == "infinity",
                mode = if (mode == "infinity") "elimination" else mode,
                teamMode = if (mode in listOf("ctf", "survival")) "teams" else "ffa",
                scoreTarget =
                    when (mode) {
                        "survival" -> 15
                        "koth" -> 30
                        "ctf" -> 3
                        else -> 5
                    },
                timeLimit = if (mode in listOf("ctf", "koth")) 180 else 75,
            )

        fun localDefaults(mode: String = "elimination") =
            modeDefaults(mode).apply { mapSize = "compact" }
    }
}
