import Foundation

/// Authenticated account metadata. The private key never appears in a response.
public struct AccountInfo: Decodable, Equatable, Sendable {
    public struct PublicProfile: Decodable, Equatable, Sendable {
        public let name: String
        public let score: Int
        public let localName: String?
        public let localScore: Int?
    }

    public let names: [String]
    public let totalNames: Int
    public let publicProfile: PublicProfile?
    public var preferredCallsign: String? { publicProfile?.name ?? names.first }

    private enum CodingKeys: String, CodingKey { case names, totalNames, publicProfile }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        names = try values.decode([String].self, forKey: .names)
        totalNames = try values.decodeIfPresent(Int.self, forKey: .totalNames) ?? names.count
        publicProfile = try values.decodeIfPresent(PublicProfile.self, forKey: .publicProfile)
        guard names.count <= 128, totalNames >= names.count,
              names.allSatisfy({ !$0.isEmpty && $0.count <= 16 }),
              publicProfile.map({ !$0.name.isEmpty && $0.name.count <= 16 && ($0.localName.map { !$0.isEmpty && $0.count <= 16 } ?? true) }) ?? true else {
            throw DecodingError.dataCorruptedError(forKey: .names, in: values, debugDescription: "Invalid account metadata")
        }
    }
}

/// Returned only by an explicit rotation. Never encode or log this value.
public struct AccountKeyRotation: Decodable, Sendable {
    public let publicToken: String
    public let account: AccountInfo
    private enum CodingKeys: String, CodingKey { case publicToken }

    public init(from decoder: Decoder) throws {
        publicToken = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .publicToken)
        account = try AccountInfo(from: decoder)
    }
}
