import XCTest
@testable import leqraCore

final class PowerupHelpTests: XCTestCase {
    func testMapDescriptionsMatchRealCollectedPowerAndGroundLifetime() {
        for map in ["compact", "standard", "large", "huge", "giant", "ultrawide"] {
            var rules = RoomRules.localDefaults(); rules.mapSize = map; rules.pickupRate = "normal"
            let world = FixedArena(rules: rules, name: "HELP", colorIndex: 0, botCount: 0, seed: 17).world
            let help = PowerupHelp(rules: rules, world: world)
            let arena = PracticeArena(seed: 17, name: "HELP", colorIndex: 0, botCount: 0, world: world)
            arena.configure(rules: rules)
            let tank = arena.snapshot.tanks[0]
            arena.snapshot.pickups = [ArenaPickup(id: 9001, x: tank.x, y: tank.y, type: "ghost")]
            arena.step(input: GameInput(), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.tanks[0].ghostTime, Double(help.powerDuration), map)
            arena.snapshot.pickups = [ArenaPickup(id: 9002, x: tank.x, y: tank.y, type: "starman")]
            arena.step(input: GameInput(), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.tanks[0].starmanTime, Double(help.starDuration), map)
            arena.snapshot.pickups.removeAll(); arena.seedFixedPickups(count: 1)
            XCTAssertEqual(arena.snapshot.pickups.first?.life, Double(help.groundLifetime), map)
        }
    }
    func testInfinityIgnoresFiniteFrequencyAndAllowedTypes() {
        var rules = RoomRules(); rules.infinity = true; rules.pickupRate = "off"; rules.weapons = []; rules.mapSize = "compact"
        let help = PowerupHelp(rules: rules)
        XCTAssertTrue(help.spawningEnabled); XCTAssertEqual(help.enabledKinds.count, 10)
        XCTAssertEqual(help.powerDuration, 15); XCTAssertEqual(help.starDuration, 8); XCTAssertEqual(help.groundLifetime, 30)
        XCTAssertFalse(help.description(for: "laser").contains("Disabled"))
        XCTAssertTrue(help.description(for: "rapid").contains("18 maze cells"))
    }
    func testGrenadeControlsAreOptIn() {
        let help = PowerupHelp(rules: .localDefaults())
        let description = help.description(for: "grenade")
        let tip = " Press Fire again to detonate early. Release Fire before throwing another grenade."
        XCTAssertTrue(description.contains("explodes on tank impact or after its 10-second fuse"))
        XCTAssertFalse(description.contains("Fire"))
        XCTAssertEqual(help.description(for: "grenade", includeGrenadeControls: true), description + tip)
    }
    func testDraftRulesDescribeDisabledTypesAndCurrentFrequency() {
        var rules = RoomRules(); rules.infinity = false; rules.pickupRate = "slow"; rules.weapons = ["laser"]
        let help = PowerupHelp(rules: rules)
        XCTAssertTrue(help.summary.contains("1 of 10")); XCTAssertTrue(help.summary.contains("7–10"))
        XCTAssertTrue(help.description(for: "grenade").hasPrefix("Disabled in this room."))
        XCTAssertFalse(help.description(for: "laser").contains("Disabled"))
        rules.pickupRate = "off"
        XCTAssertTrue(PowerupHelp(rules: rules).summary.contains("spawning is off"))
    }
}
