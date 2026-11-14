import Foundation

// The native wire model mirrors the Go server. Omitted optional gameplay fields
// use the protocol defaults, allowing the same renderer to display both arenas.
public enum GamePalette {
    public static let colors = ["#d2f65a", "#ff9679", "#73cee4", "#c5a2ff", "#ffc46b", "#ff83bd", "#75f0cb", "#b7c6ee"]
    public static let displayColors = ["#32c5ff", "#ff758f", "#3ee6c5", "#ba91ff", "#ffcb66", "#ff7bd5", "#79d878", "#91a9ff"]
    public static let names = ["Electric blue", "Coral", "Jade", "Amethyst", "Amber", "Orchid", "Leaf", "Iris"]
    public static func index(_ value: Int) -> Int { ((value % colors.count) + colors.count) % colors.count }
}

public struct GameInput: Codable, Equatable, Sendable {
    public var seq: UInt64 = 0
    public var forward: Bool = false
    public var reverse: Bool = false
    public var left: Bool = false
    public var right: Bool = false
    public var fire: Bool = false
    public var stickX: Double = 0
    public var stickY: Double = 0
    public var touchAim: Bool = true
    public var aimOnly: Bool = false

    public init(
        seq: UInt64 = 0,
        forward: Bool = false,
        reverse: Bool = false,
        left: Bool = false,
        right: Bool = false,
        fire: Bool = false,
        stickX: Double = 0,
        stickY: Double = 0,
        touchAim: Bool = true,
        aimOnly: Bool = false
    ) {
        self.seq = seq
        self.forward = forward
        self.reverse = reverse
        self.left = left
        self.right = right
        self.fire = fire
        self.stickX = stickX
        self.stickY = stickY
        self.touchAim = touchAim
        self.aimOnly = aimOnly
    }

    private enum CodingKeys: String, CodingKey {
        case seq, forward, reverse, left, right, fire, stickX, stickY, touchAim, aimOnly
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seq = try c.decodeIfPresent(UInt64.self, forKey: .seq) ?? 0
        forward = try c.decodeIfPresent(Bool.self, forKey: .forward) ?? false
        reverse = try c.decodeIfPresent(Bool.self, forKey: .reverse) ?? false
        left = try c.decodeIfPresent(Bool.self, forKey: .left) ?? false
        right = try c.decodeIfPresent(Bool.self, forKey: .right) ?? false
        fire = try c.decodeIfPresent(Bool.self, forKey: .fire) ?? false
        stickX = try c.decodeIfPresent(Double.self, forKey: .stickX) ?? 0
        stickY = try c.decodeIfPresent(Double.self, forKey: .stickY) ?? 0
        touchAim = try c.decodeIfPresent(Bool.self, forKey: .touchAim) ?? false
        aimOnly = try c.decodeIfPresent(Bool.self, forKey: .aimOnly) ?? false
    }
}

public struct MazeWall: Codable, Equatable, Sendable {
    public var x: Double = 0
    public var y: Double = 0
    public var w: Double = 0
    public var h: Double = 0
    public var axis: String = ""
    public var line: Double = 0

    public init(
        x: Double = 0,
        y: Double = 0,
        w: Double = 0,
        h: Double = 0,
        axis: String = "",
        line: Double = 0
    ) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.axis = axis
        self.line = line
    }

    private enum CodingKeys: String, CodingKey {
        case x, y, w, h, axis, line
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0
        w = try c.decodeIfPresent(Double.self, forKey: .w) ?? 0
        h = try c.decodeIfPresent(Double.self, forKey: .h) ?? 0
        axis = try c.decodeIfPresent(String.self, forKey: .axis) ?? ""
        line = try c.decodeIfPresent(Double.self, forKey: .line) ?? 0
    }
}

public struct BeamPoint: Codable, Equatable, Sendable {
    public var x: Double = 0
    public var y: Double = 0

    public init(
        x: Double = 0,
        y: Double = 0
    ) {
        self.x = x
        self.y = y
    }

    private enum CodingKeys: String, CodingKey {
        case x, y
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0
    }
}

