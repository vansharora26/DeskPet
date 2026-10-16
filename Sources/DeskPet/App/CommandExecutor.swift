import DeskPetCore
import Foundation

/// Outcome of running a command, shown as feedback in the launcher, chat, or pet.
struct CommandResult {
    enum Style { case success, info, error }

    var style: Style
    var message: String
    /// Extra lines (task lists, stats rows).
    var details: [String] = []
    var undo: (@MainActor () -> Void)?
    /// Where to take the user to see more, if anywhere.
    var destination: Destination?
    /// When a command was ambiguous: the candidates to choose from.
    var choices: [Item] = []

    static func error(_ message: String) -> CommandResult { CommandResult(style: .error, message: message) }

    /// Plain-text rendering for AI tool results and accessibility.
    var plainText: String {
        ([message] + details.map { "• \($0)" }).joined(separator: "\n")
    }
}

/// Runs AppCommands against the model. This is the only place commands take
/// effect, so validation and feedback are identical everywhere.
@MainActor
struct CommandExecutor {
    let model: AppModel

    private var cal: Calendar { model.calendar }

    func run(_ command: AppCommand) -> CommandResult {
        do {
            return try execute(command)
        } catch {
            return .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func execute(_ command: AppCommand) throws -> CommandResult {
        switch command {
        case .logWater(let ml):
            let entry = try model.logWater(ml)
            let target = model.hydrationSettings.dailyTargetML
            return CommandResult(
                style: .success,
                message: "Logged \(entry.ml) ml · \(AppCommand.formatML(model.todayWaterML)) of \(AppCommand.formatML(target)) today",
                undo: { [model] in _ = model.removeWater(entry.id) })

        case .undoWater:
            guard let removed = model.undoLastWater() else { return .error("Nothing to undo today.") }
            return CommandResult(style: .success, message: "Removed \(removed.ml) ml",
                                 undo: { [model] in model.restoreWater(removed) })

        case .setWaterGoal(let ml):
            guard HydrationSettings.targetRange.contains(ml) else {
                return .error("Choose a goal between \(AppCommand.formatML(HydrationSettings.targetRange.lowerBound)) and \(AppCommand.formatML(HydrationSettings.targetRange.upperBound)).")
            }
            let old = model.hydrationSettings.dailyTargetML
            model.updateHydrationSettings { $0.dailyTargetML = ml }
            return CommandResult(style: .success, message: "Daily water goal set to \(AppCommand.formatML(ml))",
                                 undo: { [model] in model.updateHydrationSettings { $0.dailyTargetML = old } })

        case .startFocus(let minutes, let label):
            if let t = model.focusTimerState { return .error(busyMessage(t)) }
            try model.startFocus(.focus, minutes: minutes, label: label)
            let m = minutes ?? model.focusSettings.focusMinutes
            return CommandResult(style: .success, message: "Focus started: \(m) minutes\(label.map { " on \($0)" } ?? "")",
                                 destination: .focus)

        case .startBreak(let minutes):
            if let t = model.focusTimerState { return .error(busyMessage(t)) }
            let phase: FocusPhase = (minutes ?? 0) >= 15 ? .longBreak : .shortBreak
            try model.startFocus(phase, minutes: minutes)
            return CommandResult(style: .success,
                                 message: "Break started: \(minutes ?? model.focusSettings.minutes(for: phase)) minutes")

        case .pauseFocus:
            guard let t = model.focusTimerState, t.isRunning else { return .error("No timer is running.") }
            try model.pauseFocus()
            return CommandResult(style: .success, message: "Paused with \(Self.clock(t.remaining(at: Date()))) left",
                                 undo: { [model] in try? model.resumeFocus() })

        case .resumeFocus:
            guard let t = model.focusTimerState, t.isPaused else { return .error("There's no paused timer.") }
            try model.resumeFocus()
            return CommandResult(style: .success, message: "Resumed · \(Self.clock(t.remaining(at: Date()))) left")

        case .stopFocus:
            guard model.focusTimerState != nil else { return .error("No timer is active.") }
            try model.stopFocus()
            return CommandResult(style: .info, message: "Timer stopped")

        case .skipPhase:
            guard let t = model.focusTimerState else { return .error("No timer is active.") }
            try model.skipPhase()
            return CommandResult(style: .info, message: "Skipped the rest of this \(t.phase.title.lowercased())")

        case .createTask(let title, let due, let hasTime, let remindAt):
            if let remindAt, remindAt <= Date() { return .error("That reminder time has already passed.") }
            let item = try model.addItem(title, kind: .task, due: due, dueHasTime: hasTime, remindAt: remindAt)
            var msg = "Added task “\(item.title)”"
            if let remindAt { msg += " · I’ll remind you \(AppCommand.formatDate(remindAt, hasTime: true, calendar: cal))" }
            else if let due { msg += " · due \(AppCommand.formatDate(due, hasTime: hasTime, calendar: cal))" }
            return CommandResult(style: .success, message: msg, undo: { [model] in try? model.deleteItem(item.id) })

        case .createNote(let text):
            let item = try model.addItem(text, kind: .note)
            return CommandResult(style: .success, message: "Saved note “\(item.title.prefix(50))”",
                                 undo: { [model] in try? model.deleteItem(item.id) })

        case .completeTask(let query):
            let matches = model.data.items.matchOpenTasks(query)
            if matches.isEmpty { return .error("No open task matches “\(query)”.") }
            if matches.count > 1 {
                return CommandResult(style: .info, message: "Which one did you mean?",
                                     details: matches.prefix(5).map(\.title), choices: Array(matches.prefix(5)))
            }
            let task = matches[0]
            try model.setCompleted(task.id, true)
            return CommandResult(style: .success, message: "Completed “\(task.title)”",
                                 undo: { [model] in try? model.setCompleted(task.id, false) })

        case .showTasks(let filter):
            let list: [Item]
            if let filter { list = model.data.items.tasks(filter, now: Date(), calendar: cal) }
            else { list = model.data.items.openTasks().sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) } }
            let name = filter.map { $0.title.lowercased() } ?? "unfinished"
            if list.isEmpty {
                return CommandResult(style: .info, message: "No \(name) tasks. Nice!", destination: .tasks)
            }
            return CommandResult(style: .info, message: "\(list.count) \(name) task\(list.count == 1 ? "" : "s")",
                                 details: list.prefix(8).map(taskLine) + (list.count > 8 ? ["…and \(list.count - 8) more"] : []),
                                 destination: .tasks)

        case .showStats(let period):
            return period == .today ? todayStats() : weekStats()

        case .summarizeFocus(let period):
            return focusSummary(period)

        case .configureReminder(let kind, let enabled, let interval):
            if let interval {
                let range = kind == .hydration ? HydrationSettings.intervalRange : FocusSettings.movementRange
                guard range.contains(interval) else {
                    return .error("Pick an interval between \(range.lowerBound) and \(range.upperBound) minutes.")
                }
            }
            switch kind {
            case .hydration:
                model.updateHydrationSettings { s in
                    if let enabled { s.remindersEnabled = enabled }
                    if let interval { s.reminderIntervalMinutes = interval; s.remindersEnabled = true }
                }
                let s = model.hydrationSettings
                return CommandResult(style: .success, message: s.remindersEnabled
                    ? "Water reminders on, every \(s.reminderIntervalMinutes) minutes"
                    : "Water reminders off")
            case .movement:
                model.updateFocusSettings { s in
                    if let enabled { s.movementRemindersEnabled = enabled }
                    if let interval { s.movementIntervalMinutes = interval; s.movementRemindersEnabled = true }
                }
                let s = model.focusSettings
                return CommandResult(style: .success, message: s.movementRemindersEnabled
                    ? "Movement reminders on, every \(s.movementIntervalMinutes) minutes"
                    : "Movement reminders off")
            }

        case .open(let destination):
            return CommandResult(style: .info, message: "Opening \(destination.rawValue)", destination: destination)

        case .waterTotal:
            let total = model.todayWaterML
            let target = model.hydrationSettings.dailyTargetML
            let message: String
            if total == 0 {
                message = "No water logged yet today. Your goal is \(AppCommand.formatML(target))."
            } else if total >= target {
                message = "You’ve had \(AppCommand.formatML(total)) today — goal of \(AppCommand.formatML(target)) reached!"
            } else {
                message = "You’ve had \(AppCommand.formatML(total)) today, \(AppCommand.formatML(target - total)) to go to your \(AppCommand.formatML(target)) goal."
            }
            return CommandResult(style: .info, message: message, destination: .water)

        case .timerStatus:
            guard let t = model.focusTimerState else {
                return CommandResult(style: .info, message: "No timer is running.", destination: .focus)
            }
            let left = Self.spokenDuration(t.remaining(at: Date()))
            let what = t.phase == .focus ? "focus session" : "break"
            return CommandResult(style: .info, message: t.isRunning ? "\(left) left in your \(what)." : "Your \(what) is paused with \(left) left.",
                                 destination: .focus)
        }
    }

