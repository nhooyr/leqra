import Foundation

public enum ArenaTypography {
    /// Screen-space size shared by tank identities and their death notices.
    public static func labelSize(zoom: Double, infinity: Bool, fontScale: Double = 1) -> Double {
        max(10 * max(1, fontScale), (infinity ? 11 : 10) * zoom)
    }
}

public struct DeathNotice: Equatable, Sendable {
    public let killer: String
    public let color: String
    public var text: String { "Killed by " + killer }

    public init?(tank: ArenaTank?) {
        guard let tank, tank.hp <= 0, !tank.killedBy.isEmpty else { return nil }
        killer = tank.killedBy
        color = tank.killedByColor
    }
}