public struct ArenaTank: Codable, Equatable, Sendable {
    public var vx: Double = 0
    public var vy: Double = 0
    public var survivalEnemy: Bool = false
    public var survivalBoss: Bool = false
    public var difficulty: String = "normal"
    public var id: Int = 0
    public var name: String = ""
    public var x: Double = 0
    public var y: Double = 0
    public var angle: Double = 0
    public var hp: Int = 1
    public var colorIndex: Int = 0
    public var score: Int = 0
    public var rank: Int = 0
    public var team: Int = 0
    public var bot: Bool = false
    public var protected: Bool = false
    public var spawnProtected: Bool = false
    public var ack: UInt64 = 0
    public var ackSteps: UInt32 = 0
    public var spawnSerial: Int = 0
    public var track: Double = 0
    public var recoil: Double = 0
    public var cooldown: Double = 0
    public var cooldownTotal: Double = 0
    public var invulnerable: Double = 0
    public var powerTime: Double = 0
    public var shield: Double = 0
    public var speedTime: Double = 0
    public var ghostTime: Double = 0
    public var starmanTime: Double = 0
    public var respawnTime: Double = 0
    public var grenadeLife: Double = 0
    public var power: String = ""
    public var charges: Int = 0
    public var machineRounds: Int = 0
    public var shieldCharges: Int = 0
    public var speedStacks: Int = 0
    public var ammoUsed: Int = 0
    public var grenades: Int = 0
    public var locked: Bool = false
    public var killedBy: String = ""
    public var killedByColor: String = ""

