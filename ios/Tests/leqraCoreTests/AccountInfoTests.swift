import Foundation
import XCTest
@testable import leqraCore

final class AccountInfoTests: XCTestCase {
    private let key = "p_" + String(repeating: "A", count: 43)
    private let replacement = "p_" + String(repeating: "B", count: 43)

    func testImportedAccountChoosesSavedPublicCallsignBeforeAliases() throws {
        let info = try decode(["names": ["OLD FOX", "WING"], "totalNames": 200,
                               "publicProfile": ["name": "CURRENT FOX", "score": 37, "localName": "WING", "localScore": -2]])
        XCTAssertEqual(info.preferredCallsign, "CURRENT FOX")
        XCTAssertEqual(info.totalNames, 200)
        XCTAssertEqual(info.publicProfile?.score, 37)
        XCTAssertEqual(info.publicProfile?.localScore, -2)
        XCTAssertEqual(try decode(["names": ["PRIVATE FOX"]]).preferredCallsign, "PRIVATE FOX")
    }

    func testMalformedAccountMetadataCannotChangeSavedCallsign() throws {
        for value: [String: Any] in [
            ["names": ["FOX"], "totalNames": 0],
            ["names": [""]],
            ["names": [String(repeating: "A", count: 17)]],
            ["names": Array(repeating: "FOX", count: 129)],
            ["names": ["FOX"], "publicProfile": ["name": "", "score": 1]],
        ] { XCTAssertThrowsError(try decode(value)) }
    }

    @MainActor func testAuthenticatedAccountRequestKeepsKeyOutOfURLAndScoresOutOfBody() async throws {
        let client = transport { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://account.test/api/account")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://account.test")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let body = try self.body(request)
            XCTAssertEqual(Set(body.keys), ["publicToken"])
            XCTAssertEqual(body["publicToken"] as? String, self.key)
            return (200, ["names": ["SNOW FOX"], "totalNames": 1, "publicProfile": ["name": "SNOW FOX", "score": 37]])
        }
        let info = try await client.fetchAccountInfo(baseURL: URL(string: "https://ACCOUNT.test:443/play?publicToken=forged#score")!, publicToken: key)
        XCTAssertEqual(info.preferredCallsign, "SNOW FOX")
        XCTAssertEqual(info.publicProfile?.score, 37)
    }

    @MainActor func testInvalidAndRevokedAccountKeysHaveExplicitErrors() async throws {
        for code in ["account_key_invalid", "account_key_revoked"] {
            let client = transport { _ in (401, ["code": code, "message": "Do not display a server-supplied secret."]) }
            do {
                _ = try await client.fetchAccountInfo(baseURL: URL(string: "https://account.test")!, publicToken: key)
                XCTFail("An invalid account key was accepted")
            } catch let error as GameNetworkError {
                if code == "account_key_revoked" {
                    guard case .accountKeyRevoked = error else { return XCTFail("Expected revoked-key error") }
                } else {
                    guard case .invalidAccountKey = error else { return XCTFail("Expected invalid-key error") }
                }
                XCTAssertFalse(error.localizedDescription.contains("secret"))
            }
        }
    }

    @MainActor func testRotationUsesPersistableClientCandidateAndDoesNotUploadScore() async throws {
        let client = transport { request in
            XCTAssertEqual(request.url?.path, "/api/account/rotate")
            let body = try self.body(request)
            XCTAssertEqual(Set(body.keys), ["publicToken", "newPublicToken"])
            XCTAssertEqual(body["publicToken"] as? String, self.key)
            XCTAssertEqual(body["newPublicToken"] as? String, self.replacement)
            return (200, ["publicToken": self.replacement, "names": ["SNOW FOX"], "publicProfile": ["name": "SNOW FOX", "score": 37]])
        }
        let result = try await client.rotateAccountKey(baseURL: URL(string: "https://account.test")!, publicToken: key, newPublicToken: replacement)
        XCTAssertEqual(result.publicToken, replacement)
        XCTAssertEqual(result.account.publicProfile?.score, 37)
    }

