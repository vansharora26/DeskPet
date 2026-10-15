import Foundation

/// Small regex helper over NSRegularExpression (case-insensitive).
enum Rx {
    private static var cache: [String: NSRegularExpression] = [:]
    private static let lock = NSLock()

    static func regex(_ pattern: String) -> NSRegularExpression {
        lock.lock(); defer { lock.unlock() }
        if let r = cache[pattern] { return r }
        // Patterns are compile-time constants; a bad one is a programmer error caught by tests.
        let r = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        cache[pattern] = r
        return r
    }

    struct Match {
        let range: NSRange
        let groups: [String?]
        subscript(_ i: Int) -> String? { i < groups.count ? groups[i] : nil }
    }

    static func first(_ pattern: String, in s: String) -> Match? {
        let ns = s as NSString
        guard let m = regex(pattern).firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let groups: [String?] = (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        return Match(range: m.range, groups: groups)
    }

    static func removing(_ range: NSRange, from s: String) -> String {
        (s as NSString).replacingCharacters(in: range, with: " ")
    }

    static func tidy(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Drop connectors left dangling by removed date phrases ("buy milk by" → "buy milk").
        while let m = first(#"(?:^|\s)(by|due|on|at|before|for|to)$"#, in: t) {
            t = (t as NSString).replacingCharacters(in: m.range, with: "").trimmingCharacters(in: .whitespaces)
        }
        return t.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-"))
    }
}

/// A date phrase found inside free text.
public struct ParsedDate: Equatable, Sendable {
    public var date: Date
    /// False when only a day was given ("tomorrow", "friday").
    public var hasTime: Bool
    /// The input with the date phrase removed.
    public var remainder: String
}

/// Understands the everyday date phrases people type into a launcher:
/// "in 20 minutes", "at 7 pm", "tomorrow at 9:30am", "by friday", "tonight", "noon".
public enum NaturalDate {
    private static let weekdays: [(String, Int)] = [
        ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4), ("thursday", 5), ("friday", 6), ("saturday", 7),
    ]
    private static let shortWeekdays: [(String, Int)] = [
        ("sun", 1), ("mon", 2), ("tues", 3), ("tue", 3), ("wed", 4), ("thurs", 5), ("thu", 5), ("fri", 6), ("sat", 7),
    ]

