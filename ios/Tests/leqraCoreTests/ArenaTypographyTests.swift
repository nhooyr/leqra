import Foundation
import XCTest

@testable import leqraCore

final class ArenaTypographyTests: XCTestCase {
    func testIdentityAndDeathNoticeSizesMatchSharedZoomFixtures() throws {
        struct Fixture: Decodable {
            let zoom: Double
            let infinity: Bool
            let fontScale: Double
            let size: Double
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(
            contentsOf: root.appendingPathComponent("src/tests/arena-typography-fixtures.json"))
        for fixture in try JSONDecoder().decode([Fixture].self, from: data) {
            XCTAssertEqual(
                ArenaTypography.labelSize(
                    zoom: fixture.zoom, infinity: fixture.infinity, fontScale: fixture.fontScale),
                fixture.size, accuracy: 0.0001)
        }
    }

    func testDeathNoticeUsesOnlyTheVictimsRecordedKillerAndClearsOnRespawn() {
        var tank = ArenaTank(id: 1, hp: 0, killedBy: "Missing <pilot> 雪", killedByColor: "#ff83bd")
        let notice = DeathNotice(tank: tank)
        XCTAssertEqual(notice?.text, "Killed by Missing <pilot> 雪")
        XCTAssertEqual(notice?.color, "#ff83bd")
        tank.hp = 1
        XCTAssertNil(DeathNotice(tank: tank))
        tank.hp = 0
        tank.killedBy = ""
        XCTAssertNil(DeathNotice(tank: tank))
        XCTAssertNil(DeathNotice(tank: nil))
    }
}
