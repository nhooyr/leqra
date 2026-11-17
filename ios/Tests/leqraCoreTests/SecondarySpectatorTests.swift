import Foundation
import XCTest
@testable import leqraCore

final class SecondarySpectatorTests: XCTestCase {
    @MainActor func testFixedSpectatorCanOnlySendItsSecondaryTankInput() throws {
        let welcome = try JSONDecoder().decode(NetworkWelcome.self, from: Data(#"{"id":8,"spectating":true,"localId":1}"#.utf8))
        XCTAssertTrue(NetworkClient.permitsInput(welcome: welcome, infinity: false, local: true, player: 1))
        XCTAssertFalse(NetworkClient.permitsInput(welcome: welcome, infinity: false, local: false, player: nil))
        XCTAssertFalse(NetworkClient.permitsInput(welcome: welcome, infinity: false, local: true, player: 2))
        XCTAssertFalse(NetworkClient.permitsInput(welcome: welcome, infinity: true, local: true, player: 1))
        let noSecondary = try JSONDecoder().decode(NetworkWelcome.self, from: Data(#"{"id":8,"spectating":true}"#.utf8))
        XCTAssertFalse(NetworkClient.permitsInput(welcome: noSecondary, infinity: false, local: true, player: nil))
    }

    @MainActor func testLiveFixedSecondaryMovesWhilePrimarySpectates() async throws {
        guard let address = ProcessInfo.processInfo.environment["LEQRA_TEST_SERVER"], let base = URL(string: address) else {
            throw XCTSkip("Set LEQRA_TEST_SERVER to a disposable server.")
        }
        let client = NetworkClient()
        defer { client.disconnect() }
        func key() -> String {
            "p_" + Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let suffix = String(UUID().uuidString.prefix(6)), primaryKey = key(), localKey = key()
        let primaryName = "WATCH " + suffix, secondaryName = "PLAY " + suffix
        _ = try await client.createAccount(baseURL: base, publicToken: primaryKey, name: primaryName)
        _ = try await client.createAccount(baseURL: base, publicToken: localKey, name: secondaryName)
        var room: RoomInfo?, state: ArenaSnapshot?, failures: [String] = []
        client.onEvent = { event in
            switch event {
            case .room(let value): room = value
            case .state(let value): state = value
            case .error(let value): failures.append(value)
            default: break
            }
        }
        func wait(_ condition: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(12)
            while !condition(), failures.isEmpty, Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
            XCTAssertTrue(failures.isEmpty, failures.joined(separator: ", "))
            guard condition() else { throw GameNetworkError.timeout }
        }
        var rules = RoomRules.localDefaults(); rules.pickupRate = "off"
        client.connectPublishedRoom(baseURL: base, rules: rules, roster: [
            NativeSeatSpec(kind: "human", name: primaryName), NativeSeatSpec(kind: "local", name: secondaryName),
            NativeSeatSpec(kind: "bot", name: "Rust", difficulty: "dumb"), NativeSeatSpec(kind: "bot", name: "Vapor", difficulty: "dumb")
        ], publicToken: primaryKey, localPublicToken: localKey)
        try await wait { room?.players.count == 4 }
        client.sendCommand(["type":"spectate", "spectating":true])
        try await wait { client.welcome?.spectating == true && room?.spectators.contains(where: { $0.name == primaryName }) == true }
        let pilot = try XCTUnwrap(room?.players.first { $0.kind == "local" })
        XCTAssertEqual(client.welcome?.localId, pilot.id)
        client.sendCommand(["type":"start"])
        try await wait { state?.phase == "playing" }
        let angle = try XCTUnwrap(state?.tanks.first { $0.id == pilot.id }?.angle)
        let primarySequence = client.lastInputSequence
        client.sendInput(GameInput(seq: primarySequence + 1, fire: true))
        XCTAssertEqual(client.lastInputSequence, primarySequence, "Spectating P1 cannot submit combat input")
        client.sendInput(GameInput(seq: 1, left: true), local: true, player: pilot.id, member: pilot.member)
        try await wait { state?.tanks.contains(where: { $0.id == pilot.id && $0.ack == 1 && $0.angle != angle }) == true }
        client.sendInput(GameInput(seq: 2), local: true, player: pilot.id, member: pilot.member)
        try await wait { state?.tanks.contains(where: { $0.id == pilot.id && $0.ack == 2 }) == true }
    }

}
