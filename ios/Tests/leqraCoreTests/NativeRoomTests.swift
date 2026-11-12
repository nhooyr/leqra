import Foundation
import XCTest
@testable import leqraCore

final class NativeRoomTests: XCTestCase {
    func testMemberScopedCommandsCarryCurrentOccupantSafeguards() throws {
        let commands: [NativeRoomCommand] = [
            .configure(target: 2, member: 19, name: "SNOW BOT", difficulty: "godlike", team: 3),
            .paint(target: 2, member: 19, colorIndex: 5), .kick(target: 2, member: 19),
            .spectate(true, target: 2, member: 19), .renameLocal(target: 2, member: 19, name: "CO-PILOT")
        ]
        for command in commands {
            let data = try JSONSerialization.data(withJSONObject: command.payload)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["target"] as? Int, 2)
            XCTAssertEqual(object["member"] as? Int, 19)
        }
        let swap = NativeRoomCommand.swap(target: 2, member: 19, spectator: 8, spectatorMember: 20).payload
        XCTAssertEqual(swap["spectatorMember"] as? UInt64, 20)
        XCTAssertEqual(swap["spectator"] as? Int, 8)
    }

    func testQueueAcceptanceIsExplicitConsentAndCancellationPinsTicket() {
        let accept = NativeRoomCommand.queueAccept(42).payload
        XCTAssertEqual(accept["type"] as? String, "queue_accept")
        XCTAssertEqual(accept["ready"] as? Bool, true)
        XCTAssertEqual(accept["queueId"] as? UInt64, 42)
        XCTAssertEqual(NativeRoomCommand.queueCancel(42).payload["queueId"] as? UInt64, 42)
    }

    func testPresetPayloadNeverContainsCredentials() throws {
        let roster = [NativeSeatSpec(kind: "human", name: "SNOW", colorIndex: 2),
                      NativeSeatSpec(kind: "bot", name: "FOX", difficulty: "hard", colorIndex: 5)]
        let data = try JSONSerialization.data(withJSONObject: NativeRoomCommand.preset(rules: RoomRules(), roster: roster).payload)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "preset")
        let rows = try XCTUnwrap(object["roster"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1]["difficulty"] as? String, "hard")
        XCTAssertEqual(rows[1]["colorIndex"] as? Int, 5)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("token"))
    }

    func testChatHistoryAndLiveMessagesShareTheSameModel() throws {
        let row = #"{"id":2,"member":10,"name":"SNOW","text":"hello 🦊","spectating":false,"team":1,"at":1234}"#
        let live = try JSONDecoder().decode(ChatPacket.self, from: Data("{\"type\":\"chat\",\"room\":\"A\",\"channel\":\"room\",\"message\":\(row)}".utf8))
        let history = try JSONDecoder().decode(ChatPacket.self, from: Data("{\"type\":\"chat_history\",\"room\":\"A\",\"channel\":\"room\",\"messages\":[\(row)]}".utf8))
        XCTAssertEqual(live.messages, history.messages)
        XCTAssertFalse(live.isHistory)
        XCTAssertTrue(history.isHistory)
        XCTAssertEqual(live.messages.first?.text, "hello 🦊")
    }

    func testQueueStatusDecodesConsentAndCatalog() throws {
        let data = Data(#"{"type":"queue_status","queue":{"id":4,"key":"ctf-3","name":"CTF","stage":"confirming","players":2,"required":6,"members":[{"member":10,"name":"SNOW","kind":"human","controller":10,"accepted":false}],"since":100},"queues":[{"definition":{"key":"ctf-3","name":"CTF","mode":"ctf","teamSize":3,"players":6,"map":"huge","cols":14,"rows":12,"target":3,"seconds":180},"waitingPlayers":2,"waitingParties":1}],"capacityBlocked":false}"#.utf8)
        let status = try JSONDecoder().decode(QueuePacket.self, from: data)
        XCTAssertEqual(status.queue?.members.first?.accepted, false)
        XCTAssertEqual(status.queue?.id, 4)
        XCTAssertEqual(status.queues.first?.definition.teamSize, 3)
        XCTAssertEqual(status.queues.first?.waitingParties, 1)
    }

    func testPublicPreviewIncludesRankAndTankCount() throws {
        let data = Data(#"{"players":1,"tankCount":8,"capacity":32,"leaders":[{"id":8,"name":"SNOW","score":5,"bot":false,"colorIndex":2,"rank":1}]}"#.utf8)
        let status = try JSONDecoder().decode(NativePublicStatus.self, from: data)
        XCTAssertEqual(status.players, 1)
        XCTAssertEqual(status.tankCount, 8)
        XCTAssertEqual(status.capacity, 32)
        XCTAssertEqual(status.leaders.first?.rank, 1)
        XCTAssertEqual(status.leaders.first?.colorIndex, 2)
        XCTAssertEqual(status.latencyMilliseconds, 0)
    }

    func testFixedHUDDerivesAmmoGrenadeFuseAndHostileLocksFromAuthoritativeProjectiles() throws {
        let data = Data(#"{"type":"state","phase":"playing","tick":4,"tanks":[{"id":0,"alive":true,"team":1},{"id":1,"alive":true,"team":2}],"bullets":[{"id":1,"owner":0,"kind":"grenade","life":6},{"id":2,"owner":0,"kind":"rapid","life":1},{"id":3,"owner":1,"kind":"homing","target":0,"life":2}],"boostedBulletIds":[2],"rules":{"friendlyFire":false},"events":[{"id":1,"type":"shot","text":"homing","owner":1}]}"#.utf8)
        let normalized = try SnapshotDecoder.normalized(data: data, previousWorld: nil)
        let state = try JSONDecoder().decode(ArenaSnapshot.self, from: normalized.data)
        XCTAssertEqual(state.tanks[0].ammoUsed, 1)
        XCTAssertEqual(state.tanks[0].grenades, 1)
        XCTAssertEqual(state.tanks[0].grenadeLife, 6)
        XCTAssertTrue(state.tanks[0].locked)
        XCTAssertEqual(state.effects[0].kind, "shot:homing")
        var allied = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var tanks = try XCTUnwrap(allied["tanks"] as? [[String: Any]])
        tanks[1]["team"] = 1; allied["tanks"] = tanks
        let safe = try SnapshotDecoder.normalized(data: JSONSerialization.data(withJSONObject: allied), previousWorld: nil)
        XCTAssertFalse(try JSONDecoder().decode(ArenaSnapshot.self, from: safe.data).tanks[0].locked)
    }

    /// Uses a disposable Go server, never the public deployment.
    @MainActor func testLiveRoomControlsChatAndPrivateReconnect() async throws {
        guard let address = ProcessInfo.processInfo.environment["LEQRA_TEST_SERVER"], let base = URL(string: address) else {
            throw XCTSkip("Set LEQRA_TEST_SERVER to a disposable local server.")
        }
        let client = NetworkClient(), arena = NetworkClient()
        defer { client.disconnect(); arena.disconnect() }
        let suffix = UUID().uuidString.prefix(8).uppercased(), roomName = "ROOM " + suffix, botName = "FOX " + suffix
        let preview = try await client.fetchPublicStatus(baseURL: base)
        XCTAssertEqual(preview.capacity, 32)
        XCTAssertGreaterThanOrEqual(preview.latencyMilliseconds, 0)
        var room: RoomInfo?, welcome: NetworkWelcome?, arenaWelcome: NetworkWelcome?, arenaState: ArenaSnapshot?
        var chats: [NativeChatMessage] = [], errors: [String] = [], reconnects = 0
        client.onEvent = { event in
            switch event {
            case .welcome(let value): welcome = value
            case .room(let value): room = value
            case .roomEvent(.chat(let value)): chats.append(contentsOf: value.messages)
            case .roomEvent(.reconnecting): reconnects += 1
            case .error(let value): errors.append(value)
            default: break
            }
        }
        client.connectRoom(baseURL: base, name: roomName)
        try await waitFor { room != nil && welcome != nil || !errors.isEmpty }
        let identity = try XCTUnwrap(welcome)
        client.send(.add(kind: "bot", name: "BOT " + suffix, difficulty: "easy"))
        try await waitFor { room?.players.contains { $0.kind == "bot" } == true || !errors.isEmpty }
        let bot = try XCTUnwrap(room?.players.first { $0.kind == "bot" })
        client.send(.configure(target: bot.id, member: bot.member, name: botName, difficulty: "hard"))
        try await waitFor { room?.players.contains { $0.name == botName && $0.difficulty == "hard" } == true || !errors.isEmpty }
        client.send(.paint(target: bot.id, member: bot.member, colorIndex: 5))
        try await waitFor { room?.players.contains { $0.id == bot.id && $0.colorIndex == 5 } == true || !errors.isEmpty }
        client.send(.chat("NATIVE CHAT"))
        try await waitFor { chats.contains { $0.text == "NATIVE CHAT" } || !errors.isEmpty }
        let code = "Swift room \(UUID().uuidString.prefix(8))"
        client.send(.renameRoom(code))
        try await waitFor { room?.code == code || !errors.isEmpty }
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: ", "))
        client.reconnect()
        try await waitFor { welcome?.resumed == true || !errors.isEmpty }
        XCTAssertGreaterThan(reconnects, 0)
        XCTAssertEqual(welcome?.id, identity.id)
        XCTAssertEqual(welcome?.token, identity.token)
        XCTAssertEqual(welcome?.room, code)
        XCTAssertEqual(client.lastInputSequence, 0)
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: ", "))

        var rules = try XCTUnwrap(room?.rules)
        rules.infinity = true
        client.send(.rules(rules))
        try await waitFor { room?.rules.infinity == true || !errors.isEmpty }
        client.send(.start)
        try await waitFor { room?.infinityActive == true || !errors.isEmpty }
        arena.onEvent = { event in
            switch event {
            case .welcome(let value): arenaWelcome = value
            case .state(let value): arenaState = value
            case .error(let value): errors.append(value)
            default: break
            }
        }
        arena.connectRoomInfinity(baseURL: base, code: code, token: try XCTUnwrap(welcome?.token))
        try await waitFor { arenaWelcome != nil && arenaState != nil || !errors.isEmpty }
        let arenaIdentity = try XCTUnwrap(arenaWelcome)
        arena.sendInput(GameInput(seq: 1, stickX: 1))
        try await waitFor { arenaState?.tanks.contains { $0.id == arenaIdentity.id && $0.ack == 1 } == true || !errors.isEmpty }
        arena.reconnect()
        try await waitFor { arenaWelcome?.resumed == true || !errors.isEmpty }
        XCTAssertEqual(arenaWelcome?.id, arenaIdentity.id)
        XCTAssertEqual(arenaWelcome?.seed, arenaIdentity.seed)
        XCTAssertEqual(arenaWelcome?.generation, arenaIdentity.generation)
        XCTAssertEqual(arena.lastInputSequence, 0)
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: ", "))
    }

    @MainActor private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(12)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        if !condition() { XCTFail("Timed out waiting for the local server"); throw GameNetworkError.timeout }
    }

    @MainActor func testLiveSpectatorQueueConsentKickAndLocalRename() async throws {
        guard let address = ProcessInfo.processInfo.environment["LEQRA_TEST_SERVER"], let base = URL(string: address) else {
            throw XCTSkip("Set LEQRA_TEST_SERVER to a disposable local server.")
        }
        let host = NetworkClient(), guest = NetworkClient()
        defer { host.disconnect(); guest.disconnect() }
        let suffix = UUID().uuidString.prefix(8).uppercased()
        let hostName = "HOST " + suffix, guestName = "GUEST " + suffix, localName = "WING " + suffix
        var room: RoomInfo?, guestWelcome: NetworkWelcome?, catalog: QueuePacket?
        var hostErrors: [String] = [], cancelled = false, kicked = false
        host.onEvent = { event in
            switch event {
            case .room(let value): room = value
            case .roomEvent(.queue(let value)):
                catalog = value
                if value.type == "queue_cancelled" { cancelled = true }
            case .error(let value): hostErrors.append(value)
            default: break
            }
        }
        guest.onEvent = { event in
            switch event {
            case .welcome(let value): guestWelcome = value
            case .roomEvent(.notice(let value)): if value.type == "kicked" { kicked = true }
            default: break
            }
        }
        host.connectRoom(baseURL: base, name: hostName)
        try await waitFor { room != nil || !hostErrors.isEmpty }
        guest.connectRoom(baseURL: base, name: guestName, code: try XCTUnwrap(room?.code), spectating: true)
        try await waitFor { room?.spectators.count == 1 && guestWelcome != nil || !hostErrors.isEmpty }
        XCTAssertEqual(guestWelcome?.spectating, true)
        guest.send(.spectate(false))
        try await waitFor { room?.players.count == 2 && guestWelcome?.spectating == false || !hostErrors.isEmpty }
        host.send(.queueInfo)
        try await waitFor { catalog?.queues.count == 6 || !hostErrors.isEmpty }
        host.send(.queueJoin("elimination-2"))
        try await waitFor { room?.queue?.stage == "confirming" || !hostErrors.isEmpty }
        guest.send(.queueAccept(try XCTUnwrap(room?.queue?.id)))
        try await waitFor { room?.queue?.stage == "searching" || !hostErrors.isEmpty }
        host.send(.queueCancel(try XCTUnwrap(room?.queue?.id)))
        try await waitFor { cancelled && room?.queue == nil || !hostErrors.isEmpty }
        let player = try XCTUnwrap(room?.players.first { $0.name == guestName })
        host.send(.kick(target: player.id, member: player.member))
        try await waitFor { kicked && room?.players.count == 1 || !hostErrors.isEmpty }
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        let localKey = "p_" + Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let proof = FileManager.default.temporaryDirectory.appendingPathComponent("leqra-p2-" + UUID().uuidString + ".key")
        try Data(localKey.utf8).write(to: proof, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: proof.path)
        defer { try? FileManager.default.removeItem(at: proof) }
        var add = NativeRoomCommand.add(kind: "local", name: "CO " + suffix).payload
        add["independentAccounts"] = true; add["localPublicToken"] = localKey; add["localNewAccount"] = true
        host.sendCommand(add)
        try await waitFor { room?.players.contains { $0.kind == "local" } == true || !hostErrors.isEmpty }
        let local = try XCTUnwrap(room?.players.first { $0.kind == "local" })
        // Host action budget is eight per second; the queue and roster actions
        // above intentionally stay within that existing server limit.
        var rename = NativeRoomCommand.renameLocal(target: local.id, member: local.member, name: localName).payload
        rename["independentAccounts"] = true; rename["localPublicToken"] = localKey
        host.sendCommand(rename)
        try await waitFor { room?.players.contains { $0.name == localName } == true || !hostErrors.isEmpty }
        XCTAssertTrue(hostErrors.isEmpty, hostErrors.joined(separator: ", "))
        XCTAssertEqual(host.localAccountKey, localKey)
        XCTAssertNotEqual(host.accountKey, localKey)
    }
}
