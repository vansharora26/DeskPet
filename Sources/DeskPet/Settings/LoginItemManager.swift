import AppKit
import ServiceManagement

/// Wraps SMAppService (macOS 13+) for "Open at Login".
@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var lastError: String?

    /// Login items only work for a real .app bundle (not `swift run`).
    var isSupported: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    init() { refresh() }

    func refresh() {
        guard isSupported else {
            isEnabled = false
            needsApproval = false
            return
        }
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        guard isSupported else {
            lastError = "Open at Login is only available when DeskPet runs as an app bundle."
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = "Couldn't update login item: \(error.localizedDescription)"
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
