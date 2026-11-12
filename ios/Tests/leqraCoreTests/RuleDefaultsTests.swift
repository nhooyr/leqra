import XCTest
@testable import leqraCore

final class RuleDefaultsTests: XCTestCase {
    func testFreshTouchRoomUsesCompactWithoutChangingTransportDefaults() {
        XCTAssertEqual(RoomRules().mapSize, "large")
        let rules = RoomRules.localDefaults()
        XCTAssertEqual(rules.mapSize, "compact")
        XCTAssertEqual(rules.mode, "elimination")
        let arena = FixedArena(rules: rules, name: "SNOW FOX", colorIndex: 0, botCount: 0, seed: 42)
        XCTAssertEqual(arena.world.cols, 7)
        XCTAssertEqual(arena.world.rows, 7)
        XCTAssertEqual(arena.world.width, 7 * 84)
        XCTAssertEqual(arena.world.height, 7 * 84)
    }

    func testEachModeLoadsItsWebTargetsTimersAndFormat() {
        for (mode, target, seconds, format) in [
            ("elimination", 5, 75, "ffa"), ("ctf", 3, 180, "teams"),
            ("koth", 30, 180, "ffa"), ("survival", 15, 75, "teams"),
            ("infinity", 5, 75, "ffa")
        ] {
            let rules = RoomRules.localDefaults(mode: mode)
            XCTAssertEqual(rules.scoreTarget, target, mode)
            XCTAssertEqual(rules.timeLimit, seconds, mode)
            XCTAssertEqual(rules.teamMode, format, mode)
            XCTAssertEqual(rules.infinity, mode == "infinity", mode)
            XCTAssertEqual(rules.respawnSeconds, 3, mode)
            XCTAssertEqual(rules.pickupRate, "superfast", mode)
            XCTAssertEqual(rules.weapons.count, 10, mode)
        }
    }

    func testFiniteModeSwitchRetainsRoomMapFormatAndArsenal() {
        var rules = RoomRules.localDefaults()
        rules.mapSize = "ultrawide"; rules.portraitMaze = true; rules.teamMode = "teams"
        rules.weapons = ["grenade"]; rules.pickupRate = "slow"; rules.friendlyFire = true
        rules.scoreTarget = 12; rules.timeLimit = 240
        XCTAssertEqual(rules.selectingMode("elimination"), rules)
        let hill = rules.selectingMode("koth")
        XCTAssertEqual(hill.scoreTarget, 30); XCTAssertEqual(hill.timeLimit, 180)
        XCTAssertEqual(hill.mapSize, "ultrawide"); XCTAssertTrue(hill.portraitMaze)
        XCTAssertEqual(hill.teamMode, "teams"); XCTAssertEqual(hill.weapons, ["grenade"])
        XCTAssertEqual(hill.pickupRate, "slow"); XCTAssertTrue(hill.friendlyFire)
        rules.teamMode = "ffa"
        XCTAssertEqual(rules.selectingMode("ctf").teamMode, "teams")
        XCTAssertEqual(rules.selectingMode("survival").teamMode, "teams")
    }

    func testInfinitySwitchAndRememberedProfilesKeepRoomGeometry() {
        var rules = RoomRules.localDefaults()
        rules.mapSize = "huge"; rules.portraitMaze = true; rules.teamMode = "teams"
        rules.teamNames[0] = "FOXES"; rules.teamColors[0] = 6; rules.friendlyFire = true
        rules.weapons = ["laser"]; rules.pickupRate = "off"
        let endless = rules.selectingMode("infinity")
        XCTAssertTrue(endless.infinity)
        XCTAssertEqual(endless.mapSize, "huge"); XCTAssertTrue(endless.portraitMaze)
        XCTAssertEqual(endless.teamMode, "teams"); XCTAssertEqual(endless.teamNames[0], "FOXES")
        XCTAssertEqual(endless.teamColors[0], 6); XCTAssertTrue(endless.friendlyFire)
        XCTAssertEqual(endless.weapons.count, 10)
        XCTAssertEqual(endless.selectingMode("infinity"), endless)
        let unsavedHill = endless.selectingMode("koth")
        XCTAssertEqual(unsavedHill.teamMode, "ffa")
        XCTAssertEqual(unsavedHill.weapons.count, 10)
        var saved = RoomRules.modeDefaults("koth")
        saved.mapSize = "standard"; saved.scoreTarget = 45; saved.teamMode = "teams"; saved.weapons = ["cannon"]
        let restored = endless.selectingMode("koth", remembered: saved)
        XCTAssertFalse(restored.infinity); XCTAssertEqual(restored.mode, "koth")
        XCTAssertEqual(restored.scoreTarget, 45); XCTAssertEqual(restored.teamMode, "teams")
        XCTAssertEqual(restored.weapons, ["cannon"])
        XCTAssertEqual(restored.mapSize, "huge"); XCTAssertTrue(restored.portraitMaze)
    }

    func testRestoreDefaultsRetainsMapFormatAndHiddenInfinitySettings() {
        var rules = RoomRules.localDefaults(mode: "koth")
        rules.mapSize = "giant"; rules.portraitMaze = true; rules.teamMode = "teams"
        rules.scoreTarget = 120; rules.timeLimit = 600; rules.weapons = ["ghost"]
        let finite = rules.restoringModeDefaults()
        XCTAssertEqual(finite.mapSize, "giant"); XCTAssertTrue(finite.portraitMaze)
        XCTAssertEqual(finite.teamMode, "teams")
        XCTAssertEqual(finite.scoreTarget, 30); XCTAssertEqual(finite.timeLimit, 180)
        XCTAssertEqual(finite.weapons.count, 10)
        rules.infinity = true; rules.infinityTarget = 200; rules.infinityRandomBots = true
        rules.infinityBotDifficulty = "godlike"; rules.infinityRandomDifficulty = true
        rules.teamNames[0] = "FOXES"; rules.teamColors[0] = 6; rules.friendlyFire = true
        let endless = rules.restoringModeDefaults()
        XCTAssertTrue(endless.infinity); XCTAssertEqual(endless.mapSize, "giant")
        XCTAssertTrue(endless.portraitMaze); XCTAssertEqual(endless.teamMode, "teams")
        XCTAssertEqual(endless.infinityTarget, 0); XCTAssertFalse(endless.infinityRandomBots)
        XCTAssertEqual(endless.infinityBotDifficulty, "normal"); XCTAssertFalse(endless.infinityRandomDifficulty)
        XCTAssertEqual(endless.teamNames[0], "Team 1"); XCTAssertEqual(endless.teamColors[0], 0)
        XCTAssertFalse(endless.friendlyFire)
        XCTAssertEqual(endless.scoreTarget, 120); XCTAssertEqual(endless.timeLimit, 600)
        XCTAssertEqual(endless.weapons, ["ghost"])
    }

    func testDifficultyNamesMatchMobileRoster() {
        XCTAssertEqual(BotDifficulty.allCases.map(\.displayName), ["Chill", "Normal", "Fierce", "Godlike"])
    }

    func testResetRequiredTeamModesNormalizesOldFreeForAllRules() {
        for mode in ["ctf", "survival"] {
            var rules = RoomRules(); rules.mode = mode; rules.teamMode = "ffa"
            XCTAssertEqual(rules.restoringModeDefaults().teamMode, "teams", mode)
        }
    }
}
