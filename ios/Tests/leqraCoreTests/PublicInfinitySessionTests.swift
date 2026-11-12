import Foundation
import XCTest
@testable import leqraCore

final class PublicInfinitySessionTests: XCTestCase {
    private let firstToken = String(repeating: "a", count: 64)
    private let secondToken = String(repeating: "b", count: 64)

    func testCredentialIsBoundToCanonicalServerOriginAndContainsNoScore() throws {
        let session = try PublicInfinitySession(baseURL: URL(string: "https://EXAMPLE.com:443/play?score=999#room")!, publicToken: firstToken)
        XCTAssertEqual(session.origin, "https://example.com")
        XCTAssertTrue(session.matches(URL(string: "https://example.com/other")!))
        XCTAssertFalse(session.matches(URL(string: "http://example.com")!))
        XCTAssertFalse(session.matches(URL(string: "https://example.com:8443")!))
        XCTAssertFalse(session.matches(URL(string: "https://other.example")!))
        let data = try JSONEncoder().encode(session)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["origin", "publicToken"])
        XCTAssertEqual(try JSONDecoder().decode(PublicInfinitySession.self, from: data), session)
    }

    func testDifferentBearersAreDifferentIdentitiesRegardlessOfCallsign() throws {
        let base = URL(string: "http://localhost:8080")!
        let first = try PublicInfinitySession(baseURL: base, publicToken: firstToken)
        let second = try PublicInfinitySession(baseURL: base, publicToken: secondToken)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.origin, second.origin)
        XCTAssertEqual(first.publicToken, firstToken)
        // Names and score cannot participate in credential decoding or lookup.
        let augmented = Data(("{\"origin\":\"http://localhost:8080\",\"publicToken\":\"" + firstToken + "\",\"name\":\"SAME NAME\",\"score\":999}").utf8)
        XCTAssertEqual(try JSONDecoder().decode(PublicInfinitySession.self, from: augmented), first)
    }

    func testMalformedStoredCredentialsAreRejected() throws {
        for token in ["", "with space", "line\nbreak", "🔑", String(repeating: "a", count: 257)] {
            XCTAssertThrowsError(try PublicInfinitySession(baseURL: URL(string: "https://example.com")!, publicToken: token))
        }
        for origin in ["file:///tmp/game", "https://user:password@example.com", "example.com"] {
            let value = ["origin": origin, "publicToken": firstToken]
            XCTAssertThrowsError(try JSONDecoder().decode(PublicInfinitySession.self, from: JSONSerialization.data(withJSONObject: value)))
        }
    }

    func testPublicWelcomeKeepsPublicAndRoomCredentialsSeparate() throws {
        let data = try JSONSerialization.data(withJSONObject: ["type": "welcome", "id": 9, "seed": 42,
            "public": true, "publicToken": firstToken, "resumed": true])
        let welcome = try JSONDecoder().decode(NetworkWelcome.self, from: data)
        XCTAssertEqual(welcome.publicToken, firstToken)
        XCTAssertNil(welcome.token)
        XCTAssertNil(welcome.room)
        XCTAssertTrue(welcome.resumed)
        XCTAssertTrue(welcome.isPublic)
    }

    @MainActor func testPublicTransportSuspendsWithoutLosingAuthenticatedResume() throws {
        let client = NetworkClient()
        defer { client.disconnect() }
        var errors: [String] = [], attempts = 0
        client.onEvent = { event in
            if case .error(let value) = event { errors.append(value) }
            if case .roomEvent(.reconnecting) = event { attempts += 1 }
        }
        client.connectPublic(baseURL: URL(string: "http://127.0.0.1:9")!, name: "SAME NAME", colorIndex: 2)
        try client.receive(packet(["type": "welcome", "id": 7, "seed": 42, "public": true, "publicToken": firstToken]))
        XCTAssertTrue(client.connected)
        client.suspend()
        XCTAssertFalse(client.connected)
        XCTAssertTrue(client.reconnect())
        XCTAssertEqual(attempts, 1)
        XCTAssertTrue(errors.isEmpty)
        client.disconnect()
        XCTAssertFalse(client.reconnect(), "Explicit transport exit must stop automatic retries.")
    }

    @MainActor func testUnknownPublicBearerGetsOnlyOneFreshJoinFallback() throws {
        let client = NetworkClient()
        defer { client.disconnect() }
        var errors: [String] = []
        client.onEvent = { if case .error(let value) = $0 { errors.append(value) } }
        client.connectPublic(baseURL: URL(string: "http://127.0.0.1:9")!, name: "SAME NAME", colorIndex: 2, publicToken: firstToken)
        let invalid = try packet(["type": "error", "code": "public_resume_invalid", "message": "Unknown recovery key."])
        try client.receive(invalid)
        XCTAssertTrue(errors.isEmpty, "An expired key should gracefully attempt a fresh identity, never a name lookup.")
        try client.receive(invalid)
        XCTAssertEqual(errors, ["Unknown recovery key."])
        XCTAssertFalse(client.reconnect(), "A server rejecting a fresh join must not loop indefinitely.")
    }

    @MainActor func testPublicShutdownRetriesButVersionFailureStops() throws {
        let client = NetworkClient()
        defer { client.disconnect() }
        var errors: [String] = [], attempts = 0
        client.onEvent = { event in
            if case .error(let value) = event { errors.append(value) }
            if case .roomEvent(.reconnecting) = event { attempts += 1 }
        }
        client.connectPublic(baseURL: URL(string: "http://127.0.0.1:9")!, name: "PILOT", colorIndex: 0)
        try client.receive(packet(["type": "welcome", "id": 1, "seed": 42, "public": true, "publicToken": firstToken]))
        try client.receive(packet(["type": "server_shutdown", "message": "Server restarting."]))
        XCTAssertEqual(attempts, 1)
        XCTAssertTrue(errors.isEmpty)
        try client.receive(packet(["type": "error", "action": "version", "message": "Update required."]))
        XCTAssertEqual(errors, ["Update required."])
        XCTAssertFalse(client.reconnect())
    }

    @MainActor func testLeaderboardResetIsInformationalAndRetainsPublicIdentity() throws {
        let client = NetworkClient()
        defer { client.disconnect() }
        var resets = 0, errors = 0
        client.onEvent = { event in
            if case .roomEvent(.notice(let value)) = event, value.type == "leaderboard_reset" { resets += 1 }
            if case .error = event { errors += 1 }
        }
        client.connectPublic(baseURL: URL(string: "http://127.0.0.1:9")!, name: "PILOT", colorIndex: 0)
        try client.receive(packet(["type": "welcome", "id": 1, "seed": 42, "public": true, "publicToken": firstToken]))
        try client.receive(packet(["type": "leaderboard_reset", "scope": "selected", "message": "Leaderboard updated."]))
        XCTAssertEqual(resets, 1)
        XCTAssertEqual(errors, 0)
        XCTAssertTrue(client.connected)
        XCTAssertEqual(client.welcome?.publicToken, firstToken)
        client.suspend()
        XCTAssertTrue(client.reconnect())
    }

    @MainActor func testCallsignConflictIdentifiesLocalSeatsAndStopsRetries() throws {
        let client = NetworkClient()
        defer { client.disconnect() }
        var conflicts: [CallsignConflict] = [], errors: [String] = []
        client.onEvent = { event in
            if case .roomEvent(.notice(let notice)) = event, notice.code == "callsign_taken" { conflicts = notice.conflicts ?? [] }
            if case .error(let message) = event { errors.append(message) }
        }
        client.connectPublic(baseURL: URL(string: "http://127.0.0.1:9")!, name: "TAKEN FOX", colorIndex: 0)
        try client.receive(packet(["type": "error", "code": "callsign_taken", "message": "Rename TAKEN FOX (P1) and TAKEN CAT (P2).",
            "conflicts": [["seat": 0, "name": "TAKEN FOX"], ["seat": 1, "name": "TAKEN CAT"]]]))
        XCTAssertEqual(conflicts.map(\.seat), [0, 1])
        XCTAssertEqual(conflicts.map(\.name), ["TAKEN FOX", "TAKEN CAT"])
        XCTAssertEqual(errors.count, 1)
        XCTAssertFalse(client.reconnect(), "Rejected names require an edit, not repeated joins.")
        XCTAssertNil(client.welcome?.publicToken)
    }

    @MainActor func testPrivateOwnerCredentialDoesNotEnablePublicAutomaticResume() throws {
        let client = NetworkClient()
        defer { client.disconnect() }
        var errors = 0, retries = 0
        client.onEvent = { event in
            if case .error = event { errors += 1 }
            if case .roomEvent(.reconnecting) = event { retries += 1 }
        }
        client.connectRoom(baseURL: URL(string: "http://127.0.0.1:9")!, name: "PILOT", publicToken: firstToken)
        try client.receive(packet(["type": "welcome", "id": 1, "room": "ABC", "token": "private-room-key", "publicToken": firstToken]))
        XCTAssertEqual(client.welcome?.token, "private-room-key")
        XCTAssertEqual(client.welcome?.publicToken, firstToken)
        try client.receive(packet(["type": "server_shutdown"]))
        XCTAssertEqual(errors, 1)
        XCTAssertEqual(retries, 0, "A name-ownership key must not change private reservation semantics.")
        XCTAssertFalse(client.reconnect())
    }

    @MainActor func testSupersededPublicTransportStopsAutomaticRejoin() throws {
        let client = NetworkClient()
        defer { client.disconnect() }
        var replacements = 0, errors = 0, attempts = 0
        client.onEvent = { event in
            if case .roomEvent(.notice(let notice)) = event, notice.code == "session_replaced" { replacements += 1 }
            if case .error = event { errors += 1 }
            if case .roomEvent(.reconnecting) = event { attempts += 1 }
        }
        client.connectPublic(baseURL: URL(string: "http://127.0.0.1:9")!, name: "PILOT", colorIndex: 0)
        try client.receive(packet(["type": "welcome", "id": 1, "seed": 42, "public": true, "publicToken": firstToken]))
        try client.receive(packet(["type": "error", "code": "session_replaced", "message": "This pilot was opened on another connection."]))
        XCTAssertEqual(replacements, 1)
        XCTAssertEqual(errors, 1)
        XCTAssertEqual(attempts, 0)
        XCTAssertFalse(client.connected)
        XCTAssertFalse(client.reconnect(), "Two valid clients must not repeatedly take the same pilot from one another.")
    }

    @MainActor func testPrivateInfinityOwnerCredentialDoesNotBecomeStandalonePublicResume() throws {
        let client = NetworkClient()
        defer { client.disconnect() }
        var errors = 0, attempts = 0
        client.onEvent = { event in
            if case .error = event { errors += 1 }
            if case .roomEvent(.reconnecting) = event { attempts += 1 }
        }
        client.connectRoomInfinity(baseURL: URL(string: "http://127.0.0.1:9")!, code: "PRIVATE", token: "private-room-key")
        try client.receive(packet(["type": "welcome", "id": 7, "seed": 42, "generation": 3, "publicToken": firstToken]))
        XCTAssertFalse(try XCTUnwrap(client.welcome).isPublic)
        try client.receive(packet(["type": "server_shutdown"]))
        XCTAssertEqual(errors, 1)
        XCTAssertEqual(attempts, 0, "A private Infinity welcome carrying name ownership must retain the private route.")
        XCTAssertFalse(client.reconnect())
    }

    @MainActor func testLivePublicIdentitySurvivesNewClientAndSameNameDoesNotAuthenticate() async throws {
        guard let address = ProcessInfo.processInfo.environment["LEQRA_TEST_SERVER"], let base = URL(string: address) else {
            throw XCTSkip("Set LEQRA_TEST_SERVER to a disposable server with durable public identities.")
        }
        let first = NetworkClient(), other = NetworkClient(), restored = NetworkClient(), forged = NetworkClient()
        defer { first.disconnect(); other.disconnect(); restored.disconnect(); forged.disconnect() }
        var firstWelcome: NetworkWelcome?, otherWelcome: NetworkWelcome?, restoredWelcome: NetworkWelcome?, forgedWelcome: NetworkWelcome?
        var initialScore: Int?, restoredScore: Int?, errors: [String] = [], otherErrors: [String] = [], forgedErrors: [String] = []
        let suffix = UUID().uuidString.prefix(8).uppercased(), name = "NATIVE " + suffix
        first.onEvent = { event in
            if case .welcome(let value) = event { firstWelcome = value }
            if case .state(let value) = event { initialScore = value.tanks.first(where: { $0.id == firstWelcome?.id })?.score }
            if case .error(let value) = event { errors.append(value) }
        }
        other.onEvent = { event in
            if case .welcome(let value) = event { otherWelcome = value }
            if case .error(let value) = event { otherErrors.append(value) }
        }
        first.connectPublic(baseURL: base, name: name, colorIndex: 2)
        try await waitFor { firstWelcome?.publicToken != nil && initialScore != nil || !errors.isEmpty }
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: ", "))
        let original = try XCTUnwrap(firstWelcome)
        let token = try XCTUnwrap(original.publicToken)
        first.suspend()
        other.connectPublic(baseURL: base, name: name, colorIndex: 2)
        try await waitFor { !otherErrors.isEmpty || otherWelcome != nil }
        XCTAssertNil(otherWelcome, "The same callsign is not proof of ownership, even after disconnect.")
        XCTAssertFalse(otherErrors.isEmpty)
        otherErrors = []
        other.connectPublic(baseURL: base, name: "OTHER " + suffix, colorIndex: 2)
        try await waitFor { otherWelcome?.publicToken != nil || !otherErrors.isEmpty }
        XCTAssertTrue(otherErrors.isEmpty, otherErrors.joined(separator: ", "))
        let competitor = try XCTUnwrap(otherWelcome)
        XCTAssertNotEqual(original.id, competitor.id)
        XCTAssertNotEqual(token, competitor.publicToken)
        let persisted = try PublicInfinitySession(baseURL: base, publicToken: token)
        let loaded = try JSONDecoder().decode(PublicInfinitySession.self, from: JSONEncoder().encode(persisted))
        let owned = try await first.fetchCallsignAvailability(baseURL: base, names: [name], publicToken: token)
        let unowned = try await first.fetchCallsignAvailability(baseURL: base, names: [name])
        XCTAssertEqual(owned.first?.available, true)
        XCTAssertEqual(unowned.first?.available, false)
        restored.onEvent = { event in
            if case .welcome(let value) = event { restoredWelcome = value }
            if case .state(let value) = event { restoredScore = value.tanks.first(where: { $0.id == restoredWelcome?.id })?.score }
            if case .error(let value) = event { errors.append(value) }
        }
        restored.connectPublic(baseURL: loaded.baseURL, name: "A CHANGED NAME", colorIndex: 4, publicToken: loaded.publicToken)
        try await waitFor { restoredWelcome != nil && restoredScore != nil || !errors.isEmpty }
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: ", "))
        XCTAssertEqual(restoredWelcome?.id, original.id)
        XCTAssertEqual(restoredWelcome?.publicToken, token)
        XCTAssertEqual(restoredWelcome?.resumed, true)
        XCTAssertEqual(restoredScore, initialScore)
        forged.onEvent = { event in
            if case .welcome(let value) = event { forgedWelcome = value }
            if case .error(let value) = event { forgedErrors.append(value) }
        }
        forged.connectPublic(baseURL: base, name: name, colorIndex: 2, publicToken: String(repeating: "f", count: 64))
        try await waitFor { forgedWelcome != nil || !forgedErrors.isEmpty }
        XCTAssertNil(forgedWelcome, "A forged bearer must never recover another device's identity or score.")
        XCTAssertFalse(forgedErrors.isEmpty)
        XCTAssertNil(forged.welcome?.publicToken)
        XCTAssertFalse(forged.reconnect(), "A callsign conflict after the one fresh-join fallback is terminal.")
    }

    @MainActor func testLiveManualNameEditRetainsIdentityAndRecoveryIgnoresStaleDraft() async throws {
        guard let address = ProcessInfo.processInfo.environment["LEQRA_TEST_SERVER"], let base = URL(string: address) else {
            throw XCTSkip("Set LEQRA_TEST_SERVER to a disposable server with online callsign ownership.")
        }
        let first = NetworkClient(), competitor = NetworkClient(), manual = NetworkClient(), recovery = NetworkClient()
        defer { first.disconnect(); competitor.disconnect(); manual.disconnect(); recovery.disconnect() }
        let suffix = UUID().uuidString.prefix(8).uppercased()
        let initialName = "MAN " + suffix, takenName = "TAKEN " + suffix, editedName = "EDIT " + suffix
        var firstWelcome: NetworkWelcome?, competingWelcome: NetworkWelcome?, manualWelcome: NetworkWelcome?, recoveredWelcome: NetworkWelcome?
        var manualName: String?, recoveredName: String?, errors: [String] = [], conflicts: [String] = []
        first.onEvent = { event in
            if case .welcome(let value) = event { firstWelcome = value }
            if case .error(let value) = event { errors.append(value) }
        }
        competitor.onEvent = { event in
            if case .welcome(let value) = event { competingWelcome = value }
            if case .error(let value) = event { errors.append(value) }
        }
        first.connectPublic(baseURL: base, name: initialName, colorIndex: 2, updateNames: true)
        competitor.connectPublic(baseURL: base, name: takenName, colorIndex: 3, updateNames: true)
        try await waitFor { firstWelcome?.publicToken != nil && competingWelcome != nil || !errors.isEmpty }
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: ", "))
        let original = try XCTUnwrap(firstWelcome), token = try XCTUnwrap(original.publicToken)
        first.suspend()
        manual.onEvent = { event in
            if case .welcome(let value) = event { manualWelcome = value }
            if case .state(let value) = event { manualName = value.tanks.first(where: { $0.id == manualWelcome?.id })?.name }
            if case .error(let value) = event { conflicts.append(value) }
        }
        manual.connectPublic(baseURL: base, name: takenName, colorIndex: 2, publicToken: token, updateNames: true)
        try await waitFor { !conflicts.isEmpty || manualWelcome != nil }
        XCTAssertNil(manualWelcome, "Deliberate Play must reject a newly chosen occupied callsign instead of silently using the saved name.")
        XCTAssertFalse(conflicts.isEmpty)
        conflicts = []
        manual.connectPublic(baseURL: base, name: editedName, colorIndex: 2, publicToken: token, updateNames: true)
        try await waitFor { manualName == editedName || !conflicts.isEmpty }
        XCTAssertTrue(conflicts.isEmpty, conflicts.joined(separator: ", "))
        XCTAssertEqual(manualWelcome?.id, original.id)
        XCTAssertEqual(manualWelcome?.publicToken, token)
        manual.suspend()
        recovery.onEvent = { event in
            if case .welcome(let value) = event { recoveredWelcome = value }
            if case .state(let value) = event { recoveredName = value.tanks.first(where: { $0.id == recoveredWelcome?.id })?.name }
            if case .error(let value) = event { errors.append(value) }
        }
        recovery.connectPublic(baseURL: base, name: initialName, colorIndex: 2, publicToken: token)
        try await waitFor { recoveredName != nil || !errors.isEmpty }
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: ", "))
        XCTAssertEqual(recoveredWelcome?.id, original.id)
        XCTAssertEqual(recoveredName, editedName, "Automatic recovery must never apply an old locally cached name over the authoritative name.")
        let owned = try await recovery.fetchCallsignAvailability(baseURL: base, names: [initialName, editedName], publicToken: token)
        let unowned = try await recovery.fetchCallsignAvailability(baseURL: base, names: [initialName, editedName])
        XCTAssertEqual(owned.map(\.available), [true, true])
        XCTAssertEqual(unowned.map(\.available), [false, false], "Renaming must not release either claimed name to another owner.")
    }

    private func packet(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }

    @MainActor private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(12)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        if !condition() { XCTFail("Timed out waiting for authenticated public recovery."); throw GameNetworkError.timeout }
    }
}
