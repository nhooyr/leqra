/// Touch and hardware Fire are independent sources for one local controller.
/// Releasing one source must not invent a release while the other is held.
public struct FireInputSources: Sendable {
    public enum Source { case touch, keyboard }
    private var touch = false
    private var keyboard = false
    public var held: Bool { touch || keyboard }
    public init() {}
    @discardableResult public mutating func set(_ source: Source, down: Bool) -> Bool {
        switch source { case .touch: touch = down; case .keyboard: keyboard = down }
        return held
    }
    public mutating func reset() { touch = false; keyboard = false }
}
