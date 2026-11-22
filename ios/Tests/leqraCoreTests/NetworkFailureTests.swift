import Foundation
import XCTest

@testable import leqraCore

final class NetworkFailureTests: XCTestCase {
    @MainActor func testConnectedServerVersionFollowsHandshakeAndClearsOnDisconnect() throws {
        let client = NetworkClient()
        defer { client.disconnect() }
        try client.receive(Data(#"{"type":"server_hello","version":"v9.1.0-dev","protocol":1}"#.utf8))
        XCTAssertNil(client.connectedServerVersion)
        try client.receive(Data(#"{"type":"welcome","id":0,"protocol":1}"#.utf8))
        XCTAssertEqual(client.connectedServerVersion, "v9.1.0-dev")
        client.disconnect()
        XCTAssertNil(client.connectedServerVersion)
        try client.receive(
            Data(#"{"type":"welcome","id":1,"public":true,"version":"v9.2.0","protocol":1}"#.utf8))
        XCTAssertEqual(client.connectedServerVersion, "v9.2.0")
        client.disconnect()
        try client.receive(Data(#"{"type":"welcome","id":1,"protocol":1}"#.utf8))
        XCTAssertNil(
            client.connectedServerVersion, "A new server cannot inherit the previous server's version")
    }

    @MainActor func testBuildDiscoveryAcceptsDifferentOrMissingReleasesOnTheSameProtocol() {
        for build in [
            #"{"version":"99.0.0","protocol":\#(NetworkClient.protocolVersion)}"#,
            #"{"version":"0.1.0"}"#,
            #"{"protocol":\#(NetworkClient.protocolVersion)}"#,
        ] {
            XCTAssertNoThrow(try NetworkClient.validateServerProtocol(Data(build.utf8)))
        }
    }

    @MainActor func testIncompatibleBuildStopsPublicReconnectsEvenWithTheSameRelease() async {
        let body = """
            {"version":"\(NetworkClient.supportedVersion)","protocol":\(NetworkClient.protocolVersion + 1)}
            """
        let client = transport(status: 200, body: body)
        defer { client.disconnect() }
        let stopped = expectation(description: "Incompatible protocol stops discovery")
        var errors: [String] = []
        client.onEvent = { event in
            if case .error(let message) = event { errors.append(message) }
            if case .roomEvent(.reconnecting) = event {
                XCTFail("An incompatible protocol cannot be retried.")
            }
            if case .disconnected = event { stopped.fulfill() }
        }
        client.connectPublic(baseURL: URL(string: "https://discovery.test")!, name: "PILOT", colorIndex: 0)
        await fulfillment(of: [stopped], timeout: 2)
        XCTAssertEqual(errors, [GameNetworkError.unsupportedProtocol.localizedDescription])
        XCTAssertFalse(client.reconnect())
    }

    @MainActor func testMalformedBuildDiscoveryStopsPublicReconnects() async {
        for body in [
            "<html>Proxy error</html>", "{broken", "", "[]", String(repeating: "x", count: 8193),
            #"{"version":"1.0.0","protocol":true}"#, #"{"version":"1.0.0","protocol":null}"#,
        ] {
            let client = transport(status: 200, body: body)
            let stopped = expectation(description: "Malformed discovery stops")
            var retries = 0
            client.onEvent = { event in
                if case .roomEvent(.reconnecting) = event { retries += 1 }
                if case .disconnected = event { stopped.fulfill() }
            }
            client.connectPublic(
                baseURL: URL(string: "https://discovery.test")!, name: "PILOT", colorIndex: 0)
            await fulfillment(of: [stopped], timeout: 2)
            XCTAssertEqual(
                retries, 0, "An invalid server response cannot be repaired by automatic reconnects")
            XCTAssertFalse(client.reconnect())
            client.disconnect()
        }
    }

    @MainActor func testTemporaryBuildOutageStillRetries() async {
        let client = transport(status: 503, body: "Unavailable")
        defer { client.disconnect() }
        let retry = expectation(description: "Temporary outage retries")
        client.onEvent = { event in
            if case .roomEvent(.reconnecting) = event { retry.fulfill() }
            if case .disconnected = event {
                XCTFail("A temporary outage should retain the public recovery route")
            }
        }
        client.connectPublic(baseURL: URL(string: "https://discovery.test")!, name: "PILOT", colorIndex: 0)
        await fulfillment(of: [retry], timeout: 2)
    }

    @MainActor func testMalformedWebSocketPayloadsUseTerminalProtocolError() {
        let client = NetworkClient()
        for payload in [
            "<html>Proxy error</html>", "{broken", "[]", #"{"type":"welcome","id":"wrong"}"#,
            #"{"type":"state","tanks":"wrong"}"#,
        ] {
            XCTAssertThrowsError(try client.receive(Data(payload.utf8))) { error in
                guard case GameNetworkError.invalidResponse = error else {
                    return XCTFail("Malformed wire data must be classified as a protocol error: \(error)")
                }
            }
        }
    }

    @MainActor func testRoomHelloChecksProtocolIndependentlyOfRelease() throws {
        let client = NetworkClient()
        let compatible = """
            {"type":"server_hello","version":"99.0.0","protocol":\(NetworkClient.protocolVersion)}
            """
        XCTAssertNoThrow(try client.receive(Data(compatible.utf8)))
        let incompatible = """
            {"type":"server_hello","version":"\(NetworkClient.supportedVersion)","protocol":\(NetworkClient.protocolVersion + 1)}
            """
        XCTAssertThrowsError(try client.receive(Data(incompatible.utf8))) { error in
            guard case GameNetworkError.unsupportedProtocol = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    @MainActor func testInfinityWelcomeValidatesEpochBeforeAcceptingThePilot() throws {
        let client = NetworkClient()
        defer { client.disconnect() }
        client.connectPublic(baseURL: URL(string: "http://127.0.0.1:9")!, name: "PILOT", colorIndex: 0)
        let incompatible = """
            {"type":"welcome","id":1,"public":true,"protocol":\(NetworkClient.protocolVersion + 1)}
            """
        XCTAssertThrowsError(try client.receive(Data(incompatible.utf8))) { error in
            guard case GameNetworkError.unsupportedProtocol = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertFalse(client.connected)
        XCTAssertNil(client.welcome)

        let compatible = """
            {"type":"welcome","id":1,"public":true,"protocol":\(NetworkClient.protocolVersion)}
            """
        try client.receive(Data(compatible.utf8))
        XCTAssertTrue(client.connected)
    }

    @MainActor private func transport(status: Int, body: String) -> NetworkClient {
        BuildFailureProtocol.status = status
        BuildFailureProtocol.body = Data(body.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BuildFailureProtocol.self]
        return NetworkClient(session: URLSession(configuration: configuration))
    }
}

private final class BuildFailureProtocol: URLProtocol, @unchecked Sendable {
    static var status = 200
    static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