    public static func extract(from text: String, now: Date, calendar: Calendar) -> ParsedDate? {
        var s = text
        var day: Date?
        var time: (h: Int, m: Int)?
        var defaultTime: (h: Int, m: Int)?
        let today = calendar.startOfDay(for: now)

        // 1. Relative offsets: "in 20 minutes", "in an hour", "in 2 days".
        if let m = Rx.first(#"\bin\s+(\d+|an?|one|half an)\s*(minutes?|mins?|hours?|hrs?|h|days?|weeks?)\b"#, in: s) {
            let qtyWord = (m[1] ?? "").lowercased()
            let unit = (m[2] ?? "").lowercased()
            let qty: Double = qtyWord == "half an" ? 0.5 : (Double(qtyWord) ?? 1)
            s = Rx.removing(m.range, from: s)
            if unit.hasPrefix("min") {
                return ParsedDate(date: now.addingTimeInterval(qty * 60), hasTime: true, remainder: Rx.tidy(s))
            } else if unit.hasPrefix("h") {
                return ParsedDate(date: now.addingTimeInterval(qty * 3600), hasTime: true, remainder: Rx.tidy(s))
            } else {
                let days = Int(qty) * (unit.hasPrefix("week") ? 7 : 1)
                day = calendar.date(byAdding: .day, value: days, to: today)
            }
        }

        // 2. Part-of-day combos: "tomorrow morning", "this evening".
        if day == nil, let m = Rx.first(#"\b(this|tomorrow)\s+(morning|afternoon|evening)\b"#, in: s) {
            let isTomorrow = (m[1] ?? "").lowercased() == "tomorrow"
            day = isTomorrow ? calendar.date(byAdding: .day, value: 1, to: today) : today
            switch (m[2] ?? "").lowercased() {
            case "morning": time = (9, 0)
            case "afternoon": time = (14, 0)
            default: time = (18, 0)
            }
            s = Rx.removing(m.range, from: s)
        }

        // 3. Day words.
        if day == nil, let m = Rx.first(#"\b(?:(?:by|due|on|before)\s+)?(?:the\s+)?day after tomorrow\b"#, in: s) {
            day = calendar.date(byAdding: .day, value: 2, to: today)
            s = Rx.removing(m.range, from: s)
        }
        if day == nil, let m = Rx.first(#"\b(?:(?:by|due|on|before)\s+)?(today|tonight|tomorrow|tmrw|tmr)\b"#, in: s) {
            switch (m[1] ?? "").lowercased() {
            case "today": day = today
            case "tonight": day = today; defaultTime = (20, 0)
            default: day = calendar.date(byAdding: .day, value: 1, to: today)
            }
            s = Rx.removing(m.range, from: s)
        }
        if day == nil {
            let current = calendar.component(.weekday, from: now)
            func resolve(_ weekday: Int) -> Date? {
                var ahead = (weekday - current + 7) % 7
                if ahead == 0 { ahead = 7 }
                return calendar.date(byAdding: .day, value: ahead, to: today)
            }
            for (name, wd) in weekdays {
                if let m = Rx.first(#"\b(?:(?:by|due|on|before|this|next)\s+)?"# + name + #"\b"#, in: s) {
                    day = resolve(wd)
                    s = Rx.removing(m.range, from: s)
                    break
                }
            }
            // Abbreviations only with a marker word, so "the sun" isn't Sunday.
            if day == nil {
                for (name, wd) in shortWeekdays {
                    if let m = Rx.first(#"\b(?:by|due|on|before|this|next)\s+"# + name + #"\b"#, in: s) {
                        day = resolve(wd)
                        s = Rx.removing(m.range, from: s)
                        break
                    }
                }
            }
        }

        // 4. Times of day.
        if time == nil, let m = Rx.first(#"\b(?:at\s+|@\s*|by\s+|before\s+)?(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)(?=\s|$|[,.!?])"#, in: s) {
            if var h = Int(m[1] ?? ""), h >= 1, h <= 12 {
                let minute = Int(m[2] ?? "0") ?? 0
                let pm = (m[3] ?? "").lowercased().hasPrefix("p")
                if pm && h < 12 { h += 12 }
                if !pm && h == 12 { h = 0 }
                if minute < 60 { time = (h, minute); s = Rx.removing(m.range, from: s) }
            }
        }
        if time == nil, let m = Rx.first(#"\b(?:at|@|by)\s*(\d{1,2}):(\d{2})\b"#, in: s) {
            if let h = Int(m[1] ?? ""), let minute = Int(m[2] ?? ""), h < 24, minute < 60 {
                time = (h, minute)
                s = Rx.removing(m.range, from: s)
            }
        }
        if time == nil, let m = Rx.first(#"\b(?:at\s+)?(noon|midday|midnight)\b"#, in: s) {
            time = (m[1] ?? "").lowercased() == "midnight" ? (23, 59) : (12, 0)
            s = Rx.removing(m.range, from: s)
        }
        if time == nil, let m = Rx.first(#"\bat\s+(\d{1,2})\b(?!\s*(?:%|ml|l\b|minutes?|mins?|hours?|:))"#, in: s) {
            if var h = Int(m[1] ?? ""), h >= 1, h <= 23 {
                if h <= 7 { h += 12 } // "at 7" almost always means 7 pm
                time = (h, 0)
                s = Rx.removing(m.range, from: s)
            }
        }

        guard day != nil || time != nil else { return nil }
        let baseDay = day ?? today
        if let t = time ?? defaultTime {
            var date = calendar.date(bySettingHour: t.h, minute: t.m, second: 0, of: baseDay) ?? baseDay
            if day == nil && date <= now { date = calendar.date(byAdding: .day, value: 1, to: date) ?? date }
            return ParsedDate(date: date, hasTime: true, remainder: Rx.tidy(s))
        }
        return ParsedDate(date: baseDay, hasTime: false, remainder: Rx.tidy(s))
    }
}
