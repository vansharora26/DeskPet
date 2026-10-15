import DeskPetCore
import Foundation

/// The AI's only way to affect DeskPet: a fixed set of typed tools that map
/// onto AppCommands. No shell, no file access, no arbitrary code.
@MainActor
struct AssistantTools {
    let model: AppModel
    let accessToData: () -> AIDataAccess

    /// A validated tool call, ready to run (possibly after confirmation).
    struct Planned {
        enum Kind {
            case command(AppCommand)
            case read(ReadQuery)
        }
        var kind: Kind
        /// Shown to the user when asking for confirmation / permission.
        var description: String
        var needsConfirmation: Bool
        var isDataRead: Bool { if case .read(let q) = kind { return q.isPersonal }; return false }
    }

    enum ReadQuery {
        case tasks(TaskFilter?)
        case searchNotes(String)
        case dailyStats(Date)
        case weeklySummary
        case focusStatus

        /// Focus status is just "is a timer running" — not personal history.
        var isPersonal: Bool { if case .focusStatus = self { return false }; return true }
    }

    struct InputError: Error { let message: String }

    struct Outcome {
        var text: String
        var isError: Bool
        var result: CommandResult?
    }

    // MARK: - Definitions sent to the model

    static var definitions: [JSONValue] {
        func tool(_ name: String, _ description: String, _ properties: [String: JSONValue] = [:], required: [String] = []) -> JSONValue {
            ["name": .string(name), "description": .string(description),
             "input_schema": ["type": "object", "properties": .object(properties),
                              "required": .array(required.map { .string($0) }), "additionalProperties": false]]
        }
        let int: (String) -> JSONValue = { ["type": "integer", "description": .string($0)] }
        let str: (String) -> JSONValue = { ["type": "string", "description": .string($0)] }
        return [
            tool("log_water", "Log water the user drank, in millilitres. Only when the user says they drank water or asks to log it.",
                 ["ml": int("Amount in ml (10–2000).")], required: ["ml"]),
            tool("undo_last_water", "Remove the most recent water entry from today."),
            tool("set_water_goal", "Set the user's personal daily water goal.", ["ml": int("Goal in ml (250–6000).")], required: ["ml"]),
            tool("create_task", "Create a task, optionally with a deadline and/or a one-time reminder.",
                 ["title": str("Short task title."),
                  "due": str("Optional deadline as local ISO 8601: YYYY-MM-DD or YYYY-MM-DDTHH:MM."),
                  "remind_at": str("Optional reminder time as local ISO 8601 YYYY-MM-DDTHH:MM, in the future.")],
                 required: ["title"]),
            tool("create_note", "Save a note or idea.", ["text": str("The note text.")], required: ["text"]),
            tool("complete_task", "Mark an open task as done, matched by its title text.",
                 ["query": str("Words from the task title.")], required: ["query"]),
            tool("list_tasks", "Read the user's tasks (titles and due dates). Requires the user's permission.",
                 ["filter": ["type": "string", "enum": ["open", "inbox", "today", "upcoming", "completed"],
                             "description": "Which tasks. Default: open."]]),
            tool("search_notes", "Search the user's saved notes and tasks by text. Requires the user's permission.",
                 ["query": str("Search words.")], required: ["query"]),
            tool("get_daily_stats", "Read one day's water, focus, breaks and completed tasks. Requires the user's permission.",
                 ["date": str("'today', 'yesterday', or YYYY-MM-DD. Default: today.")]),
            tool("get_weekly_summary", "Read totals for the last 7 days. Requires the user's permission."),
            tool("get_focus_status", "Check whether a focus or break timer is active and how much time is left."),
            tool("start_focus_timer", "Start a focus session.",
                 ["minutes": int("Length in minutes (1–180). Omit for the user's default."),
                  "label": str("Optional: what the session is for.")]),
            tool("start_break", "Start a break timer.", ["minutes": int("Length in minutes (1–60). Omit for default.")]),
            tool("pause_focus_timer", "Pause the running timer."),
            tool("resume_focus_timer", "Resume a paused timer."),
            tool("stop_focus_timer", "Stop and discard the current timer. The user will be asked to confirm."),
            tool("skip_focus_phase", "End the current focus or break phase early."),
            tool("configure_reminder", "Turn water or movement reminders on/off or change how often they appear.",
                 ["type": ["type": "string", "enum": ["hydration", "movement"]],
                  "enabled": ["type": "boolean"],
                  "interval_minutes": int("How often, in minutes (15–240).")],
                 required: ["type"]),
        ]
    }

