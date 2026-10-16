import Foundation

/// The immersive environments. Each world is configuration plus a scene; all
/// share the one authoritative focus timer (`FocusData`), so switching worlds
/// never creates a second timer. New worlds can be added as new cases.
public enum FocusWorld: String, Codable, CaseIterable, Identifiable, Sendable {
    case deepFocus, study, workSprint, recharge, planning

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .deepFocus: return "Deep Focus"
        case .study: return "Study"
        case .workSprint: return "Work Sprint"
        case .recharge: return "Recharge"
        case .planning: return "Daily Planning"
        }
    }

    public var tagline: String {
        switch self {
        case .deepFocus: return "A quiet night forest. One task, no distractions."
        case .study: return "A cozy study room for sprints, notes and breaks."
        case .workSprint: return "What are you trying to finish? Let’s finish it."
        case .recharge: return "A gentle garden break. Breathe, stretch, rest your eyes."
        case .planning: return "A bright morning desk to choose today’s three things."
        }
    }

    public var primaryAction: String {
        switch self {
        case .deepFocus: return "Begin deep focus"
        case .study: return "Start studying"
        case .workSprint: return "Start sprint"
        case .recharge: return "Take a break"
        case .planning: return "Plan my day"
        }
    }

    /// Recharge runs a break; planning doesn't run a timer at all.
    public var timerPhase: FocusPhase? {
        switch self {
        case .recharge: return .shortBreak
        case .planning: return nil
        default: return .focus
        }
    }

    public var suggestedMinutes: Int {
        switch self {
        case .deepFocus: return 50
        case .study: return 25
        case .workSprint: return 45
        case .recharge: return 5
        case .planning: return 10
        }
    }

    public var minuteRange: ClosedRange<Int> {
        timerPhase == .shortBreak ? FocusSettings.breakRange : 5...180
    }

    /// Procedural ambient sounds that suit this world (empty = no audio).
    public var ambientSounds: [AmbientSound] {
        switch self {
        case .deepFocus: return [.rain, .forest, .brownNoise]
        case .study: return [.fireplace, .rain, .brownNoise]
        case .recharge: return [.forest, .rain]
        case .workSprint, .planning: return []
        }
    }

    public var supportsAmbience: Bool { !ambientSounds.isEmpty }
}

/// Sounds generated live on the Mac (no recordings, no licensing issues).
public enum AmbientSound: String, Codable, CaseIterable, Identifiable, Sendable {
    case rain, forest, brownNoise, fireplace
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .rain: return "Rain"
        case .forest: return "Forest breeze"
        case .brownNoise: return "Soft room noise"
        case .fireplace: return "Fireplace"
        }
    }
}

public enum MotionLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case full, subtle, still
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .full: return "Lively"
        case .subtle: return "Subtle"
        case .still: return "Still"
        }
    }
}

public enum SceneryStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case illustrated, minimal
    public var id: String { rawValue }
    public var title: String { self == .illustrated ? "Illustrated scene" : "Minimal gradient" }
}

public enum SessionEndBehavior: String, Codable, CaseIterable, Identifiable, Sendable {
    case summary, summaryThenBreak, returnToPet
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .summary: return "Show a summary"
        case .summaryThenBreak: return "Show a summary, then offer Recharge"
        case .returnToPet: return "Close the world and return to DeskPet"
        }
    }
}

public struct WorldsSettings: Codable, Equatable, Sendable {
    public var defaultWorld: FocusWorld = .deepFocus
    /// Open to the world picker (true) or straight into `defaultWorld` (false).
    public var openToLobby = true
    /// Per-world session length (minutes), keyed by world id.
    public var minutes: [String: Int] = [:]
    /// Ambient audio is opt-in.
    public var ambientEnabled = false
    /// Preferred sound per world id.
    public var ambientSound: [String: AmbientSound] = [:]
    public var volume: Double = 0.45
    public var motion: MotionLevel = .subtle
    public var scenery: SceneryStyle = .illustrated
    public var showPet = true
    public var sessionEnd: SessionEndBehavior = .summary
    /// Hide the floating desktop pet while a world is open (it appears inside the world instead).
    public var hideDesktopPet = true
    public var breathingGuide = true

    public init() {}

    public func minutes(for world: FocusWorld) -> Int {
        (minutes[world.rawValue] ?? world.suggestedMinutes).clamped(to: world.minuteRange)
    }

    public mutating func setMinutes(_ m: Int, for world: FocusWorld) {
        minutes[world.rawValue] = m.clamped(to: world.minuteRange)
    }

    public func sound(for world: FocusWorld) -> AmbientSound? {
        guard world.supportsAmbience else { return nil }
        if let s = ambientSound[world.rawValue], world.ambientSounds.contains(s) { return s }
        return world.ambientSounds.first
    }
}