    public init(
        id: Int = 0,
        name: String = "",
        x: Double = 0,
        y: Double = 0,
        angle: Double = 0,
        hp: Int = 1,
        colorIndex: Int = 0,
        score: Int = 0,
        rank: Int = 0,
        team: Int = 0,
        bot: Bool = false,
        protected: Bool = false,
        spawnProtected: Bool = false,
        ack: UInt64 = 0,
        ackSteps: UInt32 = 0,
        spawnSerial: Int = 0,
        track: Double = 0,
        recoil: Double = 0,
        cooldown: Double = 0,
        cooldownTotal: Double = 0,
        invulnerable: Double = 0,
        powerTime: Double = 0,
        shield: Double = 0,
        speedTime: Double = 0,
        ghostTime: Double = 0,
        starmanTime: Double = 0,
        respawnTime: Double = 0,
        grenadeLife: Double = 0,
        power: String = "",
        charges: Int = 0,
        machineRounds: Int = 0,
        shieldCharges: Int = 0,
        speedStacks: Int = 0,
        ammoUsed: Int = 0,
        grenades: Int = 0,
        locked: Bool = false,
        killedBy: String = "",
        killedByColor: String = "",
        survivalEnemy: Bool = false,
        survivalBoss: Bool = false,
        difficulty: String = "normal",
        vx: Double = 0,
        vy: Double = 0
    ) {
        self.id = id
        self.name = name
        self.x = x
        self.y = y
        self.angle = angle
        self.hp = hp
        self.colorIndex = colorIndex
        self.score = score
        self.rank = rank
        self.team = team
        self.bot = bot
        self.protected = protected
        self.spawnProtected = spawnProtected
        self.ack = ack
        self.ackSteps = ackSteps
        self.spawnSerial = spawnSerial
        self.track = track
        self.recoil = recoil
        self.cooldown = cooldown
        self.cooldownTotal = cooldownTotal
        self.invulnerable = invulnerable
        self.powerTime = powerTime
        self.shield = shield
        self.speedTime = speedTime
        self.ghostTime = ghostTime
        self.starmanTime = starmanTime
        self.respawnTime = respawnTime
        self.grenadeLife = grenadeLife
        self.power = power
        self.charges = charges
        self.machineRounds = machineRounds
        self.shieldCharges = shieldCharges
        self.speedStacks = speedStacks
        self.ammoUsed = ammoUsed
        self.grenades = grenades
        self.locked = locked
        self.killedBy = killedBy
        self.killedByColor = killedByColor
        self.survivalEnemy = survivalEnemy
        self.survivalBoss = survivalBoss
        self.difficulty = difficulty
        self.vx = vx; self.vy = vy
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, x, y, vx, vy, angle, hp, colorIndex, score, rank, team, bot, protected, spawnProtected, ack, ackSteps, spawnSerial, track, recoil, cooldown, cooldownTotal, invulnerable, powerTime, shield, speedTime, ghostTime, starmanTime, respawnTime, grenadeLife, power, charges, machineRounds, shieldCharges, speedStacks, ammoUsed, grenades, locked, killedBy, killedByColor, survivalEnemy, survivalBoss, difficulty
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0
        vx = try c.decodeIfPresent(Double.self, forKey: .vx) ?? 0
        vy = try c.decodeIfPresent(Double.self, forKey: .vy) ?? 0
        angle = try c.decodeIfPresent(Double.self, forKey: .angle) ?? 0
        hp = try c.decodeIfPresent(Int.self, forKey: .hp) ?? 1
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        score = try c.decodeIfPresent(Int.self, forKey: .score) ?? 0
        rank = try c.decodeIfPresent(Int.self, forKey: .rank) ?? 0
        team = try c.decodeIfPresent(Int.self, forKey: .team) ?? 0
        bot = try c.decodeIfPresent(Bool.self, forKey: .bot) ?? false
        protected = try c.decodeIfPresent(Bool.self, forKey: .protected) ?? false
        spawnProtected = try c.decodeIfPresent(Bool.self, forKey: .spawnProtected) ?? false
        ack = try c.decodeIfPresent(UInt64.self, forKey: .ack) ?? 0
        ackSteps = try c.decodeIfPresent(UInt32.self, forKey: .ackSteps) ?? 0
        spawnSerial = try c.decodeIfPresent(Int.self, forKey: .spawnSerial) ?? 0
        track = try c.decodeIfPresent(Double.self, forKey: .track) ?? 0
        recoil = try c.decodeIfPresent(Double.self, forKey: .recoil) ?? 0
        cooldown = try c.decodeIfPresent(Double.self, forKey: .cooldown) ?? 0
        cooldownTotal = try c.decodeIfPresent(Double.self, forKey: .cooldownTotal) ?? 0
        invulnerable = try c.decodeIfPresent(Double.self, forKey: .invulnerable) ?? 0
        powerTime = try c.decodeIfPresent(Double.self, forKey: .powerTime) ?? 0
        shield = try c.decodeIfPresent(Double.self, forKey: .shield) ?? 0
        speedTime = try c.decodeIfPresent(Double.self, forKey: .speedTime) ?? 0
        ghostTime = try c.decodeIfPresent(Double.self, forKey: .ghostTime) ?? 0
        starmanTime = try c.decodeIfPresent(Double.self, forKey: .starmanTime) ?? 0
        respawnTime = try c.decodeIfPresent(Double.self, forKey: .respawnTime) ?? 0
        grenadeLife = try c.decodeIfPresent(Double.self, forKey: .grenadeLife) ?? 0
        power = try c.decodeIfPresent(String.self, forKey: .power) ?? ""
        charges = try c.decodeIfPresent(Int.self, forKey: .charges) ?? 0
        machineRounds = try c.decodeIfPresent(Int.self, forKey: .machineRounds) ?? 0
        shieldCharges = try c.decodeIfPresent(Int.self, forKey: .shieldCharges) ?? 0
        speedStacks = try c.decodeIfPresent(Int.self, forKey: .speedStacks) ?? 0
        ammoUsed = try c.decodeIfPresent(Int.self, forKey: .ammoUsed) ?? 0
        grenades = try c.decodeIfPresent(Int.self, forKey: .grenades) ?? 0
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        killedBy = try c.decodeIfPresent(String.self, forKey: .killedBy) ?? ""
        killedByColor = try c.decodeIfPresent(String.self, forKey: .killedByColor) ?? ""
        survivalEnemy = try c.decodeIfPresent(Bool.self, forKey: .survivalEnemy) ?? false
        survivalBoss = try c.decodeIfPresent(Bool.self, forKey: .survivalBoss) ?? false
        difficulty = try c.decodeIfPresent(String.self, forKey: .difficulty) ?? "normal"
    }
}

