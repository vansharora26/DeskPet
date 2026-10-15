import Foundation

/// Bookkeeping for one repeating reminder (hydration, movement).
public struct ReminderState: Codable, Equatable, Sendable {
    /// When the schedule (re)started — e.g. reminders were enabled or the app first ran.
    public var anchor: Date?
    /// Last time the user did the thing (logged water, marked done).
    public var lastSatisfied: Date?
    /// Last time the reminder was shown.
    public var lastFired: Date?
    public var snoozedUntil: Date?

    public init(anchor: Date? = nil, lastSatisfied: Date? = nil, lastFired: Date? = nil, snoozedUntil: Date? = nil) {
        self.anchor = anchor
        self.lastSatisfied = lastSatisfied
        self.lastFired = lastFired
        self.snoozedUntil = snoozedUntil
    }

    public mutating func markFired(at date: Date) {
        lastFired = date
        snoozedUntil = nil
    }

    public mutating func markDone(at date: Date) {
        lastSatisfied = date
        snoozedUntil = nil
    }

    /// Dismiss = "not now": wait a full interval from now.
    public mutating func dismiss(at date: Date) {
        lastFired = date
        snoozedUntil = nil
    }

    public mutating func snooze(minutes: Int, from date: Date) {
        snoozedUntil = date.addingTimeInterval(TimeInterval(max(1, minutes)) * 60)
    }
}

extension ReminderState {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            anchor: c.value(.anchor, default: nil),
            lastSatisfied: c.value(.lastSatisfied, default: nil),
            lastFired: c.value(.lastFired, default: nil),
            snoozedUntil: c.value(.snoozedUntil, default: nil)
        )
    }
}

/// Pure scheduling rules. Computing the *next* due date from state (instead of
/// queueing many future notifications) is what makes duplicates impossible:
/// there is only ever one pending reminder per kind.
public enum ReminderPlanner {
    public struct Config: Equatable, Sendable {
        public var enabled: Bool
        public var intervalMinutes: Int
        public var quietHours: QuietHours

        public init(enabled: Bool, intervalMinutes: Int, quietHours: QuietHours) {
            self.enabled = enabled
            self.intervalMinutes = intervalMinutes
            self.quietHours = quietHours
        }
    }

    /// Next time the reminder should appear, or nil if it shouldn't.
    /// - Parameter notBefore: e.g. the end of a focus session or the start of tomorrow
    ///   (goal reached) — the reminder is deferred until then.
    public static func nextDue(
        config: Config, state: ReminderState, now: Date, calendar: Calendar, notBefore: Date? = nil
    ) -> Date? {
        guard config.enabled, config.intervalMinutes > 0 else { return nil }
        let base = [state.anchor, state.lastSatisfied, state.lastFired].compactMap { $0 }.max() ?? now
        var due = base.addingTimeInterval(TimeInterval(config.intervalMinutes) * 60)
        if let snoozed = state.snoozedUntil, snoozed > base { due = snoozed }
        if let notBefore, due < notBefore { due = notBefore }
        // Quiet hours push the reminder to when they end.
        due = config.quietHours.end(after: due, calendar: calendar)
        return due
    }
}