    // MARK: - Validation

    func plan(name: String, input: JSONValue) throws -> Planned {
        let args = input.object ?? [:]
        func command(_ c: AppCommand) -> Planned {
            Planned(kind: .command(c), description: c.summary(defaultServing: model.hydrationSettings.defaultServingML),
                    needsConfirmation: c.needsConfirmation)
        }
        func read(_ q: ReadQuery, _ d: String) -> Planned { Planned(kind: .read(q), description: d, needsConfirmation: false) }
        func text(_ key: String, max: Int, required: Bool = true) throws -> String? {
            guard let raw = args[key] else {
                if required { throw InputError(message: "Missing '\(key)'.") }
                return nil
            }
            guard let s = raw.string?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw InputError(message: "'\(key)' must be a string.")
            }
            if s.isEmpty { if required { throw InputError(message: "'\(key)' is empty.") }; return nil }
            guard s.count <= max else { throw InputError(message: "'\(key)' is too long (max \(max)).") }
            return s
        }
        func integer(_ key: String, _ range: ClosedRange<Int>, required: Bool = true) throws -> Int? {
            guard let raw = args[key] else {
                if required { throw InputError(message: "Missing '\(key)'.") }
                return nil
            }
            guard let n = raw.int else { throw InputError(message: "'\(key)' must be a whole number.") }
            guard range.contains(n) else { throw InputError(message: "'\(key)' must be between \(range.lowerBound) and \(range.upperBound).") }
            return n
        }

