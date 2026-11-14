import Foundation
import XCTest
import leqraCore
@testable import leqraAccountStore

@MainActor
final class AccountKeychainTests: XCTestCase {
    private let base = URL(string: "https://leqra.test")!
    private func credential(_ letter: String, server: URL? = nil) throws -> PublicInfinitySession {
        try PublicInfinitySession(baseURL: server ?? base, publicToken: "p_" + String(repeating: letter, count: 43))
    }

    func testMalformedStoredCredentialsStillProtectLegacyNamesFromMigration() throws {
        let io = MemoryAccountKeychain(), store = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        XCTAssertFalse(store.hasStoredCredential(for: base, seat: 0))
        XCTAssertTrue(store.remember(try credential("A"), seat: 0))
        let account = try XCTUnwrap(io.values.keys.first { $0.hasPrefix("identity-") })
        io.values[account] = Data("malformed saved credential".utf8)
        XCTAssertNil(store.session(for: base, seat: 0))
        XCTAssertTrue(store.hasStoredCredential(for: base, seat: 0))
        XCTAssertFalse(store.hasStoredCredential(for: base, seat: 1))
        XCTAssertFalse(store.hasStoredCredential(for: URL(string: "https://other.test")!, seat: 0))
    }

    func testP1AndP2CredentialsAndOriginsStayIndependent() throws {
        let io = MemoryAccountKeychain()
        let tested = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        let primary = try credential("A"), local = try credential("B")
        XCTAssertTrue(tested.remember(primary, seat: 0)); XCTAssertTrue(tested.remember(local, seat: 1))
        XCTAssertEqual(tested.session(for: base, seat: 0), primary)
        XCTAssertEqual(tested.session(for: base, seat: 1), local)
        XCTAssertNil(tested.session(for: URL(string: "http://leqra.test")!, seat: 1))
        XCTAssertNil(tested.session(for: URL(string: "https://other.test")!, seat: 0))
        XCTAssertTrue(tested.forget(base, ifMatching: primary.publicToken, seat: 1))
        XCTAssertEqual(tested.session(for: base, seat: 1), local, "P1's old event cannot erase P2")
    }

    func testFreshCandidateSurvivesImportAndStaleWelcomeUntilExplicitRecovery() throws {
        let io = MemoryAccountKeychain(), store = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        let candidate = try credential("C"), imported = try credential("B")
        XCTAssertTrue(store.rememberNew(candidate, seat: 1))
        XCTAssertTrue(store.registrationPending(for: base, seat: 1))
        // The candidate's server join may commit after this import.
        XCTAssertTrue(store.remember(imported, seat: 1))
        XCTAssertEqual(store.registrationCandidates(for: base, seat: 1), [candidate])
        XCTAssertFalse(store.confirm(candidate, requested: candidate.publicToken, seat: 1))
        XCTAssertEqual(store.session(for: base, seat: 1), imported)
        XCTAssertEqual(store.registrationCandidates(for: base, seat: 1), [candidate])
        let cold = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        XCTAssertEqual(cold.registrationCandidates(for: base, seat: 1), [candidate])
        // Only a deliberate, validated selection makes this backup redundant.
        XCTAssertTrue(cold.remember(candidate, seat: 1))
        XCTAssertEqual(cold.session(for: base, seat: 1), candidate)
        XCTAssertTrue(cold.registrationCandidates(for: base, seat: 1).isEmpty)
    }

    func testFreshPrivateResumeCanConfirmRecoveredKeyWithoutLosingUnusedCandidate() throws {
        let io = MemoryAccountKeychain(), store = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        let candidate = try credential("C"), recovered = try credential("B")
        XCTAssertTrue(store.rememberNew(candidate, seat: 1))
        XCTAssertTrue(store.confirm(recovered, requested: candidate.publicToken, seat: 1))
        XCTAssertEqual(store.session(for: base, seat: 1), recovered)
        XCTAssertFalse(store.registrationPending(for: base, seat: 1))
        XCTAssertEqual(store.registrationCandidates(for: base, seat: 1), [candidate])
    }

    func testRotationPendingRecordsAndColdLocalIntentAreScopedToEachSeat() throws {
        let io = MemoryAccountKeychain(), store = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        let primary = try credential("A"), local = try credential("B")
        let primaryNext = try credential("D"), localNext = try credential("E")
        XCTAssertTrue(store.remember(primary, seat: 0)); XCTAssertTrue(store.remember(local, seat: 1))
        XCTAssertTrue(store.activate(base, local: true))
        let p1 = PendingAccountKey(previous: primary, replacement: primaryNext), p2 = PendingAccountKey(previous: local, replacement: localNext)
        XCTAssertTrue(store.rememberPendingKey(p1, seat: 0)); XCTAssertTrue(store.rememberPendingKey(p2, seat: 1))
        XCTAssertTrue(store.clearPendingKey(base, ifMatching: primaryNext.publicToken, seat: 1))
        let cold = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        XCTAssertEqual(cold.pendingKey(for: base, seat: 0), p1); XCTAssertEqual(cold.pendingKey(for: base, seat: 1), p2)
        XCTAssertTrue(cold.activeLocal); XCTAssertEqual(cold.activeServer, base)
        XCTAssertTrue(cold.remember(localNext, seat: 1))
        XCTAssertEqual(cold.session(for: base, seat: 0), primary)
        XCTAssertTrue(cold.forget(base, ifMatching: local.publicToken, seat: 1))
        XCTAssertEqual(cold.session(for: base, seat: 1), localNext, "A late revocation cannot delete the replacement")
        XCTAssertTrue(cold.activate(base, local: false))
        XCTAssertFalse(cold.activeLocal); XCTAssertEqual(cold.activeServer, base)
        XCTAssertEqual(cold.pendingKey(for: base, seat: 0), p1)
    }

    func testCandidateBackupIsWrittenBeforeSelectedCredentialAndSurvivesWriteFailure() throws {
        let io = MemoryAccountKeychain(), store = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        io.failSelectedLocalWrites = true
        let candidate = try credential("C")
        XCTAssertFalse(store.rememberNew(candidate, seat: 1))
        XCTAssertNil(store.session(for: base, seat: 1))
        XCTAssertEqual(store.registrationCandidates(for: base, seat: 1), [candidate])
        XCTAssertTrue(io.writes.first?.hasPrefix("registrations-local-identity-") == true)
    }

    func testLegacyPrimaryIntentAndCredentialsRemainReadableWithoutSelectingP2() throws {
        let io = MemoryAccountKeychain(), store = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        let primary = try credential("A")
        XCTAssertTrue(store.remember(primary))
        io.values["active-origin"] = Data("https://leqra.test".utf8)
        let cold = KeychainPublicInfinitySessions(namespace: "unit", storage: io)
        XCTAssertEqual(cold.activeServer, base); XCTAssertFalse(cold.activeLocal)
        XCTAssertEqual(cold.session(for: base), primary); XCTAssertNil(cold.session(for: base, seat: 1))
    }
}

@MainActor
private final class MemoryAccountKeychain: AccountKeychainIO {
    var values: [String: Data] = [:]
    var writes: [String] = []
    var failSelectedLocalWrites = false
    func read(account: String) -> Data? { values[account] }
    func write(_ data: Data, account: String) -> Bool {
        writes.append(account)
        if failSelectedLocalWrites && account.hasPrefix("local-identity-") { return false }
        values[account] = data; return true
    }
    func delete(account: String?) -> Bool {
        if let account { values.removeValue(forKey: account) } else { values.removeAll() }
        return true
    }
}
