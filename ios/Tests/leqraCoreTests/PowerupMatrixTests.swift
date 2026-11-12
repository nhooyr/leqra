import XCTest
@testable import leqraCore

final class PowerupMatrixTests: XCTestCase {
    private let pickups = ["rapid", "scatter", "shield", "homing", "grenade", "speed", "laser", "cannon", "ghost", "starman"]
    private let weapons = ["", "rapid", "scatter", "homing", "grenade", "laser", "cannon"]
    private let profiles = ["shield5", "speed5", "ghost", "starman", "ghost-starman", "all"]
    private let maps = ["infinity", "compact", "standard", "large", "huge", "giant", "ultrawide"]

    private func makeArena(_ map: String, bots: Int = 0, world suppliedWorld: ArenaWorld? = nil) -> PracticeArena {
        var rules = RoomRules.localDefaults()
        rules.mapSize = map == "infinity" ? "compact" : map
        rules.infinity = map == "infinity"
        rules.pickupRate = "off"
        rules.weapons = []
        let world = suppliedWorld ?? (map == "infinity" ? nil : FixedArena(rules: rules, name: "MATRIX", colorIndex: 0, botCount: 0, seed: 42).world)
        let arena = PracticeArena(seed: 42, name: "MATRIX", colorIndex: 0, botCount: bots, world: world)
        arena.configure(rules: rules)
        for index in arena.snapshot.tanks.indices {
            arena.snapshot.tanks[index].spawnProtected = false
            arena.snapshot.tanks[index].invulnerable = 0
            arena.snapshot.tanks[index].protected = false
        }
        return arena
    }

    private func durations(_ arena: PracticeArena) -> (power: Double, star: Double) {
        guard let world = arena.maze.world else { return (15, 8) }
        let area = world.cols * world.rows
        return (area >= 168 ? 15 : 10, area >= 336 ? 8 : area >= 224 ? 7 : area >= 168 ? 6 : area >= 120 ? 5 : 4)
    }

    private func advance(_ arena: PracticeArena, input: GameInput = GameInput(), ticks: Int = 1) {
        for _ in 0..<ticks {
            // Isolate the selected loadout from unrelated ambient pickups.
            arena.snapshot.pickups.removeAll()
            arena.step(input: input, dt: 1 / 60)
        }
    }

    private func equip(_ tank: inout ArenaTank, weapon: String, profile: String, power: Double, star: Double) {
        if !weapon.isEmpty { PracticeArena.applyPower(tank: &tank, kind: weapon, duration: power) }
        if profile == "shield5" || profile == "all" {
            for _ in 0..<7 { PracticeArena.applyPower(tank: &tank, kind: "shield", duration: power) }
        }
        if profile == "speed5" || profile == "all" {
            for _ in 0..<7 { PracticeArena.applyPower(tank: &tank, kind: "speed", duration: power) }
        }
        if ["ghost", "ghost-starman", "all"].contains(profile) { PracticeArena.applyPower(tank: &tank, kind: "ghost", duration: power) }
        if ["starman", "ghost-starman", "all"].contains(profile) { PracticeArena.applyPower(tank: &tank, kind: "starman", starDuration: star) }
    }

