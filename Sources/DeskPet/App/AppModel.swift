import AppKit
import Combine
import DeskPetCore
import os

/// Things that happened, so the pet (and other observers) can react.
/// Only emitted for real, recorded state changes — never for guessed activity.
enum AppEvent {
    case waterLogged(ml: Int, totalToday: Int, goalReachedNow: Bool)
    case waterUndone(ml: Int)
    case focusStarted(FocusPhase, minutes: Int)
    case focusPaused
    case focusResumed
    case focusStopped
    case phaseCompleted(FocusRecord, next: FocusPhase?)
    case itemCreated(Item)
    case taskCompleted(Item)
    case movementDone
    case leveledUp(Int)
    case milestone(Milestone)
}

/// Single source of truth for DeskPet's habit data. Wraps the pure core
/// types, persists every change, awards XP, and publishes events.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var data: DeskPetData
    @Published private(set) var lastSaveError: String?
    /// Refreshed every minute and on day/clock changes so "today" views stay correct.
    @Published private(set) var now = Date()

    let events = PassthroughSubject<AppEvent, Never>()
    var calendar: Calendar { Calendar.autoupdatingCurrent }
    let launchDate = Date()

    private let store: JSONDocumentStore<DeskPetData>
    private let log = Logger(subsystem: "app.deskpet.DeskPet", category: "data")
    private var saveScheduled = false
    private var clockTimer: Timer?
    private var focusTimer: Timer?
    private var focusActivity: NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []
    private(set) var recoveredFromCorruptFile = false

    init(store: JSONDocumentStore<DeskPetData>) {
        self.store = store
        switch store.load() {
        case .loaded(let d): data = d
        case .none: data = DeskPetData()
        case .recovered(let backup):
            data = DeskPetData()
            recoveredFromCorruptFile = true
            Logger(subsystem: "app.deskpet.DeskPet", category: "data")
                .error("Data file unreadable; backed up to \(backup?.path ?? "nowhere", privacy: .public)")
        }
        if data.hydration.reminder.anchor == nil { data.hydration.reminder.anchor = Date() }
        if data.movementReminder.anchor == nil { data.movementReminder.anchor = Date() }
        data.items.purgeTrash(now: Date())
        startClock()
        advanceFocus()
    }

    // MARK: - Persistence

    /// Applies a change, then saves (coalesced to one write per run-loop turn).
    @discardableResult
    func mutate<T>(_ change: (inout DeskPetData) throws -> T) rethrows -> T {
        var copy = data
        let result = try change(&copy)
        data = copy
        scheduleSave()
        return result
    }

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.saveScheduled = false
            self?.saveNow()
        }
    }

    func saveNow() {
        do {
            try store.save(data)
            lastSaveError = nil
        } catch {
            if lastSaveError == nil { log.error("Save failed: \(error.localizedDescription, privacy: .public)") }
            lastSaveError = error.localizedDescription
        }
    }

    // MARK: - Clock

    private func startClock() {
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        clockTimer = t
        let nc = NotificationCenter.default
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange, .NSSystemClockDidChange] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        })
    }

    func tick() {
        now = Date()
        advanceFocus()
    }

    func shutdown() {
        advanceFocus()
        saveNow()
        clockTimer?.invalidate()
        focusTimer?.invalidate()
    }

    // MARK: - Hydration

    var hydrationSettings: HydrationSettings { data.hydration.settings }

    var todayWaterML: Int { Hydration.total(on: Date(), in: data.hydration.entries, calendar: calendar) }

    var todayWaterEntries: [WaterEntry] {
        Hydration.entries(on: Date(), in: data.hydration.entries, calendar: calendar).sorted { $0.date > $1.date }
    }

    @discardableResult
    func logWater(_ ml: Int?) throws -> WaterEntry {
        let amount = ml ?? data.hydration.settings.defaultServingML
        let before = todayWaterML
        let target = data.hydration.settings.dailyTargetML
        let entry = try mutate { try $0.hydration.log(amount, at: Date()) }
        let total = todayWaterML
        let reached = before < target && total >= target
        award(.water)
        if reached { award(.hydrationGoal) }
        milestone("first-water", "First water logged")
        if reached { milestone("first-hydration-goal", "Reached a daily water goal") }
        events.send(.waterLogged(ml: amount, totalToday: total, goalReachedNow: reached))
        return entry
    }

    @discardableResult
    func undoLastWater() -> WaterEntry? {
        let removed = mutate { $0.hydration.undoLast(now: Date(), calendar: calendar) }
        if let removed { events.send(.waterUndone(ml: removed.ml)) }
        return removed
    }

    func removeWater(_ id: UUID) -> WaterEntry? {
        mutate { $0.hydration.remove(id: id) }
    }

    func restoreWater(_ entry: WaterEntry) {
        mutate { $0.hydration.restore(entry) }
    }

    func updateHydrationSettings(_ change: (inout HydrationSettings) -> Void) {
        mutate { d in
            let wasEnabled = d.hydration.settings.remindersEnabled
            change(&d.hydration.settings)
            d.hydration.settings = d.hydration.settings.validated()
            // Re-enabling starts a fresh interval instead of firing immediately.
            if !wasEnabled && d.hydration.settings.remindersEnabled { d.hydration.reminder.anchor = Date() }
        }
    }

    // MARK: - Focus

    var focusSettings: FocusSettings { data.focus.settings }
    var focusTimerState: FocusTimer? { data.focus.timer }

    func startFocus(_ phase: FocusPhase = .focus, minutes: Int? = nil, label: String? = nil, replacing: Bool = false) throws {
        try mutate { try $0.focus.start(phase, minutes: minutes, label: label, now: Date(), replacing: replacing) }
        let m = minutes ?? data.focus.settings.minutes(for: phase)
        events.send(.focusStarted(phase, minutes: m))
        scheduleFocusTimer()
    }

    func pauseFocus() throws {
        guard data.focus.timer != nil else { throw FocusError.noActiveTimer }
        if mutate({ $0.focus.pause(now: Date()) }) { events.send(.focusPaused) }
        scheduleFocusTimer()
    }

    func resumeFocus() throws {
        guard data.focus.timer != nil else { throw FocusError.noActiveTimer }
        if mutate({ $0.focus.resume(now: Date()) }) { events.send(.focusResumed) }
        scheduleFocusTimer()
    }

    func skipPhase() throws {
        guard data.focus.timer != nil else { throw FocusError.noActiveTimer }
        mutate { _ = $0.focus.skip(now: Date()) }
        events.send(.focusStopped)
        scheduleFocusTimer()
    }

    func stopFocus() throws {
        guard data.focus.timer != nil else { throw FocusError.noActiveTimer }
        mutate { $0.focus.reset() }
        events.send(.focusStopped)
        scheduleFocusTimer()
    }

    func updateFocusSettings(_ change: (inout FocusSettings) -> Void) {
        mutate { d in
            let wasEnabled = d.focus.settings.movementRemindersEnabled
            change(&d.focus.settings)
            d.focus.settings = d.focus.settings.validated()
            if !wasEnabled && d.focus.settings.movementRemindersEnabled { d.movementReminder.anchor = Date() }
        }
    }

    /// Completes the current phase if its end time has passed (from absolute time,
    /// so it's correct after sleep, App Nap, or a relaunch).
    func advanceFocus() {
        guard let endsAt = data.focus.timer?.endsAt, endsAt <= Date() else {
            scheduleFocusTimer()
            return
        }
        let events = mutate { $0.focus.advance(now: Date()) }
        for case .completed(let record, let next) in events {
            if record.phase == .focus {
                award(.focusSession)
                milestone("first-focus", "First focus session")
                let today = Focus.day(Date(), records: data.focus.records, calendar: calendar)
                if today.sessionsCompleted == data.focus.settings.dailyGoalSessions { award(.focusGoal) }
                if data.focus.records.filter({ $0.phase == .focus && $0.completed }).count == 10 {
                    milestone("focus-10", "10 focus sessions")
                }
            } else {
                award(.breakCompleted)
            }
            self.events.send(.phaseCompleted(record, next: next))
        }
        scheduleFocusTimer()
    }

    /// One-shot timer at the exact end time (no polling loop). While a focus
    /// phase is running, App Nap is held off so the end isn't delayed.
    private func scheduleFocusTimer() {
        focusTimer?.invalidate()
        focusTimer = nil
        guard let endsAt = data.focus.timer?.endsAt else {
            if let a = focusActivity { ProcessInfo.processInfo.endActivity(a); focusActivity = nil }
            return
        }
        if focusActivity == nil {
            focusActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep], reason: "Focus timer running")
        }
        let t = Timer(fire: max(endsAt, Date().addingTimeInterval(0.05)), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceFocus() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        focusTimer = t
    }

    var todayFocus: Focus.DaySummary { Focus.day(Date(), records: data.focus.records, calendar: calendar) }

    // MARK: - Movement

    func markMovementDone() {
        mutate {
            $0.movementReminder.markDone(at: Date())
            $0.movementBreaks.append(Date())
            if $0.movementBreaks.count > 2000 { $0.movementBreaks.removeFirst($0.movementBreaks.count - 2000) }
        }
        award(.breakCompleted)
        events.send(.movementDone)
    }

    func movementBreaks(on day: Date) -> Int {
        data.movementBreaks.filter { calendar.isDate($0, inSameDayAs: day) }.count
    }

    // MARK: - Notes & tasks

    @discardableResult
    func addItem(_ text: String, kind: Item.Kind, due: Date? = nil, dueHasTime: Bool = false,
                 remindAt: Date? = nil, pinned: Bool = false) throws -> Item {
        let item = try mutate {
            try $0.items.add(text, kind: kind, due: due, dueHasTime: dueHasTime, remindAt: remindAt, pinned: pinned, now: Date())
        }
        events.send(.itemCreated(item))
        return item
    }

    func updateItem(_ id: UUID, _ change: (inout Item) -> Void) throws {
        try mutate { try $0.items.update(id, now: Date(), change) }
    }

    func setCompleted(_ id: UUID, _ done: Bool) throws {
        let wasDone = data.items.item(id)?.isCompleted ?? false
        try mutate { try $0.items.setCompleted(id, done, now: Date()) }
        if done && !wasDone, let item = data.items.item(id) {
            award(.taskCompleted)
            if data.items.live.filter(\.isCompleted).count == 10 { milestone("tasks-10", "10 tasks completed") }
            events.send(.taskCompleted(item))
        }
    }

    func deleteItem(_ id: UUID) throws { try mutate { try $0.items.softDelete(id, now: Date()) } }
    func restoreItem(_ id: UUID) throws { try mutate { try $0.items.restore(id, now: Date()) } }
    func emptyTrash() { mutate { $0.items.emptyTrash() } }

    // MARK: - Progression

    private func award(_ source: XPSource) {
        let award = mutate { $0.progression.earn(source, on: Date(), calendar: calendar) }
        guard data.progression.gamificationEnabled else { return }
        if let level = award.leveledUpTo { events.send(.leveledUp(level)) }
        let streak = data.progression.currentStreak(now: Date(), calendar: calendar)
        if streak >= 7 { milestone("streak-7", "A 7-day streak") }
    }

    /// Small XP for petting (capped daily), kept separate so the pet module stays decoupled.
    func notePetting() { award(.petting) }

    private func milestone(_ id: String, _ title: String) {
        if let m = mutate({ $0.progression.reach(id, title: title) }), data.progression.gamificationEnabled {
            events.send(.milestone(m))
        }
    }

    func updateProgression(_ change: (inout Progression) -> Void) {
        mutate { change(&$0.progression) }
    }

    func updateBriefing(_ change: (inout BriefingSettings) -> Void) {
        mutate { change(&$0.briefing) }
    }

    // MARK: - Data control

    /// Writes a JSON export plus CSVs into a new folder inside `parent`.
    func export(to parent: URL, pet: PetSnapshot?) throws -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm"
        let folder = parent.appendingPathComponent("DeskPet Export \(f.string(from: Date()))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try DataExport.json(data: data, pet: pet, now: Date()).write(to: folder.appendingPathComponent("deskpet.json"), options: .atomic)
        try Data(DataExport.waterCSV(data).utf8).write(to: folder.appendingPathComponent("water.csv"), options: .atomic)
        try Data(DataExport.focusCSV(data).utf8).write(to: folder.appendingPathComponent("focus.csv"), options: .atomic)
        try Data(DataExport.itemsCSV(data).utf8).write(to: folder.appendingPathComponent("notes-and-tasks.csv"), options: .atomic)
        return folder
    }

    /// Erases all habit data, notes, tasks and progress.
    func deleteAllData() {
        data = DeskPetData()
        data.hydration.reminder.anchor = Date()
        data.movementReminder.anchor = Date()
        store.delete()
        saveNow()
        scheduleFocusTimer()
    }
}