    @MainActor func testRotationRejectsUnexpectedReplacementBeforeActivatingIt() async throws {
        let client = transport { _ in (200, ["publicToken": self.key, "names": ["SNOW FOX"]]) }
        do {
            _ = try await client.rotateAccountKey(baseURL: URL(string: "https://account.test")!, publicToken: key, newPublicToken: replacement)
            XCTFail("Unexpected server key was accepted")
        } catch let error as GameNetworkError {
            guard case .invalidResponse = error else { return XCTFail("Expected invalid response") }
        }
    }

    @MainActor func testAccountKeyPostIsNeverForwardedThroughRedirects() async throws {
        var requests = 0
        let client = transport { request in
            requests += 1
            if request.url?.host == "account.test" { return (307, ["redirect": "https://untrusted.test/api/account"]) }
            XCTFail("The account key was forwarded to another origin")
            return (200, ["names": ["FOX"]])
        }
        do {
            _ = try await client.fetchAccountInfo(baseURL: URL(string: "https://account.test")!, publicToken: key)
            XCTFail("A redirected account response was accepted")
        } catch {}
        XCTAssertEqual(requests, 1)
    }

    @MainActor func testRevokedTransportRetainsOldKeyForConditionalKeychainRemovalAndStopsRetrying() throws {
        let client = NetworkClient()
        defer { client.disconnect() }
        var notices = 0
        client.onEvent = { event in
            if case .roomEvent(.notice(let notice)) = event, notice.code == "account_key_revoked" {
                XCTAssertEqual(client.accountKey, self.key)
                notices += 1
            }
        }
        client.connectPublic(baseURL: URL(string: "http://127.0.0.1:9")!, name: "FOX", colorIndex: 0, publicToken: key)
        try client.receive(JSONSerialization.data(withJSONObject: ["type": "welcome", "id": 7, "seed": 42, "public": true, "publicToken": key]))
        try client.receive(JSONSerialization.data(withJSONObject: ["type": "error", "code": "account_key_revoked", "message": "Account key reset on another device."]))
        XCTAssertEqual(notices, 1)
        XCTAssertFalse(client.connected)
        XCTAssertFalse(client.reconnect())
    }

    @MainActor func testIndependentP2WelcomeRequiresItsOwnMatchingKey() throws {
        let client = NetworkClient()
        defer { client.disconnect() }
        client.connectPublic(baseURL: URL(string: "http://127.0.0.1:9")!, name: "FOX", colorIndex: 0,
                             localName: "WING", publicToken: key, localPublicToken: replacement, localNewAccount: true)
        XCTAssertThrowsError(try client.receive(packet(["type": "welcome", "id": 7, "localId": 8, "seed": 42, "public": true, "publicToken": key]))) { error in
            guard case GameNetworkError.localAccountUnconfirmed = error else { return XCTFail("Old server failed to confirm P2") }
        }
        XCTAssertFalse(client.connected)
        try client.receive(packet(["type": "welcome", "id": 7, "localId": 8, "seed": 42, "public": true,
                                   "publicToken": key, "localPublicToken": replacement]))
        XCTAssertEqual(client.accountKey, key)
        XCTAssertEqual(client.localAccountKey, replacement)
    }

    @MainActor func testOnlyFreshPrivateResumedCandidateMayRecoverTheRoomsExistingP2Key() throws {
        let recovered = "p_" + String(repeating: "C", count: 43)
        for fresh in [false, true] {
            let client = NetworkClient()
            defer { client.disconnect() }
            client.connectRoomInfinity(baseURL: URL(string: "http://127.0.0.1:9")!, code: "PRIVATE", token: "room-proof",
                                       resume: true, localPublicToken: replacement, localNewAccount: fresh)
            let welcome = try packet(["type": "welcome", "id": 7, "localId": 8, "seed": 42, "resumed": true,
                                      "publicToken": key, "localPublicToken": recovered])
            if fresh {
                try client.receive(welcome)
                XCTAssertEqual(client.localAccountKey, recovered)
                XCTAssertEqual(client.localAccountRequestKey, replacement, "Keychain replacement must still compare against the pre-saved candidate")
            } else {
                XCTAssertThrowsError(try client.receive(welcome)) { error in
                    guard case GameNetworkError.localAccountMismatch = error else { return XCTFail("An imported key cannot silently become another account") }
                }
            }
        }
    }

