import Foundation

/// Cosmetic items. Purely visual; nothing functional is ever locked.
public enum Accessory: String, Codable, CaseIterable, Sendable, Identifiable {
    case bow, flower, glasses, bellCollar, scarf, partyHat, sunglasses, headphones, beanie, crown, wizardHat
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .bow: return "Bow"
        case .flower: return "Flower"
        case .glasses: return "Glasses"
        case .bellCollar: return "Bell collar"
        case .scarf: return "Scarf"
        case .partyHat: return "Party hat"
        case .sunglasses: return "Sunglasses"
        case .headphones: return "Headphones"
        case .beanie: return "Beanie"
        case .crown: return "Crown"
        case .wizardHat: return "Wizard hat"
        }
    }
    public var unlockLevel: Int {
        switch self {
        case .bow, .flower: return 2
        case .glasses: return 3
        case .bellCollar, .scarf: return 4
        case .partyHat: return 5
        case .sunglasses, .headphones: return 6
        case .beanie: return 7
        case .crown: return 8
        case .wizardHat: return 10
        }
    }
}

/// Fur colours and markings (tabby, tuxedo, calico, Siamese points, solid).
public enum CoatTheme: String, Codable, CaseIterable, Sendable, Identifiable {
    case ginger, smoky, midnight, snow, tuxedo, calico, siamese, cocoa, biscuit, lilac, mint, bubblegum
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .ginger: return "Ginger"
        case .smoky: return "Smoky"
        case .midnight: return "Midnight"
        case .snow: return "Snow"
        case .tuxedo: return "Tuxedo"
        case .calico: return "Calico"
        case .siamese: return "Siamese"
        case .cocoa: return "Cocoa"
        case .biscuit: return "Biscuit"
        case .lilac: return "Lilac"
        case .mint: return "Mint"
        case .bubblegum: return "Bubblegum"
        }
    }
    public var unlockLevel: Int {
        switch self {
        case .ginger, .smoky, .midnight, .snow: return 1
        case .calico: return 2
        case .tuxedo: return 3
        case .siamese, .cocoa: return 4
        case .biscuit: return 5
        case .lilac: return 6
        case .mint: return 7
        case .bubblegum: return 9
        }
    }
}

/// Eye colour. `nil` in `Progression.eyeColor` means the coat's natural colour.
public enum EyeColor: String, Codable, CaseIterable, Sendable, Identifiable {
    case dark, amber, green, blue, hazel, violet, oddEyed
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .dark: return "Dark"
        case .amber: return "Amber"
        case .green: return "Green"
        case .blue: return "Blue"
        case .hazel: return "Hazel"
        case .violet: return "Violet"
        case .oddEyed: return "Odd-eyed"
        }
    }
}

/// Things that earn experience. Daily caps keep it about habits, not grinding.
public enum XPSource: String, Codable, CaseIterable, Sendable {
    case water, focusSession, breakCompleted, taskCompleted, petting, hydrationGoal, focusGoal

    public var points: Int {
        switch self {
        case .water: return 5
        case .focusSession: return 20
        case .breakCompleted: return 5
        case .taskCompleted: return 10
        case .petting: return 1
        case .hydrationGoal: return 25
        case .focusGoal: return 25
        }
    }

    public var dailyCap: Int {
        switch self {
        case .water: return 40
        case .focusSession: return 160
        case .breakCompleted: return 40
        case .taskCompleted: return 100
        case .petting: return 10
        case .hydrationGoal, .focusGoal: return 25 // once a day
        }
    }
}

public struct Milestone: Equatable, Sendable {
    public var id: String
    public var title: String
}

public struct Progression: Codable, Equatable, Sendable {
    public var xp = 0
    /// When false: no XP shown, no level-up fanfare, and every cosmetic is available.
    public var gamificationEnabled = true
    public var showStreaks = true
    public var accessory: Accessory?
    public var coat: CoatTheme = .ginger
    /// Never locked; nil follows the coat.
    public var eyeColor: EyeColor?
    /// dayKey → source → points earned that day.
    public var dailyXP: [String: [String: Int]] = [:]
    public var milestones: [String] = []
    /// Local days with at least one tracked activity (for streaks).
    public var activeDays: [String] = []

