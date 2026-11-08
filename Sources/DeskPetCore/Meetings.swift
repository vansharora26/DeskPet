import Foundation

// MARK: - Calendar heads-up

/// A calendar event as DeskPet sees it (read from macOS Calendar; never changed).
public struct CalendarEvent: Equatable, Sendable, Identifiable {
    /// Stable per occurrence (recurring events repeat the series ID, so the start is included).
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var joinURL: URL?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false, joinURL: URL? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.joinURL = joinURL
    }
}

public enum MeetingHeadsUp {
    public static let leadRange = 1...30

    /// Timed events starting within `leadMinutes` that haven't been announced yet.
    /// Events that already started more than a minute ago are skipped (too late to help).
    public static func due(_ events: [CalendarEvent], now: Date, leadMinutes: Int, announced: Set<String>) -> [CalendarEvent] {
        let horizon = now.addingTimeInterval(TimeInterval(leadMinutes) * 60)
        return events
            .filter { !$0.isAllDay && !announced.contains($0.id) && $0.start <= horizon && $0.start > now.addingTimeInterval(-60) }
            .sorted { $0.start < $1.start }
    }

    /// What's left of today: all-day events first, then timed events that haven't ended.
    public static func restOfDay(_ events: [CalendarEvent], now: Date, calendar: Calendar) -> [CalendarEvent] {
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return events
            .filter { $0.end > now && $0.start < endOfDay }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    /// The next timed event that hasn't started.
    public static func next(_ events: [CalendarEvent], now: Date) -> CalendarEvent? {
        events.filter { !$0.isAllDay && $0.start > now }.min { $0.start < $1.start }
    }

    /// Minutes until `event` starts, rounded up (so "in 1 min", never "in 0 min").
    public static func minutesUntil(_ event: CalendarEvent, now: Date) -> Int {
        max(0, Int((event.start.timeIntervalSince(now) / 60).rounded(.up)))
    }

    private static let joinHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
                                    "webex.com", "whereby.com", "around.co", "facetime.apple.com", "meet.jit.si"]

    /// The first video-call link in the event's URL, location or notes.
    public static func joinURL(in texts: [String?]) -> URL? {
        for text in texts.compactMap({ $0 }) {
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let range = NSRange(text.startIndex..., in: text)
            for match in detector?.matches(in: text, range: range) ?? [] {
                guard let url = match.url, url.scheme == "https" || url.scheme == "http",
                      let host = url.host?.lowercased() else { continue }
                if joinHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return url }
            }
        }
        return nil
    }
}
