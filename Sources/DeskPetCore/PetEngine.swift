import Foundation

/// Pure rules for how the pet's needs change. Contains no timers or I/O so it
/// can be unit-tested deterministically.
public enum PetEngine {

    // MARK: Rates (points per hour)

    public struct Rates: Sendable {
        public var hungerAwake = 6.0
        public var hungerAsleep = 3.0
        public var energyAwake = -5.0
        /// Napping is fast on purpose so it feels responsive: ~25 min from empty to full.
        public var energyAsleep = 240.0
        public var happinessBase = -3.0
        /// Extra happiness drain while very hungry or exhausted.
        public var happinessNeglect = -4.0
        public init() {}
    }

    public static let rates = Rates()

    /// Gaps longer than this are treated as "the app was closed / the Mac slept".
    public static let offlineThreshold: TimeInterval = 5 * 60
    /// At most this much offline time counts toward decay.
    public static let maxOfflineCredit: TimeInterval = 8 * 60 * 60

    /// While offline, needs never get worse than these. Coming back should
    /// feel like a reunion, not a punishment.
    public static let offlineFloorHappiness = 40.0
    public static let offlineFloorEnergy = 30.0
    public static let offlineCeilingHunger = 70.0

    // MARK: Passive change

    /// Advances stats by `elapsed` seconds.
    public static func advance(_ stats: PetStats, by elapsed: TimeInterval, sleeping: Bool) -> PetStats {
        guard elapsed > 0, elapsed.isFinite else { return stats }
        let offline = elapsed > offlineThreshold
        let seconds = offline ? min(elapsed, maxOfflineCredit) : elapsed
        let hours = seconds / 3600

        var s = stats
        let before = stats
        s.hunger += (sleeping ? rates.hungerAsleep : rates.hungerAwake) * hours
        s.energy += (sleeping ? rates.energyAsleep : rates.energyAwake) * hours

        var happinessDelta = rates.happinessBase
        if before.hunger >= 75 || before.energy <= 15 { happinessDelta += rates.happinessNeglect }
        if sleeping { happinessDelta = 0 } // dreaming of fish, no sadness
        s.happiness += happinessDelta * hours

        if offline {
            // Floors apply only to decay; never make a stat better than it was.
            s.happiness = max(s.happiness, min(before.happiness, offlineFloorHappiness))
            s.energy = max(s.energy, min(before.energy, offlineFloorEnergy))
            s.hunger = min(s.hunger, max(before.hunger, offlineCeilingHunger))
        }
        return s
    }

    // MARK: Actions

    public enum Outcome: Equatable, Sendable {
        case done
        /// Action refused, with a reason the UI can turn into speech.
        case refused(Refusal)
    }

    public enum Refusal: Equatable, Sendable {
        case tooFull, tooTired, asleep
    }

    public static func feed(_ stats: inout PetStats, sleeping: Bool) -> Outcome {
        if sleeping { return .refused(.asleep) }
        if stats.hunger < 8 { return .refused(.tooFull) }
        stats.hunger -= 35
        stats.happiness += 6
        stats.energy += 3
        return .done
    }

    public static func play(_ stats: inout PetStats, sleeping: Bool) -> Outcome {
        if sleeping { return .refused(.asleep) }
        if stats.energy < 15 { return .refused(.tooTired) }
        stats.happiness += 15
        stats.energy -= 12
        stats.hunger += 6
        return .done
    }

    /// Petting has diminishing returns so click-spamming isn't the meta.
    public static func pet(_ stats: inout PetStats, recentPets: Int) {
        let gain = max(0.5, 4.0 - Double(recentPets))
        stats.happiness += gain
    }

    /// The pet wakes on its own once fully rested.
    public static func shouldWake(_ stats: PetStats) -> Bool {
        stats.energy >= 100
    }
}
