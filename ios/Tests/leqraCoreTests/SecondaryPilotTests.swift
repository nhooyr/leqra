import XCTest

@testable import leqraCore

final class SecondaryPilotTests: XCTestCase {
    private let second = NativeSeatSpec(kind: "local", name: "WING", team: 2, colorIndex: 3)
    private let world = ArenaWorld(width: 840, height: 504, cols: 10, rows: 6)

    private func practice() -> PracticeArena {
        let game = PracticeArena(
            seed: 42, name: "PRIMARY", colorIndex: 0, botCount: 0,
            world: world, secondaryPlayer: second)
        game.snapshot.tanks[0].x = 200
        game.snapshot.tanks[0].y = 200
        game.snapshot.tanks[1].x = 600
        game.snapshot.tanks[1].y = 200
        for i in game.snapshot.tanks.indices {
            game.snapshot.tanks[i].angle = 0
            game.snapshot.tanks[i].invulnerable = 0
            game.snapshot.tanks[i].spawnProtected = false
        }
        var rules = RoomRules()
        rules.pickupRate = "off"
        game.configure(rules: rules)
        return game
    }

    func testSecondaryIsExplicitAndAuthoredRosterReservesItsSeat() {
        let solo = PracticeArena(seed: 42, name: "PRIMARY", colorIndex: 0, botCount: 0)
        XCTAssertNil(solo.secondaryLocalID)
        XCTAssertEqual(solo.snapshot.players, 1)
        let paired = PracticeArena(
            seed: 42, name: "PRIMARY", colorIndex: 0, botCount: 99, secondaryPlayer: second)
        XCTAssertEqual(paired.secondaryLocalID, 2)
        XCTAssertEqual(paired.snapshot.players, 2)
        XCTAssertEqual(paired.snapshot.tanks.count, 8)
        XCTAssertEqual(paired.snapshot.tanks[1].name, "WING")
        XCTAssertFalse(paired.snapshot.tanks[1].bot)
        XCTAssertEqual(paired.snapshot.tanks[1].colorIndex, 3)
        XCTAssertEqual(paired.snapshot.tanks.filter(\.bot).map(\.id), Array(3...8))
    }

    func testPracticeInputsMoveAndFireOnlyTheirOwnPilot() {
        let game = practice()
        game.step(
            input: GameInput(forward: true, fire: true), secondaryInput: GameInput(reverse: true), dt: 1 / 60)
        XCTAssertGreaterThan(game.snapshot.tanks[0].x, 200)
        XCTAssertLessThan(game.snapshot.tanks[1].x, 600)
        XCTAssertEqual(Set(game.snapshot.bullets.map(\.owner)), [1])
        let before = game.snapshot.tanks[1].x
        game.step(input: GameInput(forward: true), dt: 1 / 60)
        XCTAssertEqual(game.snapshot.tanks[1].x, before)
        game.step(input: GameInput(), secondaryInput: GameInput(fire: true), dt: 1 / 60)
        XCTAssertEqual(Set(game.snapshot.bullets.map(\.owner)), [1, 2])
    }

    func testPracticePresentationHasIndependentLocalMotionAndDoesNotMutateAuthority() {
        let game = practice()
        let authority = game.snapshot
        let shown = game.presentationSnapshot(
            fraction: 0.5, localInput: GameInput(forward: true),
            secondaryInput: GameInput(reverse: true), now: 1)
        XCTAssertGreaterThan(shown.tanks[0].x, 200)
        XCTAssertLessThan(shown.tanks[1].x, 600)
        XCTAssertEqual(game.snapshot, authority)
        let neutral = game.presentationSnapshot(
            fraction: 0.5, localInput: GameInput(), secondaryInput: GameInput(), now: 2)
        XCTAssertLessThan(abs(neutral.tanks[0].x - 200), 5)
        XCTAssertLessThan(abs(neutral.tanks[1].x - 600), 5)
    }

    func testGrenadeBanksAndReleaseLatchesAreIndependent() {
        let game = practice()
        for i in game.snapshot.tanks.indices {
            PracticeArena.applyPower(tank: &game.snapshot.tanks[i], kind: "grenade")
        }
        game.step(input: GameInput(fire: true), secondaryInput: GameInput(fire: true), dt: 1 / 60)
        XCTAssertEqual(game.snapshot.bullets.filter { $0.kind == "grenade" }.count, 2)
        game.step(input: GameInput(), secondaryInput: GameInput(fire: true), dt: 1 / 60)
        game.step(input: GameInput(fire: true), secondaryInput: GameInput(fire: true), dt: 1 / 60)
        XCTAssertEqual(game.snapshot.bullets.filter { $0.kind == "grenade" }.map(\.owner), [2])
        for _ in 0..<30 { game.step(input: GameInput(fire: true), secondaryInput: GameInput(), dt: 1 / 60) }
        XCTAssertFalse(game.snapshot.bullets.contains { $0.owner == 1 })
        game.step(input: GameInput(), secondaryInput: GameInput(), dt: 1 / 60)
        game.snapshot.tanks[0].cooldown = 0
        game.step(input: GameInput(fire: true), secondaryInput: GameInput(), dt: 1 / 60)
        XCTAssertTrue(game.snapshot.bullets.contains { $0.owner == 1 })
    }