public struct ArenaBullet: Codable, Equatable, Sendable {
    public var id: Int = 0
    public var x: Double = 0
    public var y: Double = 0
    public var vx: Double = 0
    public var vy: Double = 0
    public var owner: Int = 0
    public var kind: String = ""
    public var colorIndex: Int = 0
    public var life: Double = 0
    public var bounces: Int = 0
    public var target: Int = 0

    public init(
        id: Int = 0,
        x: Double = 0,
        y: Double = 0,
        vx: Double = 0,
        vy: Double = 0,
        owner: Int = 0,
        kind: String = "",
        colorIndex: Int = 0,
        life: Double = 0,
        bounces: Int = 0,
        target: Int = 0
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
        self.owner = owner
        self.kind = kind
        self.colorIndex = colorIndex
        self.life = life
        self.bounces = bounces
        self.target = target
    }

    private enum CodingKeys: String, CodingKey {
        case id, x, y, vx, vy, owner, kind, colorIndex, life, bounces, target
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0
        vx = try c.decodeIfPresent(Double.self, forKey: .vx) ?? 0
        vy = try c.decodeIfPresent(Double.self, forKey: .vy) ?? 0
        owner = try c.decodeIfPresent(Int.self, forKey: .owner) ?? 0
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        life = try c.decodeIfPresent(Double.self, forKey: .life) ?? 0
        bounces = try c.decodeIfPresent(Int.self, forKey: .bounces) ?? 0
        target = try c.decodeIfPresent(Int.self, forKey: .target) ?? 0
    }
}

public struct ArenaPickup: Codable, Equatable, Sendable {
    public var id: Int = 0
    public var x: Double = 0
    public var y: Double = 0
    public var type: String = ""
    public var age: Double = 0
    public var life: Double = 30

    public init(
        id: Int = 0,
        x: Double = 0,
        y: Double = 0,
        type: String = "",
        age: Double = 0,
        life: Double = 30
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.type = type
        self.age = age
        self.life = life
    }

    private enum CodingKeys: String, CodingKey {
        case id, x, y, type, age, life
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        age = try c.decodeIfPresent(Double.self, forKey: .age) ?? 0
        life = try c.decodeIfPresent(Double.self, forKey: .life) ?? 30
    }
}

public struct ArenaEffect: Codable, Equatable, Sendable {
    public var id: Int = 0
    public var kind: String = ""
    public var x: Double = 0
    public var y: Double = 0
    public var owner: Int = 0
    public var points: [BeamPoint] = []
    public var player: Int?
    public var tick: Int?
    public var spawnSerial: Int?
    public var shotSerial: UInt64?
    public var flight: CannonFlight?
    public var contact: ImpactContact?

    public init(
        id: Int = 0,
        kind: String = "",
        x: Double = 0,
        y: Double = 0,
        owner: Int = 0,
        points: [BeamPoint] = [],
        player: Int? = nil,
        tick: Int? = nil,
        spawnSerial: Int? = nil,
        shotSerial: UInt64? = nil,
        flight: CannonFlight? = nil,
        contact: ImpactContact? = nil
    ) {
        self.id = id
        self.kind = kind
        self.x = x
        self.y = y
        self.owner = owner
        self.points = points
        self.player = player
        self.tick = tick
        self.spawnSerial = spawnSerial
        self.shotSerial = shotSerial
        self.flight = flight
        self.contact = contact
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, x, y, owner, points, player, tick, spawnSerial, shotSerial, flight, contact
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0
        owner = try c.decodeIfPresent(Int.self, forKey: .owner) ?? 0
        points = try c.decodeIfPresent([BeamPoint].self, forKey: .points) ?? []
        player = try c.decodeIfPresent(Int.self, forKey: .player)
        tick = try c.decodeIfPresent(Int.self, forKey: .tick)
        spawnSerial = try c.decodeIfPresent(Int.self, forKey: .spawnSerial)
        shotSerial = try c.decodeIfPresent(UInt64.self, forKey: .shotSerial)
        flight = try c.decodeIfPresent(CannonFlight.self, forKey: .flight)
        contact = try c.decodeIfPresent(ImpactContact.self, forKey: .contact)
    }
}

