import Foundation
import XCTest
@testable import leqraCore

final class BotStandingsTests: XCTestCase {
    func testNumberedBotsKeepDifficultyInArenaButMoveItIntoLeaderboardBadge() {
        for level in ["Dumb", "Normal", "Godlike", "Easy", "Hard"] {
            let name = "Bot 17 - \(level)"
            let entry = LeaderboardEntry(id: 17, name: name, score: 9, bot: true)
            XCTAssertEqual(CallsignPolicy.displayName(name, bot: true), name)
            XCTAssertEqual(entry.displayName, "Bot 17")
            XCTAssertEqual(entry.difficultyLabel, BotDifficulty(rawValue: level.lowercased())!.displayName.uppercased())
        }
    }

    func testMetadataOverridesSuffixAndWorksForNamedRoomBots() {
        let changed = LeaderboardEntry(name: "Bot 7 - Dumb", bot: true, difficulty: "normal")
        XCTAssertEqual(changed.displayName, "Bot 7")
        XCTAssertEqual(changed.difficultyLabel, "NORMAL")
        for name in ["RUST", "BOT RUST", "Bot Rust"] {
            let entry = LeaderboardEntry(name: name, bot: true, difficulty: "hard")
            XCTAssertEqual(entry.displayName, "Bot Rust")
            XCTAssertEqual(entry.difficultyLabel, "FIERCE")
        }
        let custom = LeaderboardEntry(name: "Rust - Normal", bot: true, difficulty: "easy")
        XCTAssertEqual(custom.displayName, "Bot Rust - Normal", "Only a canonical numbered suffix moves into the badge")
        XCTAssertEqual(custom.difficultyLabel, "CHILL")
    }

    func testLegacyOrUnknownMetadataNeverInventsDifficultyOrChangesHumanIdentity() {
        for name in ["Bot 1", "RUST", "Bot 8 - Unknown"] {
            let entry = LeaderboardEntry(name: name, bot: true, difficulty: "unknown")
            XCTAssertNil(entry.difficultyLabel)
        }
        let old = LeaderboardEntry(name: "Bot 3 - Godlike", bot: true, difficulty: "unknown")
        XCTAssertEqual(old.difficultyLabel, "GODLIKE")
        for name in ["Godlike Bot 7", "Rust - Normal", "Bot 7 - Normal", "pilot#ABCD23"] {
            let human = LeaderboardEntry(name: name, bot: false, difficulty: "godlike")
            XCTAssertEqual(human.displayName, name)
            XCTAssertNil(human.difficultyLabel)
        }
    }

    func testSnapshotAndPublicPreviewDecodeDifficultyWithoutRequiringItFromOlderServers() throws {
        let decoder = JSONDecoder()
        for difficulty in [nil, "dumb", "normal", "godlike"] as [String?] {
            var record: [String: Any] = ["id": 8, "name": "Bot 8 - Normal", "score": 5, "colorIndex": 1, "bot": true, "rank": 1]
            record["difficulty"] = difficulty
            let entry = try decoder.decode(LeaderboardEntry.self, from: JSONSerialization.data(withJSONObject: record))
            XCTAssertEqual(entry.difficulty, difficulty)
            let snapshot = try decoder.decode(ArenaSnapshot.self, from: JSONSerialization.data(withJSONObject: ["leaderboard": [record]]))
            XCTAssertEqual(snapshot.leaderboard.first?.difficulty, difficulty)
            let status = try decoder.decode(NativePublicStatus.self, from: JSONSerialization.data(withJSONObject: ["players": 1, "tankCount": 2, "capacity": 32, "leaders": [record]]))
            let leader = try XCTUnwrap(status.leaders.first)
            XCTAssertEqual(leader.difficulty, difficulty)
            let preview = LeaderboardEntry(id: leader.id, name: leader.name, score: leader.score, colorIndex: leader.colorIndex, bot: leader.bot, team: leader.team ?? 0, difficulty: leader.difficulty)
            XCTAssertEqual(preview, entry)
            let roundtrip = try decoder.decode(LeaderboardEntry.self, from: JSONEncoder().encode(entry))
            XCTAssertEqual(roundtrip, entry)
        }
    }

    func testOfflineStandingsCarryActualDifficultyWithoutChangingArenaNames() throws {
        let practice = PracticeArena(name: "PILOT", colorIndex: 0, botCount: 1, difficulty: "hard")
        let bot = try XCTUnwrap(practice.snapshot.tanks.first(where: \.bot))
        let standing = try XCTUnwrap(practice.snapshot.leaderboard.first(where: \.bot))
        XCTAssertEqual(standing.name, bot.name)
        XCTAssertEqual(standing.difficultyLabel, "FIERCE")
        XCTAssertNil(practice.snapshot.leaderboard.first(where: { !$0.bot })?.difficultyLabel)

        let fixed = FixedArena(rules: RoomRules(), name: "PILOT", colorIndex: 0, botCount: 1, difficulty: "easy", seed: 42)
        XCTAssertEqual(fixed.snapshot.leaderboard.first(where: \.bot)?.difficultyLabel, "CHILL")
        XCTAssertNil(fixed.snapshot.leaderboard.first(where: { !$0.bot })?.difficultyLabel)
    }
}
