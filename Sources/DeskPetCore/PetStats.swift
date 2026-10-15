import Foundation

/// The three needs of the pet. Every value is clamped to 0...100.
/// - happiness: higher is better
/// - energy: higher is better
/// - hunger: higher means *more* hungry
public struct PetStats: Codable, Equatable, Sendable {
    public var happiness: Double { didSet { happiness = Self.clamp(happiness) } }
    public var energy: Double { didSet { energy = Self.clamp(energy) } }
    public var hunger: Double { didSet { hunger = Self.clamp(hunger) } }

    public init(happiness: Double, energy: Double, hunger: Double) {
        self.happiness = Self.clamp(happiness)
        self.energy = Self.clamp(energy)
        self.hunger = Self.clamp(hunger)
    }

    public static let fresh = PetStats(happiness: 80, energy: 85, hunger: 25)

    public static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 50 }
        return min(100, max(0, value))
    }

    // Custom decoding so corrupted/out-of-range files still produce valid stats.
    private enum CodingKeys: String, CodingKey { case happiness, energy, hunger }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            happiness: (try? c.decode(Double.self, forKey: .happiness)) ?? Self.fresh.happiness,
            energy: (try? c.decode(Double.self, forKey: .energy)) ?? Self.fresh.energy,
            hunger: (try? c.decode(Double.self, forKey: .hunger)) ?? Self.fresh.hunger
        )
    }
}

/// High-level mood derived from stats, used to pick animations and chatter.
public enum PetMood: String, Sendable {
    case content, happy, hungry, tired, sad
}

public extension PetStats {
    var mood: PetMood {
        if hunger >= 75 { return .hungry }
        if energy <= 20 { return .tired }
        if happiness <= 30 { return .sad }
        if happiness >= 75 { return .happy }
        return .content
    }
}
