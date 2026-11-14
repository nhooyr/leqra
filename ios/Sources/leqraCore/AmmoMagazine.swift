import Foundation

extension ArenaTank {
    static let maximumAmmoEpoch: UInt64 = 9_007_199_254_740_991
    static func nextAmmoEpoch(_ value: UInt64) -> UInt64 { value >= maximumAmmoEpoch ? 1 : value + 1 }

    /// Only magazine accounting changes. Shots from an older magazine retain
    /// their complete collision, damage and natural lifetime.
    mutating func refillAmmo() {
        ammoEpoch = Self.nextAmmoEpoch(ammoEpoch)
        cooldown = 0; cooldownTotal = 0; ammoUsed = 0; grenades = 0; grenadeLife = 0
        machineRounds = power == "rapid" ? 180 : 0
        switch power {
        case "scatter": charges = 5
        case "homing", "grenade", "laser", "cannon": charges = 3
        default: charges = 0
        }
    }
}
