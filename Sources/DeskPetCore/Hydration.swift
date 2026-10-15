import Foundation

/// One logged drink.
public struct WaterEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var ml: Int

    public init(id: UUID = UUID(), date: Date, ml: Int) {
        self.id = id
        self.date = date
        self.ml = ml
    }
}

/// Personal hydration preferences. The target is a user setting, not advice.
public struct HydrationSettings: Codable, Equatable, Sendable {
    public var dailyTargetML: Int = 2000
    public var servingSizes: [Int] = [150, 250, 500]
    public var defaultServingML: Int = 250
    public var remindersEnabled: Bool = true
    public var reminderIntervalMinutes: Int = 60
    public var snoozeMinutes: Int = 15
    public var quietHours = QuietHours()
    /// Stop nudging for the rest of the day once the target is reached.
    public var pauseAfterGoal: Bool = true

    public static let servingRange = 10...2000
    public static let targetRange = 250...6000
    public static let intervalRange = 15...240
    public static let snoozeRange = 5...120

    public init() {}

    /// Returns a copy with every value forced into its valid range.
    public func validated() -> HydrationSettings {
        var s = self
        s.dailyTargetML = s.dailyTargetML.clamped(to: Self.targetRange)
        s.defaultServingML = s.defaultServingML.clamped(to: Self.servingRange)
        var sizes = s.servingSizes.map { $0.clamped(to: Self.servingRange) }
        sizes = Array(Set(sizes)).sorted()
        s.servingSizes = sizes.isEmpty ? [250] : Array(sizes.prefix(6))
        s.reminderIntervalMinutes = s.reminderIntervalMinutes.clamped(to: Self.intervalRange)
        s.snoozeMinutes = s.snoozeMinutes.clamped(to: Self.snoozeRange)
        return s
    }
}

extension HydrationSettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HydrationSettings()
        self.init()
        dailyTargetML = c.value(.dailyTargetML, default: d.dailyTargetML)
        servingSizes = c.value(.servingSizes, default: d.servingSizes)
        defaultServingML = c.value(.defaultServingML, default: d.defaultServingML)
        remindersEnabled = c.value(.remindersEnabled, default: d.remindersEnabled)
        reminderIntervalMinutes = c.value(.reminderIntervalMinutes, default: d.reminderIntervalMinutes)
        snoozeMinutes = c.value(.snoozeMinutes, default: d.snoozeMinutes)
        quietHours = c.value(.quietHours, default: d.quietHours)
        pauseAfterGoal = c.value(.pauseAfterGoal, default: d.pauseAfterGoal)
        self = validated()
    }
}

public enum HydrationError: Error, Equatable, LocalizedError {
    case invalidAmount(Int)
    public var errorDescription: String? {
        switch self {
        case .invalidAmount(let ml):
            return "\(ml) ml isn't a valid amount. Use \(HydrationSettings.servingRange.lowerBound)–\(HydrationSettings.servingRange.upperBound) ml."
        }
    }
}

/// Persisted hydration state.
public struct HydrationData: Codable, Equatable, Sendable {
    public var entries: [WaterEntry] = []
    public var settings = HydrationSettings()
    public var reminder = ReminderState()

    public init() {}

    @discardableResult
    public mutating func log(_ ml: Int, at date: Date) throws -> WaterEntry {
        guard HydrationSettings.servingRange.contains(ml) else { throw HydrationError.invalidAmount(ml) }
        let entry = WaterEntry(date: date, ml: ml)
        entries.append(entry)
        entries.sort { $0.date < $1.date }
        reminder.lastSatisfied = max(reminder.lastSatisfied ?? .distantPast, date)
        reminder.snoozedUntil = nil
        return entry
    }

    /// Removes the most recent entry logged today (accidental-tap protection).
    @discardableResult
    public mutating func undoLast(now: Date, calendar: Calendar) -> WaterEntry? {
        guard let idx = entries.lastIndex(where: { calendar.isDate($0.date, inSameDayAs: now) }) else { return nil }
        return entries.remove(at: idx)
    }

    @discardableResult
    public mutating func remove(id: UUID) -> WaterEntry? {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return entries.remove(at: idx)
    }

    public mutating func restore(_ entry: WaterEntry) {
        guard !entries.contains(where: { $0.id == entry.id }) else { return }
        entries.append(entry)
        entries.sort { $0.date < $1.date }
    }
}

extension HydrationData {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        entries = c.value(.entries, default: []).filter { HydrationSettings.servingRange.contains($0.ml) }
        settings = c.value(.settings, default: HydrationSettings())
        reminder = c.value(.reminder, default: ReminderState())
    }
}

/// Read-only summaries over hydration entries.
public enum Hydration {
    public struct DaySummary: Equatable, Sendable {
        public var day: Date
        public var ml: Int
        public var drinks: Int
        public var target: Int
        public var reachedGoal: Bool { ml >= target }
        public var progress: Double { target > 0 ? min(1, Double(ml) / Double(target)) : 0 }
    }

    public struct WeekSummary: Equatable, Sendable {
        public var days: [DaySummary]
        public var totalML: Int { days.reduce(0) { $0 + $1.ml } }
        public var daysLogged: Int { days.filter { $0.ml > 0 }.count }
        public var daysGoalMet: Int { days.filter(\.reachedGoal).count }
        /// Average over days that have at least one entry (not penalising unlogged days).
        public var averagePerLoggedDay: Int { daysLogged > 0 ? totalML / daysLogged : 0 }
    }

    public static func entries(on day: Date, in entries: [WaterEntry], calendar: Calendar) -> [WaterEntry] {
        entries.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    public static func total(on day: Date, in entries: [WaterEntry], calendar: Calendar) -> Int {
        self.entries(on: day, in: entries, calendar: calendar).reduce(0) { $0 + $1.ml }
    }

    public static func day(_ day: Date, entries: [WaterEntry], target: Int, calendar: Calendar) -> DaySummary {
        let list = self.entries(on: day, in: entries, calendar: calendar)
        return DaySummary(day: calendar.startOfDay(for: day), ml: list.reduce(0) { $0 + $1.ml },
                          drinks: list.count, target: target)
    }

    /// The last 7 local days ending today, oldest first.
    public static func week(endingOn now: Date, entries: [WaterEntry], target: Int, calendar: Calendar) -> WeekSummary {
        WeekSummary(days: calendar.recentDays(7, endingOn: now).map {
            day($0, entries: entries, target: target, calendar: calendar)
        })
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(range.upperBound, max(range.lowerBound, self)) }
}
