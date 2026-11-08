import AppKit
import Combine
import DeskPetCore
import os

/// During a focus session, notices when a distracting app (or, with permission,
/// a distracting site in a supported browser) is in front, and has the pet give
/// a gentle nudge. Off outside focus sessions, and off entirely unless enabled.
///
/// It looks only at which app is frontmost and — for listed sites — asks the
/// browser for the current tab's address. Nothing is stored or sent anywhere.
@MainActor
final class DistractionGuardController {
    private let model: AppModel
    private let pet: PetViewModel
    private let settings: AppSettings
    private let notifications: NotificationManager
    private let isAllowed: () -> Bool
    private let isPetVisible: () -> Bool

    private var tracker = DistractionTracker()
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    /// Browsers that refused Apple Events (Automation permission denied).
    private var deniedBrowsers: Set<String> = []
    private var explainedPermission = false
    private let log = Logger(subsystem: "app.deskpet.DeskPet", category: "distraction")

    private static let checkInterval: TimeInterval = 3
    private static let notificationID = "deskpet.distraction"

    init(model: AppModel, pet: PetViewModel, settings: AppSettings, notifications: NotificationManager,
         isAllowed: @escaping () -> Bool, isPetVisible: @escaping () -> Bool) {
        self.model = model
        self.pet = pet
        self.settings = settings
        self.notifications = notifications
        self.isAllowed = isAllowed
        self.isPetVisible = isPetVisible
    }

    func start() {
        Publishers.CombineLatest(model.$data.map(\.focus.timer).removeDuplicates(),
                                 settings.objectWillChange.map { _ in () }.prepend(()))
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.update() }
            .store(in: &cancellables)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    private var focusTimer: FocusTimer? {
        guard let t = model.focusTimerState, t.isRunning, t.phase == .focus else { return nil }
        return t
    }

    private var isActive: Bool {
        settings.distractionGuardEnabled && focusTimer != nil && isAllowed()
    }

    private func update() {
        // `objectWillChange` fires before the new value lands; look again on the next turn.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isActive {
                guard self.timer == nil else { return }
                self.tracker.reset()
                let t = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.check() }
                }
                t.tolerance = 0.5
                RunLoop.main.add(t, forMode: .common)
                self.timer = t
                self.check()
            } else if self.timer != nil {
                self.timer?.invalidate()
                self.timer = nil
                self.tracker.reset()
                self.pet.clearCallout(kind: .distraction)
                self.notifications.remove(id: Self.notificationID)
            }
        }
    }

    // MARK: - Checking

    private func check() {
        guard isActive else { return }
        let front = NSWorkspace.shared.frontmostApplication
        let bundleID = front?.bundleIdentifier
        let rules = settings.distractionRules
        var url: String?
        if let bundleID, !rules.sites.isEmpty, !rules.apps.contains(bundleID) {
            url = currentTabURL(of: bundleID)
        }
        let match = DistractionGuard.match(bundleID: bundleID, url: url, rules: rules)

        switch tracker.observe(match, now: Date()) {
        case .nudge(let m):
            nudge(m, appName: front?.localizedName ?? "That app", app: front)
        case .cameBack:
            pet.clearCallout(kind: .distraction)
            notifications.remove(id: Self.notificationID)
            pet.say(Speech.backToFocus.randomElement())
        case nil:
            break
        }
    }

    /// Asks a supported browser for its current tab's address. Only called for the
    /// frontmost app, so it never launches anything.
    private func currentTabURL(of bundleID: String) -> String? {
        guard let tab = DistractionGuard.browsers[bundleID], !deniedBrowsers.contains(bundleID) else { return nil }
        let source = "tell application id \"\(bundleID)\" to get URL of \(tab) of front window"
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 { // errAEEventNotPermitted: the user said no in System Settings › Privacy › Automation
                deniedBrowsers.insert(bundleID)
                explainPermission(browser: NSWorkspace.shared.frontmostApplication?.localizedName ?? "your browser")
            } else if code != -1728 && code != -1719 { // no window / no tab: nothing to check
                log.debug("Tab address unavailable (\(code))")
            }
            return nil
        }
        return result?.stringValue
    }

    private func explainPermission(browser: String) {
        guard !explainedPermission else { return }
        explainedPermission = true
        pet.show(PetCallout(kind: .distraction, symbol: "lock.shield",
                            message: "I can’t see which site \(browser) is on. Allow DeskPet in System Settings › Privacy › Automation to guard sites too.",
                            actions: [.init(title: "Open Settings", isPrimary: true) { [weak self] in
                                self?.pet.clearCallout(kind: .distraction)
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                            }]))
    }

    // MARK: - Nudging

    private func nudge(_ match: DistractionMatch, appName: String, app: NSRunningApplication?) {
        let minutes = max(1, Int(((focusTimer?.remaining(at: Date()) ?? 0) / 60).rounded(.up)))
        let left = "\(minutes) min of focus left"
        let message: String
        var actions: [PetCallout.Action] = []
        switch match {
        case .app:
            message = "Psst… \(appName) during focus? \(left) — you’ve got this."
            actions.append(.init(title: "Hide \(appName)", isPrimary: true) { [weak self] in
                self?.pet.clearCallout(kind: .distraction)
                app?.hide()
            })
        case .site(let domain):
            message = "\(domain) can wait. \(left)!"
            actions.append(.init(title: "Back to work", isPrimary: true) { [weak self] in
                self?.pet.clearCallout(kind: .distraction)
            })
        }
        actions.append(.init(title: "5 more min") { [weak self] in
            self?.tracker.snooze(minutes: 5, now: Date())
            self?.pet.clearCallout(kind: .distraction)
            self?.pet.say("Okay, 5 minutes. I’m counting!")
        })

        if isPetVisible() {
            pet.react(.refused) // a little head shake
            pet.show(PetCallout(kind: .distraction, symbol: "eyes", message: message, actions: actions))
        } else {
            // In a Focus World the desktop pet is hidden; fall back to a notification if allowed.
            notifications.post(id: Self.notificationID, title: "Back to focus?", body: message, category: .info)
        }
    }
}