extension WorldsSettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WorldsSettings()
        self.init()
        defaultWorld = c.value(.defaultWorld, default: d.defaultWorld)
        openToLobby = c.value(.openToLobby, default: true)
        minutes = c.value(.minutes, default: [:])
        ambientEnabled = c.value(.ambientEnabled, default: false)
        ambientSound = c.value(.ambientSound, default: [:])
        volume = min(1, max(0, c.value(.volume, default: d.volume)))
        motion = c.value(.motion, default: d.motion)
        scenery = c.value(.scenery, default: d.scenery)
        showPet = c.value(.showPet, default: true)
        sessionEnd = c.value(.sessionEnd, default: .summary)
        hideDesktopPet = c.value(.hideDesktopPet, default: true)
        breathingGuide = c.value(.breathingGuide, default: true)
    }
}

/// A small checklist entry; optionally linked to a real DeskPet task.
public struct ChecklistItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var done: Bool
    public var taskID: UUID?

    public init(id: UUID = UUID(), title: String, done: Bool = false, taskID: UUID? = nil) {
        self.id = id
        self.title = title
        self.done = done
        self.taskID = taskID
    }
}

/// Work Sprint: one objective, optional milestones and deadline.
public struct SprintPlan: Codable, Equatable, Sendable {
    public var objective: String
    public var taskID: UUID?
    public var milestones: [ChecklistItem]
    public var deadline: Date?
    public var createdAt: Date
    /// Set when the user reports the objective finished (even before the timer ends).
    public var finishedAt: Date?

    public init(objective: String, taskID: UUID? = nil, milestones: [ChecklistItem] = [], deadline: Date? = nil, createdAt: Date) {
        self.objective = objective
        self.taskID = taskID
        self.milestones = milestones
        self.deadline = deadline
        self.createdAt = createdAt
    }

    public var milestonesDone: Int { milestones.filter(\.done).count }
}

/// Study mode working state (checklist and running notes).
public struct StudyPlan: Codable, Equatable, Sendable {
    public var topic = ""
    public var checklist: [ChecklistItem] = []
    public var notes = ""
    public init() {}
}

/// Daily Planning: up to three outcomes for one local day.
public struct DayPlan: Codable, Equatable, Sendable {
    public static let maxPriorities = 3

    public var dayKey: String
    public var priorities: [ChecklistItem]
    public var availableHours: Double
    public var notes: String
    public var review: String?
    public var reviewedAt: Date?

    public init(dayKey: String, priorities: [ChecklistItem] = [], availableHours: Double = 4, notes: String = "") {
        self.dayKey = dayKey
        self.priorities = priorities
        self.availableHours = availableHours
        self.notes = notes
    }

    /// Adds a priority unless the plan already has three. Returns false when full or empty.
    @discardableResult
    public mutating func addPriority(_ title: String, taskID: UUID? = nil) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, priorities.count < Self.maxPriorities else { return false }
        if let taskID, priorities.contains(where: { $0.taskID == taskID }) { return false }
        priorities.append(ChecklistItem(title: String(t.prefix(200)), taskID: taskID))
        return true
    }
}

/// Everything Focus Worlds stores (inside DeskPetData).
public struct WorldsData: Codable, Equatable, Sendable {
    public var settings = WorldsSettings()
    public var sprint: SprintPlan?
    public var study = StudyPlan()
    public var plans: [DayPlan] = []
    public var lastWorld: FocusWorld?
    /// A finished world session waiting for its (optional) reflection screen.
    public var pendingSummary: UUID?

    public init() {}

    public func plan(for dayKey: String) -> DayPlan? { plans.first { $0.dayKey == dayKey } }

    public mutating func updatePlan(for dayKey: String, _ change: (inout DayPlan) -> Void) {
        if let i = plans.firstIndex(where: { $0.dayKey == dayKey }) {
            change(&plans[i])
        } else {
            var p = DayPlan(dayKey: dayKey)
            change(&p)
            plans.append(p)
        }
        plans.sort { $0.dayKey < $1.dayKey }
        if plans.count > 60 { plans.removeFirst(plans.count - 60) }
    }
}

extension WorldsData {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        settings = c.value(.settings, default: WorldsSettings())
        sprint = c.value(.sprint, default: nil)
        study = c.value(.study, default: StudyPlan())
        plans = c.value(.plans, default: [])
        lastWorld = c.value(.lastWorld, default: nil)
        pendingSummary = c.value(.pendingSummary, default: nil)
    }
}

/// Read-only helpers for world screens.
public enum Worlds {
    /// How many focus sessions fit into the hours available (focus + short break each).
    public static func estimatedSessions(hours: Double, focusMinutes: Int, breakMinutes: Int) -> Int {
        guard hours > 0, focusMinutes > 0 else { return 0 }
        return Int((hours * 60 + Double(breakMinutes)) / Double(focusMinutes + max(0, breakMinutes)))
    }

    /// Completed sessions in a world on a given day (from the shared history).
    public static func completedSessions(_ world: FocusWorld, on day: Date, records: [FocusRecord], calendar: Calendar) -> [FocusRecord] {
        records.filter { $0.world == world.rawValue && $0.completed && calendar.isDate($0.end, inSameDayAs: day) }
    }
}
