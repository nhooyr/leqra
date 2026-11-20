import XCTest

@testable import leqraCore

final class MutualStarmanTests: XCTestCase {
    private func arena(fixed: Bool, teams: Bool = false, friendlyFire: Bool = false) -> PracticeArena {
        let arena = PracticeArena(
            seed: 42, name: "STAR A", colorIndex: 0, botCount: 0,
            world: fixed ? ArenaWorld(width: 1000, height: 1000) : nil)
        var rules = RoomRules()
        rules.infinity = !fixed
        rules.infinityRandomBots = false
        rules.pickupRate = "off"
        rules.infinityTarget = 1
        rules.teamMode = teams ? "teams" : "ffa"
        rules.friendlyFire = friendlyFire
        arena.configure(rules: rules)
        arena.snapshot.tanks = [
            ArenaTank(
                id: 1, name: "STAR A", x: 42, y: 42, score: 0, team: teams ? 1 : 0,
                spawnSerial: 1, invulnerable: 5, shield: 5, starmanTime: 5, shieldCharges: 5),
            ArenaTank(
                id: 2, name: "STAR B", x: 72, y: 42, colorIndex: 1, score: 0, team: teams ? 1 : 0,
                spawnSerial: 2, invulnerable: 5, shield: 5, starmanTime: 5, shieldCharges: 5),
        ]
        return arena
    }

    func testTouchingStarsBothDieWithMutualCreditAndNoTransientWinner() {
        for fixed in [false, true] {
            for reversed in [false, true] {
                let arena = arena(fixed: fixed)
                if reversed { arena.snapshot.tanks.reverse() }
                arena.step(input: GameInput(), dt: 1 / 60)
                XCTAssertTrue(arena.snapshot.tanks.allSatisfy { $0.hp == 0 && $0.score == 0 })
                XCTAssertEqual(arena.snapshot.tanks.first { $0.id == 1 }?.killedBy, "STAR B")
                XCTAssertEqual(arena.snapshot.tanks.first { $0.id == 2 }?.killedBy, "STAR A")
                XCTAssertNil(arena.snapshot.result, "The first temporary +1 must not end target-one Infinity")
                let hits = arena.snapshot.effects.filter { $0.kind == "hit" }
                XCTAssertEqual(hits.count, 2)
                XCTAssertEqual(Set(hits.compactMap { $0.contact?.target }), [1, 2])
                XCTAssertTrue(hits.allSatisfy { $0.contact?.before.hp == 1 })
            }
        }
    }

    func testAlliesRequireFriendlyFireForMutualStarDeaths() {
        for fixed in [false, true] {
            for friendlyFire in [false, true] {
                let arena = arena(fixed: fixed, teams: true, friendlyFire: friendlyFire)
                arena.step(input: GameInput(), dt: 1 / 60)
                XCTAssertTrue(arena.snapshot.tanks.allSatisfy { $0.hp == (friendlyFire ? 0 : 1) })
                XCTAssertTrue(arena.snapshot.tanks.allSatisfy { $0.score == 0 })
                XCTAssertNil(arena.snapshot.result)
            }
        }
    }

    func testMutualDeathsCannotContinueKillingAThirdTank() {
        for fixed in [false, true] {
            let arena = arena(fixed: fixed)
            arena.snapshot.tanks.append(ArenaTank(id: 3, name: "NEIGHBOUR", x: 57, y: 42))
            arena.step(input: GameInput(), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.tanks.map(\.hp), [0, 0, 1])
        }
    }

    func testASeparatingWallStillBlocksTwoPhasedStars() {
        let world = ArenaWorld(width: 1000, height: 1000, walls: [MazeWall(x: 56, y: 0, w: 4, h: 1000)])
        let arena = PracticeArena(seed: 42, name: "STAR A", colorIndex: 0, botCount: 0, world: world)
        arena.snapshot.tanks = [
            ArenaTank(id: 1, x: 42, y: 42, ghostTime: 5, starmanTime: 5),
            ArenaTank(id: 2, x: 72, y: 42, ghostTime: 5, starmanTime: 5),
        ]
        arena.step(input: GameInput(), dt: 1 / 60)
        XCTAssertEqual(arena.snapshot.tanks.map(\.hp), [1, 1])
    }
}
