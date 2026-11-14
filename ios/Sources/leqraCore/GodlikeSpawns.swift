import Foundation

public struct GodlikeSpawn: Codable, Equatable, Sendable {
    public var id: Int
    public var spawnSerial: Int
    public var name: String
    public init(id: Int, spawnSerial: Int, name: String) { self.id = id; self.spawnSerial = spawnSerial; self.name = name }
}

/// A passive notice is independent of errors/audio. Retained across reconnects,
/// the bounded life history prevents repeated snapshots replaying a warning.
public struct GodlikeSpawnNotices {
    private struct Life: Hashable { var id: Int; var serial: Int }
    private var seen = Set<Life>()
    private var order: [Life] = []
    private var message = ""
    private var until = 0.0
    public init() {}
    public var seenCount: Int { seen.count }
    @discardableResult public mutating func accept(_ births: [GodlikeSpawn], now: Double) -> Bool {
        var changed = false
        for birth in births.prefix(64) {
            let life = Life(id: birth.id, serial: birth.spawnSerial)
            guard birth.spawnSerial >= 0, seen.insert(life).inserted else { continue }
            changed = true
            order.append(life)
            if order.count > 256 { seen.remove(order.removeFirst()) }
            message = CallsignPolicy.displayName(birth.name, bot: true) + " spawned nearby. Watch out!"
            until = now + 6
        }
        return changed
    }
    public func text(at now: Double) -> String { now < until ? message : "" }
}
