import Foundation

public enum FocusPhase: String, Codable, Sendable, CaseIterable {
    case focus, shortBreak, longBreak
    public var isBreak: Bool { self != .focus }
    public var title: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }
}

public struct FocusSettings: Codable, Equatable, Sendable {
    public var focusMinutes = 25
    public var shortBreakMinutes = 5
    public var longBreakMinutes = 15
    public var longBreakEvery = 4
    public var breaksEnabled = true
    public var autoStartBreaks = true
    public var autoStartFocus = false
    /// Hold back hydration/movement reminders while a focus session runs.
    public var muteNonessentialDuringFocus = true
    public var notifyWhenPhaseEnds = true
    public var dailyGoalSessions = 4
    public var movementRemindersEnabled = false
    public var movementIntervalMinutes = 60

    public static let focusRange = 1...180
    public static let breakRange = 1...60
    public static let goalRange = 1...20
    public static let movementRange = 15...240

    public init() {}

    public func validated() -> FocusSettings {
        var s = self
        s.focusMinutes = s.focusMinutes.clamped(to: Self.focusRange)
        s.shortBreakMinutes = s.shortBreakMinutes.clamped(to: Self.breakRange)
        s.longBreakMinutes = s.longBreakMinutes.clamped(to: Self.breakRange)
        s.longBreakEvery = s.longBreakEvery.clamped(to: 2...10)
        s.dailyGoalSessions = s.dailyGoalSessions.clamped(to: Self.goalRange)
        s.movementIntervalMinutes = s.movementIntervalMinutes.clamped(to: Self.movementRange)
        return s
    }

    public func minutes(for phase: FocusPhase) -> Int {
        switch phase {
        case .focus: return focusMinutes
        case .shortBreak: return shortBreakMinutes
        case .longBreak: return longBreakMinutes
        }
    }
}

extension FocusSettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FocusSettings()
        self.init()
        focusMinutes = c.value(.focusMinutes, default: d.focusMinutes)
        shortBreakMinutes = c.value(.shortBreakMinutes, default: d.shortBreakMinutes)
        longBreakMinutes = c.value(.longBreakMinutes, default: d.longBreakMinutes)
        longBreakEvery = c.value(.longBreakEvery, default: d.longBreakEvery)
        breaksEnabled = c.value(.breaksEnabled, default: d.breaksEnabled)
        autoStartBreaks = c.value(.autoStartBreaks, default: d.autoStartBreaks)
        autoStartFocus = c.value(.autoStartFocus, default: d.autoStartFocus)
        muteNonessentialDuringFocus = c.value(.muteNonessentialDuringFocus, default: d.muteNonessentialDuringFocus)
        notifyWhenPhaseEnds = c.value(.notifyWhenPhaseEnds, default: d.notifyWhenPhaseEnds)
        dailyGoalSessions = c.value(.dailyGoalSessions, default: d.dailyGoalSessions)
        movementRemindersEnabled = c.value(.movementRemindersEnabled, default: d.movementRemindersEnabled)
        movementIntervalMinutes = c.value(.movementIntervalMinutes, default: d.movementIntervalMinutes)
        self = validated()
    }
}

/// The active timer. Time is stored as absolute dates, never as a counter, so
/// the remaining time is correct after sleep, hiding the app, or a restart.
public struct FocusTimer: Codable, Equatable, Sendable {
    public var phase: FocusPhase
    public var plannedSeconds: TimeInterval
    public var startedAt: Date
    /// Set while running.
    public var endsAt: Date?
    /// Set while paused.
    public var pausedRemaining: TimeInterval?
    public var label: String?
    /// Which Focus World started this session (nil = classic timer).
    public var world: String?

    public var isRunning: Bool { endsAt != nil }
    public var isPaused: Bool { endsAt == nil }

    public func remaining(at now: Date) -> TimeInterval {
        if let endsAt { return max(0, endsAt.timeIntervalSince(now)) }
        return max(0, pausedRemaining ?? 0)
    }

