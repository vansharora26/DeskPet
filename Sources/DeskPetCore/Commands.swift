import Foundation

public enum ReminderKind: String, Codable, Sendable, CaseIterable {
    case hydration, movement
    public var title: String { self == .hydration ? "Water reminders" : "Movement reminders" }
}

public enum StatsPeriod: String, Codable, Sendable {
    case today, week
}

public enum Destination: String, Codable, Sendable, CaseIterable {
    case today, chat, capture, water, focus, tasks, notes, stats, settings, launcher
}

/// Every action DeskPet can perform, from the launcher, chat, AI tools, or UI.
/// Each case carries already-validated, typed arguments.
public enum AppCommand: Equatable, Sendable {
    /// nil = the user's default serving.
    case logWater(ml: Int?)
    case undoWater
    case setWaterGoal(ml: Int)
    case startFocus(minutes: Int?, label: String?)
    case startBreak(minutes: Int?)
    case pauseFocus
    case resumeFocus
    case stopFocus
    case skipPhase
    case createTask(title: String, due: Date?, dueHasTime: Bool, remindAt: Date?)
    case createNote(text: String)
    case completeTask(query: String)
    /// nil = all open tasks.
    case showTasks(TaskFilter?)
    case showStats(StatsPeriod)
    case summarizeFocus(StatsPeriod)
    /// "What's my total?" — today's water so far.
    case waterTotal
    /// "How long is left?" — the active timer.
    case timerStatus
    case configureReminder(kind: ReminderKind, enabled: Bool?, intervalMinutes: Int?)
    case open(Destination)

    /// Actions that lose data or can't be undone need an explicit confirmation.
    public var needsConfirmation: Bool {
        switch self {
        case .stopFocus: return true
        case .configureReminder(_, let enabled, _): return enabled == false
        default: return false
        }
    }

    /// Short human description of what will happen, shown before running.
    public func summary(defaultServing: Int, calendar: Calendar = .current) -> String {
        switch self {
        case .logWater(let ml): return "Log \(ml ?? defaultServing) ml of water"
        case .undoWater: return "Undo the last water entry"
        case .setWaterGoal(let ml): return "Set daily water goal to \(Self.formatML(ml))"
        case .startFocus(let m, let label):
            let base = m.map { "Start a \($0)-minute focus session" } ?? "Start a focus session"
            return label.map { "\(base): \($0)" } ?? base
        case .startBreak(let m): return m.map { "Start a \($0)-minute break" } ?? "Start a break"
        case .pauseFocus: return "Pause the timer"
        case .resumeFocus: return "Resume the timer"
        case .stopFocus: return "Stop and discard the current timer"
        case .skipPhase: return "Skip to the end of this phase"
        case .createTask(let title, let due, let hasTime, let remind):
            var s = "Add task “\(title)”"
            if let remind { s += " · remind \(Self.formatDate(remind, hasTime: true, calendar: calendar))" }
            else if let due { s += " · due \(Self.formatDate(due, hasTime: hasTime, calendar: calendar))" }
            return s
        case .createNote(let text): return "Save note “\(text.prefix(60))\(text.count > 60 ? "…" : "")”"
        case .completeTask(let q): return "Complete task matching “\(q)”"
        case .showTasks(let f): return f.map { "Show \($0.title.lowercased()) tasks" } ?? "Show unfinished tasks"
        case .showStats(let p): return p == .today ? "Show today’s progress" : "Show this week’s summary"
        case .summarizeFocus(let p): return p == .today ? "Summarize today’s focus" : "Summarize this week’s focus"
        case .configureReminder(let kind, let enabled, let interval):
            if enabled == false { return "Turn off \(kind.title.lowercased())" }
            if let interval { return "\(kind.title) every \(interval) minutes" }
            return "Turn on \(kind.title.lowercased())"
        case .open(let d): return "Open \(d.rawValue.capitalized)"
        case .waterTotal: return "Show today’s water total"
        case .timerStatus: return "Show time left on the timer"
        }
    }