public struct LeaderboardEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: Int = 0
    public var name: String = ""
    public var score: Int = 0
    public var colorIndex: Int = 0
    public var bot: Bool = false
    public var team: Int = 0

    public init(
        id: Int = 0,
        name: String = "",
        score: Int = 0,
        colorIndex: Int = 0,
        bot: Bool = false,
        team: Int = 0
    ) {
        self.id = id
        self.name = name
        self.score = score
        self.colorIndex = colorIndex
        self.bot = bot
        self.team = team
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, score, colorIndex, bot, team
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        score = try c.decodeIfPresent(Int.self, forKey: .score) ?? 0
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        bot = try c.decodeIfPresent(Bool.self, forKey: .bot) ?? false
        team = try c.decodeIfPresent(Int.self, forKey: .team) ?? 0
    }
}

public struct ArenaWorld: Codable, Equatable, Sendable {
    public var width: Double = 0
    public var height: Double = 0
    public var cols: Int = 0
    public var rows: Int = 0
    public var walls: [MazeWall] = []

    public init(
        width: Double = 0,
        height: Double = 0,
        cols: Int = 0,
        rows: Int = 0,
        walls: [MazeWall] = []
    ) {
        self.width = width
        self.height = height
        self.cols = cols
        self.rows = rows
        self.walls = walls
    }

    private enum CodingKeys: String, CodingKey {
        case width, height, cols, rows, walls
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 0
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? 0
        cols = try c.decodeIfPresent(Int.self, forKey: .cols) ?? 0
        rows = try c.decodeIfPresent(Int.self, forKey: .rows) ?? 0
        walls = try c.decodeIfPresent([MazeWall].self, forKey: .walls) ?? []
    }
}

public struct ArenaSnapshot: Codable, Equatable, Sendable {
    public var spectating = false
    public var following: Int?
    public var godlikeSpawns: [GodlikeSpawn] = []
    public var rules: RoomRules?
    public var matchStats: NativeMatchReport?
    public var boostedBulletIds: [Int] = []
    public var generation: Int = 0
    public var objectives: ArenaObjectives?
    public var result: ArenaResult?
    public var teamScores: [Int] = []
    public var type: String = "state"
    public var tick: UInt64 = 0
    public var tanks: [ArenaTank] = []
    public var bullets: [ArenaBullet] = []
    public var pickups: [ArenaPickup] = []
    public var effects: [ArenaEffect] = []
    public var leaderboard: [LeaderboardEntry] = []
    public var players: Int = 0
    public var tankCount: Int = 0
    public var world: ArenaWorld? = nil
    public var phase: String = "playing"
    public var phaseTime: Double = 0
    public var roundClock: Double = 0
    public var round: Int = 0
    public var scores: [Int] = []
    public var winner: Int = -1

    public init(
        type: String = "state",
        tick: UInt64 = 0,
        tanks: [ArenaTank] = [],
        bullets: [ArenaBullet] = [],
        pickups: [ArenaPickup] = [],
        effects: [ArenaEffect] = [],
        leaderboard: [LeaderboardEntry] = [],
        players: Int = 0,
        tankCount: Int = 0,
        world: ArenaWorld? = nil,
        phase: String = "playing",
        phaseTime: Double = 0,
        roundClock: Double = 0,
        round: Int = 0,
        scores: [Int] = [],
        winner: Int = -1
    ) {
        self.type = type
        self.tick = tick
        self.tanks = tanks
        self.bullets = bullets
        self.pickups = pickups
        self.effects = effects
        self.leaderboard = leaderboard
        self.players = players
        self.tankCount = tankCount
        self.world = world
        self.phase = phase
        self.phaseTime = phaseTime
        self.roundClock = roundClock
        self.round = round
        self.scores = scores
        self.winner = winner
    }