        switch name {
        case "log_water":
            return command(.logWater(ml: try integer("ml", HydrationSettings.servingRange)))
        case "undo_last_water":
            return command(.undoWater)
        case "set_water_goal":
            return command(.setWaterGoal(ml: try integer("ml", HydrationSettings.targetRange)!))
        case "create_task":
            let title = try text("title", max: 500)!
            var due: Date?, dueHasTime = false, remind: Date?
            if let d = try text("due", max: 40, required: false) {
                guard let parsed = Self.parseDate(d) else { throw InputError(message: "Couldn't read 'due' date '\(d)'.") }
                (due, dueHasTime) = parsed
            }
            if let r = try text("remind_at", max: 40, required: false) {
                guard let parsed = Self.parseDate(r), parsed.hasTime else {
                    throw InputError(message: "'remind_at' needs a date and time, like 2026-10-15T19:00.")
                }
                guard parsed.date > Date() else { throw InputError(message: "'remind_at' is in the past.") }
                guard parsed.date < Date().addingTimeInterval(366 * 86_400) else { throw InputError(message: "'remind_at' is too far ahead.") }
                remind = parsed.date
                if due == nil { (due, dueHasTime) = (parsed.date, true) }
            }
            return command(.createTask(title: title, due: due, dueHasTime: dueHasTime, remindAt: remind))
        case "create_note":
            return command(.createNote(text: try text("text", max: ItemStore.maxLength)!))
        case "complete_task":
            return command(.completeTask(query: try text("query", max: 200)!))
        case "list_tasks":
            let f = try text("filter", max: 20, required: false) ?? "open"
            let filter: TaskFilter?
            switch f {
            case "open": filter = nil
            default:
                guard let tf = TaskFilter(rawValue: f) else { throw InputError(message: "Unknown filter '\(f)'.") }
                filter = tf
            }
            return read(.tasks(filter), "read your \(filter?.title.lowercased() ?? "open") tasks (titles and due dates)")
        case "search_notes":
            let q = try text("query", max: 200)!
            return read(.searchNotes(q), "search your notes and tasks for “\(q)”")
        case "get_daily_stats":
            let raw = try text("date", max: 20, required: false) ?? "today"
            let cal = model.calendar
            let day: Date
            switch raw.lowercased() {
            case "today": day = Date()
            case "yesterday": day = cal.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            default:
                guard let p = Self.parseDate(raw), !p.hasTime, p.date <= Date(),
                      p.date > Date().addingTimeInterval(-366 * 86_400) else {
                    throw InputError(message: "'date' must be today, yesterday, or a past YYYY-MM-DD within a year.")
                }
                day = p.date
            }
            return read(.dailyStats(day), "read your water, focus and task stats for \(AppCommand.formatDate(day, hasTime: false, calendar: cal))")
        case "get_weekly_summary":
            return read(.weeklySummary, "read your stats for the last 7 days")
        case "get_focus_status":
            return read(.focusStatus, "check the focus timer")
        case "start_focus_timer":
            let label = try text("label", max: 100, required: false)
            return command(.startFocus(minutes: try integer("minutes", FocusSettings.focusRange, required: false), label: label))
        case "start_break":
            return command(.startBreak(minutes: try integer("minutes", FocusSettings.breakRange, required: false)))
        case "pause_focus_timer": return command(.pauseFocus)
        case "resume_focus_timer": return command(.resumeFocus)
        case "stop_focus_timer": return command(.stopFocus)
        case "skip_focus_phase": return command(.skipPhase)
        case "configure_reminder":
            guard let t = try text("type", max: 20), let kind = ReminderKind(rawValue: t) else {
                throw InputError(message: "'type' must be hydration or movement.")
            }
            let enabled: Bool?
            if let e = args["enabled"] {
                guard let b = e.bool else { throw InputError(message: "'enabled' must be true or false.") }
                enabled = b
            } else { enabled = nil }
            let range = kind == .hydration ? HydrationSettings.intervalRange : FocusSettings.movementRange
            let interval = try integer("interval_minutes", range, required: false)
            guard enabled != nil || interval != nil else { throw InputError(message: "Give 'enabled' and/or 'interval_minutes'.") }
            return command(.configureReminder(kind: kind, enabled: enabled, intervalMinutes: interval))
        default:
            throw InputError(message: "Unknown tool '\(name)'.")
        }
    }

    // MARK: - Execution

    func perform(_ planned: Planned) -> Outcome {
        switch planned.kind {
        case .command(let c):
            // Ambiguous completions only reveal candidate titles if reading data is allowed.
            let result = CommandExecutor(model: model).run(c)
            if !result.choices.isEmpty && accessToData() != .always {
                return Outcome(text: "Several tasks match. Ask the user which one (their task list is private).", isError: true, result: nil)
            }
            if case .open = c { return Outcome(text: "Navigation isn't available to the assistant.", isError: true, result: nil) }
            return Outcome(text: result.plainText, isError: result.style == .error, result: result)
        case .read(let q):
            return Outcome(text: readText(q), isError: false, result: nil)
        }
    }

    private func readText(_ q: ReadQuery) -> String {
        let exec = CommandExecutor(model: model)
        let cal = model.calendar
        switch q {
        case .tasks(let filter):
            let r = exec.run(.showTasks(filter))
            return r.plainText
        case .searchNotes(let query):
            let hits = model.data.items.search(query).prefix(8)
            if hits.isEmpty { return "No notes or tasks match “\(query)”." }
            return hits.map { item in
                let kind = item.isTask ? (item.isCompleted ? "done task" : "task") : "note"
                return "• [\(kind)] \(item.text.prefix(300))"
            }.joined(separator: "\n")
        case .dailyStats(let day):
            let target = model.hydrationSettings.dailyTargetML
            let w = Hydration.day(day, entries: model.data.hydration.entries, target: target, calendar: cal)
            let f = Focus.day(day, records: model.data.focus.records, calendar: cal)
            let done = model.data.items.completedCount(on: day, calendar: cal)
            return """
            Date: \(cal.dayKey(day))
            Water: \(w.ml) ml in \(w.drinks) entries (goal \(target) ml)
            Focus: \(f.sessionsCompleted) completed sessions, \(f.focusMinutes) minutes (daily goal \(model.focusSettings.dailyGoalSessions))
            Breaks: \(f.breaksCompleted) timer breaks, \(model.movementBreaks(on: day)) movement breaks
            Tasks completed: \(done)
            """
        case .weeklySummary:
            return exec.weekStats().plainText + "\n" + exec.focusSummary(.week).plainText
        case .focusStatus:
            guard let t = model.focusTimerState else { return "No timer is active." }
            return "\(t.phase.title) timer \(t.isRunning ? "running" : "paused"), \(CommandExecutor.clock(t.remaining(at: Date()))) left."
        }
    }

    /// Accepts "YYYY-MM-DD", "YYYY-MM-DDTHH:MM[:SS]" (local), or full ISO 8601 with offset.
    static func parseDate(_ s: String) -> (date: Date, hasTime: Bool)? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return (d, true) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        for (format, hasTime) in [("yyyy-MM-dd'T'HH:mm:ss", true), ("yyyy-MM-dd'T'HH:mm", true), ("yyyy-MM-dd HH:mm", true), ("yyyy-MM-dd", false)] {
            f.dateFormat = format
            if let d = f.date(from: s) { return (d, hasTime) }
        }
        return nil
    }
}
