import Foundation

/// Local-calendar day helpers. "Today" is always derived from the user's
/// current calendar and time zone, so daily totals reset naturally at local
/// midnight without any stored "reset" state.
public extension Calendar {
    /// Stable "yyyy-MM-dd" key for the local day containing `date`.
    func dayKey(_ date: Date) -> String {
        let c = dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func startOfNextDay(after date: Date) -> Date {
        let start = startOfDay(for: date)
        return self.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    /// The last `count` local days ending with the day containing `date`, oldest first.
    func recentDays(_ count: Int, endingOn date: Date) -> [Date] {
        let today = startOfDay(for: date)
        return (0..<max(0, count)).reversed().compactMap { self.date(byAdding: .day, value: -$0, to: today) }
    }

    /// Minutes since local midnight.
    func minuteOfDay(_ date: Date) -> Int {
        let c = dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// The date today (or the next day if already past) at the given minute of day.
    func nextOccurrence(ofMinute minute: Int, after date: Date) -> Date {
        let start = startOfDay(for: date)
        let candidate = self.date(byAdding: .minute, value: minute, to: start) ?? start
        return candidate > date ? candidate : (self.date(byAdding: .day, value: 1, to: candidate) ?? candidate)
    }
}

/// Tolerant decoding: missing or malformed fields fall back to defaults so
/// older or partially corrupted files still load.
extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, default fallback: @autoclosure () -> T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback()
    }
}

/// A daily window during which nonessential reminders stay silent.
/// Handles windows that wrap past midnight (e.g. 22:00 → 08:00).
public struct QuietHours: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// Minutes since midnight.
    public var startMinute: Int
    public var endMinute: Int

    public init(enabled: Bool = true, startMinute: Int = 22 * 60, endMinute: Int = 8 * 60) {
        self.enabled = enabled
        self.startMinute = Self.clampMinute(startMinute)
        self.endMinute = Self.clampMinute(endMinute)
    }

    static func clampMinute(_ m: Int) -> Int { min(24 * 60 - 1, max(0, m)) }

    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        guard enabled, startMinute != endMinute else { return false }
        let m = calendar.minuteOfDay(date)
        if startMinute < endMinute { return m >= startMinute && m < endMinute }
        return m >= startMinute || m < endMinute // wraps midnight
    }

    /// First moment at or after `date` that is outside quiet hours.
    public func end(after date: Date, calendar: Calendar) -> Date {
        guard contains(date, calendar: calendar) else { return date }
        return calendar.nextOccurrence(ofMinute: endMinute, after: date)
    }
}

extension QuietHours {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: c.value(.enabled, default: true),
            startMinute: c.value(.startMinute, default: 22 * 60),
            endMinute: c.value(.endMinute, default: 8 * 60)
        )
    }
}
