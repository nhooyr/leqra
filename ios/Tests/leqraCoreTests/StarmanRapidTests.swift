import Foundation
import XCTest
@testable import leqraCore

final class StarmanRapidTests: XCTestCase {
    private func arena(star: Bool, world: ArenaWorld? = nil) -> PracticeArena {
        let tank = ArenaTank(id: 1, name: "RAPID", x: 42, y: 42, invulnerable: 120,
            powerTime: 15, starmanTime: star ? 8 : 0, power: "rapid", machineRounds: 180)
        let arena = PracticeArena(seed: 42, name: tank.name, colorIndex: 0, botCount: 0, world: world, initialTanks: [tank])
        var rules = RoomRules(); rules.pickupRate = "off"; arena.configure(rules: rules)
        return arena
    }

    func testOnlyEquippedRapidDoublesBornVelocityAndTotalRangeWithUnchangedRadius() throws {
        for world in [nil, ArenaWorld(width: 2016, height: 1176, cols: 24, rows: 14)] {
            let normal = arena(star: false, world: world), star = arena(star: true, world: world)
            for game in [normal, star] { game.step(input: GameInput(fire: true), dt: 1 / 60) }
            let ordinary = try XCTUnwrap(normal.snapshot.bullets.first), boosted = try XCTUnwrap(star.snapshot.bullets.first)
            XCTAssertEqual(hypot(ordinary.vx, ordinary.vy), 846, accuracy: 1e-9)
            XCTAssertEqual(hypot(boosted.vx, boosted.vy), 1692, accuracy: 1e-9)
            XCTAssertEqual(2 * ((ordinary.life + 1 / 60) * 846 + 28), (boosted.life + 1 / 60) * 1692 + 28, accuracy: 1e-8)
            XCTAssertEqual(ordinary.y, boosted.y, accuracy: 1e-9)
        }
        for power in ["", "scatter", "homing", "grenade", "cannon"] {
            let game = arena(star: true, world: ArenaWorld(width: 1000, height: 1000))
            game.snapshot.tanks[0].power = power; game.snapshot.tanks[0].charges = 3
            game.step(input: GameInput(fire: true), dt: 1 / 60)
            let shot = try XCTUnwrap(game.snapshot.bullets.first)
            XCTAssertEqual(hypot(shot.vx, shot.vy), ["": 282, "scatter": 846, "homing": 235, "grenade": 205, "cannon": 1128][power]!, accuracy: power == "grenade" ? 0.2 : 1e-8)
        }
    }

    func testHeldCadenceAndFeedbackStaySixtyHertzWithoutConsumingBoostedAmmunition() {
        for star in [false, true] {
            let game = arena(star: star, world: ArenaWorld(width: 2016, height: 1176, cols: 24, rows: 14))
            var shots = Set<Int>(), events = Set<Int>(), peak = 0
            for _ in 0..<120 {
                game.step(input: GameInput(fire: true), dt: 1 / 60)
                for shot in game.snapshot.bullets { shots.insert(shot.id) }
                for effect in game.snapshot.effects where effect.kind == "shot:rapid" { events.insert(effect.id) }
                peak = max(peak, game.snapshot.bullets.count)
            }
            XCTAssertEqual(shots.count, 120); XCTAssertEqual(events.count, 120)
            XCTAssertEqual(game.snapshot.tanks[0].machineRounds, star ? 180 : 60)
            XCTAssertEqual(game.snapshot.tanks[0].powerTime, star ? 15 : 13, accuracy: 1e-9)
            XCTAssertLessThanOrEqual(peak, 115); XCTAssertGreaterThan(peak, 100)
        }
    }

    func testExistingFastShotsKeepTheirVelocityAndTracerAfterExpiry() throws {
        let pickup = arena(star: false, world: ArenaWorld(width: 1000, height: 1000))
        pickup.step(input: GameInput(fire: true), dt: 1 / 60)
        let oldID = try XCTUnwrap(pickup.snapshot.bullets.first?.id)
        PracticeArena.applyPower(tank: &pickup.snapshot.tanks[0], kind: "starman")
        pickup.step(input: GameInput(fire: true), dt: 1 / 60)
        XCTAssertEqual(try XCTUnwrap(pickup.snapshot.bullets.first { $0.id == oldID }).vx, 846, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(pickup.snapshot.bullets.first { $0.id != oldID }).vx, 1692, accuracy: 1e-9)
        let game = arena(star: true, world: ArenaWorld(width: 1000, height: 1000))
        game.snapshot.tanks[0].starmanTime = 0.025
        game.step(input: GameInput(fire: true), dt: 1 / 60)
        let id = try XCTUnwrap(game.snapshot.bullets.first?.id)
        game.step(input: GameInput(), dt: 1 / 60)
        XCTAssertEqual(game.snapshot.tanks[0].starmanTime, 0)
        let old = try XCTUnwrap(game.snapshot.bullets.first { $0.id == id })
        XCTAssertEqual(hypot(old.vx, old.vy), 1692, accuracy: 1e-9)
        XCTAssertEqual(ProjectileAppearance.rapidTracerLength(old), 16)
        game.step(input: GameInput(fire: true), dt: 1 / 60)
        let fresh = try XCTUnwrap(game.snapshot.bullets.first { $0.id != id })
        XCTAssertEqual(hypot(fresh.vx, fresh.vy), 846, accuracy: 1e-9)
        XCTAssertEqual(ProjectileAppearance.rapidTracerLength(fresh), 8)
    }

