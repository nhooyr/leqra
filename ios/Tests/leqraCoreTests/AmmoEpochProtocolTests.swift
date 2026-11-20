import Foundation
import XCTest

@testable import leqraCore

final class AmmoEpochProtocolTests: XCTestCase {
    func testLegacyEpochDefaultsAndNonnegativeIntegerRoundTrips() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(ArenaTank.self, from: Data("{}".utf8)).ammoEpoch, 0)
        XCTAssertEqual(try decoder.decode(ArenaBullet.self, from: Data("{}".utf8)).ammoEpoch, 0)
        let value = ArenaTank.maximumAmmoEpoch
        XCTAssertEqual(
            try decoder.decode(ArenaTank.self, from: JSONEncoder().encode(ArenaTank(ammoEpoch: value)))
                .ammoEpoch, value)
        XCTAssertEqual(
            try decoder.decode(ArenaBullet.self, from: JSONEncoder().encode(ArenaBullet(ammoEpoch: value)))
                .ammoEpoch, value)
        for bad in ["-1", "1.5", "true", "\"1\""] {
            XCTAssertThrowsError(
                try decoder.decode(ArenaTank.self, from: Data("{\"ammoEpoch\":\(bad)}".utf8)))
            XCTAssertThrowsError(
                try decoder.decode(ArenaBullet.self, from: Data("{\"ammoEpoch\":\(bad)}".utf8)))
        }
        XCTAssertEqual(ArenaTank.nextAmmoEpoch(value), 1)
    }

    private func fixed(epochs: Any? = nil, tankEpoch: UInt64 = 7) throws -> ArenaSnapshot {
        let rows: [[Double]] = [
            [10, 0, 42, 42, 60, 42, 846, 0, 0, 1, 0, 0], [11, 0, 42, 42, 80, 42, 846, 0, 0, 1, 0, 0],
        ]
        XCTAssertTrue(rows.allSatisfy { $0.count == 12 })
        var object: [String: Any] = [
            "phase": "playing", "tick": 2,
            "tanks": [["id": 0, "alive": true, "name": "PILOT", "power": "rapid", "ammoEpoch": tankEpoch]],
            "bullets": [["id": 9, "owner": 0, "ammoEpoch": 6]], "machineBullets": rows,
        ]
        object["machineAmmoEpochs"] = epochs
        let result = try SnapshotDecoder.normalized(
            data: JSONSerialization.data(withJSONObject: object), previousWorld: nil)
        return try JSONDecoder().decode(ArenaSnapshot.self, from: result.data)
    }

    func testCompactRapidTuplesStayTwelveWideWithOptionalParallelEpochs() throws {
        let state = try fixed(epochs: [7])
        XCTAssertEqual(state.bullets.map(\.ammoEpoch), [6, 7, 0])
        XCTAssertEqual(
            state.bullets.map(\.id), [9, 10, 11], "Older magazines remain visible in their original order")
        XCTAssertEqual(state.tanks.first?.ammoUsed, 1)
        let legacy = try fixed(tankEpoch: 0)
        XCTAssertEqual(legacy.bullets.suffix(2).map(\.ammoEpoch), [0, 0])
        XCTAssertEqual(legacy.tanks.first?.ammoUsed, 2)
        for bad: [Any] in [[-1], [1.5], [true], ["7"]] { XCTAssertThrowsError(try fixed(epochs: bad)) }
    }

    func testFixedPacketsRetainFinalGrenadeControlWithoutChargingTheFreshMagazine() throws {
        for retained: UInt64 in [0, 7, ArenaTank.maximumAmmoEpoch] {
            let fresh = ArenaTank.nextAmmoEpoch(retained)
            let object: [String: Any] = [
                "phase": "playing", "tick": 2,
                "tanks": [
                    ["id": 0, "alive": true, "power": "", "ammoEpoch": fresh, "grenadeEpoch": retained]
                ],
                "bullets": [["id": 9, "owner": 0, "kind": "grenade", "ammoEpoch": retained, "life": 1.8]],
            ]
            let result = try SnapshotDecoder.normalized(
                data: JSONSerialization.data(withJSONObject: object), previousWorld: nil)
            let state = try JSONDecoder().decode(ArenaSnapshot.self, from: result.data)
            let tank = try XCTUnwrap(state.tanks.first)
            XCTAssertEqual(tank.grenadeEpoch, retained)
            XCTAssertEqual(tank.grenades, 1)
            XCTAssertEqual(tank.grenadeLife, 1.8)
            XCTAssertEqual(tank.ammoUsed, 0)
            var delayed = state
            delayed.bullets = []
            let readout = PilotReadout(tank: tank, snapshot: delayed, infinity: false)
            XCTAssertEqual(readout.available, 5)
            XCTAssertEqual(readout.fireLabel, "BOOM")
        }
    }

    func testAuthoritativeEpochAdoptsFreshAmmoWithoutDroppingUnacknowledgedMovement() throws {
        var sent: [GameInput] = []
        let timeline = RenderTimeline(localID: 1) { tank, input, dt in if input.forward { tank.x += 120 * dt }
        }
        var state = ArenaSnapshot(
            tick: 60,
            tanks: [
                ArenaTank(
                    id: 1, x: 100, y: 42,
                    spawnSerial: 1, cooldown: 0.5, powerTime: 15, power: "cannon", charges: 1, ammoUsed: 3,
                    ammoEpoch: 3)
            ],
            bullets: (1...3).map {
                ArenaBullet(id: $0, x: 150, y: 42, owner: 1, kind: "cannon", life: 5, ammoEpoch: 3)
            })
        timeline.accept(state, at: 1)
        var before: ArenaSnapshot?
        for frame in 0..<5 {
            before = timeline.render(dt: 1 / 60, input: GameInput(forward: true), now: 1 + Double(frame) / 60)
            { sent.append($0) }
        }
        let oldX = try XCTUnwrap(before?.tanks.first?.x)
        state.tick = 62
        state.tanks[0].x = 104
        state.tanks[0].ack = try XCTUnwrap(sent.first?.seq)
        state.tanks[0].ammoEpoch = 4
        state.tanks[0].charges = 3
        state.tanks[0].ammoUsed = 0
        state.tanks[0].cooldown = 0
        state.tanks[0].cooldownTotal = 0
        timeline.accept(state, at: 1.1)
        let visible = try XCTUnwrap(
            timeline.render(dt: 1 / 120, input: GameInput(forward: true), now: 1.11) { sent.append($0) })
        let tank = try XCTUnwrap(visible.tanks.first)
        XCTAssertEqual(tank.ammoEpoch, 4)
        XCTAssertEqual(tank.charges, 3)
        XCTAssertEqual(tank.cooldown, 0)
        XCTAssertGreaterThanOrEqual(
            tank.x, oldX - 2, "Refilling cannot reset the movement prediction history")
        XCTAssertEqual(PilotReadout(tank: tank, snapshot: visible, infinity: false).available, 3)
        XCTAssertEqual(visible.bullets.count, 3, "Refill does not hide old projectiles")
    }
}
