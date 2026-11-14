import Foundation

public enum CallsignPolicy {
    /// Match the server's allowed characters, whitespace cleanup and 16-rune
    /// bound. Custom bot names are unrestricted by the human namespace rule.
    public static func clean(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = trimmed.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber: return true
            default: return scalar == " " || scalar == "_" || scalar == "-" || scalar == "#"
            }
        }.prefix(16)
        return String(String.UnicodeScalarView(allowed)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    public static func reservedForBots(_ name: String) -> Bool {
        let key = clean(name).lowercased()
        return key == "bot" || key.hasPrefix("bot ")
    }
    public static func displayName(_ name: String, bot: Bool) -> String {
        guard bot else { return name }
        if name.range(of: #"^Bot [0-9]+(?: - Godlike)?$"#, options: .regularExpression) != nil { return name }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.lowercased().hasPrefix("bot ") ? String(trimmed.dropFirst(4)) : trimmed.lowercased() == "bot" ? "" : trimmed
        return body.isEmpty ? "Bot" : "Bot " + body.capitalized(with: Locale(identifier: "en_US_POSIX"))
    }
    public static func isGenerated(_ name: String) -> Bool {
        name.range(of: #"^(?:pilot#[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}|pilot-[a-z2-7]{10})$"#, options: .regularExpression) != nil
    }
    public static func isLegacyDefault(_ name: String) -> Bool {
        let key = name.split(whereSeparator: \.isWhitespace).joined(separator: " ").uppercased()
        return ["PILOT", "PLAYER 1", "PLAYER 2", "CO-PILOT", "YOU", "SNOW FOX"].contains(key)
            || key.range(of: #"^PILOT [1-9][0-9]{2}$"#, options: .regularExpression) != nil
    }
    public static func migratingLegacyRoster(_ roster: [NativeSeatSpec], primaryName: String, secondaryName: String,
                                             unownedSeats: Set<Int>) -> [NativeSeatSpec] {
        roster.map { original in
            var seat = original
            let index = seat.kind == "human" ? 0 : seat.kind == "local" ? 1 : -1
            if unownedSeats.contains(index), isLegacyDefault(seat.name) { seat.name = index == 0 ? primaryName : secondaryName }
            return seat
        }
    }
    public static func updatingGeneratedRoster(_ roster: [NativeSeatSpec], seat: Int, previous: String, claimed: String) -> [NativeSeatSpec] {
        guard isGenerated(previous) else { return roster }
        return roster.map { original in
            var row = original
            if row.kind == (seat == 1 ? "local" : "human"), row.name == previous { row.name = claimed }
            return row
        }
    }
    public static func bootstrap() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return "pilot#" + String((0..<6).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
    }
}

public struct CallsignGenerationAttempt: Codable, Equatable, Sendable {
    public struct Draft: Codable, Equatable, Sendable {
        public let seat: Int
        public let name: String
        public let revision: String
    }
    public let requestId: UUID
    public let origin: String
    public let drafts: [Draft]
}

protocol CallsignPreferences {
    func string(forKey: String) -> String?
    func data(forKey: String) -> Data?
    func bool(forKey: String) -> Bool
    func set(_ value: Any?, forKey: String)
    func removeObject(forKey: String)
    func synchronize() -> Bool
}
extension UserDefaults: CallsignPreferences {}

/// Only names and request metadata live in preferences. Bearer keys remain in
/// Keychain and must be saved before the generation endpoint is contacted.
public final class CallsignDraftStore {
    private let defaults: CallsignPreferences
    private let attemptKey = "callsignGenerationAttempt"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    init(preferences: CallsignPreferences) { self.defaults = preferences }
    private func nameKey(_ seat: Int) -> String { seat == 1 ? "localCallsign" : "callsign" }
    private func pendingKey(_ seat: Int) -> String { nameKey(seat) + "AutoPending" }
    private func revisionKey(_ seat: Int) -> String { nameKey(seat) + "Revision" }
    /// Invoke once at startup, before any new credential is prepared. Stored
    /// credentials, including malformed ones, must not be replaced by repair.
    @discardableResult public func migrateLegacyDefaults(credentialPresent: (Int) -> Bool) -> Set<Int> {
        var migrated = Set<Int>()
        for seat in 0...1 {
            guard !credentialPresent(seat), let old = defaults.string(forKey: nameKey(seat)), CallsignPolicy.isLegacyDefault(old) else { continue }
            defaults.removeObject(forKey: nameKey(seat))
            _ = name(seat: seat)
            migrated.insert(seat)
        }
        return migrated
    }
    public func name(seat: Int) -> String {
        if let existing = defaults.string(forKey: nameKey(seat)) { return existing }
        var value = CallsignPolicy.bootstrap()
        while value == defaults.string(forKey: nameKey(seat == 1 ? 0 : 1)) { value = CallsignPolicy.bootstrap() }
        defaults.set(value, forKey: nameKey(seat))
        defaults.set(true, forKey: pendingKey(seat))
        defaults.set(value, forKey: pendingKey(seat) + "Name")
        defaults.set(UUID().uuidString, forKey: revisionKey(seat))
        return value
    }
    public func automaticPending(seat: Int) -> Bool {
        defaults.bool(forKey: pendingKey(seat)) && defaults.string(forKey: pendingKey(seat) + "Name") == defaults.string(forKey: nameKey(seat))
    }
    public func edited(_ name: String, seat: Int) {
        defaults.set(name, forKey: nameKey(seat))
        defaults.set(false, forKey: pendingKey(seat))
        defaults.set(UUID().uuidString, forKey: revisionKey(seat))
    }
    public func editorChanged(from previous: String, to name: String, seat: Int) {
        guard previous != name else { return }
        if CallsignPolicy.reservedForBots(name) { invalidateEditedDraft(seat: seat) }
        else { edited(name, seat: seat) }
    }
    public func invalidateEditedDraft(seat: Int) {
        defaults.set(false, forKey: pendingKey(seat))
        defaults.set(UUID().uuidString, forKey: revisionKey(seat))
    }
    public func begin(server: URL, seats: [Int]) throws -> CallsignGenerationAttempt {
        let origin = try PublicInfinitySession.normalizedOrigin(server)
        let requested = Set(seats)
        var attempts = savedAttempts()
        if let old = attempts.first(where: { value in
            value.origin == origin && requested.isSubset(of: Set(value.drafts.map(\.seat)))
                && value.drafts.filter { requested.contains($0.seat) }.allSatisfy { matches($0) }
        }) {
            guard defaults.synchronize() else { throw GameNetworkError.temporarilyUnavailable }
            return CallsignGenerationAttempt(requestId: old.requestId, origin: old.origin, drafts: old.drafts.filter { requested.contains($0.seat) })
        }
        let drafts = seats.sorted().map { seat -> CallsignGenerationAttempt.Draft in
            let value = name(seat: seat)
            let revision = defaults.string(forKey: revisionKey(seat)) ?? UUID().uuidString
            defaults.set(revision, forKey: revisionKey(seat))
            return .init(seat: seat, name: value, revision: revision)
        }
        let attempt = CallsignGenerationAttempt(requestId: UUID(), origin: origin, drafts: drafts)
        // A manual request for P1 must not erase P2's ambiguous earlier retry.
        attempts = attempts.compactMap { previous in
            guard previous.origin == origin else { return previous }
            let remaining = previous.drafts.filter { !requested.contains($0.seat) }
            return remaining.isEmpty ? nil : .init(requestId: previous.requestId, origin: origin, drafts: remaining)
        }
        attempts.append(attempt)
        defaults.set(try JSONEncoder().encode(Array(attempts.suffix(8))), forKey: attemptKey)
        guard defaults.synchronize() else { throw GameNetworkError.temporarilyUnavailable }
        return attempt
    }
    public func matches(_ draft: CallsignGenerationAttempt.Draft) -> Bool {
        defaults.string(forKey: nameKey(draft.seat)) == draft.name && defaults.string(forKey: revisionKey(draft.seat)) == draft.revision
    }
    @discardableResult public func apply(_ name: String, seat: Int, attempt: CallsignGenerationAttempt) -> Bool {
        guard let draft = attempt.drafts.first(where: { $0.seat == seat }), matches(draft) else { return false }
        edited(name, seat: seat)
        return true
    }
    public func provisionalName(seat: Int, attempt: CallsignGenerationAttempt) throws -> String? {
        guard let draft = attempt.drafts.first(where: { $0.seat == seat }), matches(draft) else { return nil }
        var name = CallsignPolicy.bootstrap()
        while name == defaults.string(forKey: nameKey(seat == 1 ? 0 : 1)) { name = CallsignPolicy.bootstrap() }
        let revision = UUID().uuidString
        defaults.set(name, forKey: nameKey(seat)); defaults.set(revision, forKey: revisionKey(seat))
        defaults.set(true, forKey: pendingKey(seat)); defaults.set(name, forKey: pendingKey(seat) + "Name")
        let attempts = savedAttempts().map { old -> CallsignGenerationAttempt in
            guard old.requestId == attempt.requestId else { return old }
            return .init(requestId: old.requestId, origin: old.origin, drafts: old.drafts.map {
                $0.seat == seat ? .init(seat: seat, name: name, revision: revision) : $0
            })
        }
        defaults.set(try JSONEncoder().encode(attempts), forKey: attemptKey)
        guard defaults.synchronize() else { throw GameNetworkError.temporarilyUnavailable }
        return name
    }
    public func complete(_ attempt: CallsignGenerationAttempt) {
        let completed = Set(attempt.drafts.map(\.seat))
        let remaining = savedAttempts().compactMap { current -> CallsignGenerationAttempt? in
            guard current.requestId == attempt.requestId else { return current }
            let drafts = current.drafts.filter { !completed.contains($0.seat) }
            return drafts.isEmpty ? nil : .init(requestId: current.requestId, origin: current.origin, drafts: drafts)
        }
        if let data = try? JSONEncoder().encode(remaining) { defaults.set(data, forKey: attemptKey) }
    }
    private func savedAttempts() -> [CallsignGenerationAttempt] {
        guard let data = defaults.data(forKey: attemptKey) else { return [] }
        if let array = try? JSONDecoder().decode([CallsignGenerationAttempt].self, from: data) { return array }
        return (try? JSONDecoder().decode(CallsignGenerationAttempt.self, from: data)).map { [$0] } ?? []
    }
}

public struct GeneratedCallsign: Decodable, Equatable, Sendable {
    public let seat: Int
    public let name: String
}
