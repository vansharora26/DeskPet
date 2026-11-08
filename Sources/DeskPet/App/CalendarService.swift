import AppKit
import Combine
import DeskPetCore
import EventKit

/// Reads upcoming events from macOS Calendar (read-only) and has the pet give a
/// heads-up shortly before each meeting. Off until the user turns it on and
/// grants Calendar access; nothing leaves the Mac.
@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    private let store = EKEventStore()
    private var refreshTimer: Timer?
    private var headsUpTimer: Timer?
    private var changeObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    /// Occurrence IDs already announced (kept for a day so restarts don't repeat them).
    private var announced: [String: Date] = [:]

    private weak var pet: PetViewModel?
    private weak var model: AppModel?
    private weak var settings: AppSettings?
    private weak var notifications: NotificationManager?
    private var isAllowed: () -> Bool = { false }
    private var isPetVisible: () -> Bool = { false }

    var hasAccess: Bool { status == .fullAccess }

    /// Active = turned on, permitted by the user, and licensed.
    var isActive: Bool { (settings?.calendarEnabled ?? false) && hasAccess && isAllowed() }

    func start(pet: PetViewModel, model: AppModel, settings: AppSettings, notifications: NotificationManager,
               isAllowed: @escaping () -> Bool, isPetVisible: @escaping () -> Bool) {
        self.pet = pet
        self.model = model
        self.settings = settings
        self.notifications = notifications
        self.isAllowed = isAllowed
        self.isPetVisible = isPetVisible

        changeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        settings.$calendarEnabled.removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.apply() } }
            .store(in: &cancellables)
    }

    /// Asks for Calendar access (macOS shows its prompt once), then starts.
    func requestAccess() async {
        _ = try? await store.requestFullAccessToEvents()
        status = EKEventStore.authorizationStatus(for: .event)
        apply()
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }

    private func apply() {
        status = EKEventStore.authorizationStatus(for: .event)
        guard isActive else {
            refreshTimer?.invalidate(); refreshTimer = nil
            headsUpTimer?.invalidate(); headsUpTimer = nil
            if !events.isEmpty { events = [] }
            pet?.clearCallout(kind: .meeting)
            return
        }
        reload()
        if refreshTimer == nil {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
        }
        if headsUpTimer == nil {
            let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkHeadsUp() }
            }
            t.tolerance = 5
            RunLoop.main.add(t, forMode: .common)
            headsUpTimer = t
        }
    }

    /// Events from now until the end of tomorrow, from every calendar.
    private func reload() {
        guard isActive else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 2, to: start) ?? Date()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .filter { $0.status != .canceled && !Self.declined($0) }
            .map { e in
                CalendarEvent(id: "\(e.calendarItemIdentifier)@\(e.startDate.timeIntervalSinceReferenceDate)",
                              title: (e.title?.isEmpty == false ? e.title : nil) ?? "Untitled event",
                              start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                              joinURL: MeetingHeadsUp.joinURL(in: [e.url?.absoluteString, e.location, e.notes]))
            }
        checkHeadsUp()
    }

    private static func declined(_ e: EKEvent) -> Bool {
        e.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }

    // MARK: - Heads-up

    private func checkHeadsUp() {
        guard isActive, let settings, let pet else { return }
        let now = Date()
        announced = announced.filter { now.timeIntervalSince($0.value) < 86_400 }
        let due = MeetingHeadsUp.due(events, now: now, leadMinutes: settings.meetingLeadMinutes, announced: Set(announced.keys))
        guard let event = due.first else { return }
        for e in due { announced[e.id] = now } // several at once: announce the first, don't queue the rest

        let mins = MeetingHeadsUp.minutesUntil(event, now: now)
        let when = mins <= 0 ? "is starting now" : "starts in \(mins) min"
        let focusing = model?.focusTimerState.map { $0.isRunning && $0.phase == .focus } ?? false
        let message = "“\(event.title)” \(when)." + (focusing ? " Good spot to wrap up your focus session." : "")

        var actions: [PetCallout.Action] = []
        if let url = event.joinURL {
            actions.append(.init(title: "Join", isPrimary: true) { [weak self] in
                self?.pet?.clearCallout(kind: .meeting)
                NSWorkspace.shared.open(url)
            })
        }
        if focusing {
            actions.append(.init(title: "Pause focus", isPrimary: actions.isEmpty) { [weak self] in
                self?.pet?.clearCallout(kind: .meeting)
                try? self?.model?.pauseFocus()
            })
        }
        actions.append(.init(title: "Thanks!") { [weak self] in self?.pet?.clearCallout(kind: .meeting) })

        if isPetVisible() {
            pet.show(PetCallout(kind: .meeting, symbol: "calendar", message: message, actions: actions))
            pet.chime(.play)
        }
        if settings.systemNotifications || !isPetVisible() {
            notifications?.post(id: "deskpet.meeting", title: event.title, body: "Your meeting \(when).", category: .info)
        }
    }
}