    public init() {}

    // MARK: Levels

    /// XP needed to *reach* a level: 0, 60, 180, 360, 600, …
    public static func xpForLevel(_ level: Int) -> Int {
        let n = max(1, level) - 1
        return 30 * n * (n + 1)
    }

    public var level: Int {
        var l = 1
        while xp >= Self.xpForLevel(l + 1) { l += 1 }
        return l
    }

    public var progressToNextLevel: (current: Int, needed: Int) {
        let base = Self.xpForLevel(level)
        return (xp - base, Self.xpForLevel(level + 1) - base)
    }

    public func isUnlocked(_ a: Accessory) -> Bool { !gamificationEnabled || level >= a.unlockLevel }
    public func isUnlocked(_ c: CoatTheme) -> Bool { !gamificationEnabled || level >= c.unlockLevel }

    // MARK: Earning

    public struct Award: Equatable, Sendable {
        public var points: Int
        public var leveledUpTo: Int?
        public var newMilestones: [Milestone]
    }

    /// Adds XP (respecting the daily cap), records activity, and reports level-ups.
    @discardableResult
    public mutating func earn(_ source: XPSource, on date: Date, calendar: Calendar) -> Award {
        let key = calendar.dayKey(date)
        if !activeDays.contains(key) {
            activeDays.append(key)
            activeDays.sort()
            if activeDays.count > 400 { activeDays.removeFirst(activeDays.count - 400) }
        }
        var day = dailyXP[key] ?? [:]
        let already = day[source.rawValue] ?? 0
        let points = max(0, min(source.points, source.dailyCap - already))
        let before = level
        if points > 0 {
            day[source.rawValue] = already + points
            dailyXP[key] = day
            xp += points
        }
        // Keep two weeks of caps; older days don't matter.
        if dailyXP.count > 14 {
            for old in dailyXP.keys.sorted().dropLast(14) { dailyXP.removeValue(forKey: old) }
        }
        let after = level
        return Award(points: points, leveledUpTo: after > before ? after : nil, newMilestones: [])
    }

    /// Records a milestone once; returns it if new.
    public mutating func reach(_ id: String, title: String) -> Milestone? {
        guard !milestones.contains(id) else { return nil }
        milestones.append(id)
        return Milestone(id: id, title: title)
    }

    // MARK: Streaks (never punitive: a missed day just starts a new count)

    public func currentStreak(now: Date, calendar: Calendar) -> Int {
        let days = Set(activeDays)
        var count = 0
        var cursor = calendar.startOfDay(for: now)
        // Today not done yet doesn't break the streak.
        if !days.contains(calendar.dayKey(cursor)) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        while days.contains(calendar.dayKey(cursor)) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    public func bestStreak(calendar: Calendar) -> Int {
        let dates = activeDays.compactMap { Self.parseKey($0, calendar: calendar) }.sorted()
        var best = 0, run = 0
        var previous: Date?
        for d in dates {
            if let p = previous, let next = calendar.date(byAdding: .day, value: 1, to: p), calendar.isDate(next, inSameDayAs: d) {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = d
        }
        return best
    }

    static func parseKey(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

extension Progression {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        xp = max(0, c.value(.xp, default: 0))
        gamificationEnabled = c.value(.gamificationEnabled, default: true)
        showStreaks = c.value(.showStreaks, default: true)
        accessory = c.value(.accessory, default: nil)
        coat = c.value(.coat, default: .ginger)
        eyeColor = c.value(.eyeColor, default: nil)
        dailyXP = c.value(.dailyXP, default: [:])
        milestones = c.value(.milestones, default: [])
        activeDays = c.value(.activeDays, default: [])
    }
}
