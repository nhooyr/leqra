import Foundation
import CryptoKit
import Security
import leqraCore

struct PendingAccountKey: Codable, Equatable {
    let previous: PublicInfinitySession
    let replacement: PublicInfinitySession
}

/// Injection keeps credential lifecycle regressions isolated from real Keychain
/// entries. The app always uses the Security-backed default below.
@MainActor
protocol AccountKeychainIO: AnyObject {
    func read(account: String) -> Data?
    func write(_ data: Data, account: String) -> Bool
    func delete(account: String?) -> Bool
}

@MainActor
protocol PublicInfinitySessionStoring: AnyObject {
    var activeServer: URL? { get }
    var activeLocal: Bool { get }
    func session(for server: URL, seat: Int) -> PublicInfinitySession?
    func hasStoredCredential(for server: URL, seat: Int) -> Bool
    @discardableResult func remember(_ session: PublicInfinitySession, seat: Int) -> Bool
    @discardableResult func confirm(_ session: PublicInfinitySession, requested: String?, seat: Int) -> Bool
    @discardableResult func rememberNew(_ session: PublicInfinitySession, seat: Int) -> Bool
    func registrationPending(for server: URL, seat: Int) -> Bool
    func registrationCandidates(for server: URL, seat: Int) -> [PublicInfinitySession]
    @discardableResult func activate(_ server: URL?, local: Bool) -> Bool
    @discardableResult func forget(_ server: URL, ifMatching key: String, seat: Int) -> Bool
    func pendingKey(for server: URL, seat: Int) -> PendingAccountKey?
    @discardableResult func rememberPendingKey(_ pending: PendingAccountKey, seat: Int) -> Bool
    @discardableResult func clearPendingKey(_ server: URL, ifMatching key: String, seat: Int) -> Bool
}

extension PublicInfinitySessionStoring {
    func hasStoredCredential(for server: URL, seat: Int) -> Bool { session(for: server, seat: seat) != nil || pendingKey(for: server, seat: seat) != nil }
    func session(for server: URL) -> PublicInfinitySession? { session(for: server, seat: 0) }
    @discardableResult func remember(_ session: PublicInfinitySession) -> Bool { remember(session, seat: 0) }
    @discardableResult func activate(_ server: URL?) -> Bool { activate(server, local: false) }
    @discardableResult func forget(_ server: URL, ifMatching key: String) -> Bool { forget(server, ifMatching: key, seat: 0) }
    func pendingKey(for server: URL) -> PendingAccountKey? { pendingKey(for: server, seat: 0) }
    @discardableResult func rememberPendingKey(_ pending: PendingAccountKey) -> Bool { rememberPendingKey(pending, seat: 0) }
    @discardableResult func clearPendingKey(_ server: URL, ifMatching key: String) -> Bool { clearPendingKey(server, ifMatching: key, seat: 0) }
}

/// Public bearer credentials stay on this device. Callsigns and scores are
/// deliberately absent from this store; the server owns both identity and score.
@MainActor
final class KeychainPublicInfinitySessions: PublicInfinitySessionStoring {
    private let service: String
    private let storage: AccountKeychainIO?

