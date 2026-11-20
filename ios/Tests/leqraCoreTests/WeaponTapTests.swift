import XCTest

@testable import leqraCore

final class WeaponTapTests: XCTestCase {
    func testLastPowerUpChargeDoesNotFireStandardAmmoDuringATap() {
        for finite in [false, true] {
            for weapon in ["rapid", "scatter", "homing", "grenade", "laser", "cannon"] {
                for ticks in [1, 3, 6, 10] {
                    let arena = PracticeArena(
                        seed: 42, name: "TAP", colorIndex: 0, botCount: 0,
                        world: finite ? ArenaWorld(width: 1000, height: 1000) : nil)
                    var rules = RoomRules()
                    rules.infinity = !finite
                    rules.pickupRate = "off"
                    rules.infinityRandomBots = false
                    arena.configure(rules: rules)
                    arena.snapshot.tanks = [
                        ArenaTank(
                            id: 1, x: 42, y: 42, powerTime: 15,
                            power: weapon, charges: 1, machineRounds: 1, ammoEpoch: 4)
                    ]
                    arena.captureFire(true, player: 1)
                    for _ in 0..<ticks { arena.step(input: GameInput(fire: true), dt: 1 / 60) }
                    arena.captureFire(false, player: 1)
                    for _ in 0..<30 { arena.step(input: GameInput(), dt: 1 / 60) }
                    XCTAssertEqual(arena.snapshot.tanks[0].power, "", weapon)
                    XCTAssertFalse(
                        arena.snapshot.bullets.contains { $0.kind.isEmpty && $0.ammoEpoch == 5 },
                        "A single \(ticks)-tick \(weapon) tap must not fire standard ammo, finite=\(finite)")
                }
            }
        }
    }
}
