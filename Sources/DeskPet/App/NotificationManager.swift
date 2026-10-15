import AppKit
import UserNotifications

/// Optional macOS notifications. In-pet reminders work without these; this
/// only mirrors them into Notification Centre when the user opts in.
///
/// Each reminder kind uses one fixed identifier, so posting again *replaces*
/// the previous notification rather than stacking duplicates.
@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var status: UNAuthorizationStatus = .notDetermined

    enum Category: String {
        case hydration = "HYDRATION", movement = "MOVEMENT", task = "TASK", focus = "FOCUS", info = "INFO"
    }

    enum Action: String {
        case log = "LOG", done = "DONE", snooze = "SNOOZE", dismiss = "DISMISS", complete = "COMPLETE"
    }

    /// (category, action identifier, userInfo) — default tap uses UNNotificationDefaultActionIdentifier.
    var onAction: (String, String, [String: String]) -> Void = { _, _, _ in }

    /// UserNotifications needs a real app bundle; `swift run` builds can't use it.
    static var isSupported: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    private var center: UNUserNotificationCenter? { Self.isSupported ? .current() : nil }

    var isAuthorized: Bool { status == .authorized || status == .provisional }

    func setUp() {
        guard let center else { return }
        center.delegate = self
        let snooze = UNNotificationAction(identifier: Action.snooze.rawValue, title: "Snooze")
        let dismiss = UNNotificationAction(identifier: Action.dismiss.rawValue, title: "Dismiss")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.hydration.rawValue,
                                   actions: [UNNotificationAction(identifier: Action.log.rawValue, title: "Log water"), snooze, dismiss],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.movement.rawValue,
                                   actions: [UNNotificationAction(identifier: Action.done.rawValue, title: "Done"), snooze, dismiss],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.task.rawValue,
                                   actions: [UNNotificationAction(identifier: Action.complete.rawValue, title: "Mark done"), snooze],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.focus.rawValue, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.info.rawValue, actions: [], intentIdentifiers: []),
        ])
        refresh()
    }

    func refresh() {
        center?.getNotificationSettings { settings in
            let s = settings.authorizationStatus
            Task { @MainActor in self.status = s }
        }
    }

    /// Asks macOS for permission. Returns whether notifications can be shown.
    func requestAuthorization() async -> Bool {
        guard let center else { return false }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        refresh()
        return granted
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Posts (or schedules) a notification, replacing any previous one with the same id.
    func post(id: String, title: String, body: String, category: Category,
              userInfo: [String: String] = [:], at date: Date? = nil) {
        guard let center, isAuthorized else { return }
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category.rawValue
        content.userInfo = userInfo
        content.sound = .default
        var trigger: UNNotificationTrigger?
        if let date {
            let interval = date.timeIntervalSinceNow
            guard interval > -1 else { return }
            if interval >= 1 { trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false) }
        }
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func remove(id: String) {
        center?.removePendingNotificationRequests(withIdentifiers: [id])
        center?.removeDeliveredNotifications(withIdentifiers: [id])
    }

    func removeAll() {
        center?.removeAllPendingNotificationRequests()
        center?.removeAllDeliveredNotifications()
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let category = response.notification.request.content.categoryIdentifier
        let action = response.actionIdentifier
        var info: [String: String] = [:]
        for (k, v) in response.notification.request.content.userInfo {
            if let k = k as? String, let v = v as? String { info[k] = v }
        }
        Task { @MainActor in self.onAction(category, action, info) }
        completionHandler()
    }
}
