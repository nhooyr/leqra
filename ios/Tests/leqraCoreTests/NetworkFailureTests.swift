import Foundation
import XCTest
@testable import leqraCore

final class NetworkFailureTests: XCTestCase {
    @MainActor func testMalformedBuildDiscoveryStopsPublicReconnects() async {
        for body in ["<html>Proxy error</html>", "{broken", "", "[]", String(repeating: "x", count: 8193)] {
            let client = transport(status: 200, body: body)
            let stopped = expectation(description: "Malformed discovery stops")
            var retries = 0
            client.onEvent = { event in
                if case .roomEvent(.reconnecting) = event { retries += 1 }
                if case .disconnected = event { stopped.fulfill() }
            }
            client.connectPublic(baseURL: URL(string: "https://discovery.test")!, name: "PILOT", colorIndex: 0)
            await fulfillment(of: [stopped], timeout: 2)
            XCTAssertEqual(retries, 0, "An invalid server response cannot be repaired by automatic reconnects")
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
            if case .disconnected = event { XCTFail("A temporary outage should retain the public recovery route") }
        }
        client.connectPublic(baseURL: URL(string: "https://discovery.test")!, name: "PILOT", colorIndex: 0)
        await fulfillment(of: [retry], timeout: 2)
    }

    @MainActor func testMalformedWebSocketPayloadsUseTerminalProtocolError() {
        let client = NetworkClient()
        for payload in ["<html>Proxy error</html>", "{broken", "[]", #"{"type":"welcome","id":"wrong"}"#,
                        #"{"type":"state","tanks":"wrong"}"#] {
            XCTAssertThrowsError(try client.receive(Data(payload.utf8))) { error in
                guard case GameNetworkError.invalidResponse = error else {
                    return XCTFail("Malformed wire data must be classified as a protocol error: \(error)")
                }
            }
        }
    }

    @MainActor private func transport(status: Int, body: String) -> NetworkClient {
        BuildFailureProtocol.status = status; BuildFailureProtocol.body = Data(body.utf8)
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
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
