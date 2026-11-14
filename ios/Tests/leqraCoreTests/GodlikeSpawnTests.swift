import Foundation
import XCTest
@testable import leqraCore

final class GodlikeSpawnTests: XCTestCase {
    func testBirthIsDecodedOncePerLifeAndDoesNotReplayOnReconnect() throws {
        let data = Data(#"{"godlikeSpawns":[{"id":99,"spawnSerial":7,"name":"Bot 3 - Godlike"}]}"#.utf8)
        let value = try JSONDecoder().decode(ArenaSnapshot.self, from: data)
        var notices = GodlikeSpawnNotices()
        XCTAssertTrue(notices.accept(value.godlikeSpawns, now: 10))
        XCTAssertEqual(notices.text(at: 10), "Bot 3 - Godlike spawned nearby. Watch out!")
        XCTAssertFalse(notices.accept(value.godlikeSpawns, now: 15.9))
        XCTAssertEqual(notices.text(at: 16), "")
        XCTAssertFalse(notices.accept(value.godlikeSpawns, now: 20), "Reconnect must retain life history")
        XCTAssertTrue(notices.accept([GodlikeSpawn(id: 99, spawnSerial: 8, name: "Bot 3 - Godlike")], now: 21))
        XCTAssertFalse(notices.text(at: 26.9).isEmpty); XCTAssertEqual(notices.text(at: 27), "")
        XCTAssertTrue(try JSONDecoder().decode(ArenaSnapshot.self, from: Data("{}".utf8)).godlikeSpawns.isEmpty)
    }
    func testBirthHistoryIsBoundedAndOrdinaryTanksNeverCreateNotices() {
        var notices = GodlikeSpawnNotices()
        notices.accept([], now: 0); XCTAssertTrue(notices.text(at: 0).isEmpty)
        for serial in 0..<1000 { notices.accept([GodlikeSpawn(id: 1, spawnSerial: serial, name: "Bot 1 - Godlike")], now: Double(serial)) }
        XCTAssertEqual(notices.seenCount, 256)
        notices.accept([GodlikeSpawn(id: 1, spawnSerial: -1, name: "INVALID")], now: 2000)
        XCTAssertEqual(notices.text(at: 2000), "")
    }
}
