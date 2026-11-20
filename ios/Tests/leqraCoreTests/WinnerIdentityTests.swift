import Foundation
import XCTest

@testable import leqraCore

final class WinnerIdentityTests: XCTestCase {
    func testIndividualRoundAndInfinityWinnersKeepSeatLabelsAndTankPaint() throws {
        for seat in [1, 2] {
            for infinity in [false, true] {
                let tank = ArenaTank(id: seat, name: seat == 1 ? "PRIMARY" : "WING", colorIndex: seat + 2)
                var state = ArenaSnapshot(tanks: [tank])
                state.winner = seat
                if infinity { state.result = ArenaResult(id: seat, name: tank.name, score: 5) }
                let identity = try XCTUnwrap(
                    WinnerIdentity(snapshot: state, rules: RoomRules(), primaryID: 1, secondaryID: 2))
                XCTAssertEqual(identity.label, tank.name + " (P\(seat))")
                XCTAssertEqual(identity.color, GamePalette.colors[seat + 2])
            }
        }
    }

    func testTeamsUseConfiguredNamesAndPaintWhileArchivedBotsKeepTheirIdentity() throws {
        var rules = RoomRules()
        rules.teamNames[2] = "NIGHT OWLS"
        rules.teamColors[2] = 7
        var state = ArenaSnapshot()
        state.result = ArenaResult(id: 3, name: "Team 3", team: 3, score: 5)
        let team = try XCTUnwrap(WinnerIdentity(snapshot: state, rules: rules, primaryID: 1))
        XCTAssertEqual(team.label, "NIGHT OWLS")
        XCTAssertEqual(team.color, GamePalette.colors[7])
        state.result = ArenaResult(id: 64, name: "Bot 64 - Godlike", score: 5)
        state.leaderboard = [LeaderboardEntry(id: 64, name: "Bot 64 - Godlike", colorIndex: 4, bot: true)]
        let bot = try XCTUnwrap(WinnerIdentity(snapshot: state, rules: rules, primaryID: 1))
        XCTAssertEqual(bot.label, "Bot 64 - Godlike")
        XCTAssertEqual(bot.color, GamePalette.colors[4])
    }

    func testReportMembersDetermineTheLocalSeatAfterTankSeatsChange() throws {
        for kind in ["human", "local", "bot"] {
            let raw: [String: Any] = [
                "id": 100, "member": kind == "human" ? 42 : 43,
                "controllerMember": 42, "seat": 5, "name": "ARCHIVED", "color": GamePalette.colors[6],
                "team": 0, "score": 5, "kind": kind, "eliminations": 2, "deaths": 1,
                "selfDestructs": 0, "teamKills": 0, "captures": 0, "flagReturns": 0,
                "hillSeconds": 0, "active": false, "winner": true, "mixedTeams": false,
            ]
            let player = try JSONDecoder().decode(
                NativeMatchPlayer.self, from: JSONSerialization.data(withJSONObject: raw))
            XCTAssertEqual(
                player.localSeat(controllerMember: nil), nil,
                "No controller is never an implicit local identity")
            if kind == "bot" { continue }
            let report: [String: Any] = [
                "mode": "elimination", "duration": 8, "rounds": 2, "players": [raw], "limited": false,
            ]
            var state = ArenaSnapshot(tanks: [ArenaTank(id: 5, name: "NEW OCCUPANT")])
            state.winner = 5
            state.matchStats = try JSONDecoder().decode(
                NativeMatchReport.self, from: JSONSerialization.data(withJSONObject: report))
            let winner = try XCTUnwrap(
                WinnerIdentity(
                    snapshot: state, rules: RoomRules(), primaryID: 1, secondaryID: 2, controllerMember: 42))
            XCTAssertEqual(winner.label, "ARCHIVED (P\(kind == "local" ? 2 : 1))")
            XCTAssertEqual(winner.color, GamePalette.colors[6])
        }
        XCTAssertNil(WinnerIdentity(snapshot: ArenaSnapshot(), rules: RoomRules(), primaryID: 1))
    }
}