    /// Time actually spent in this phase (pauses excluded).
    public func activeSeconds(at now: Date) -> TimeInterval {
        max(0, plannedSeconds - remaining(at: now))
    }

    public func progress(at now: Date) -> Double {
        plannedSeconds > 0 ? min(1, activeSeconds(at: now) / plannedSeconds) : 0
    }
}

public struct FocusRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var phase: FocusPhase
    public var start: Date
    public var end: Date
    public var plannedSeconds: TimeInterval
    public var activeSeconds: TimeInterval
    /// False when skipped or stopped early.
    public var completed: Bool
    public var label: String?
    /// Focus World the session ran in, if any.
    public var world: String?
    /// Optional "What did you accomplish?" answer.
    public var reflection: String?

    public init(id: UUID = UUID(), phase: FocusPhase, start: Date, end: Date, plannedSeconds: TimeInterval,
                activeSeconds: TimeInterval, completed: Bool, label: String? = nil, world: String? = nil,
                reflection: String? = nil) {
        self.id = id
        self.phase = phase
        self.start = start
        self.end = end
        self.plannedSeconds = plannedSeconds
        self.activeSeconds = activeSeconds
        self.completed = completed
        self.label = label
        self.world = world
        self.reflection = reflection
    }
}

public enum FocusError: Error, Equatable, LocalizedError {
    case invalidMinutes(Int)
    case timerAlreadyActive
    case noActiveTimer

    public var errorDescription: String? {
        switch self {
        case .invalidMinutes(let m): return "\(m) minutes is out of range (1–180)."
        case .timerAlreadyActive: return "A timer is already running. Stop it first."
        case .noActiveTimer: return "There's no active timer."
        }
    }
}

public enum FocusEvent: Equatable, Sendable {
    /// A phase ran to completion. `next` is the phase that auto-started, if any.
    case completed(FocusRecord, next: FocusPhase?)
}

public struct FocusData: Codable, Equatable, Sendable {
    public var settings = FocusSettings()
    public var timer: FocusTimer?
    public var records: [FocusRecord] = []
    /// Completed focus sessions since the last long break.
    public var cycleCount = 0

    public init() {}

    // MARK: Commands

    public mutating func start(_ phase: FocusPhase, minutes: Int? = nil, label: String? = nil,
                               now: Date, replacing: Bool = false, world: String? = nil) throws {
        if timer != nil && !replacing { throw FocusError.timerAlreadyActive }
        let m = minutes ?? settings.minutes(for: phase)
        let range = phase == .focus ? FocusSettings.focusRange : FocusSettings.breakRange
        guard range.contains(m) else { throw FocusError.invalidMinutes(m) }
        if replacing, let current = timer { records.append(record(for: current, end: now, completed: false)) }
        let seconds = TimeInterval(m) * 60
        timer = FocusTimer(phase: phase, plannedSeconds: seconds, startedAt: now,
                           endsAt: now.addingTimeInterval(seconds), pausedRemaining: nil,
                           label: label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty, world: world)
    }

    @discardableResult
    public mutating func pause(now: Date) -> Bool {
        guard var t = timer, let endsAt = t.endsAt else { return false }
        t.pausedRemaining = max(0, endsAt.timeIntervalSince(now))
        t.endsAt = nil
        timer = t
        return true
    }

    @discardableResult
    public mutating func resume(now: Date) -> Bool {
        guard var t = timer, t.endsAt == nil else { return false }
        t.endsAt = now.addingTimeInterval(t.pausedRemaining ?? 0)
        t.pausedRemaining = nil
        timer = t
        return true
    }

    /// Ends the current phase early. Recorded as not completed; nothing auto-starts.
    @discardableResult
    public mutating func skip(now: Date) -> FocusRecord? {
        guard let t = timer else { return nil }
        let r = record(for: t, end: now, completed: false)
        records.append(r)
        timer = nil
        return r
    }

