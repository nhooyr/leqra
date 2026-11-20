import Foundation

/// Describes the rules currently being edited or played, including fixed-map
/// duration thresholds and Infinity's independent pickup population.
public struct PowerupHelp: Sendable {
    public static let kinds = [
        "cannon", "ghost", "laser", "homing", "grenade", "speed", "rapid", "scatter", "shield", "starman",
    ]
    public let infinity: Bool
    public let powerDuration: Int
    public let starDuration: Int
    public let groundLifetime: Int
    public let enabledKinds: Set<String>
    public let spawningEnabled: Bool
    private let frequency: String

    public init(rules: RoomRules, world: ArenaWorld? = nil, infinity override: Bool? = nil) {
        infinity = override ?? rules.infinity
        let sizes = [
            "compact": 49, "standard": 72, "large": 120, "huge": 168, "giant": 224, "ultrawide": 336,
        ]
        let area = world.map { $0.cols * $0.rows } ?? sizes[rules.mapSize] ?? 72
        powerDuration = infinity || area >= 168 ? 15 : 10
        starDuration =
            infinity ? 8 : area >= 336 ? 8 : area >= 224 ? 7 : area >= 168 ? 6 : area >= 120 ? 5 : 4
        let cap = Int((Double(area) / 9.8).rounded())
        groundLifetime = infinity ? 30 : max(area <= 120 ? 30 : 0, cap * 8 / 3)
        enabledKinds = infinity ? Set(Self.kinds) : Set(rules.weapons).intersection(Self.kinds)
        spawningEnabled = infinity || rules.pickupRate != "off" && !enabledKinds.isEmpty
        frequency = rules.pickupRate
    }

    public var summary: String {
        let timing =
            "Most power-ups last \(powerDuration) seconds; Starman lasts \(starDuration) seconds. Uncollected pickups expire after \(groundLifetime) seconds."
        if infinity {
            return "All 10 power-ups spawn near active pilots. " + timing
                + " Infinity uses its own spawn frequency and all power-up types."
        }
        guard spawningEnabled else { return "Power-up spawning is off in this room. " + timing }
        let interval =
            frequency == "superfast"
            ? "1–2" : frequency == "fast" ? "2–3.5" : frequency == "slow" ? "7–10" : "4–6"
        return
            "\(enabledKinds.count) of 10 power-up types enabled. New power-ups spawn every \(interval) seconds while there is space. "
            + timing
    }

    public func description(for kind: String, includeGrenadeControls: Bool = false) -> String {
        let timer = "\(powerDuration) seconds"
        var effect: String
        switch kind {
        case "cannon":
            effect =
                "3 shots or \(timer). Pierces every opponent and internal wall, bounces off the rim, and flies for 5.3 seconds."
        case "ghost":
            effect =
                "Phase through internal walls for \(timer). The rim stays solid. Stacks with weapons and other buffs."
        case "laser":
            effect =
                "3 shots or \(timer). Instant ricocheting beams hit every opponent in their path. Range: \(infinity ? "36 maze cells" : "twice the maze perimeter")."
        case "homing":
            effect =
                "3 missiles or \(timer). Tracks visible opponents and bounces off walls. Range: \(infinity ? "18 maze cells" : "half the maze perimeter")."
        case "grenade":
            effect =
                "3 throws or \(timer). Homes toward opponents and explodes on tank impact or after its 10-second fuse. Walls block the blast."
            if includeGrenadeControls {
                effect += " Press Fire again to detonate early. Release Fire before throwing another grenade."
            }
        case "speed":
            effect =
                "Up to 5 stacks, each adding 65% movement speed and 25% turn speed. Another pickup refreshes the shared \(timer)."
        case "rapid":
            effect =
                "3 seconds of firing within \(timer), using tiny, fast ricocheting rounds. Range: \(infinity ? "18 maze cells" : "a quarter of the maze perimeter")."
        case "scatter": effect = "5 volleys or \(timer). Fires three fast ricocheting pellets in a spread."
        case "shield":
            effect =
                "Up to 5 charges, each absorbing one damaging hit. Another pickup refreshes the shared \(timer)."
        case "starman":
            effect =
                "\(starDuration) seconds of invincibility, lethal contact, wall phasing, unlimited ammunition and no cooldown. Pauses the equipped weapon's timer."
        default: effect = ""
        }
        if !infinity && (!spawningEnabled || !enabledKinds.contains(kind)) {
            return "Disabled in this room. " + effect
        }
        return effect
    }
}