    private enum CodingKeys: String, CodingKey {
        case spectating, following, godlikeSpawns, rules, matchStats, boostedBulletIds, generation, objectives, result, teamScores, type, tick, tanks, bullets, pickups, effects, leaderboard, players, tankCount, world, phase, phaseTime, roundClock, round, scores, winner
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spectating = try c.decodeIfPresent(Bool.self, forKey: .spectating) ?? false
        following = try c.decodeIfPresent(Int.self, forKey: .following)
        godlikeSpawns = Array((try c.decodeIfPresent([GodlikeSpawn].self, forKey: .godlikeSpawns) ?? []).prefix(64))
        rules = try c.decodeIfPresent(RoomRules.self, forKey: .rules)
        matchStats = try c.decodeIfPresent(NativeMatchReport.self, forKey: .matchStats)
        boostedBulletIds = try c.decodeIfPresent([Int].self, forKey: .boostedBulletIds) ?? []
        generation = try c.decodeIfPresent(Int.self, forKey: .generation) ?? 0
        objectives = try c.decodeIfPresent(ArenaObjectives.self, forKey: .objectives)
        result = try c.decodeIfPresent(ArenaResult.self, forKey: .result)
        teamScores = try c.decodeIfPresent([Int].self, forKey: .teamScores) ?? []
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "state"
        tick = try c.decodeIfPresent(UInt64.self, forKey: .tick) ?? 0
        tanks = try c.decodeIfPresent([ArenaTank].self, forKey: .tanks) ?? []
        bullets = try c.decodeIfPresent([ArenaBullet].self, forKey: .bullets) ?? []
        pickups = try c.decodeIfPresent([ArenaPickup].self, forKey: .pickups) ?? []
        effects = try c.decodeIfPresent([ArenaEffect].self, forKey: .effects) ?? []
        leaderboard = try c.decodeIfPresent([LeaderboardEntry].self, forKey: .leaderboard) ?? []
        players = try c.decodeIfPresent(Int.self, forKey: .players) ?? 0
        tankCount = try c.decodeIfPresent(Int.self, forKey: .tankCount) ?? 0
        world = try c.decodeIfPresent(ArenaWorld.self, forKey: .world)
        phase = try c.decodeIfPresent(String.self, forKey: .phase) ?? "playing"
        phaseTime = try c.decodeIfPresent(Double.self, forKey: .phaseTime) ?? 0
        roundClock = try c.decodeIfPresent(Double.self, forKey: .roundClock) ?? 0
        round = try c.decodeIfPresent(Int.self, forKey: .round) ?? 0
        scores = try c.decodeIfPresent([Int].self, forKey: .scores) ?? []
        winner = try c.decodeIfPresent(Int.self, forKey: .winner) ?? -1
    }
}

public struct ArenaFlag: Codable, Equatable, Sendable {
    public var team: Int = 0
    public var homeX: Double = 0
    public var homeY: Double = 0
    public var x: Double = 0
    public var y: Double = 0
    public var carrier: Int = -1
    public var home: Bool = true
    public var returnIn: Double = 0
    public init(team: Int = 0, homeX: Double = 0, homeY: Double = 0, x: Double = 0, y: Double = 0, carrier: Int = -1, home: Bool = true, returnIn: Double = 0) {
        self.team = team
        self.homeX = homeX
        self.homeY = homeY
        self.x = x
        self.y = y
        self.carrier = carrier
        self.home = home
        self.returnIn = returnIn
    }
    private enum CodingKeys: String, CodingKey { case team, homeX, homeY, x, y, carrier, home, returnIn }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        team = try c.decodeIfPresent(Int.self, forKey: .team) ?? 0
        homeX = try c.decodeIfPresent(Double.self, forKey: .homeX) ?? 0
        homeY = try c.decodeIfPresent(Double.self, forKey: .homeY) ?? 0
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0
        carrier = try c.decodeIfPresent(Int.self, forKey: .carrier) ?? -1
        home = try c.decodeIfPresent(Bool.self, forKey: .home) ?? true
        returnIn = try c.decodeIfPresent(Double.self, forKey: .returnIn) ?? 0
    }
}

