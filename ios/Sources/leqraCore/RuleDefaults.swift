import Foundation

public extension RoomRules {
    /// The shared room/transport defaults remain the Go server's Large map.
    /// Only a fresh touch-device local room starts on the Compact maze.
    static func localDefaults(mode: String = "elimination") -> RoomRules {
        var rules = modeDefaults(mode)
        rules.mapSize = "compact"
        return rules
    }

    static func modeDefaults(_ mode: String) -> RoomRules {
        var rules = RoomRules()
        rules.infinity = mode == "infinity"
        rules.mode = mode == "infinity" ? "elimination" : mode
        rules.teamMode = ["ctf", "survival"].contains(mode) ? "teams" : "ffa"
        rules.scoreTarget = mode == "survival" ? 15 : mode == "koth" ? 30 : mode == "ctf" ? 3 : 5
        rules.timeLimit = ["ctf", "koth"].contains(mode) ? 180 : 75
        return rules
    }

    /// Mirrors rulesForRoomMode without its browser storage dependency. Pass a
    /// saved profile when one exists; map size/orientation belong to the room.
    func selectingMode(_ mode: String, remembered: RoomRules? = nil) -> RoomRules {
        if mode == "infinity" {
            if infinity { return self }
            var profile = remembered ?? Self.modeDefaults("elimination")
            if remembered == nil {
                profile.teamMode = teamMode; profile.teamNames = teamNames
                profile.teamColors = teamColors; profile.friendlyFire = friendlyFire
            }
            profile.infinity = true; profile.mapSize = mapSize; profile.portraitMaze = portraitMaze
            return profile
        }
        if self.mode == mode && !infinity { return self }
        let defaults = Self.modeDefaults(mode)
        var base = infinity ? defaults : self
        if !infinity { base.scoreTarget = defaults.scoreTarget; base.timeLimit = defaults.timeLimit }
        if let remembered { base = remembered }
        base.infinity = false; base.mode = mode
        base.mapSize = mapSize; base.portraitMaze = portraitMaze
        base.teamMode = ["ctf", "survival"].contains(mode) ? "teams" : infinity ? remembered?.teamMode ?? defaults.teamMode : teamMode
        return base
    }

    func restoringModeDefaults() -> RoomRules {
        let defaults = Self.modeDefaults(mode)
        if infinity {
            var rules = self
            rules.infinityTarget = defaults.infinityTarget
            rules.infinityRandomBots = defaults.infinityRandomBots
            rules.infinityBotDifficulty = defaults.infinityBotDifficulty
            rules.infinityRandomDifficulty = defaults.infinityRandomDifficulty
            rules.teamNames = defaults.teamNames; rules.teamColors = defaults.teamColors; rules.friendlyFire = false
            return rules
        }
        var rules = defaults
        rules.mapSize = mapSize; rules.portraitMaze = portraitMaze
        rules.teamMode = ["ctf", "survival"].contains(mode) ? "teams" : teamMode
        return rules
    }
}

/// Names and finite-maze movement rates match bots.go / game.js. Infinity uses
/// its own roaming encounter tuning rather than these finite driving speeds.
public enum BotDifficulty: String, CaseIterable, Codable, Sendable {
    case dumb, easy, normal, hard, godlike
    public var displayName: String {
        switch self { case .dumb: return "Dumb"; case .easy: return "Chill"; case .normal: return "Normal"; case .hard: return "Fierce"; case .godlike: return "Godlike" }
    }
    var speed: Double { self == .dumb ? 60 : self == .easy ? 89 : self == .normal ? 108 : 123 }
    var turn: Double { self == .dumb ? 1.8 : self == .easy ? 2.8 : self == .normal ? 3.4 : 4.3 }
    var think: Double { self == .dumb ? 0.9 : self == .easy ? 0.30 : self == .normal ? 0.19 : self == .hard ? 0.13 : 0.075 }
}
