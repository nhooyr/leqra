import Foundation

/// Deliberately hesitant, inaccurate decisions shared by native finite and
/// Infinity practice. Other difficulties retain their existing bot behavior.
struct DumbBotBrain {
    private(set) var aim = 0.0
    private(set) var attacks = false
    private(set) var targetID: Int?
    private var nextDecision: Double
    private var nextFire: Double

    init(spawnedAt time: Double) {
        nextDecision = time
        nextFire = time + 1.8
    }

    /// Returns whether navigation should also be reconsidered this frame.
    /// Both the missed decision and the aim error stay fixed for 0.9 seconds.
    @discardableResult
    mutating func decide(now: Double, visibleAim: Double?, targetID: Int?, random: () -> Double) -> Bool {
        guard now + 1e-9 >= nextDecision else { return false }
        nextDecision = now + 0.9
        attacks = false
        self.targetID = nil
        if let visibleAim, let targetID, random() >= 0.35 {
            aim = visibleAim + (random() * 2 - 1) * 0.6
            attacks = true
            self.targetID = targetID
        }
        return true
    }

    /// This timer controls trigger pulses, independently of weapon cooldowns,
    /// so Machine Gun and Starman cannot bypass the difficulty's reaction time.
    mutating func fire(now: Double, facing: Double, targetID: Int?, protected: Bool) -> Bool {
        guard attacks, let targetID, targetID == self.targetID, !protected, now + 1e-9 >= nextFire,
              abs(atan2(sin(aim - facing), cos(aim - facing))) < 0.36 else { return false }
        nextFire = now + 1.8
        return true
    }
}
