import Foundation
import CryptoKit
import Security
import leqraCore

@MainActor
protocol PublicInfinitySessionStoring: AnyObject {
    var activeServer: URL? { get }
    func session(for server: URL) -> PublicInfinitySession?
    @discardableResult func remember(_ session: PublicInfinitySession) -> Bool
    @discardableResult func activate(_ server: URL?) -> Bool
}

/// Public bearer credentials stay on this device. Callsigns and scores are
/// deliberately absent from this store; the server owns both identity and score.
@MainActor
final class KeychainPublicInfinitySessions: PublicInfinitySessionStoring {
    private let service: String

    init(namespace: String? = nil) {
        let suffix = namespace.map { value in
            String(value.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }.prefix(80))
        }
        service = "com.leqra.ios.public-infinity" + (suffix.map { "." + ($0.isEmpty ? "test" : $0) } ?? "")
    }

    static func applicationStore(arguments: [String] = ProcessInfo.processInfo.arguments) -> KeychainPublicInfinitySessions {
        let index = arguments.firstIndex(of: "--public-session-test-namespace")
        let testNamespace = index.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        let diagnostic = arguments.contains("--native-performance-probe") || arguments.contains("--native-render-probe")
        let result = KeychainPublicInfinitySessions(namespace: testNamespace ?? (diagnostic ? "diagnostic" : nil))
        if testNamespace != nil, arguments.contains("--reset-public-session-test-store") {
            SecItemDelete(result.query(account: nil) as CFDictionary)
        }
        return result
    }

    var activeServer: URL? {
        guard let data = read(account: "active-origin"), let origin = String(data: data, encoding: .utf8),
              let url = URL(string: origin), (try? PublicInfinitySession.normalizedOrigin(url)) == origin else { return nil }
        return url
    }

    func session(for server: URL) -> PublicInfinitySession? {
        guard let origin = try? PublicInfinitySession.normalizedOrigin(server),
              let data = read(account: account(for: origin)),
              let result = try? JSONDecoder().decode(PublicInfinitySession.self, from: data), result.matches(server) else { return nil }
        return result
    }

    @discardableResult func remember(_ session: PublicInfinitySession) -> Bool {
        guard let data = try? JSONEncoder().encode(session) else { return false }
        return write(data, account: account(for: session.origin))
    }

    @discardableResult func activate(_ server: URL?) -> Bool {
        guard let server else {
            let status = SecItemDelete(query(account: "active-origin") as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        guard let origin = try? PublicInfinitySession.normalizedOrigin(server) else { return false }
        return write(Data(origin.utf8), account: "active-origin")
    }

    private func account(for origin: String) -> String {
        "identity-" + SHA256.hash(data: Data(origin.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func query(account: String?) -> [String: Any] {
        var result: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrSynchronizable as String: false]
        result[kSecAttrAccount as String] = account
        return result
    }

    private func read(account: String) -> Data? {
        var values = query(account: account)
        values[kSecReturnData as String] = true
        values[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(values as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func write(_ data: Data, account: String) -> Bool {
        let match = query(account: account)
        let status = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var values = match
        values[kSecValueData as String] = data
        values[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(values as CFDictionary, nil) == errSecSuccess
    }
}