    func testAllTenPickupsCollectAndExpireOnInfinityAndEveryFiniteMapSize() {
        XCTAssertEqual(Set(pickups), Set(RoomRules().weapons))
        var cases = 0
        for map in maps {
            for kind in pickups {
                let arena = makeArena(map), duration = durations(arena)
                PracticeArena.applyPower(tank: &arena.snapshot.tanks[0], kind: "cannon", duration: duration.power)
                let point = arena.snapshot.tanks[0]
                arena.snapshot.pickups = [ArenaPickup(id: 9001, x: point.x, y: point.y, type: kind)]
                arena.step(input: GameInput(), dt: 1 / 60)
                let tank = arena.snapshot.tanks[0], label = "\(map), \(kind)"
                XCTAssertFalse(arena.snapshot.pickups.contains { $0.id == 9001 }, label)
                XCTAssertTrue(arena.snapshot.effects.contains { $0.kind == "pickup" && $0.owner == 1 }, label)
                XCTAssertEqual(tank.power, ["shield", "speed", "ghost", "starman"].contains(kind) ? "cannon" : kind, label)
                switch kind {
                case "shield": XCTAssertEqual(tank.shield, duration.power); XCTAssertEqual(tank.shieldCharges, 1)
                case "speed": XCTAssertEqual(tank.speedTime, duration.power); XCTAssertEqual(tank.speedStacks, 1)
                case "ghost": XCTAssertEqual(tank.ghostTime, duration.power)
                case "starman":
                    XCTAssertEqual(tank.starmanTime, duration.star)
                    XCTAssertGreaterThanOrEqual(tank.invulnerable, duration.star)
                    XCTAssertGreaterThanOrEqual(tank.ghostTime, duration.star)
                    XCTAssertFalse(tank.spawnProtected)
                default:
                    XCTAssertEqual(tank.powerTime, duration.power)
                    XCTAssertEqual(tank.charges, ["rapid", "scatter"].contains(kind) ? 5 : 3)
                    XCTAssertEqual(tank.machineRounds, kind == "rapid" ? 180 : 0)
                }
                advance(arena, ticks: Int((kind == "starman" ? duration.star : duration.power) * 60) + 2)
                let expired = arena.snapshot.tanks[0]
                switch kind {
                case "shield": XCTAssertEqual(expired.shield, 0); XCTAssertEqual(expired.shieldCharges, 0)
                case "speed": XCTAssertEqual(expired.speedTime, 0); XCTAssertEqual(expired.speedStacks, 0)
                case "ghost": XCTAssertEqual(expired.ghostTime, 0)
                case "starman":
                    XCTAssertEqual(expired.starmanTime, 0); XCTAssertEqual(expired.invulnerable, 0)
                    XCTAssertEqual(expired.ghostTime, 0)
                    XCTAssertEqual(expired.power, "cannon")
                    XCTAssertGreaterThan(expired.powerTime, duration.power - 0.1, "Starman pauses the held weapon timer.")
                default:
                    XCTAssertEqual(expired.power, "", label)
                    XCTAssertEqual(expired.powerTime, 0); XCTAssertEqual(expired.charges, 0); XCTAssertEqual(expired.machineRounds, 0)
                }
                XCTAssertEqual(expired.hp, 1, label)
                cases += 1
            }
        }
        XCTAssertEqual(cases, 70)
    }

    func testEveryWeaponRetainsItsBehaviorWithEachBuffAndFullStack() {
        var cases = 0
        for map in ["infinity", "compact"] {
            for weapon in weapons {
                for profile in profiles {
                    let arena = makeArena(map), duration = durations(arena)
                    equip(&arena.snapshot.tanks[0], weapon: weapon, profile: profile, power: duration.power, star: duration.star)
                    let equipped = arena.snapshot.tanks[0], boosted = equipped.starmanTime > 0
                    let label = "\(map), \(weapon), \(profile)"
                    XCTAssertEqual(equipped.power, weapon, label)
                    if ["shield5", "all"].contains(profile) { XCTAssertEqual(equipped.shieldCharges, 5) }
                    if ["speed5", "all"].contains(profile) { XCTAssertEqual(equipped.speedStacks, 5) }
                    if ["ghost-starman", "all"].contains(profile) { XCTAssertEqual(equipped.ghostTime, duration.power, "Starman must not shorten Ghost.") }
                    let input = GameInput(forward: true, fire: true, touchAim: false)
                    advance(arena, input: input)
                    let tank = arena.snapshot.tanks[0]
                    XCTAssertEqual(tank.power, weapon, label)
                    XCTAssertEqual(tank.x - equipped.x, 128 * (equipped.speedStacks == 5 ? 4.25 : 1) / 60, accuracy: 1e-8, label)
                    XCTAssertEqual(tank.charges, equipped.charges - (!boosted && !weapon.isEmpty && weapon != "rapid" ? 1 : 0), label)
                    XCTAssertEqual(tank.machineRounds, equipped.machineRounds - (!boosted && weapon == "rapid" ? 1 : 0), label)
                    XCTAssertEqual(tank.ammoUsed, boosted || weapon == "laser" ? 0 : weapon == "scatter" ? 3 : 1, label)
                    XCTAssertEqual(tank.hp, 1, label)
                    XCTAssertTrue(arena.snapshot.effects.contains { $0.kind == (weapon == "laser" ? "laser" : "shot:" + weapon) }, label)
                    let authoritative = arena.snapshot
                    _ = arena.presentationSnapshot(fraction: 0.5, localInput: input)
                    XCTAssertTrue(arena.snapshot == authoritative, label)
                    cases += 1
                }
            }
        }
        XCTAssertEqual(cases, 84)
    }

