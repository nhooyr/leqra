import Foundation

/// One identity presentation for round banners, final results and reports.
/// Report members survive seat changes; tank IDs identify the active arena.
public struct WinnerIdentity: Equatable, Sendable {
    public let label: String
    public let color: String

    public init?(
        snapshot: ArenaSnapshot, rules: RoomRules, primaryID: Int, secondaryID: Int? = nil,
        controllerMember: UInt64? = nil
    ) {
        let result = snapshot.result
        let reported = result == nil ? snapshot.matchStats?.players.first(where: \.winner) : nil
        let id = result?.id ?? snapshot.winner
        let tank = snapshot.tanks.first { $0.id == id }
        let archived = snapshot.leaderboard.first { $0.id == id }
        let team = result?.team ?? reported?.team ?? tank?.team ?? 0
        if team > 0 {
            label = rules.teamNames.indices.contains(team - 1) ? rules.teamNames[team - 1] : "Team \(team)"
            let paint = rules.teamColors.indices.contains(team - 1) ? rules.teamColors[team - 1] : team - 1
            color = GamePalette.colors[GamePalette.index(paint)]
            return
        }
        guard let name = result?.name ?? reported?.name ?? tank?.name ?? archived?.name else { return nil }
        let bot = reported.map { $0.kind == "bot" } ?? tank?.bot ?? archived?.bot ?? false
        let localSeat: Int?
        if let reported {
            localSeat = reported.localSeat(controllerMember: controllerMember)
        } else {
            localSeat = bot ? nil : id == primaryID ? 1 : id == secondaryID ? 2 : nil
        }
        label = CallsignPolicy.displayName(name, bot: bot) + (localSeat.map { " (P\($0))" } ?? "")
        color =
            reported?.color
            ?? GamePalette.colors[GamePalette.index(tank?.colorIndex ?? archived?.colorIndex ?? 0)]
    }
}

extension NativeMatchPlayer {
    public func localSeat(controllerMember: UInt64?) -> Int? {
        guard kind != "bot", let controllerMember,
            member == controllerMember || self.controllerMember == controllerMember
        else { return nil }
        return kind == "local" ? 2 : 1
    }
}
