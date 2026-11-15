import XCTest
@testable import leqraCore

final class AuditConsistencyTests: XCTestCase {
    func testGhostSolidifiesBeforeEveryAttackRegardlessOfActorOrder() throws {
        let fixedWorld = ArenaWorld(width: 588, height: 588, cols: 7, rows: 7,
            walls: [MazeWall(x: 248, y: 0, w: 8, h: 588, axis: "v", line: 252)])
        for fixed in [false, true] {
            let maze = fixed ? InfiniteMaze(world: fixedWorld) : InfiniteMaze(seed: 42)
            let wall = try XCTUnwrap(maze.walls(x0: 0, y0: 0, x1: 1000, y1: 1000).first { wall in
                guard wall.axis == "v" else { return false }
                let exit = maze.phaseExit(x: wall.x + 5, y: wall.y + wall.h / 2)
                return exit.x > wall.x + wall.w + 17
            })
            let y = wall.y + wall.h / 2
            for reverse in [false, true] {
                let arena = PracticeArena(seed: 42, name: "LASER", colorIndex: 0, botCount: 0, world: fixed ? fixedWorld : nil)
                var rules = RoomRules(); rules.pickupRate = "off"; arena.configure(rules: rules)
                let shooter = ArenaTank(id: 1, x: wall.x - 50, y: y, powerTime: 10, power: "laser", charges: 3)
                let target = ArenaTank(id: 2, x: wall.x + 5, y: y, ghostTime: 1 / 120)
                arena.snapshot.tanks = reverse ? [target, shooter] : [shooter, target]
                arena.step(input: GameInput(fire: true), dt: 1 / 60)
                let survivor = try XCTUnwrap(arena.snapshot.tanks.first { $0.id == 2 })
                XCTAssertEqual(survivor.hp, 1, "Ghost expiry is global before firing, fixed=\(fixed), reverse=\(reverse)")
                XCTAssertEqual(survivor.ghostTime, 0)
                XCTAssertEqual(survivor.ammoEpoch, 1, "Ghost expiry refills exactly once")
                XCTAssertGreaterThan(survivor.x, wall.x + wall.w + 17)
            }
        }
    }

    func testGhostTimerAgesOncePerTickWhileMovementPredictionRemainsIndependent() {
        let arena = PracticeArena(seed: 42, name: "GHOST", colorIndex: 0, botCount: 0)
        arena.snapshot.tanks = [ArenaTank(id: 1, x: 42, y: 42, ghostTime: 0.025)]
        arena.step(input: GameInput(), dt: 1 / 60)
        XCTAssertEqual(arena.snapshot.tanks[0].ghostTime, 0.025 - 1 / 60, accuracy: 1e-12)
        XCTAssertEqual(arena.snapshot.tanks[0].ammoEpoch, 0)
        let shown = arena.presentationSnapshot(fraction: 0.5, localInput: GameInput())
        XCTAssertEqual(arena.snapshot.tanks[0].ghostTime, 0.025 - 1 / 60, accuracy: 1e-12)
        XCTAssertEqual(shown.tanks[0].hp, 1)
        arena.step(input: GameInput(), dt: 1 / 60)
        XCTAssertEqual(arena.snapshot.tanks[0].ghostTime, 0)
        XCTAssertEqual(arena.snapshot.tanks[0].ammoEpoch, 1)
    }

    func testInfinityPickupsServeEveryLivingHumanRatherThanTheFirstTank() {
        for firstIsBot in [false, true] {
            let arena = PracticeArena(seed: 42, name: "FIRST", colorIndex: 0, botCount: 0)
            arena.respawnsEnabled = false
            arena.snapshot.tanks = [ArenaTank(id: 1, x: 42, y: 42, hp: firstIsBot ? 1 : 0, bot: firstIsBot),
                                    ArenaTank(id: 2, x: 4242, y: 42), ArenaTank(id: 3, x: -4158, y: 42)]
            arena.step(input: GameInput(), dt: 1 / 60)
            for human in arena.snapshot.tanks where !human.bot && human.hp > 0 {
                XCTAssertEqual(arena.snapshot.pickups.filter { hypot($0.x - human.x, $0.y - human.y) < 5 * 84 }.count, 3)
            }
            XCTAssertEqual(arena.snapshot.pickups.count, 6)
        }
    }

    func testInfinityPickupMaintenanceRetainsDeadHumanAnchorsAndAgesWithoutLivingHumans() {
        let arena = PracticeArena(seed: 42, name: "DEAD", colorIndex: 0, botCount: 0)
        arena.respawnsEnabled = false
        arena.snapshot.tanks = [ArenaTank(id: 1, x: 42, y: 42, hp: 0)]
        arena.snapshot.pickups = [ArenaPickup(id: 10, x: 210, y: 42, type: "shield", life: 2),
                                  ArenaPickup(id: 11, x: 4242, y: 42, type: "speed", life: 2),
                                  ArenaPickup(id: 12, x: 42, y: 126, type: "ghost", life: 0.001)]
        arena.step(input: GameInput(), dt: 1 / 60)
        XCTAssertEqual(arena.snapshot.pickups.map(\.id), [10])
        XCTAssertEqual(arena.snapshot.pickups[0].life, 2 - 1 / 60, accuracy: 1e-12)
    }

}