public struct ArenaSurvival: Codable, Equatable, Sendable {
    public var wave: Int = 0
    public var wavesCleared: Int = 0
    public var waveTarget: Int = 0
    public var enemiesRemaining: Int = 0
    public var boss: Bool = false
    public var breakTime: Double = 0
    public var status: String = ""
    public init(wave: Int = 0, wavesCleared: Int = 0, waveTarget: Int = 0, enemiesRemaining: Int = 0, boss: Bool = false, breakTime: Double = 0, status: String = "") {
        self.wave = wave
        self.wavesCleared = wavesCleared
        self.waveTarget = waveTarget
        self.enemiesRemaining = enemiesRemaining
        self.boss = boss
        self.breakTime = breakTime
        self.status = status
    }
    private enum CodingKeys: String, CodingKey { case wave, wavesCleared, waveTarget, enemiesRemaining, boss, breakTime, status }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wave = try c.decodeIfPresent(Int.self, forKey: .wave) ?? 0
        wavesCleared = try c.decodeIfPresent(Int.self, forKey: .wavesCleared) ?? 0
        waveTarget = try c.decodeIfPresent(Int.self, forKey: .waveTarget) ?? 0
        enemiesRemaining = try c.decodeIfPresent(Int.self, forKey: .enemiesRemaining) ?? 0
        boss = try c.decodeIfPresent(Bool.self, forKey: .boss) ?? false
        breakTime = try c.decodeIfPresent(Double.self, forKey: .breakTime) ?? 0
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
    }
}

public struct ArenaObjectives: Codable, Equatable, Sendable {
    public var mode: String = ""
    public var flags: [ArenaFlag] = []
    public var hillX: Double = 0
    public var hillY: Double = 0
    public var radius: Double = 32
    public var owner: Int = 0
    public var contested: Bool = false
    public var hold: Double = 0
    public var suddenDeath: Bool = false
    public var survival: ArenaSurvival? = nil
    public init(mode: String = "", flags: [ArenaFlag] = [], hillX: Double = 0, hillY: Double = 0, radius: Double = 32, owner: Int = 0, contested: Bool = false, hold: Double = 0, suddenDeath: Bool = false, survival: ArenaSurvival? = nil) {
        self.mode = mode
        self.flags = flags
        self.hillX = hillX
        self.hillY = hillY
        self.radius = radius
        self.owner = owner
        self.contested = contested
        self.hold = hold
        self.suddenDeath = suddenDeath
        self.survival = survival
    }
    private enum CodingKeys: String, CodingKey { case mode, flags, hillX, hillY, radius, owner, contested, hold, suddenDeath, survival }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? ""
        flags = try c.decodeIfPresent([ArenaFlag].self, forKey: .flags) ?? []
        hillX = try c.decodeIfPresent(Double.self, forKey: .hillX) ?? 0
        hillY = try c.decodeIfPresent(Double.self, forKey: .hillY) ?? 0
        radius = try c.decodeIfPresent(Double.self, forKey: .radius) ?? 32
        owner = try c.decodeIfPresent(Int.self, forKey: .owner) ?? 0
        contested = try c.decodeIfPresent(Bool.self, forKey: .contested) ?? false
        hold = try c.decodeIfPresent(Double.self, forKey: .hold) ?? 0
        suddenDeath = try c.decodeIfPresent(Bool.self, forKey: .suddenDeath) ?? false
        survival = try c.decodeIfPresent(ArenaSurvival.self, forKey: .survival)
    }
}

public struct ArenaResult: Codable, Equatable, Sendable {
    public var id: Int = 0
    public var name: String = ""
    public var team: Int = 0
    public var score: Int = 0
    public init(id: Int = 0, name: String = "", team: Int = 0, score: Int = 0) {
        self.id = id
        self.name = name
        self.team = team
        self.score = score
    }
    private enum CodingKeys: String, CodingKey { case id, name, team, score }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        team = try c.decodeIfPresent(Int.self, forKey: .team) ?? 0
        score = try c.decodeIfPresent(Int.self, forKey: .score) ?? 0
    }
}