    @MainActor func testP2RevocationReportsItsSlotAndPreservesP1TransportProof() throws {
        let client = NetworkClient()
        defer { client.disconnect() }
        var affectedSeat: Int?
        client.onEvent = { event in
            if case .roomEvent(.notice(let notice)) = event, notice.code == "account_key_revoked" {
                affectedSeat = notice.seat
                XCTAssertEqual(client.accountKey, self.key)
                XCTAssertEqual(client.localAccountKey, self.replacement)
            }
        }
        client.connectPublic(baseURL: URL(string: "http://127.0.0.1:9")!, name: "FOX", colorIndex: 0,
                             localName: "WING", publicToken: key, localPublicToken: replacement)
        try client.receive(packet(["type": "welcome", "id": 7, "localId": 8, "seed": 42, "public": true,
                                   "publicToken": key, "localPublicToken": replacement]))
        try client.receive(packet(["type": "error", "code": "account_key_revoked", "seat": 1, "message": "P2 key reset elsewhere."]))
        XCTAssertEqual(affectedSeat, 1)
        XCTAssertEqual(client.accountKey, key)
        XCTAssertFalse(client.reconnect(), "A replaced pair must wait for deliberate recovery, avoiding a takeover fight")
    }

    @MainActor func testSoloPublicPlayDoesNotReattachThePreviousP2ProofOnReconnect() throws {
        let client = NetworkClient()
        defer { client.disconnect() }
        let server = URL(string: "http://127.0.0.1:9")!
        client.connectPublic(baseURL: server, name: "FOX", colorIndex: 0, localName: "WING",
                             publicToken: key, localPublicToken: replacement)
        try client.receive(packet(["type": "welcome", "id": 7, "localId": 8, "seed": 42, "public": true,
                                   "publicToken": key, "localPublicToken": replacement]))
        XCTAssertEqual(client.localAccountKey, replacement)
        client.connectPublic(baseURL: server, name: "FOX", colorIndex: 0, publicToken: key, updateNames: true)
        try client.receive(packet(["type": "welcome", "id": 7, "seed": 42, "public": true, "publicToken": key]))
        XCTAssertNil(client.localAccountKey)
        XCTAssertNil(client.localAccountRequestKey)
        client.suspend()
        XCTAssertTrue(client.reconnect())
        XCTAssertNil(client.localAccountKey)
    }