    init(namespace: String? = nil, storage: AccountKeychainIO? = nil) {
        self.storage = storage
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
            result.delete(account: nil)
        }
        return result
    }

    private struct ActiveIntent: Codable { let origin: String; let local: Bool }
    private struct FreshCredential: Codable { let origin: String; let publicToken: String; let registrationPending: Bool }

    private var activeIntent: ActiveIntent? {
        guard let data = read(account: "active-origin") else { return nil }
        if let value = try? JSONDecoder().decode(ActiveIntent.self, from: data) { return value }
        return String(data: data, encoding: .utf8).map { ActiveIntent(origin: $0, local: false) }
    }
    var activeServer: URL? {
        guard let intent = activeIntent, let url = URL(string: intent.origin),
              (try? PublicInfinitySession.normalizedOrigin(url)) == intent.origin else { return nil }
        return url
    }
    var activeLocal: Bool { activeIntent?.local ?? false }

    func session(for server: URL, seat: Int) -> PublicInfinitySession? {
        guard let origin = try? PublicInfinitySession.normalizedOrigin(server),
              let data = read(account: account(for: origin, seat: seat)),
              let result = try? JSONDecoder().decode(PublicInfinitySession.self, from: data), result.matches(server) else { return nil }
        return result
    }

    func hasStoredCredential(for server: URL, seat: Int) -> Bool {
        guard let origin = try? PublicInfinitySession.normalizedOrigin(server) else { return false }
        let selected = account(for: origin, seat: seat)
        return read(account: selected) != nil || read(account: "pending-" + selected) != nil
    }

    @discardableResult func remember(_ session: PublicInfinitySession, seat: Int) -> Bool {
        guard let data = try? JSONEncoder().encode(session) else { return false }
        guard write(data, account: account(for: session.origin, seat: seat)) else { return false }
        // Only the selected, durably saved credential makes its backup redundant.
        let backupAccount = "registrations-" + account(for: session.origin, seat: seat)
        if let old = read(account: backupAccount), let backups = try? JSONDecoder().decode([PublicInfinitySession].self, from: old),
           let updated = try? JSONEncoder().encode(backups.filter { $0 != session }) { _ = write(updated, account: backupAccount) }
        return true
    }

    @discardableResult func confirm(_ session: PublicInfinitySession, requested: String?, seat: Int) -> Bool {
        let current = self.session(for: session.baseURL, seat: seat)
        guard current == nil || current == session || current?.publicToken == requested else { return false }
        return remember(session, seat: seat)
    }

    @discardableResult func activate(_ server: URL?, local: Bool) -> Bool {
        guard let server else {
            return delete(account: "active-origin")
        }
        guard let origin = try? PublicInfinitySession.normalizedOrigin(server) else { return false }
        guard let data = try? JSONEncoder().encode(ActiveIntent(origin: origin, local: local)) else { return false }
        return write(data, account: "active-origin")
    }

    @discardableResult func forget(_ server: URL, ifMatching key: String, seat: Int) -> Bool {
        guard let saved = session(for: server, seat: seat), saved.publicToken == key else { return true }
        return delete(account: account(for: saved.origin, seat: seat))
    }

    func pendingKey(for server: URL, seat: Int) -> PendingAccountKey? {
        guard let origin = try? PublicInfinitySession.normalizedOrigin(server),
              let data = read(account: "pending-" + account(for: origin, seat: seat)),
              let pending = try? JSONDecoder().decode(PendingAccountKey.self, from: data),
              pending.previous.matches(server), pending.replacement.matches(server) else { return nil }
        return pending
    }

    @discardableResult func rememberPendingKey(_ pending: PendingAccountKey, seat: Int) -> Bool {
        guard pending.previous.origin == pending.replacement.origin,
              let data = try? JSONEncoder().encode(pending) else { return false }
        return write(data, account: "pending-" + account(for: pending.previous.origin, seat: seat))
    }

    @discardableResult func clearPendingKey(_ server: URL, ifMatching key: String, seat: Int) -> Bool {
        guard let pending = pendingKey(for: server, seat: seat), pending.replacement.publicToken == key else { return true }
        return delete(account: "pending-" + account(for: pending.replacement.origin, seat: seat))
    }

    @discardableResult func rememberNew(_ session: PublicInfinitySession, seat: Int) -> Bool {
        let backupAccount = "registrations-" + account(for: session.origin, seat: seat)
        var backups: [PublicInfinitySession] = []
        if let data = read(account: backupAccount) {
            guard let saved = try? JSONDecoder().decode([PublicInfinitySession].self, from: data),
                  saved.allSatisfy({ $0.matches(session.baseURL) }) else { return false }
            backups = saved
        }
        if !backups.contains(session) { backups.append(session) }
        guard let backup = try? JSONEncoder().encode(backups), write(backup, account: backupAccount) else { return false }
        guard let data = try? JSONEncoder().encode(FreshCredential(origin: session.origin, publicToken: session.publicToken, registrationPending: true)) else { return false }
        return write(data, account: account(for: session.origin, seat: seat))
    }

    func registrationCandidates(for server: URL, seat: Int) -> [PublicInfinitySession] {
        guard let origin = try? PublicInfinitySession.normalizedOrigin(server),
              let data = read(account: "registrations-" + account(for: origin, seat: seat)),
              let saved = try? JSONDecoder().decode([PublicInfinitySession].self, from: data) else { return [] }
        return saved.filter { $0.matches(server) }
    }

    func registrationPending(for server: URL, seat: Int) -> Bool {
        guard let origin = try? PublicInfinitySession.normalizedOrigin(server),
              let data = read(account: account(for: origin, seat: seat)),
              let value = try? JSONDecoder().decode(FreshCredential.self, from: data) else { return false }
        return value.registrationPending
    }

    static func replacement(for previous: PublicInfinitySession) throws -> PublicInfinitySession {
        try newCredential(for: previous.baseURL)
    }

    static func newCredential(for server: URL) throws -> PublicInfinitySession {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw GameNetworkError.temporarilyUnavailable
        }
        let encoded = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return try PublicInfinitySession(baseURL: server, publicToken: "p_" + encoded)
    }

    private func account(for origin: String, seat: Int) -> String {
        (seat == 1 ? "local-identity-" : "identity-") + SHA256.hash(data: Data(origin.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func query(account: String?) -> [String: Any] {
        var result: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrSynchronizable as String: false]
        result[kSecAttrAccount as String] = account
        return result
    }

    private func read(account: String) -> Data? {
        if let storage { return storage.read(account: account) }
        var values = query(account: account)
        values[kSecReturnData as String] = true
        values[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(values as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func write(_ data: Data, account: String) -> Bool {
        if let storage { return storage.write(data, account: account) }
        let match = query(account: account)
        let status = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var values = match
        values[kSecValueData as String] = data
        values[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(values as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult private func delete(account: String?) -> Bool {
        if let storage { return storage.delete(account: account) }
        let status = SecItemDelete(query(account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