    // MARK: - Summaries (computed from recorded data only)

    func todayStats() -> CommandResult {
        let water = model.todayWaterML
        let target = model.hydrationSettings.dailyTargetML
        let f = model.todayFocus
        let done = model.data.items.completedCount(on: Date(), calendar: cal)
        let open = model.data.items.tasks(.today, now: Date(), calendar: cal).count
        return CommandResult(style: .info, message: "Today so far", details: [
            "Water: \(AppCommand.formatML(water)) of \(AppCommand.formatML(target))",
            "Focus: \(f.sessionsCompleted) of \(model.focusSettings.dailyGoalSessions) sessions (\(f.focusMinutes) min)",
            "Breaks: \(f.breaksCompleted + model.movementBreaks(on: Date()))",
            "Tasks: \(done) completed, \(open) due today",
        ], destination: .today)
    }

    func weekStats() -> CommandResult {
        let target = model.hydrationSettings.dailyTargetML
        let w = Hydration.week(endingOn: Date(), entries: model.data.hydration.entries, target: target, calendar: cal)
        let f = Focus.week(endingOn: Date(), records: model.data.focus.records, calendar: cal)
        let tasks = cal.recentDays(7, endingOn: Date()).reduce(0) { $0 + model.data.items.completedCount(on: $1, calendar: cal) }
        return CommandResult(style: .info, message: "Last 7 days", details: [
            "Water: \(AppCommand.formatML(w.totalML)) total, goal met on \(w.daysGoalMet) day\(w.daysGoalMet == 1 ? "" : "s")",
            "Focus: \(f.reduce(0) { $0 + $1.sessionsCompleted }) sessions, \(f.reduce(0) { $0 + $1.focusMinutes }) min",
            "Breaks: \(f.reduce(0) { $0 + $1.breaksCompleted })",
            "Tasks completed: \(tasks)",
        ], destination: .stats)
    }

