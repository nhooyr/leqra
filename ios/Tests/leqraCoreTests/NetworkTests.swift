import Foundation
import XCTest
@testable import leqraCore

final class NetworkTests: XCTestCase {
    func testFixedAudioMetadataSurvivesNormalizationAndInfinityAllowsItsAbsence() throws {
        let data = Data(#"{"type":"state","phase":"playing","tanks":[],"bullets":[],"events":[{"id":8,"type":"shot","text":"laser","owner":0,"player":0,"tick":420,"spawnSerial":7,"shotSerial":9007199254740991}]}"#.utf8)
        let normalized = try SnapshotDecoder.normalized(data: data, previousWorld: nil)
        let effect = try XCTUnwrap(JSONDecoder().decode(ArenaSnapshot.self, from: normalized.data).effects.first)
        XCTAssertEqual(effect.kind, "shot:laser")
        XCTAssertEqual(effect.player, 0)
        XCTAssertEqual(effect.tick, 420)
        XCTAssertEqual(effect.spawnSerial, 7)
        XCTAssertEqual(effect.shotSerial, 9_007_199_254_740_991)
        XCTAssertEqual(try JSONDecoder().decode(ArenaEffect.self, from: JSONEncoder().encode(effect)), effect)
        let infinity = try JSONDecoder().decode(ArenaEffect.self, from: Data(#"{"id":1,"kind":"laser","owner":9}"#.utf8))
        XCTAssertNil(infinity.player)
        XCTAssertNil(infinity.tick)
        XCTAssertNil(infinity.spawnSerial)
        XCTAssertNil(infinity.shotSerial)
    }

    func testEndpointRetainsHostAndPortAndUsesRootRoutes() throws {
        let base = try XCTUnwrap(URL(string: "https://example.com:8443/play?token=secret#room"))
        XCTAssertEqual(try ServerAddress.endpoint(base, path: "/api/build").absoluteString, "https://example.com:8443/api/build")
        XCTAssertEqual(try ServerAddress.endpoint(base, path: "/ws/infinite", webSocket: true).absoluteString, "wss://example.com:8443/ws/infinite")
        XCTAssertEqual(try ServerAddress.endpoint(URL(string: "http://127.0.0.1:8080")!, path: "/ws", webSocket: true).absoluteString, "ws://127.0.0.1:8080/ws")
        XCTAssertEqual(try ServerAddress.endpoint(URL(string: "ws://[::1]:8080")!, path: "/api/build").absoluteString, "http://[::1]:8080/api/build")
    }

    func testEndpointRejectsCredentialsAndNonHTTPOrigins() {
        for value in ["file:///tmp/game", "javascript:alert(1)", "https://user:pass@example.com", "example.com"] {
            XCTAssertThrowsError(try ServerAddress.endpoint(URL(string: value)!, path: "/ws", webSocket: true))
        }
    }

    func testInfinityWelcomeNeedsNoRoomCredentials() throws {
        let message = Data(#"{"type":"welcome","id":7,"seed":4294967295,"generation":2,"localId":8}"#.utf8)
        let welcome = try JSONDecoder().decode(NetworkWelcome.self, from: message)
        XCTAssertEqual(welcome.id, 7)
        XCTAssertEqual(welcome.seed, UInt32.max)
        XCTAssertEqual(welcome.localId, 8)
        XCTAssertNil(welcome.token)
        XCTAssertFalse(welcome.spectating)
    }

    func testRoomWelcomePreservesZeroBasedTankID() throws {
        let message = Data(#"{"type":"welcome","id":0,"room":"SNOW","token":"private","spectating":false}"#.utf8)
        let welcome = try JSONDecoder().decode(NetworkWelcome.self, from: message)
        XCTAssertEqual(welcome.id, 0)
        XCTAssertEqual(welcome.room, "SNOW")
        XCTAssertEqual(welcome.token, "private")
        XCTAssertNil(welcome.seed)
    }

    func testFixedSnapshotsNormalizeColorsScoresMachineGunAndWorld() throws {
        let data = Data(##"{"type":"state","phase":"playing","tick":2,"scores":[3,4],"tanks":[{"id":0,"name":"SNOW","alive":true,"color":"#73cee4","x":42,"y":42},{"id":1,"name":"FOX","alive":false,"color":"#ff9679","respawnTime":1}],"bullets":[{"id":9,"owner":0,"x":1,"y":2,"color":"#73cee4"}],"machineBullets":[[10,1,3,1,42,43,846,0,0.2,1.8,0,1]],"pickups":[],"events":[{"id":1,"type":"laser","x":2,"y":3,"owner":0,"points":[{"x":2,"y":3},{"x":20,"y":3}]}],"world":{"width":84,"height":84,"walls":[{"x":0,"y":0,"w":84,"h":8,"axis":"h","line":0}]}}"##.utf8)
        let normalized = try SnapshotDecoder.normalized(data: data, previousWorld: nil)
        let state = try JSONDecoder().decode(ArenaSnapshot.self, from: normalized.data)
        XCTAssertEqual(state.tanks.map(\.hp), [1, 0])
        XCTAssertEqual(state.tanks.map(\.colorIndex), [2, 1])
        XCTAssertEqual(state.tanks.map(\.score), [3, 4])
        XCTAssertEqual(state.leaderboard.map(\.name), ["FOX", "SNOW"])
        XCTAssertEqual(state.bullets.count, 2)
        XCTAssertEqual(state.bullets[1].kind, "rapid")
        XCTAssertEqual(state.bullets[1].vx, 846)
        XCTAssertEqual(state.effects.first?.kind, "laser")
        XCTAssertEqual(state.effects.first?.points.count, 2)
        XCTAssertEqual(state.world?.walls.count, 1)
        let next = Data(#"{"type":"state","phase":"playing","tick":4,"tanks":[],"bullets":[],"pickups":[]}"#.utf8)
        let retained = try SnapshotDecoder.normalized(data: next, previousWorld: normalized.world)
        XCTAssertEqual(try JSONDecoder().decode(ArenaSnapshot.self, from: retained.data).world?.width, 84)
    }

    func testInfinitySnapshotsPreserveAuthoritativeStateAndDefaults() throws {
        let data = Data(#"{"type":"state","tick":2,"tanks":[{"id":1,"name":"SNOW","hp":0,"spawnSerial":4,"ack":17,"ackSteps":2,"colorIndex":0,"respawnTime":0.5}],"bullets":[],"pickups":[],"players":1,"tankCount":8,"leaderboard":[{"id":1,"name":"SNOW","score":3,"bot":false,"colorIndex":0}]}"#.utf8)
        let normalized = try SnapshotDecoder.normalized(data: data, previousWorld: ["width": 42])
        let state = try JSONDecoder().decode(ArenaSnapshot.self, from: normalized.data)
        XCTAssertEqual(state.tanks[0].ack, 17)
        XCTAssertEqual(state.tanks[0].hp, 0)
        XCTAssertEqual(state.tanks[0].spawnSerial, 4)
        XCTAssertEqual(state.tanks[0].respawnTime, 0.5)
        XCTAssertNil(state.world)
        XCTAssertNil(normalized.world)
    }

    func testSnapshotRejectsMissingRequiredCollections() {
        for message in [#"{"type":"state","tanks":[],"bullets":[]}"#, #"{"type":"state","tanks":[],"leaderboard":[]}"#] {
            XCTAssertThrowsError(try SnapshotDecoder.normalized(data: Data(message.utf8), previousWorld: nil))
        }
    }

    func testRoomRulesRetainAllFieldsWhenChangingMode() throws {
        let data = Data(#"{"mode":"ctf","teamMode":"teams","mapSize":"giant","scoreTarget":7,"timeLimit":120,"respawnSeconds":4,"pickupRate":"normal","weapons":["cannon"],"friendlyFire":true,"teamNames":["SNOW","FOX"],"teamColors":[2,5]}"#.utf8)
        var rules = try JSONDecoder().decode(RoomRules.self, from: data)
        rules.infinity = true
        let command = rules.command()
        XCTAssertEqual(command["type"] as? String, "rules")
        let encoded = try XCTUnwrap(command["rules"] as? [String: Any])
        XCTAssertEqual(encoded["weapons"] as? [String], ["cannon"])
        XCTAssertEqual(encoded["friendlyFire"] as? Bool, true)
        XCTAssertEqual(encoded["infinity"] as? Bool, true)
        XCTAssertEqual(encoded["teamColors"] as? [Int], [2, 5])
        XCTAssertEqual(encoded["mapSize"] as? String, "giant")
    }

    /// Opt in against a disposable local Go server with LEQRA_TEST_SERVER.
    @MainActor func testLiveNativeTransport() async throws {
        guard let address = ProcessInfo.processInfo.environment["LEQRA_TEST_SERVER"], let base = URL(string: address) else {
            throw XCTSkip("Set LEQRA_TEST_SERVER to a disposable local server to exercise native WebSockets.")
        }
        let publicClient = NetworkClient(), roomClient = NetworkClient(), arenaClient = NetworkClient()
        defer { publicClient.disconnect(); roomClient.disconnect(); arenaClient.disconnect() }
        let suffix = UUID().uuidString.prefix(8).uppercased()
        let publicName = "CHECK " + suffix, roomName = "ROOM " + suffix
        var errors: [String] = []
        var publicWelcome: NetworkWelcome?, publicState: ArenaSnapshot?
        publicClient.onEvent = { event in
            switch event {
            case .welcome(let value): publicWelcome = value
            case .state(let value): publicState = value
            case .error(let value): errors.append(value)
            default: break
            }
        }
        publicClient.connectPublic(baseURL: base, name: publicName, colorIndex: 2)
        try await waitFor { publicWelcome != nil && publicState != nil || !errors.isEmpty }
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: ", "))
        let publicID = try XCTUnwrap(publicWelcome?.id)
        XCTAssertTrue(publicState?.tanks.contains { $0.id == publicID && $0.name == publicName && $0.colorIndex == 2 } == true)
        publicClient.sendInput(GameInput(seq: 1, fire: true, stickX: 1))
        try await waitFor { publicState?.tanks.contains { $0.id == publicID && $0.ack == 1 } == true || !errors.isEmpty }
        publicClient.sendInput(GameInput(seq: 2, fire: true, stickX: 1), paused: true)
        try await waitFor { publicState?.tanks.contains { $0.id == publicID && $0.ack == 2 } == true || !errors.isEmpty }
        publicClient.disconnect()

        var roomWelcome: NetworkWelcome?, room: RoomInfo?, fixedState: ArenaSnapshot?, infinityStarted = false
        roomClient.onEvent = { event in
            switch event {
            case .welcome(let value): roomWelcome = value
            case .room(let value): room = value
            case .state(let value): fixedState = value
            case .infinityStarted: infinityStarted = true
            case .error(let value): errors.append(value)
            default: break
            }
        }
        roomClient.connectRoom(baseURL: base, name: roomName)
        try await waitFor { roomWelcome != nil && room != nil || !errors.isEmpty }
        let roomID = try XCTUnwrap(roomWelcome?.id)
        let code = try XCTUnwrap(roomWelcome?.room), token = try XCTUnwrap(roomWelcome?.token)
        roomClient.sendCommand(["type": "add", "kind": "bot", "name": "BOT " + suffix, "difficulty": "normal"])
        try await waitFor { (room?.players.count ?? 0) >= 2 || !errors.isEmpty }
        roomClient.sendCommand(["type": "start"])
        try await waitFor { fixedState?.phase == "playing" && fixedState?.world != nil || !errors.isEmpty }
        XCTAssertFalse(try XCTUnwrap(fixedState?.world).walls.isEmpty)
        roomClient.sendInput(GameInput(seq: 1, stickX: 1))
        try await waitFor { fixedState?.tanks.contains { $0.id == roomID && $0.ack == 1 } == true || !errors.isEmpty }
        roomClient.sendCommand(["type": "lobby"])
        try await waitFor { room?.phase == "lobby" || !errors.isEmpty }
        var rules = try XCTUnwrap(room?.rules)
        rules.infinity = true
        roomClient.sendCommand(rules.command())
        try await waitFor { room?.rules.infinity == true || !errors.isEmpty }
        roomClient.sendCommand(["type": "start"])
        try await waitFor { infinityStarted || !errors.isEmpty }
        var arenaWelcome: NetworkWelcome?, arenaState: ArenaSnapshot?
        arenaClient.onEvent = { event in
            switch event {
            case .welcome(let value): arenaWelcome = value
            case .state(let value): arenaState = value
            case .error(let value): errors.append(value)
            default: break
            }
        }
        arenaClient.connectRoomInfinity(baseURL: base, code: code, token: token)
        try await waitFor { arenaWelcome?.seed != nil && arenaState != nil || !errors.isEmpty }
        XCTAssertTrue(arenaState?.tanks.contains { $0.id == arenaWelcome?.id && $0.name == roomName } == true)
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: ", "))
        arenaClient.disconnect()
        roomClient.sendCommand(["type": "lobby"])
    }

    @MainActor private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(12)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        if !condition() {
            XCTFail("Timed out waiting for the local server")
            throw GameNetworkError.timeout
        }
    }
}
