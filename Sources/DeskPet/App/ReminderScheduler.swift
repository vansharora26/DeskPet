import AppKit
import Combine
import DeskPetCore

/// Plans every time-based prompt — water, movement, task reminders, daily
/// briefing, end-of-day summary — and runs a *single* timer to the earliest
/// one. Due times are recomputed from saved state, so nothing is lost across
/// restarts and nothing can be scheduled twice.
@MainActor
final class ReminderScheduler {
    private let model: AppModel
    private let pet: PetViewModel
    private let notifications: NotificationManager
    private let settings: AppSettings
    private let open: (Destination) -> Void

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastFocusNotificationEnd: Date?
    /// Don't greet a fresh launch with an immediate reminder.
    private let launchGrace: TimeInterval = 90

    init(model: AppModel, pet: PetViewModel, notifications: NotificationManager, settings: AppSettings,
         open: @escaping (Destination) -> Void) {
        self.model = model
        self.pet = pet
        self.notifications = notifications
        self.settings = settings
        self.open = open
    }

    func start() {
        model.$data
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.replan() }
            .store(in: &cancellables)
        model.$now.sink { [weak self] _ in self?.replan() }.store(in: &cancellables)
        settings.$systemNotifications.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.syncFocusNotification(force: true) }
        }.store(in: &cancellables)

        if model.data.briefing.mode == .onOpen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.showBriefingIfNeeded(force: false) }
        }
        replan()
    }

    // MARK: - Planning

    private var calendar: Calendar { model.calendar }

    private var focusMutesReminders: Date? {
        guard model.focusSettings.muteNonessentialDuringFocus,
              let t = model.focusTimerState, t.phase == .focus, let end = t.endsAt else { return nil }
        return end
    }

    func hydrationDue(now: Date) -> Date? {
        let s = model.hydrationSettings
        var notBefore = model.launchDate.addingTimeInterval(launchGrace)
        if let end = focusMutesReminders { notBefore = max(notBefore, end) }
        if s.pauseAfterGoal && model.todayWaterML >= s.dailyTargetML {
            notBefore = max(notBefore, calendar.startOfNextDay(after: now))
        }
        return ReminderPlanner.nextDue(
            config: .init(enabled: s.remindersEnabled, intervalMinutes: s.reminderIntervalMinutes, quietHours: s.quietHours),
            state: model.data.hydration.reminder, now: now, calendar: calendar, notBefore: notBefore)
    }

    func movementDue(now: Date) -> Date? {
        let f = model.focusSettings
        var notBefore = model.launchDate.addingTimeInterval(launchGrace)
        if let end = focusMutesReminders { notBefore = max(notBefore, end) }
        return ReminderPlanner.nextDue(
            config: .init(enabled: f.movementRemindersEnabled, intervalMinutes: f.movementIntervalMinutes,
                          quietHours: model.hydrationSettings.quietHours),
            state: model.data.movementReminder, now: now, calendar: calendar, notBefore: notBefore)
    }

    private func briefingDue(now: Date) -> Date? {
        let b = model.data.briefing
        guard b.mode == .atTime, b.lastBriefingDay != calendar.dayKey(now) else { return nil }
        let today = calendar.date(byAdding: .minute, value: b.briefingMinute, to: calendar.startOfDay(for: now)) ?? now
        // Missed today's time (Mac was off)? Show it once now — but not after the wrap-up time.
        if today <= now {
            return calendar.minuteOfDay(now) < b.endOfDayMinute ? max(now, graceEnd) : nil
        }
        return today
    }

    private var graceEnd: Date { model.launchDate.addingTimeInterval(20) }

    /// Something worth summarising happened today.
    private func hadActivityToday(_ now: Date) -> Bool {
        model.todayWaterML > 0 || model.todayFocus.sessionsCompleted > 0 || model.todayFocus.focusMinutes > 0
            || model.data.items.completedCount(on: now, calendar: calendar) > 0 || model.movementBreaks(on: now) > 0
    }

    private func endOfDayDue(now: Date) -> Date? {
        let b = model.data.briefing
        guard b.endOfDayEnabled, b.lastEndOfDayDay != calendar.dayKey(now), hadActivityToday(now) else { return nil }
        let today = calendar.date(byAdding: .minute, value: b.endOfDayMinute, to: calendar.startOfDay(for: now)) ?? now
        return max(today, now, graceEnd)
    }

    func replan() {
        let now = Date()
        var dates = [hydrationDue(now: now), movementDue(now: now), model.data.items.nextReminderDate(),
                     briefingDue(now: now), endOfDayDue(now: now)].compactMap { $0 }
        dates = dates.map { max($0, now.addingTimeInterval(0.5)) }
        syncFocusNotification(force: false)

        timer?.invalidate()
        timer = nil
        guard let next = dates.min() else { return }
        let t = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fireDue() }
        }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func fireDue() {
        let now = Date().addingTimeInterval(1)
        if let d = hydrationDue(now: now), d <= now { fireHydration() }
        if let d = movementDue(now: now), d <= now { fireMovement() }
        for item in model.data.items.dueReminders(now: now) { fireTask(item) }
        if let d = briefingDue(now: now), d <= now { showBriefingIfNeeded(force: true) }
        if let d = endOfDayDue(now: now), d <= now { fireEndOfDay() }
        replan()
    }

    // MARK: - Hydration

    private static let waterLines = [
        "Sip break? A few gulps keep the gears turning.",
        "Psst — hydration o’clock.",
        "Water time! I’ll cheer you on.",
        "Tiny glass of water? Future you says thanks.",
    ]

    private func fireHydration() {
        model.mutate { $0.hydration.reminder.markFired(at: Date()) }
        let s = model.hydrationSettings
        let progress = "\(AppCommand.formatML(model.todayWaterML)) of \(AppCommand.formatML(s.dailyTargetML)) so far."
        let line = Self.waterLines.randomElement()!
        pet.show(PetCallout(
            kind: .hydration, symbol: "drop.fill", message: "\(line) \(progress)",
            actions: [
                .init(title: "Log \(s.defaultServingML) ml", isPrimary: true) { [weak self] in self?.handleHydration(.log) },
                .init(title: "Snooze \(s.snoozeMinutes)m") { [weak self] in self?.handleHydration(.snooze) },
            ],
            onDismiss: { [weak self] in self?.handleHydration(.dismiss) }))
        if settings.systemNotifications {
            notifications.post(id: "deskpet.hydration", title: "Water break 💧", body: "\(line) \(progress)", category: .hydration)
        }
    }

    func handleHydration(_ action: NotificationManager.Action) {
        switch action {
        case .log, .done:
            _ = try? model.logWater(nil)
        case .snooze:
            model.mutate { $0.hydration.reminder.snooze(minutes: $0.hydration.settings.snoozeMinutes, from: Date()) }
        default:
            model.mutate { $0.hydration.reminder.dismiss(at: Date()) }
        }
        pet.clearCallout(kind: .hydration)
        notifications.remove(id: "deskpet.hydration")
        replan()
    }

    // MARK: - Movement

    private static let movementTips = [
        "Stretch break: roll your shoulders and reach for the sky.",
        "Eye rest: look at something 20 feet away for 20 seconds.",
        "Stand up and walk around for a minute?",
        "Neck check: slow tilts left and right.",
        "Unclench your jaw, drop your shoulders, breathe out.",
    ]

    private func fireMovement() {
        model.mutate { $0.movementReminder.markFired(at: Date()) }
        let tip = Self.movementTips.randomElement()!
        pet.show(PetCallout(
            kind: .movement, symbol: "figure.walk", message: tip,
            actions: [
                .init(title: "Done", isPrimary: true) { [weak self] in self?.handleMovement(.done) },
                .init(title: "Snooze 10m") { [weak self] in self?.handleMovement(.snooze) },
            ],
            onDismiss: { [weak self] in self?.handleMovement(.dismiss) }))
        if settings.systemNotifications {
            notifications.post(id: "deskpet.movement", title: "Time to move", body: tip, category: .movement)
        }
    }

    func handleMovement(_ action: NotificationManager.Action) {
        switch action {
        case .done, .log: model.markMovementDone()
        case .snooze: model.mutate { $0.movementReminder.snooze(minutes: 10, from: Date()) }
        default: model.mutate { $0.movementReminder.dismiss(at: Date()) }
        }
        pet.clearCallout(kind: .movement)
        notifications.remove(id: "deskpet.movement")
        replan()
    }

    // MARK: - Task reminders

    private func fireTask(_ item: Item) {
        try? model.updateItem(item.id) { $0.reminderFired = true }
        pet.show(PetCallout(
            kind: .task(item.id), symbol: "alarm.fill", message: "Reminder: \(item.title)",
            actions: [
                .init(title: "Done", isPrimary: true) { [weak self] in self?.handleTask(item.id, .complete) },
                .init(title: "Snooze 10m") { [weak self] in self?.handleTask(item.id, .snooze) },
            ]))
        if settings.systemNotifications {
            notifications.post(id: "deskpet.task.\(item.id.uuidString)", title: "Reminder", body: item.title,
                               category: .task, userInfo: ["id": item.id.uuidString])
        }
    }

    func handleTask(_ id: UUID, _ action: NotificationManager.Action) {
        switch action {
        case .complete, .done:
            try? model.setCompleted(id, true)
        case .snooze:
            try? model.updateItem(id) { $0.remindAt = Date().addingTimeInterval(600) }
        default:
            break
        }
        pet.clearCallout(kind: .task(id))
        notifications.remove(id: "deskpet.task.\(id.uuidString)")
        replan()
    }

    // MARK: - Briefing & wrap-up

    func showBriefingIfNeeded(force: Bool) {
        let key = calendar.dayKey(Date())
        guard model.data.briefing.mode != .off, force || model.data.briefing.lastBriefingDay != key else { return }
        model.updateBriefing { $0.lastBriefingDay = key }
        let b = Briefing.build(model.data, now: Date(), calendar: calendar)
        let count = b.dueToday.count
        let message = count == 0 ? "Good day! Your briefing is ready — nothing due today."
                                 : "Your briefing is ready: \(count) task\(count == 1 ? "" : "s") for today."
        pet.show(PetCallout(kind: .briefing, symbol: "sun.max.fill", message: message,
                            actions: [.init(title: "Open", isPrimary: true) { [weak self] in
                                self?.pet.clearCallout(kind: .briefing)
                                self?.open(.today)
                            }]))
        if settings.systemNotifications {
            notifications.post(id: "deskpet.briefing", title: "Daily briefing", body: message, category: .info)
        }
    }

    private func fireEndOfDay() {
        model.updateBriefing { $0.lastEndOfDayDay = self.calendar.dayKey(Date()) }
        let b = Briefing.build(model.data, now: Date(), calendar: calendar)
        let message = "Day wrap-up: \(b.completedToday.count) task\(b.completedToday.count == 1 ? "" : "s") done, "
            + "\(b.focusSessions) focus session\(b.focusSessions == 1 ? "" : "s"), \(AppCommand.formatML(b.waterML)) water."
        pet.show(PetCallout(kind: .endOfDay, symbol: "moon.stars.fill", message: message,
                            actions: [.init(title: "See summary", isPrimary: true) { [weak self] in
                                self?.pet.clearCallout(kind: .endOfDay)
                                self?.open(.today)
                            }]))
        if settings.systemNotifications {
            notifications.post(id: "deskpet.eod", title: "Day wrap-up", body: message, category: .info)
        }
    }

    // MARK: - Focus end notification

    /// Pre-schedules a system notification at the exact phase end so it's on
    /// time even if the app is throttled. Only re-posted when the end changes.
    private func syncFocusNotification(force: Bool) {
        let end = model.focusTimerState?.endsAt
        guard force || end != lastFocusNotificationEnd else { return }
        lastFocusNotificationEnd = end
        guard let end, let t = model.focusTimerState, model.focusSettings.notifyWhenPhaseEnds,
              settings.systemNotifications else {
            notifications.remove(id: "deskpet.focus")
            return
        }
        let title = t.phase == .focus ? "Focus session complete 🎉" : "Break’s over"
        let body = t.phase == .focus ? "Nice work. Time for a breather." : "Ready for another round?"
        notifications.post(id: "deskpet.focus", title: title, body: body, category: .focus, at: end)
    }
}