    @MainActor func testLiveP2KeyBecomesAnIndependentPrimaryOnAnotherDevice() async throws {
        guard let address = ProcessInfo.processInfo.environment["LEQRA_TEST_SERVER"], let base = URL(string: address) else {
            throw XCTSkip("Set LEQRA_TEST_SERVER to a disposable independent-account server.")
        }
        let pair = NetworkClient(), standalone = NetworkClient()
        defer { pair.disconnect(); standalone.disconnect() }
        let suffix = UUID().uuidString.prefix(8), primaryName = "PAIR " + suffix, localName = "WING " + suffix
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        let localKey = "p_" + Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        var pairWelcome: NetworkWelcome?, soloWelcome: NetworkWelcome?, soloState: ArenaSnapshot?, errors: [String] = []
        pair.onEvent = { if case .welcome(let value) = $0 { pairWelcome = value } }
        pair.connectPublic(baseURL: base, name: primaryName, colorIndex: 0, localName: localName,
                           localPublicToken: localKey, localNewAccount: true)
        try await waitFor { pairWelcome != nil }
        XCTAssertEqual(pairWelcome?.localPublicToken, localKey)
        XCTAssertNotEqual(pairWelcome?.publicToken, localKey)
        let account = try await standalone.fetchAccountInfo(baseURL: base, publicToken: localKey)
        XCTAssertEqual(account.preferredCallsign, localName)
        XCTAssertFalse(account.names.contains(primaryName))
        standalone.onEvent = { event in
            if case .welcome(let value) = event { soloWelcome = value }
            if case .state(let value) = event { soloState = value }
            if case .error(let value) = event { errors.append(value) }
        }
        standalone.connectPublic(baseURL: base, name: localName, colorIndex: 1, publicToken: localKey, updateNames: true)
        try await waitFor { soloWelcome != nil && soloState != nil || !errors.isEmpty }
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: ", "))
        XCTAssertEqual(soloWelcome?.id, pairWelcome?.localId)
        XCTAssertEqual(soloState?.tanks.first { $0.id == soloWelcome?.id }?.name, localName)
    }

    @MainActor func testLiveImportedKeyKeepsSavedPublicIdentityAndCallsign() async throws {
        guard let address = ProcessInfo.processInfo.environment["LEQRA_TEST_SERVER"], let base = URL(string: address) else {
            throw XCTSkip("Set LEQRA_TEST_SERVER to a disposable account-enabled server.")
        }
        let original = NetworkClient(), imported = NetworkClient()
        defer { original.disconnect(); imported.disconnect() }
        let name = "KEY " + UUID().uuidString.prefix(8)
        var firstWelcome: NetworkWelcome?, firstState: ArenaSnapshot?, nextWelcome: NetworkWelcome?, nextState: ArenaSnapshot?
        var errors: [String] = []
        original.onEvent = { event in
            if case .welcome(let value) = event { firstWelcome = value }
            if case .state(let value) = event { firstState = value }
        }
        original.connectPublic(baseURL: base, name: name, colorIndex: 2)
        try await waitFor { firstWelcome != nil && firstState != nil }
        let token = try XCTUnwrap(firstWelcome?.publicToken)
        let account = try await imported.fetchAccountInfo(baseURL: base, publicToken: token)
        XCTAssertEqual(account.preferredCallsign, name)
        let priorScore = try XCTUnwrap(firstState?.tanks.first { $0.id == firstWelcome?.id }?.score)
        XCTAssertEqual(account.publicProfile?.score, priorScore)
        imported.onEvent = { event in
            if case .welcome(let value) = event { nextWelcome = value }
            if case .state(let value) = event { nextState = value }
            if case .error(let value) = event { errors.append(value) }
        }
        imported.connectPublic(baseURL: base, name: try XCTUnwrap(account.preferredCallsign), colorIndex: 2, publicToken: token, updateNames: true)
        try await waitFor { nextWelcome != nil && nextState != nil || !errors.isEmpty }
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: ", "))
        XCTAssertEqual(nextWelcome?.id, firstWelcome?.id)
        XCTAssertEqual(nextState?.tanks.first { $0.id == nextWelcome?.id }?.name, name)
        XCTAssertEqual(nextState?.tanks.first { $0.id == nextWelcome?.id }?.score, priorScore)
    }

    private func decode(_ value: [String: Any]) throws -> AccountInfo {
        try JSONDecoder().decode(AccountInfo.self, from: JSONSerialization.data(withJSONObject: value))
    }
    private func packet(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    private func body(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count))
            }
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    @MainActor private func transport(_ handler: @escaping (URLRequest) throws -> (Int, [String: Any])) -> NetworkClient {
        AccountTestProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountTestProtocol.self]
        return NetworkClient(session: URLSession(configuration: configuration))
    }
    @MainActor private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while !condition() {
            guard Date() < deadline else { XCTFail("Timed out waiting for account transport"); throw GameNetworkError.timeout }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private final class AccountTestProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (Int, [String: Any]))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try XCTUnwrap(Self.handler)(request)
            if status == 307, let location = body["redirect"] as? String, let url = URL(string: location) {
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Location": location])!
                var redirected = request; redirected.url = url
                client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: body))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
