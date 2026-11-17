import XCTest
@testable import leqraCore

final class ShowcaseSceneTests: XCTestCase {
    func testExplicitHeroTargetRemainsDistinctFromUntargetedProjectile() throws {
        let data = Data(#"{"seed":1,"time":0,"localID":0,"bullets":[{"id":1,"target":0},{"id":2,"target":null}],"effects":[]}"#.utf8)
        let scene = try JSONDecoder().decode(ShowcaseScene.self, from: data)
        XCTAssertEqual(scene.snapshot.bullets.map(\.target), [0, -1])
    }

    func testOrientationSelectsSeparateCanonicalSceneAndMetadata() throws {
        let data = Data(#"{"seed":1,"time":10,"localID":0,"fps":120,"ping":8,"tanks":[{"id":0,"name":"WIDE"}],"bullets":[],"effects":[],"portrait":{"seed":2,"time":20,"localID":0,"title":"Portrait battle","fps":60,"ping":7,"tanks":[{"id":0,"name":"PORTRAIT"},{"id":1}],"bullets":[],"effects":[]}}"#.utf8)
        let wide = try ShowcaseScene.decode(data)
        let portrait = try ShowcaseScene.decode(data, portrait: true)
        XCTAssertEqual(wide.seed, 1); XCTAssertEqual(wide.snapshot.tanks.count, 1)
        XCTAssertEqual(wide.fps, 120); XCTAssertEqual(wide.ping, 8)
        XCTAssertEqual(portrait.seed, 2); XCTAssertEqual(portrait.snapshot.tanks.count, 2)
        XCTAssertEqual(portrait.snapshot.tanks[0].name, "PORTRAIT")
        XCTAssertEqual(portrait.title, "Portrait battle")
        XCTAssertEqual(portrait.fps, 60); XCTAssertEqual(portrait.ping, 7)
    }

    func testMissingPortraitCannotSilentlyReuseWideComposition() {
        let data = Data(#"{"seed":1,"time":10,"localID":0,"bullets":[],"effects":[]}"#.utf8)
        XCTAssertThrowsError(try ShowcaseScene.decode(data, portrait: true))
        XCTAssertNoThrow(try ShowcaseScene.decode(data))
    }

    func testBundledPortraitUsesDenseAuthoredSceneAndSameHeaderMetadata() throws {
        let wide = try ShowcaseScene.load()
        let portrait = try ShowcaseScene.load(portrait: true)
        XCTAssertEqual(portrait.seed, 14383)
        XCTAssertEqual(portrait.snapshot.tanks.count, 10)
        XCTAssertEqual(portrait.snapshot.pickups.count, 4)
        XCTAssertEqual(portrait.snapshot.bullets.count, 52)
        XCTAssertEqual(portrait.snapshot.effects.count, 4)
        var equipped = Set(portrait.snapshot.tanks.filter { $0.hp > 0 && !$0.power.isEmpty }.map(\.power))
        for tank in portrait.snapshot.tanks where tank.hp > 0 {
            if tank.shield > 0 { equipped.insert("shield") }
            if tank.speedTime > 0 { equipped.insert("speed") }
            if tank.ghostTime > 0 { equipped.insert("ghost") }
            if tank.starmanTime > 0 { equipped.insert("starman") }
        }
        XCTAssertEqual(equipped, Set(["rapid", "scatter", "homing", "laser", "grenade", "cannon", "shield", "speed", "ghost", "starman"]))
        XCTAssertEqual(portrait.fps, 120); XCTAssertEqual(portrait.ping, 8)
        XCTAssertEqual(wide.fps, portrait.fps); XCTAssertEqual(wide.ping, portrait.ping)
        XCTAssertEqual(portrait.snapshot.players, 1)
        let hero = try XCTUnwrap(portrait.snapshot.tanks.first { $0.id == portrait.localID })
        XCTAssertEqual(hero.name, "aqsnow"); XCTAssertEqual(hero.x, 42); XCTAssertEqual(hero.y, 42)
        XCTAssertEqual(hero.power, "laser"); XCTAssertEqual(hero.shieldCharges, 2)
        XCTAssertTrue(portrait.snapshot.tanks.allSatisfy { abs($0.x - hero.x) <= 2 * 84 && abs($0.y - hero.y) <= 3 * 84 })
        XCTAssertTrue(portrait.snapshot.tanks.contains { $0.y <= hero.y - 250 })
        XCTAssertTrue(portrait.snapshot.tanks.contains { $0.y >= hero.y + 250 && abs($0.x - hero.x) < 42 })
        XCTAssertEqual(try ShowcaseScene.load().snapshot, wide.snapshot, "Selecting portrait must not rewrite the wide scene")
    }

    func testBundledSceneRetainsCanonicalEntitiesAndFrozenHistory() throws {
        let scene = try ShowcaseScene.load()
        XCTAssertEqual(scene.seed, 14383)
        XCTAssertEqual(scene.timeMilliseconds, 8420)
        XCTAssertEqual(scene.localID, 0)
        XCTAssertEqual(scene.snapshot.tanks.count, 8)
        XCTAssertEqual(scene.snapshot.bullets.count, 53)
        XCTAssertEqual(scene.snapshot.pickups.count, 10)
        XCTAssertEqual(scene.snapshot.effects.count, 4)
        let hero = try XCTUnwrap(scene.snapshot.tanks.first { $0.id == scene.localID })
        XCTAssertEqual(hero.x, 42); XCTAssertEqual(hero.y, 42)
        XCTAssertEqual(hero.power, "laser"); XCTAssertEqual(hero.shieldCharges, 2)
        XCTAssertEqual(Set(scene.snapshot.pickups.map(\.type)).count, 10)
        XCTAssertEqual(scene.projectiles.map(\.id), scene.snapshot.bullets.map(\.id))
        XCTAssertGreaterThan(scene.projectiles[0].trail.count, 1)
        XCTAssertEqual(Array(scene.effects.prefix(3).map(\.ageMilliseconds)), [36, 120, 105])
        let blastID = try XCTUnwrap(scene.snapshot.effects.first { $0.kind == "blast" }?.id)
        XCTAssertEqual(scene.effects.first { $0.id == blastID }?.outline.count, 24)
        XCTAssertEqual(scene.maze.seed, scene.seed)
        XCTAssertTrue(scene.snapshot.bullets.allSatisfy { $0.target == -1 }, "Null fixture targets must not become the hero's zero ID")
    }

    func testShowcaseLaserLeavesTheBarrelAndNeverReflectsThroughTheHero() throws {
        for portrait in [false, true] {
            let scene = try ShowcaseScene.load(portrait: portrait)
            let hero = try XCTUnwrap(scene.snapshot.tanks.first { $0.id == scene.localID })
            let laser = try XCTUnwrap(scene.snapshot.effects.first { $0.kind == "laser" && $0.owner == hero.id })
            XCTAssertGreaterThan(laser.points.count, 2, "The staged laser should still show reflections")
            guard laser.points.count > 2 else { continue }
            let heading = BeamPoint(x: cos(hero.angle), y: sin(hero.angle))
            let muzzle = laser.points[0]
            XCTAssertEqual(muzzle.x, hero.x + heading.x * 28, accuracy: 1e-6)
            XCTAssertEqual(muzzle.y, hero.y + heading.y * 28, accuracy: 1e-6)
            let first = laser.points[1]
            let dx = first.x - muzzle.x, dy = first.y - muzzle.y
            XCTAssertGreaterThan(dx * heading.x + dy * heading.y, 0, "The first segment must travel forward from the barrel")
            XCTAssertEqual(dx * heading.y - dy * heading.x, 0, accuracy: 1e-6)
            for index in 1..<(laser.points.count - 1) {
                let distance = segmentDistance(from: laser.points[index], to: laser.points[index + 1], tank: hero)
                XCTAssertGreaterThanOrEqual(distance, 30 - 1e-6, "Reflected segment \(index) returns through the hero in \(portrait ? "portrait" : "wide") Showcase")
            }
        }
    }

    func testShowcaseLaserDestroysExactlyOneTankAndClearsEveryOtherTank() throws {
        for portrait in [false, true] {
            let scene = try ShowcaseScene.load(portrait: portrait)
            let victims = scene.snapshot.tanks.filter { $0.hp <= 0 }
            XCTAssertEqual(victims.count, 1)
            let victim = try XCTUnwrap(victims.first)
            XCTAssertNotEqual(victim.id, scene.localID)
            XCTAssertFalse(victim.name.isEmpty, "The wreck retains its callsign")
            let laser = try XCTUnwrap(scene.snapshot.effects.first { $0.kind == "laser" && $0.owner == scene.localID })
            XCTAssertGreaterThan(laser.points.count, 2)
            let explosion = try XCTUnwrap(scene.snapshot.effects.first { $0.kind == "hit" && $0.owner == victim.id })
            XCTAssertEqual(explosion.x, victim.x, accuracy: 1e-6)
            XCTAssertEqual(explosion.y, victim.y, accuracy: 1e-6)
            for tank in scene.snapshot.tanks where tank.id != scene.localID {
                let clearance = zip(laser.points, laser.points.dropFirst()).map { segmentDistance(from: $0, to: $1, tank: tank) }.min() ?? .infinity
                if tank.id == victim.id {
                    XCTAssertLessThanOrEqual(clearance, 20, "The laser must hit the displayed wreck")
                } else {
                    XCTAssertGreaterThan(tank.hp, 0)
                    XCTAssertGreaterThanOrEqual(clearance, 30 - 1e-6, "The staged laser must clear \(tank.name)")
                }
            }
        }
    }

    func testShowcaseRetainsExtendedCannonHistory() throws {
        for portrait in [false, true] {
            let scene = try ShowcaseScene.load(portrait: portrait)
            let cannonIDs = Set(scene.snapshot.bullets.filter { $0.kind == "cannon" }.map(\.id))
            let trails = scene.projectiles.filter { cannonIDs.contains($0.id) }.map(\.trail)
            XCTAssertFalse(trails.isEmpty)
            XCTAssertTrue(trails.allSatisfy { $0.count > 7 }, "Frozen Cannon trails should retain more history than a live seven-frame trail")
            for trail in trails {
                let length = zip(trail, trail.dropFirst()).reduce(0.0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
                XCTAssertGreaterThan(length, 120)
            }
        }
    }

    private func segmentDistance(from: BeamPoint, to: BeamPoint, tank: ArenaTank) -> Double {
        let dx = to.x - from.x, dy = to.y - from.y
        let lengthSquared = dx * dx + dy * dy
        let projection = lengthSquared > 0 ? ((tank.x - from.x) * dx + (tank.y - from.y) * dy) / lengthSquared : 0
        let fraction = max(0, min(1, projection))
        return hypot(from.x + dx * fraction - tank.x, from.y + dy * fraction - tank.y)
    }
}