    func focusSummary(_ period: StatsPeriod) -> CommandResult {
        let days = period == .today
            ? [Focus.day(Date(), records: model.data.focus.records, calendar: cal)]
            : Focus.week(endingOn: Date(), records: model.data.focus.records, calendar: cal)
        let sessions = days.reduce(0) { $0 + $1.sessionsCompleted }
        let minutes = days.reduce(0) { $0 + $1.focusMinutes }
        if sessions == 0 && minutes == 0 {
            return CommandResult(style: .info, message: period == .today
                ? "No focus sessions yet today. Want to start one?"
                : "No focus sessions in the last 7 days yet.", destination: .focus)
        }
        var details = ["\(sessions) completed session\(sessions == 1 ? "" : "s"), \(minutes) minutes focused"]
        if period == .week {
            let f = DateFormatter()
            f.dateFormat = "EEE"
            details += days.filter { $0.focusMinutes > 0 }.map { "\(f.string(from: $0.day)): \($0.sessionsCompleted) · \($0.focusMinutes) min" }
        }
        return CommandResult(style: .info, message: period == .today ? "Today’s focus" : "Focus this week",
                             details: details, destination: .stats)
    }

    func taskLine(_ item: Item) -> String {
        guard let due = item.due else { return item.title }
        return "\(item.title) — \(AppCommand.formatDate(due, hasTime: item.dueHasTime, calendar: cal))"
    }

    private func busyMessage(_ t: FocusTimer) -> String {
        "A \(t.phase.title.lowercased()) timer is already active (\(Self.clock(t.remaining(at: Date()))) left). Stop or skip it first."
    }

    /// "18 minutes", "1 minute 30 seconds", "45 seconds" — reads well aloud.
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        if s < 60 { return "\(s) second\(s == 1 ? "" : "s")" }
        let m = s / 60, rem = s % 60
        let mins = "\(m) minute\(m == 1 ? "" : "s")"
        return m < 5 && rem >= 10 ? "\(mins) \(rem) seconds" : mins
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}
