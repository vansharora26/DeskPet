import AppKit
import Combine
import DeskPetCore
import SwiftUI

/// Composition root: creates the model, windows and menus, and wires them up.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let loginItem = LoginItemManager()
    private let sound = SoundPlayer()
    private var pet: PetViewModel!
    private var petWindow: PetWindowController!
    private var statusBar: StatusBarController?
    private var settingsWindow: AuxWindowController?
    private var welcomeWindow: AuxWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        pet = PetViewModel(store: PetStore(), settings: settings, sound: sound)

        let actions = PetMenu.Actions(
            togglePet: { [weak self] in self?.settings.petVisible.toggle() },
            isPetVisible: { [weak self] in self?.petWindow.isVisible ?? false },
            openSettings: { [weak self] in self?.showSettings() },
            openWelcome: { [weak self] in self?.showWelcome() },
            resetPosition: { [weak self] in
                self?.settings.petVisible = true
                self?.petWindow.resetPosition()
            }
        )

        let state = PetWindowState(layout: PetLayout(pixel: settings.petSize.pixel))
        let view = PetView(
            pet: pet,
            windowState: state,
            settings: settings,
            driver: PetAnimationDriver(pet: pet, windowState: state, settings: settings),
            onDragChanged: { [weak self] in self?.petWindow.dragChanged($0) },
            onDragEnded: { [weak self] in self?.petWindow.dragEnded() },
            contextMenu: { [weak self] in
                guard let self else { return nil }
                return PetMenu.contextMenu(pet: self.pet, actions: actions)
            },
            onOpenSettings: { [weak self] in self?.showSettings() }
        )
        petWindow = PetWindowController(settings: settings, state: state, content: view)
        statusBar = StatusBarController(pet: pet, actions: actions)

        // Single source of truth for visibility: the setting.
        settings.$petVisible
            .removeDuplicates()
            .sink { [weak self] visible in
                guard let self else { return }
                if visible { self.petWindow.show() } else { self.petWindow.hide() }
            }
            .store(in: &cancellables)

        if !settings.hasCompletedWelcome {
            settings.petVisible = true
            showWelcome()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pet?.shutdown() // final catch-up + save
    }

    /// Launching DeskPet again (Finder/Spotlight) while it's running brings the pet back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.petVisible = true
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // the pet lives on with no regular windows open
    }

    // MARK: - Windows

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = AuxWindowController(title: "DeskPet Settings") { [unowned self] in
                AnyView(SettingsView(pet: self.pet, settings: self.settings, loginItem: self.loginItem))
            }
        }
        settingsWindow?.show()
    }

    private func showWelcome() {
        if welcomeWindow == nil {
            let controller = AuxWindowController(title: "Welcome to DeskPet") { [unowned self] in
                AnyView(WelcomeView(pet: self.pet, settings: self.settings, loginItem: self.loginItem) {
                    self.welcomeWindow?.close()
                })
            }
            // Closing the window any way counts as finishing the welcome.
            controller.onClose = { [weak self] in self?.settings.hasCompletedWelcome = true }
            welcomeWindow = controller
        }
        welcomeWindow?.show()
    }
}
