import Foundation

/// A server-issued public identity. Scores always come from the server; a
/// callsign is never an authentication credential.
public struct PublicInfinitySession: Codable, Equatable, Sendable {
    public let origin: String
    public let publicToken: String

    public init(baseURL: URL, publicToken: String) throws {
        guard !publicToken.isEmpty, publicToken.utf8.count <= 256,
              publicToken.unicodeScalars.allSatisfy({ $0.value >= 0x21 && $0.value <= 0x7e }) else {
            throw GameNetworkError.invalidResponse
        }
        origin = try Self.normalizedOrigin(baseURL)
        self.publicToken = publicToken
    }

    public var baseURL: URL { URL(string: origin)! }

    public func matches(_ baseURL: URL) -> Bool {
        (try? Self.normalizedOrigin(baseURL)) == origin
    }

    public static func normalizedOrigin(_ baseURL: URL) throws -> String {
        let endpoint = try ServerAddress.endpoint(baseURL, path: "")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              let host = components.host else { throw GameNetworkError.invalidURL }
        components.host = host.lowercased()
        if components.scheme == "https" && components.port == 443 || components.scheme == "http" && components.port == 80 {
            components.port = nil
        }
        guard let origin = components.url?.absoluteString else { throw GameNetworkError.invalidURL }
        return origin
    }

    enum CodingKeys: String, CodingKey { case origin, publicToken }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let origin = try values.decode(String.self, forKey: .origin)
        guard let url = URL(string: origin) else { throw GameNetworkError.invalidURL }
        try self.init(baseURL: url, publicToken: values.decode(String.self, forKey: .publicToken))
    }
}