    func testVelocitySelectsOnlyRapidTracerAndSurvivesCompactPacketNormalization() throws {
        for (vx, vy, expected) in [(846.0, 0.0, 8), (-1692, 0, 16), (0, 1692, 16), (846 / sqrt(2), 846 / sqrt(2), 8)] {
            XCTAssertEqual(ProjectileAppearance.rapidTracerLength(ArenaBullet(vx: vx, vy: vy, kind: "rapid")), expected)
            XCTAssertEqual(ProjectileAppearance.rapidTracerLength(ArenaBullet(vx: vx, vy: vy, kind: "cannon")), 0)
        }
        let wire: [String: Any] = ["phase": "playing", "tick": 2,
            "tanks": [["id": 0, "alive": true, "power": "rapid", "starmanTime": 0, "ammoEpoch": 9]], "bullets": [],
            "machineBullets": [[10, 0, 42, 42, 70, 42, 1692, 0, 0.2, 0.4, 0, 0]], "machineAmmoEpochs": [9]]
        let normalized = try SnapshotDecoder.normalized(data: JSONSerialization.data(withJSONObject: wire), previousWorld: nil)
        let state = try JSONDecoder().decode(ArenaSnapshot.self, from: normalized.data)
        XCTAssertEqual(state.bullets.first?.vx, 1692); XCTAssertEqual(state.bullets.first?.life, 0.4)
        XCTAssertEqual(ProjectileAppearance.rapidTracerLength(try XCTUnwrap(state.bullets.first)), 16)
    }

    func testFastRapidReflectsAtItsUnchangedHullAndShowsEndpointBeforeDamage() throws {
        let wall = MazeWall(x: 248, y: 0, w: 8, h: 588, axis: "v", line: 252)
        let reflected = arena(star: true, world: ArenaWorld(width: 588, height: 588, cols: 7, rows: 7, walls: [wall]))
        reflected.snapshot.tanks[0].x = 200; reflected.snapshot.tanks[0].y = 210
        reflected.step(input: GameInput(fire: true), dt: 1 / 60)
        let ricochet = try XCTUnwrap(reflected.snapshot.bullets.first)
        XCTAssertEqual(ricochet.vx, -1692, accuracy: 1e-9); XCTAssertEqual(ricochet.bounces, 1)
        XCTAssertLessThanOrEqual(ricochet.x + 3.5 / 3, wall.x)
        let maze = InfiniteMaze(world: reflected.maze.world!)
        let tailWall = try XCTUnwrap(ProjectileAppearance.rapidTailWallPoint(ricochet, maze: maze))
        XCTAssertEqual(tailWall.x, wall.x - 3.5 / 3, accuracy: 1e-8)
        var clear = ricochet; clear.x = wall.x - 18
        XCTAssertNil(ProjectileAppearance.rapidTailWallPoint(clear, maze: maze))
        clear.vx = 1692; clear.x = wall.x - 10
        XCTAssertNil(ProjectileAppearance.rapidTailWallPoint(clear, maze: maze), "An approaching shot keeps its tail in free space")
        clear.vx = -846
        XCTAssertNil(ProjectileAppearance.rapidTailWallPoint(clear, maze: maze), "Baseline8px art remains unchanged")
        for star in [false, true] {
            let game = arena(star: star, world: ArenaWorld(width: 1000, height: 1000))
            game.snapshot.tanks.append(ArenaTank(id: 2, x: 150, y: 42, spawnSerial: 1))
            var probe = ContactProbeCase(), accumulator = 0.0
            for frame in 1...120 {
                accumulator += 1 / 120
                while accumulator + 1e-9 >= 1 / 60 {
                    game.step(input: GameInput(fire: frame <= 2), dt: 1 / 60)
                    accumulator = max(0, accumulator - 1 / 60)
                }
                let shown = game.presentationSnapshot(fraction: accumulator * 60, now: Double(frame) / 120)
                probe.observe(authoritative: game.snapshot, visible: shown, dt: 1 / 120)
                if probe.result != nil { break }
            }
            XCTAssertEqual(probe.result, .passed, "star=\(star)")
        }
    }

    func testEmbeddedLaunchIncludesItsActualHiddenPathInTheBoostedTotalBudget() throws {
        let wall = MazeWall(x: 200, y: 0, w: 100, h: 600, axis: "v", line: 250)
        let fixed = arena(star: true, world: ArenaWorld(width: 1000, height: 1000, cols: 12, rows: 12, walls: [wall]))
        let infinite = arena(star: true)
        let proceduralWall = try XCTUnwrap(infinite.maze.walls(x0: 0, y0: 0, x1: 1000, y1: 1000).first { $0.axis == "v" })
        for (game, x, y, isFixed) in [(fixed, 230.0, 210.0, true),
            (infinite, proceduralWall.x + proceduralWall.w / 2, proceduralWall.y + proceduralWall.h / 2, false)] {
            game.snapshot.tanks[0].x = x; game.snapshot.tanks[0].y = y; game.snapshot.tanks[0].ghostTime = 10
            let launch = try XCTUnwrap(game.maze.launchRay(x: x, y: y, angle: 0, kind: "rapid", radius: 3.5 / 3))
            XCTAssertGreaterThan(launch.distance, isFixed ? 28 : 0)
            let hidden = launch.distance + (launch.bounced ? 0 : max(0, 28 - launch.distance))
            let expectedLife = isFixed ? (2000 - hidden) / 1692 : (2 * 18 * 84 + hidden) / 1692
            game.step(input: GameInput(fire: true), dt: 1 / 60)
            let bullet = try XCTUnwrap(game.snapshot.bullets.first)
            XCTAssertEqual(bullet.life + 1 / 60, expectedLife, accuracy: 1e-9)
        }
    }
}
