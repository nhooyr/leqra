import Foundation

extension RoomRules {
    public static func validatedInfinityBotSpawnRates(_ rates: [String: Double]) -> [String: Double] {
        var validated: [String: Double] = [:]
        for level in BotDifficulty.allCases.map(\.rawValue) {
            if let rate = rates[level], rate.isFinite, (0...4).contains(rate) { validated[level] = rate }
        }
        return validated
    }

    /// Missing maps retain the total cadence of older room presets. An explicit
    /// empty map represents all difficulties Off and never falls back to legacy.
    public var effectiveInfinityBotSpawnRates: [String: Double] {
        if let rates = infinityBotSpawnRates { return Self.validatedInfinityBotSpawnRates(rates) }
        let levels = BotDifficulty.allCases.map(\.rawValue)
        let ceiling = levels.firstIndex(of: infinityBotDifficulty) ?? 2
        let enabled = infinityRandomDifficulty ? Array(levels.prefix(ceiling + 1)) : [levels[ceiling]]
        let rate = [0.5, 1, 2, 4].contains(infinityBotSpawnRate) ? infinityBotSpawnRate : 2
        return Dictionary(uniqueKeysWithValues: enabled.map { ($0, rate / Double(enabled.count)) })
    }

    public var totalInfinityBotSpawnRate: Double {
        let rates = effectiveInfinityBotSpawnRates
        return BotDifficulty.allCases.reduce(0) { $0 + (rates[$1.rawValue] ?? 0) }
    }

    public func infinityRoamingDifficulty(at unit: Double) -> String? {
        guard unit.isFinite else { return nil }
        let rates = effectiveInfinityBotSpawnRates
        let levels = BotDifficulty.allCases.map(\.rawValue)
        let total = levels.reduce(0) { $0 + (rates[$1] ?? 0) }
        guard total > 0 else { return nil }
        var remaining = min(1.0.nextDown, max(0, unit)) * total
        var last: String?
        for level in levels {
            let rate = rates[level] ?? 0
            guard rate > 0 else { continue }
            last = level
            if remaining < rate { return level }
            remaining -= rate
        }
        return last
    }

    public mutating func setInfinityBotSpawnRate(_ rate: Double, for difficulty: String) {
        guard BotDifficulty(rawValue: difficulty) != nil else { return }
        var rates = effectiveInfinityBotSpawnRates
        rates[difficulty] = rate.isFinite && (0...4).contains(rate) ? rate : 0
        infinityBotSpawnRates = rates
    }

    public func infinityBotSpawnRateChoices(for difficulty: String) -> [Double] {
        let current = effectiveInfinityBotSpawnRates[difficulty] ?? 0
        return Array(Set([0, 0.5, 1, 2, 4, current])).sorted()
    }

    public func infinityStartError(roster: [NativeSeatSpec]) -> String {
        guard infinity, infinityTarget > 0, !(infinityRandomBots && totalInfinityBotSpawnRate > 0) else {
            return ""
        }
        let sides = Set(
            roster.enumerated().filter { !$0.element.spectating }.map { index, seat in
                teamMode == "teams" && seat.team > 0 ? "team:\(seat.team)" : "seat:\(index)"
            })
        return sides.count >= 2
            ? "" : "Add an opposing tank or enable a roaming bot spawn rate to play to a score target."
    }
}