    /// Discards the current timer and cycle without recording anything.
    public mutating func reset() {
        timer = nil
        cycleCount = 0
    }

    /// Completes the phase if its end time has passed. Safe to call any time.
    /// If the app was closed long past the end, the next phase is *not*
    /// auto-started (the user wasn't there to take the break).
    public mutating func advance(now: Date) -> [FocusEvent] {
        guard let t = timer, let endsAt = t.endsAt, endsAt <= now else { return [] }
        let r = record(for: t, end: endsAt, completed: true)
        records.append(r)
        timer = nil

        var next: FocusPhase?
        if t.phase == .focus {
            cycleCount += 1
            if settings.breaksEnabled {
                next = cycleCount % settings.longBreakEvery == 0 ? .longBreak : .shortBreak
            }
        } else {
            if t.phase == .longBreak { cycleCount = 0 }
            next = .focus
        }

        let onTime = now.timeIntervalSince(endsAt) < 60
        // Focus World sessions never auto-start the next phase; the world decides what happens next.
        let auto = t.world == nil && (next.map { $0.isBreak ? settings.autoStartBreaks : settings.autoStartFocus } ?? false)
        if let phase = next, auto, onTime {
            // Starts exactly at the previous end so no time is lost or invented.
            try? start(phase, now: endsAt)
            return [.completed(r, next: phase)]
        }
        return [.completed(r, next: nil)]
    }

    /// Attaches an optional reflection to a recorded session. Returns false if not found.
    @discardableResult
    public mutating func setReflection(_ text: String?, for recordID: UUID) -> Bool {
        guard let i = records.firstIndex(where: { $0.id == recordID }) else { return false }
        let clean = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        records[i].reflection = (clean?.isEmpty ?? true) ? nil : String(clean!.prefix(2000))
        return true
    }

    /// Which phase the "start" button should suggest when idle.
    public func suggestedNextPhase(now: Date) -> FocusPhase {
        guard settings.breaksEnabled, let last = records.last, last.completed, last.phase == .focus,
              now.timeIntervalSince(last.end) < 30 * 60 else { return .focus }
        return cycleCount % settings.longBreakEvery == 0 && cycleCount > 0 ? .longBreak : .shortBreak
    }

    private func record(for t: FocusTimer, end: Date, completed: Bool) -> FocusRecord {
        FocusRecord(phase: t.phase, start: t.startedAt, end: end, plannedSeconds: t.plannedSeconds,
                    activeSeconds: completed ? t.plannedSeconds : t.activeSeconds(at: end),
                    completed: completed, label: t.label, world: t.world)
    }
}

extension FocusData {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        settings = c.value(.settings, default: FocusSettings())
        timer = c.value(.timer, default: nil)
        records = c.value(.records, default: [])
        cycleCount = c.value(.cycleCount, default: 0)
    }
}

/// Read-only focus summaries.
public enum Focus {
    public struct DaySummary: Equatable, Sendable {
        public var day: Date
        public var sessionsCompleted: Int
        public var focusMinutes: Int
        public var breaksCompleted: Int
    }

    public static func day(_ day: Date, records: [FocusRecord], calendar: Calendar) -> DaySummary {
        let list = records.filter { calendar.isDate($0.end, inSameDayAs: day) }
        let focus = list.filter { $0.phase == .focus }
        return DaySummary(
            day: calendar.startOfDay(for: day),
            sessionsCompleted: focus.filter(\.completed).count,
            focusMinutes: Int((focus.reduce(0) { $0 + $1.activeSeconds } / 60).rounded()),
            breaksCompleted: list.filter { $0.phase.isBreak && $0.completed }.count
        )
    }

    public static func week(endingOn now: Date, records: [FocusRecord], calendar: Calendar) -> [DaySummary] {
        calendar.recentDays(7, endingOn: now).map { day($0, records: records, calendar: calendar) }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