    func testFullStackEveryWeaponWithBotsIsDeterministicAndBoundedInBothArenas() {
        var cases = 0
        for map in ["infinity", "compact"] {
            for weapon in weapons {
                let count = map == "infinity" ? 8 : 7
                let first = makeArena(map, bots: count), second = makeArena(map, bots: count)
                let duration = durations(first)
                for arena in [first, second] { equip(&arena.snapshot.tanks[0], weapon: weapon, profile: "all", power: duration.power, star: duration.star) }
                let initial = first.snapshot.tanks[0]
                for tick in 0..<180 {
                    let input = GameInput(seq: UInt64(tick), forward: tick % 120 < 90, right: tick % 90 >= 60,
                                          fire: weapon == "grenade" ? tick % 60 < 40 : true, touchAim: false)
                    advance(first, input: input); advance(second, input: input)
                    let tank = first.snapshot.tanks[0], label = "\(map), \(weapon), tick\(tick)"
                    XCTAssertTrue(first.snapshot == second.snapshot, label)
                    XCTAssertEqual(tank.hp, 1, label)
                    XCTAssertEqual(tank.charges, initial.charges, label)
                    XCTAssertEqual(tank.machineRounds, initial.machineRounds, label)
                    XCTAssertEqual(tank.ammoUsed, 0, label)
                    XCTAssertEqual(tank.speedStacks, 5, label)
                    XCTAssertEqual(tank.shieldCharges, 5, label)
                    XCTAssertEqual(tank.powerTime, initial.powerTime, label)
                    XCTAssertLessThanOrEqual(first.snapshot.bullets.filter { $0.owner == 1 }.count, 115, label)
                    XCTAssertTrue(tank.x.isFinite && tank.y.isFinite && tank.angle.isFinite, label)
                    if tick.isMultiple(of: 30) {
                        let state = first.snapshot
                        _ = first.presentationSnapshot(fraction: 0.5, localInput: input)
                        XCTAssertTrue(first.snapshot == state, label)
                    }
                }
                XCTAssertGreaterThan(first.snapshot.tanks[0].track, 100)
                XCTAssertEqual(first.snapshot.tanks.count, count + 1)
                cases += 1
            }
        }
        XCTAssertEqual(cases, 14)
    }

    func testSpeedFiveRespectsWallsAndGhostExpiryReturnsTheTankToSafety() throws {
        for map in ["infinity", "compact"] {
            let arena = makeArena(map)
            let wall = try XCTUnwrap(arena.maze.walls(x0: 0, y0: 0, x1: 252, y1: 252).first { $0.axis == "v" && $0.line >= 84 && $0.line <= 168 })
            let start = ArenaTank(id: 1, x: wall.x - 17.01, y: wall.y + wall.h / 2)
            arena.snapshot.tanks = [start]
            for _ in 0..<5 { PracticeArena.applyPower(tank: &arena.snapshot.tanks[0], kind: "speed") }
            advance(arena, input: GameInput(forward: true), ticks: 3)
            XCTAssertLessThan(arena.snapshot.tanks[0].x, wall.line)
            XCTAssertFalse(arena.maze.blocked(x: arena.snapshot.tanks[0].x, y: arena.snapshot.tanks[0].y, radius: 17))
            arena.snapshot.tanks[0].x = start.x; arena.snapshot.tanks[0].y = start.y
            PracticeArena.applyPower(tank: &arena.snapshot.tanks[0], kind: "ghost", duration: 0.2)
            advance(arena, input: GameInput(forward: true), ticks: 3)
            XCTAssertTrue(arena.maze.blocked(x: arena.snapshot.tanks[0].x, y: arena.snapshot.tanks[0].y, radius: 17))
            advance(arena, ticks: 12)
            XCTAssertEqual(arena.snapshot.tanks[0].ghostTime, 0)
            XCTAssertFalse(arena.maze.blocked(x: arena.snapshot.tanks[0].x, y: arena.snapshot.tanks[0].y, radius: 17))
            XCTAssertEqual(arena.snapshot.tanks[0].speedStacks, 5)
        }
    }

