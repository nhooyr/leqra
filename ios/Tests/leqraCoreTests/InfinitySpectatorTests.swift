import Foundation
import XCTest
@testable import leqraCore

final class InfinitySpectatorTests: XCTestCase {
    func testSpectatorPacketsPreserveFollowingAndTheWholeRankedRoom() throws {
        let welcome = try JSONDecoder().decode(NetworkWelcome.self, from: Data(#"{"id":0,"seed":9,"spectating":true,"following":19,"generation":7}"#.utf8))
        XCTAssertTrue(welcome.spectating); XCTAssertEqual(welcome.following, 19)
        XCTAssertEqual(welcome.id, 0); XCTAssertNil(welcome.localId)
        XCTAssertNil(welcome.publicToken); XCTAssertNil(welcome.localPublicToken)
        var state = ArenaSnapshot(tanks: [ArenaTank(id: 19, name: "REMOTE", hp: 0)],
                                  leaderboard: (1...18).map { LeaderboardEntry(id: $0, name: "TANK \($0)", score: 19 - $0) })
        state.spectating = true; state.following = 19
        var wire = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        wire["phase"] = nil // Infinity packets omit the fixed-arena discriminator.
        let normalized = try SnapshotDecoder.normalized(data: JSONSerialization.data(withJSONObject: wire), previousWorld: nil)
        let decoded = try JSONDecoder().decode(ArenaSnapshot.self, from: normalized.data)
        XCTAssertTrue(decoded.spectating); XCTAssertEqual(decoded.following, 19)
        XCTAssertEqual(decoded.leaderboard.count, 18); XCTAssertEqual(decoded.leaderboard.last?.id, 18)
        XCTAssertEqual(decoded.tanks.first?.hp, 0, "Death must retain the followed body for respawn")
        XCTAssertFalse(StarmanAudio.isActive(snapshot: decoded, primaryID: 19))
        let old = try JSONDecoder().decode(ArenaSnapshot.self, from: Data(#"{"tick":1}"#.utf8))
        XCTAssertFalse(old.spectating); XCTAssertNil(old.following)
    }

    @MainActor func testSpectatorTransportNeverAllocatesInputSequencesAndDecodesFollowAcknowledgement() throws {
        let client = NetworkClient()
        defer { client.disconnect() }
        var followed: Int?
        client.onEvent = { if case .followed(let id) = $0 { followed = id } }
        try client.receive(Data(#"{"type":"welcome","id":0,"seed":3,"spectating":true,"following":12,"generation":1}"#.utf8))
        client.sendInput(GameInput(seq: 44, forward: true, fire: true))
        client.sendInput(GameInput(seq: 45, fire: true), local: true)
        XCTAssertEqual(client.lastInputSequence, 0); XCTAssertEqual(client.lastLocalInputSequence, 0)
        XCTAssertEqual(client.renameInfinity("NO TANK"), 0)
        try client.receive(Data(#"{"type":"followed","following":17}"#.utf8))
        XCTAssertEqual(followed, 17)
        XCTAssertThrowsError(try client.receive(Data(#"{"type":"followed","following":-1}"#.utf8)))
        try client.receive(Data(#"{"type":"identity","id":8,"spectating":true,"localId":-1,"localMember":0}"#.utf8))
        XCTAssertNil(client.welcome?.localId); XCTAssertNil(client.welcome?.localMember)
        let player = try JSONDecoder().decode(NetworkWelcome.self, from: Data(#"{"id":1,"spectating":false,"localId":0,"localMember":9}"#.utf8))
        XCTAssertEqual(player.localId, 0); XCTAssertEqual(player.localMember, 9, "Fixed tank zero remains a valid P2 identity")
        var staleErrors = 0
        client.onEvent = { event in
            if case .roomEvent(.notice(let notice)) = event, notice.code == "room_access_changed" { client.disconnect() }
            if case .error = event { staleErrors += 1 }
        }
        try client.receive(Data(#"{"type":"error","action":"spectate","code":"room_access_changed","message":"Room access changed"}"#.utf8))
        XCTAssertEqual(staleErrors, 0, "A notice handler can retire its old route without delivering a stale error to a replacement")
    }

    func testFollowingUsesSmoothRemotePresentationWithoutPredictingOrSendingInput() throws {
        var moves = 0, sends = 0
        let timeline = RenderTimeline(localID: -1) { _, _, _ in moves += 1 }
        var first = ArenaSnapshot(tick: 60, tanks: [ArenaTank(id: 12, x: 100, ghostTime: 10, vx: 60)])
        first.spectating = true; first.following = 12
        var second = first; second.tick = 62; second.tanks[0].x = 102
        timeline.accept(first, at: 1); timeline.accept(second, at: 1.033)
        var positions: [Double] = []
        for frame in 0..<24 {
            let state = try XCTUnwrap(timeline.render(dt: 1 / 120, input: GameInput(forward: true, fire: true), now: 1.034 + Double(frame) / 120) { _ in sends += 1 })
            XCTAssertTrue(state.spectating); XCTAssertEqual(state.following, 12)
            positions.append(try XCTUnwrap(state.tanks.first).x)
        }
        XCTAssertEqual(moves, 0); XCTAssertEqual(sends, 0)
        XCTAssertTrue(positions.contains { $0 > 100 && $0 < 102 }, "Followed tanks retain display-rate interpolation")
    }

    func testFrozenSameTickFollowChangeInstallsTheNewFarViewAndEmptyViewClearsIt() throws {
        let timeline = RenderTimeline(localID: -1) { _, _, _ in XCTFail("A spectator cannot predict a tank") }
        var state = ArenaSnapshot(tick: 60, tanks: [ArenaTank(id: 1, x: 100)])
        state.spectating = true; state.following = 1
        timeline.accept(state, at: 1)
        state.tanks = [ArenaTank(id: 18, x: 1_000_000, y: -1_000_000, hp: 0)]; state.following = 18
        state.result = ArenaResult(id: 18)
        timeline.accept(state, at: 1.01)
        var rendered = try XCTUnwrap(timeline.render(dt: 1 / 120, input: GameInput(), now: 1.02) { _ in XCTFail("No spectator input") })
        XCTAssertEqual(rendered.following, 18); XCTAssertEqual(rendered.tanks.first?.x, 1_000_000)
        var stale = state; stale.tick = 59; stale.following = 1
        timeline.accept(stale, at: 1.03)
        state.following = 0; state.tanks = []; state.leaderboard = []
        timeline.accept(state, at: 1.04)
        rendered = try XCTUnwrap(timeline.render(dt: 1 / 120, input: GameInput(), now: 1.05) { _ in XCTFail("No spectator input") })
        XCTAssertEqual(rendered.following, 0); XCTAssertTrue(rendered.tanks.isEmpty); XCTAssertTrue(rendered.leaderboard.isEmpty)
    }

    @MainActor func testLiveRoomInfinitySpectatorCanFollowTheFullRosterAndReconnectWithoutATank() async throws {
        guard let address = ProcessInfo.processInfo.environment["LEQRA_TEST_SERVER"], let base = URL(string: address) else {
            throw XCTSkip("Set LEQRA_TEST_SERVER to a disposable local server.")
        }
        let host = NetworkClient(), hostArena = NetworkClient(), viewer = NetworkClient(), arena = NetworkClient()
        defer { arena.disconnect(); viewer.disconnect(); hostArena.disconnect(); host.disconnect() }
        let suffix = UUID().uuidString.prefix(7).uppercased()
        var room: RoomInfo?, hostWelcome: NetworkWelcome?, viewerWelcome: NetworkWelcome?
        var arenaWelcome: NetworkWelcome?, state: ArenaSnapshot?, followed: Int?, launches = 0, welcomes = 0
        var errors: [String] = [], notices: [ServerNotice] = []
        host.onEvent = { event in
            switch event {
            case .welcome(let value): hostWelcome = value
            case .room(let value): room = value
            case .error(let value): errors.append(value)
            default: break
            }
        }
        viewer.onEvent = { event in
            switch event {
            case .welcome(let value): viewerWelcome = value
            case .infinityStarted: launches += 1
            case .error(let value): errors.append(value)
            default: break
            }
        }
        arena.onEvent = { event in
            switch event {
            case .welcome(let value): arenaWelcome = value; welcomes += 1
            case .state(let value): state = value
            case .followed(let value): followed = value
            case .roomEvent(.notice(let value)): notices.append(value)
            case .error(let value): errors.append(value)
            default: break
            }
        }
        var rules = RoomRules(); rules.infinity = true; rules.infinityRandomBots = true
        let roster = [NativeSeatSpec(kind: "human", name: "HOST " + suffix)]
            + (1...7).map { NativeSeatSpec(kind: "bot", name: "Rust \($0)", difficulty: "dumb") }
        host.connectPublishedRoom(baseURL: base, rules: rules, roster: roster)
        try await wait { hostWelcome != nil && room != nil || !errors.isEmpty }
        let code = try XCTUnwrap(hostWelcome?.room), token = try XCTUnwrap(hostWelcome?.token)
        try await wait { room?.players.count == 8 || !errors.isEmpty }
        try await wait { room?.rules.infinityRandomBots == true || !errors.isEmpty }
        viewer.connectRoom(baseURL: base, name: "WATCH " + suffix, code: code, spectating: true)
        try await wait { viewerWelcome?.spectating == true || !errors.isEmpty }
        host.send(.start)
        try await wait { launches > 0 || !errors.isEmpty }
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: ", "))
        hostArena.connectRoomInfinity(baseURL: base, code: code, token: token)
        let viewerToken = try XCTUnwrap(viewerWelcome?.token)
        arena.connectRoomInfinity(baseURL: base, code: code, token: viewerToken, spectating: true)
        try await wait { state?.spectating == true && (state?.leaderboard.count ?? 0) > 10 || !errors.isEmpty }
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: ", "))
        XCTAssertEqual(arenaWelcome?.id, 0); XCTAssertNil(arenaWelcome?.localId)
        XCTAssertNil(arenaWelcome?.publicToken); XCTAssertNil(arenaWelcome?.localPublicToken)
        let target = try XCTUnwrap(state?.leaderboard.last?.id)
        arena.follow(target)
        try await wait { followed == target && state?.following == target || !errors.isEmpty }
        XCTAssertTrue(state?.tanks.contains { $0.id == target } == true)
        arena.sendInput(GameInput(seq: 99, forward: true, fire: true))
        XCTAssertEqual(arena.lastInputSequence, 0)
        XCTAssertTrue(arena.reconnect())
        try await wait { welcomes > 1 && state?.following == target || !errors.isEmpty }
        XCTAssertTrue(arenaWelcome?.spectating == true); XCTAssertEqual(arenaWelcome?.following, target)
        arena.sendCommand(["type": "follow", "target": -1])
        try await wait { notices.contains { $0.code == "follow_invalid" } || !errors.isEmpty }
        XCTAssertEqual(state?.following, target); XCTAssertTrue(errors.isEmpty, errors.joined(separator: ", "))
        host.sendCommand(["type": "lobby"])
        try await wait { notices.contains { $0.code == "room_access_changed" } }
    }

    @MainActor private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while !condition() {
            if Date() >= deadline { XCTFail("Timed out waiting for the native spectator protocol"); throw GameNetworkError.timeout }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
    }
}