    public static func formatML(_ ml: Int) -> String {
        ml >= 1000 && ml % 100 == 0 ? String(format: "%.1f L", Double(ml) / 1000) : "\(ml) ml"
    }

    public static func formatDate(_ date: Date, hasTime: Bool, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.doesRelativeDateFormatting = true
        f.dateStyle = .medium
        f.timeStyle = hasTime ? .short : .none
        return f.string(from: date)
    }
}

/// Turns typed natural language into an AppCommand, entirely on-device.
/// Returns nil when the text isn't a recognisable command (e.g. a question for the AI).
public enum CommandParser {
    public static func parse(_ raw: String, now: Date, calendar: Calendar) -> AppCommand? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
            .replacingOccurrences(of: "’", with: "'")
        guard !text.isEmpty, text.count <= 2000 else { return nil }
        let lower = text.lowercased()

        if let c = reminder(text, lower, now, calendar) { return c }
        if let c = reminderConfig(lower) { return c }
        if let c = waterGoal(lower) { return c }
        if let c = open(lower) { return c }
        if let c = water(lower) { return c }
        if let c = focus(text, lower) { return c }
        if let c = note(text) { return c }
        if let c = task(text, now, calendar) { return c }
        if let c = complete(text) { return c }
        if let c = queries(lower) { return c }
        return nil
    }

    // MARK: Reminders

    private static func reminder(_ text: String, _ lower: String, _ now: Date, _ cal: Calendar) -> AppCommand? {
        guard let m = Rx.first(#"^(?:please\s+)?remind me\s+(?:to\s+)?(.+)$"#, in: text) else { return nil }
        let rest = m[1] ?? ""
        // "remind me to drink water every 45 minutes" configures hydration reminders instead.
        if Rx.first(#"\b(drink|water|hydrat)"#, in: rest) != nil, Rx.first(#"\bevery\b"#, in: rest) != nil {
            return reminderConfig(lower)
        }
        if Rx.first(#"\b(stretch|move|stand|walk)"#, in: rest) != nil, Rx.first(#"\bevery\b"#, in: rest) != nil {
            return reminderConfig(lower)
        }
        if let parsed = NaturalDate.extract(from: rest, now: now, calendar: cal) {
            let title = parsed.remainder
            guard !title.isEmpty else { return nil }
            var remindAt = parsed.date
            if !parsed.hasTime {
                // Day only: remind at 9:00 that day (or skip if that's already past).
                remindAt = cal.date(bySettingHour: 9, minute: 0, second: 0, of: parsed.date) ?? parsed.date
                if remindAt <= now { return .createTask(title: cap(title), due: parsed.date, dueHasTime: false, remindAt: nil) }
            }
            return .createTask(title: cap(title), due: parsed.date, dueHasTime: parsed.hasTime, remindAt: remindAt)
        }
        let title = Rx.tidy(rest)
        return title.isEmpty ? nil : .createTask(title: cap(title), due: nil, dueHasTime: false, remindAt: nil)
    }

    private static func reminderConfig(_ lower: String) -> AppCommand? {
        let kind: ReminderKind
        if Rx.first(#"\b(water|hydrat|drink)"#, in: lower) != nil { kind = .hydration }
        else if Rx.first(#"\b(movement|move|stretch|stand)"#, in: lower) != nil { kind = .movement }
        else if Rx.first(#"\breminders?\b"#, in: lower) != nil { kind = .hydration }
        else { return nil }
        guard Rx.first(#"\breminder|\bremind\b|\bnudge"#, in: lower) != nil else { return nil }

        if let m = Rx.first(#"\bevery\s+(?:(\d+|an?|half an)\s*)?(minutes?|mins?|hours?|hrs?|h)\b"#, in: lower) {
            let q = (m[1] ?? "1")
            let qty = q == "half an" ? 0.5 : (Double(q) ?? 1)
            let minutes = Int((m[2] ?? "").hasPrefix("h") ? qty * 60 : qty)
            return .configureReminder(kind: kind, enabled: true, intervalMinutes: minutes)
        }
        if Rx.first(#"\b(turn|switch)\s+off\b|\b(disable|stop|mute|pause)\b|\boff$"#, in: lower) != nil {
            return .configureReminder(kind: kind, enabled: false, intervalMinutes: nil)
        }
        if Rx.first(#"\b(turn|switch)\s+on\b|\b(enable|start|resume|unmute)\b|\bon$"#, in: lower) != nil {
            return .configureReminder(kind: kind, enabled: true, intervalMinutes: nil)
        }
        return nil
    }

    // MARK: Water

    private static func amount(_ s: String) -> Int? {
        guard let m = Rx.first(#"(\d+(?:[.,]\d+)?)\s*(ml|millilit(?:er|re)s?|l|lit(?:er|re)s?|oz|ounces?)?\b"#, in: s),
              let numStr = m[1]?.replacingOccurrences(of: ",", with: "."), let n = Double(numStr) else { return nil }
        let unit = (m[2] ?? "").lowercased()
        if unit == "l" || unit.hasPrefix("lit") { return Int((n * 1000).rounded()) }
        if unit == "oz" || unit.hasPrefix("ounce") { return Int((n * 29.5735).rounded()) }
        if unit.isEmpty && n < 10 && numStr.contains(".") { return Int((n * 1000).rounded()) } // "1.5" → litres
        if unit.isEmpty && n >= 1 && n <= 6 && n == n.rounded() { return Int(n) * 250 }      // "2 glasses"
        return Int(n.rounded())
    }

    private static func waterGoal(_ lower: String) -> AppCommand? {
        guard Rx.first(#"\b(water|hydration|drink(?:ing)?)\b.*\b(goal|target)\b|\b(goal|target)\b.*\bwater\b"#, in: lower) != nil,
              let ml = amount(lower) else { return nil }
        return .setWaterGoal(ml: ml)
    }

    private static func water(_ lower: String) -> AppCommand? {
        if Rx.first(#"^(undo|remove|delete)\s+(the\s+)?(last\s+)?(water|drink|glass)"#, in: lower) != nil { return .undoWater }
        // Spoken style: "I've had 300 ml", "just drank half a litre" — a drinking verb plus a volume.
        // Other drinks are deliberately not logged as water.
        if Rx.first(#"\b(had|drank|drunk|drink|sipped|finished)\b"#, in: lower) != nil,
           Rx.first(#"\d\s*(ml|millilit|l\b|lit(er|re))"#, in: lower) != nil,
           Rx.first(#"\b(coffee|tea|juice|soda|beer|wine|milk|cola|smoothie|alcohol|how|what|should)\b|\?$"#, in: lower) == nil,
           let ml = amount(lower) {
            return .logWater(ml: ml)
        }
        guard Rx.first(#"\b(water|drank|drink|hydrat\w*|glass|bottle|sip)\b"#, in: lower) != nil,
              Rx.first(#"\b(goal|target|every|remind|how much|reminders?)\b|\?$"#, in: lower) == nil else { return nil }
        // Accept short imperative forms; leave questions and long sentences to the AI.
        guard lower.split(separator: " ").count <= 9 else { return nil }
        if let ml = amount(lower) { return .logWater(ml: ml) }
        if Rx.first(#"\bbottle\b"#, in: lower) != nil { return .logWater(ml: 500) }
        if Rx.first(#"^(log\s+|add\s+|had\s+|drank\s+|i\s+drank\s+)?(a\s+)?(glass\s+of\s+|cup\s+of\s+)?water$|^(log|add)\s+(a\s+)?(drink|glass)$|^drank$|^glass$"#, in: lower) != nil {
            return .logWater(ml: nil)
        }
        return nil
    }

    // MARK: Focus

    private static func minutes(_ s: String) -> Int? {
        if Rx.first(#"\bhalf an hour\b"#, in: s) != nil { return 30 }
        if Rx.first(#"\b(an|one) hour\b"#, in: s) != nil { return 60 }
        guard let m = Rx.first(#"(\d+(?:\.\d+)?)\s*-?\s*(h|hrs?|hours?|m|mins?|minutes?)\b"#, in: s),
              let n = Double(m[1] ?? "") else { return nil }
        return (m[2] ?? "").lowercased().hasPrefix("h") ? Int(n * 60) : Int(n)
    }

    private static func focus(_ text: String, _ lower: String) -> AppCommand? {
        if Rx.first(#"^(pause|hold)(\s+(the\s+)?(focus|timer|session|pomodoro))?$"#, in: lower) != nil { return .pauseFocus }
        if Rx.first(#"^(resume|continue|unpause)(\s+(the\s+)?(focus|timer|session|pomodoro))?$"#, in: lower) != nil { return .resumeFocus }
        if Rx.first(#"^(stop|cancel|end|reset|quit)\s+(the\s+)?(focus|timer|session|pomodoro|break)(\s+session)?$"#, in: lower) != nil { return .stopFocus }
        if Rx.first(#"^skip(\s+(the\s+)?(break|phase|session|focus))?$"#, in: lower) != nil { return .skipPhase }
        if Rx.first(#"^(take|start|have)\s+(a\s+)?(.*\s)?break$|^break(\s+time)?$|^(\d+)\s*(min|minute)s?\s+break$"#, in: lower) != nil {
            return .startBreak(minutes: minutes(lower))
        }
        guard Rx.first(#"\b(focus|pomodoro|deep work|concentrate)\b"#, in: lower) != nil,
              Rx.first(#"\b(summar|how (much|many|long)|stats|history|sessions this|this week)\b|\?$"#, in: lower) == nil
        else { return nil }
        let mins = minutes(lower)
        if let m = mins, !FocusSettings.focusRange.contains(m) { return nil }
        // "focus on the report for 30 minutes" → label "the report".
        var label: String?
        if let m = Rx.first(#"\bfocus(?:ing)?\s+on\s+(.+?)(?:\s+for\s+.*)?$"#, in: text) {
            label = Rx.tidy(m[1] ?? "").nilIfEmpty
        }
        return .startFocus(minutes: mins, label: label)
    }

    // MARK: Notes & tasks

    private static func note(_ text: String) -> AppCommand? {
        if let m = Rx.first(#"^(?:save|capture|jot(?:\s+down)?|note|remember)(?:\s+(?:this|that))?(?:\s+(?:idea|note|thought))?\s*[:\-]\s*(.+)$"#, in: text)
            ?? Rx.first(#"^(?:save|capture|jot down)\s+(?:this|that|an?)\s+(?:idea|note|thought)\s+(.+)$"#, in: text)
            ?? Rx.first(#"^(?:idea|note|thought)\s*[:\-]\s*(.+)$"#, in: text) {
            let body = (m[1] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty ? nil : .createNote(text: body)
        }
        return nil
    }

    private static func task(_ text: String, _ now: Date, _ cal: Calendar) -> AppCommand? {
        let m = Rx.first(#"^add\s+(.+?)\s+to\s+(?:my\s+)?(?:tasks?|to-?dos?|to-?do list|list|inbox)$"#, in: text)
            ?? Rx.first(#"^(?:add\s+)?(?:a\s+)?(?:new\s+)?(?:task|to-?do)\s*[:\-]?\s+(.+)$"#, in: text)
        guard let body = m?[1]?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else { return nil }
        if let parsed = NaturalDate.extract(from: body, now: now, calendar: cal), !parsed.remainder.isEmpty {
            return .createTask(title: cap(parsed.remainder), due: parsed.date, dueHasTime: parsed.hasTime, remindAt: nil)
        }
        return .createTask(title: cap(body), due: nil, dueHasTime: false, remindAt: nil)
    }

    private static func complete(_ text: String) -> AppCommand? {
        guard let m = Rx.first(#"^(?:complete|finish|finished|done with|check off|tick off|mark)\s+(?:the\s+)?(?:task\s+)?(.+?)(?:\s+as\s+(?:done|complete|completed|finished))?$"#, in: text) else { return nil }
        let q = Rx.tidy(m[1] ?? "")
        return q.isEmpty ? nil : .completeTask(query: q)
    }

    // MARK: Queries & navigation

    private static func queries(_ lower: String) -> AppCommand? {
        if Rx.first(#"\b(time|minutes?)\s+(is\s+)?(left|remaining)\b|\bhow long (is )?left\b|\btimer status\b"#, in: lower) != nil {
            return .timerStatus
        }
        if Rx.first(#"\b(water|drunk|drank|hydration)\b"#, in: lower) != nil,
           Rx.first(#"\b(total|so far|how much|how many)\b"#, in: lower) != nil,
           Rx.first(#"\b(i|my|today|i'?ve)\b"#, in: lower) != nil,
           Rx.first(#"\b(week|weekly|should|could|ought|need to|recommend\w*|healthy|per day|a day)\b"#, in: lower) == nil {
            return .waterTotal
        }
        let mentionsWeek = Rx.first(#"\b(this week|weekly|past week|last 7 days|week)\b"#, in: lower) != nil
        if Rx.first(#"\b(focus|pomodoro)\b"#, in: lower) != nil,
           Rx.first(#"\b(summar\w*|how (much|many|long)|sessions|stats|history)\b"#, in: lower) != nil {
            return .summarizeFocus(mentionsWeek ? .week : .today)
        }
        if Rx.first(#"\b(tasks?|to-?dos?)\b"#, in: lower) != nil,
           Rx.first(#"^(show|list|what|what's|whats|which|view|see|display|my)\b"#, in: lower) != nil {
            if Rx.first(#"\b(completed|done|finished)\b"#, in: lower) != nil { return .showTasks(.completed) }
            if Rx.first(#"\b(upcoming|coming up|later|this week)\b"#, in: lower) != nil { return .showTasks(.upcoming) }
            if Rx.first(#"\b(inbox|undated)\b"#, in: lower) != nil { return .showTasks(.inbox) }
            if Rx.first(#"\b(today|due)\b"#, in: lower) != nil { return .showTasks(.today) }
            return .showTasks(nil)
        }
        if Rx.first(#"^what'?s due( today)?$"#, in: lower) != nil { return .showTasks(.today) }
        if Rx.first(#"\b(progress|stats|statistics|summary|how am i doing|how'?s my day|how much water)\b"#, in: lower) != nil,
           Rx.first(#"\b(my|i|i'?ve|me|today|today'?s|this week)\b|^(show\s+)?(progress|stats|summary)$"#, in: lower) != nil,
           Rx.first(#"\b(should|could|ought|recommend\w*|healthy|per day)\b"#, in: lower) == nil,
           lower.split(separator: " ").count <= 8 {
            return .showStats(mentionsWeek ? .week : .today)
        }
        return nil
    }

    private static func open(_ lower: String) -> AppCommand? {
        // Unambiguous words open on their own; "water"/"focus" alone are actions, so they need a verb.
        let map: [(String, Destination, Bool)] = [
            ("settings|preferences|prefs", .settings, false), ("chat|assistant", .chat, false),
            ("quick capture|capture|new note", .capture, false), ("notes", .notes, false),
            ("tasks|to-?dos|to-?do list", .tasks, false), ("stats|insights|statistics", .stats, false),
            ("today|briefing|daily briefing|dashboard|home", .today, false), ("launcher|command palette", .launcher, false),
            ("water|hydration|water tracker", .water, true), ("focus|timer|pomodoro|focus timer", .focus, true),
        ]
        for (words, dest, needsVerb) in map {
            let verb = needsVerb ? "(?:open|show|go to|view)\\s+" : "(?:(?:open|show|go to|view)\\s+)?"
            if Rx.first("^\(verb)(?:the\\s+|my\\s+)?(?:\(words))(?:\\s+(?:view|tab|panel|window))?$", in: lower) != nil {
                return .open(dest)
            }
        }
        return nil
    }

    private static func cap(_ s: String) -> String {
        guard let f = s.first else { return s }
        return f.uppercased() + s.dropFirst()
    }
}