    func testShieldFiveAbsorbsFiveSeparatedHitsBeforeTheSixthKills() {
        for map in ["infinity", "compact"] {
            let arena = makeArena(map)
            var target = ArenaTank(id: 1, x: 23, y: 42)
            for _ in 0..<7 { PracticeArena.applyPower(tank: &target, kind: "shield") }
            var shooter = ArenaTank(id: 2, x: 61, y: 42, angle: .pi)
            shooter.invulnerable = 100
            arena.snapshot.tanks = [target, shooter]
            for hit in 1...5 {
                advance(arena, input: GameInput(fire: true))
                XCTAssertEqual(arena.snapshot.tanks[0].hp, 1, map)
                XCTAssertEqual(arena.snapshot.tanks[0].shieldCharges, 5 - hit, map)
                XCTAssertTrue(arena.snapshot.effects.contains { $0.kind == "shield" }, map)
                advance(arena, ticks: 30)
            }
            advance(arena, input: GameInput(fire: true))
            XCTAssertEqual(arena.snapshot.tanks[0].hp, 0, map)
            XCTAssertTrue(arena.snapshot.effects.contains { $0.kind == "hit" }, map)
        }
    }

    func testGrenadeRequiresNewPressToDetonateWithAndWithoutStarmanInBothArenas() {
        for map in ["infinity", "compact"] {
            for boosted in [false, true] {
                let arena = makeArena(map), duration = durations(arena)
                equip(&arena.snapshot.tanks[0], weapon: "grenade", profile: boosted ? "starman" : "ghost", power: duration.power, star: duration.star)
                advance(arena, input: GameInput(fire: true), ticks: 30)
                XCTAssertEqual(arena.snapshot.bullets.filter { $0.owner == 1 && $0.kind == "grenade" }.count, 1)
                XCTAssertFalse(arena.snapshot.effects.contains { $0.kind == "blast" })
                advance(arena)
                advance(arena, input: GameInput(fire: true))
                XCTAssertFalse(arena.snapshot.bullets.contains { $0.owner == 1 && $0.kind == "grenade" })
                XCTAssertTrue(arena.snapshot.effects.contains { $0.kind == "blast" })
                XCTAssertEqual(arena.snapshot.tanks[0].hp, 1)
                XCTAssertEqual(arena.snapshot.tanks[0].charges, boosted ? 3 : 2)
            }
        }
    }

    func testLaserContactsRespectShieldAndKeepBoostedChargesAcrossBothArenas() {
        for map in ["infinity", "compact"] {
            for boosted in [false, true] {
                for shielded in [false, true] {
                    let arena = makeArena(map), duration = durations(arena)
                    arena.snapshot.tanks[0].x = 23
                    equip(&arena.snapshot.tanks[0], weapon: "laser", profile: boosted ? "starman" : "ghost", power: duration.power, star: duration.star)
                    var target = ArenaTank(id: 2, x: 61, y: 42)
                    if shielded { PracticeArena.applyPower(tank: &target, kind: "shield") }
                    arena.snapshot.tanks.append(target)
                    advance(arena, input: GameInput(fire: true))
                    XCTAssertEqual(arena.snapshot.tanks[1].hp, shielded ? 1 : 0)
                    XCTAssertEqual(arena.snapshot.tanks[1].shieldCharges, 0)
                    XCTAssertEqual(arena.snapshot.tanks[0].charges, boosted ? 3 : 2)
                    XCTAssertEqual(arena.snapshot.tanks[0].hp, 1)
                    XCTAssertTrue(arena.snapshot.effects.contains { $0.kind == "laser" && !$0.points.isEmpty })
                }
            }
        }
    }

    func testCannonPenetratesInteriorWallsAndLivesExactlyFivePointThreeSecondsInBothArenas() throws {
        let interior = MazeWall(x: 80, y: -4, w: 8, h: 848, axis: "v", line: 84)
        let world = ArenaWorld(width: 4200, height: 840, cols: 50, rows: 10, walls: [interior])
        for map in ["infinity", "large"] {
            let arena = makeArena(map, world: map == "infinity" ? nil : world)
            PracticeArena.applyPower(tank: &arena.snapshot.tanks[0], kind: "cannon")
            advance(arena, input: GameInput(fire: true))
            let first = try XCTUnwrap(arena.snapshot.bullets.first)
            XCTAssertGreaterThan(first.x, 88)
            advance(arena, ticks: 119)
            XCTAssertGreaterThan(try XCTUnwrap(arena.snapshot.bullets.first { $0.id == first.id }).x - 42, 18 * 84)
            advance(arena, ticks: 197)
            XCTAssertTrue(arena.snapshot.bullets.contains { $0.id == first.id })
            advance(arena)
            XCTAssertFalse(arena.snapshot.bullets.contains { $0.id == first.id })
            XCTAssertEqual(arena.snapshot.tanks[0].hp, 1)
        }
    }
}
