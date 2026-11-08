import Foundation

/// One reading of the Mac's internal battery.
public struct BatteryReading: Equatable, Sendable {
    /// 0–100.
    public var level: Int
    public var isCharging: Bool
    /// On AC power (charging, or full and holding).
    public var isPluggedIn: Bool

    public init(level: Int, isCharging: Bool, isPluggedIn: Bool) {
        self.level = min(100, max(0, level))
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
    }
}

/// How the battery makes the cat feel. `.none` on Macs without a battery.
public enum BatteryMood: String, Equatable, Sendable, CaseIterable {
    case none, normal, charging, full, low, critical

    public static let lowThreshold = 20
    public static let criticalThreshold = 10

    public static func of(_ r: BatteryReading?) -> BatteryMood {
        guard let r else { return .none }
        if r.isPluggedIn {
            if r.isCharging { return .charging }
            return r.level >= 95 ? .full : .normal
        }
        if r.level <= criticalThreshold { return .critical }
        if r.level <= lowThreshold { return .low }
        return .normal
    }

    /// Low or critical and not plugged in: the cat feels it.
    public var isDrained: Bool { self == .low || self == .critical }

    /// What the cat says when the mood changes (nil = stay quiet).
    public static func line(from old: BatteryMood, to new: BatteryMood, level: Int, name: String) -> String? {
        guard old != new, old != .none else { return nil }
        switch new {
        case .low where old != .critical:
            return "Feeling a bit drained… battery’s at \(level)%."
        case .critical:
            return "So… tired… only \(level)% left. Plug me in?"
        case .charging where old.isDrained:
            return "Ahh, power! That’s much better. ⚡"
        case .charging where old == .normal:
            return "Charging up! ⚡"
        case .full where old == .charging:
            return "All charged up — \(level)%!"
        default:
            return nil
        }
    }

    /// Roaming pace: drained cats dawdle; critical ones mostly stay put.
    public var walkSpeedFactor: Double {
        switch self {
        case .low: return 0.55
        case .critical: return 0.35
        default: return 1
        }
    }

    /// Multiplier on time between roaming moves.
    public var restFactor: Double {
        switch self {
        case .low: return 2
        case .critical: return 4
        default: return 1
        }
    }
}