    func testFixedP2SurvivesRoundResetAndPreservesBotConfiguration() {
        var rules = RoomRules()
        rules.teamMode = "ffa"
        let game = FixedArena(
            rules: rules, name: "PRIMARY", colorIndex: 0, botCount: 99, seed: 42,
            botNames: ["FIRST BOT"], botColors: [5], botDifficulties: ["hard"], secondaryPlayer: second)
        XCTAssertEqual(game.secondaryLocalID, 2)
        XCTAssertEqual(game.snapshot.tanks.count, 8)
        XCTAssertEqual(game.snapshot.tanks[1].name, "WING")
        XCTAssertEqual(game.snapshot.tanks[2].name, "FIRST BOT")
        XCTAssertEqual(game.snapshot.tanks[2].difficulty, "hard")
        XCTAssertEqual(game.snapshot.tanks[2].colorIndex, 5)
        game.captureFire(true, player: 2)
        for _ in 0..<10 { game.step(input: GameInput(), secondaryInput: GameInput(fire: true), dt: 0.1) }
        XCTAssertTrue(game.snapshot.bullets.isEmpty, "Countdown does not accept P2 shots")
        game.restart()
        XCTAssertEqual(game.snapshot.tanks.filter { !$0.bot }.map(\.id), [1, 2])
        XCTAssertEqual(game.snapshot.tanks[1].name, "WING")
        XCTAssertEqual(game.snapshot.tanks[2].name, "FIRST BOT")
    }

    func testSurvivalReservesTwoHumanSeatsWithoutOverlappingEnemyIDs() {
        var rules = RoomRules()
        rules.mode = "survival"
        let game = FixedArena(
            rules: rules, name: "PRIMARY", colorIndex: 0, botCount: 99, seed: 42, secondaryPlayer: second)
        let allies = game.snapshot.tanks.filter { !$0.survivalEnemy }
        XCTAssertEqual(allies.count, 4)
        XCTAssertEqual(allies.filter { !$0.bot }.map(\.id), [1, 2])
        XCTAssertTrue(allies.allSatisfy { $0.team == 1 })
        XCTAssertTrue(game.snapshot.tanks.filter(\.survivalEnemy).allSatisfy { $0.id >= 5 })
        XCTAssertEqual(Set(game.snapshot.tanks.map(\.id)).count, game.snapshot.tanks.count)
    }
    func testFixedP2FiresAndKeepsItsOwnRoundScore() {
        var rules = RoomRules()
        rules.teamMode = "ffa"
        rules.pickupRate = "off"
        let game = FixedArena(
            rules: rules, name: "PRIMARY", colorIndex: 0, botCount: 0, seed: 42, secondaryPlayer: second)
        game.captureFire(true, player: 2)
        game.captureFire(false, player: 2)
        for _ in 0..<180 { game.step(input: GameInput(), secondaryInput: GameInput(), dt: 1 / 60) }
        XCTAssertEqual(game.snapshot.phase, "playing")
        XCTAssertTrue(game.snapshot.bullets.isEmpty, "A countdown tap cannot fire on the next phase")
        game.combat.snapshot.tanks[0].invulnerable = 10
        game.combat.snapshot.tanks[1].invulnerable = 0
        game.combat.snapshot.tanks[1].spawnProtected = false
        PracticeArena.applyPower(tank: &game.combat.snapshot.tanks[1], kind: "laser")
        game.step(input: GameInput(), secondaryInput: GameInput(fire: true), dt: 1 / 60)
        XCTAssertTrue(game.snapshot.effects.contains { $0.owner == 2 && $0.kind == "laser" })
        XCTAssertFalse(game.snapshot.effects.contains { $0.owner == 1 && $0.kind.hasPrefix("shot:") })
        game.combat.snapshot.tanks[0].hp = 0
        game.step(input: GameInput(), secondaryInput: GameInput(), dt: 1 / 60)
        XCTAssertEqual(game.snapshot.scores[1], 0)
        XCTAssertEqual(game.snapshot.scores[2], 1)
        for _ in 0..<120 { game.step(input: GameInput(), secondaryInput: GameInput(), dt: 1 / 60) }
        XCTAssertEqual(game.snapshot.phase, "countdown")
        XCTAssertEqual(game.snapshot.tanks[1].name, "WING")
        XCTAssertEqual(game.snapshot.tanks[1].score, 1)
    }

}
