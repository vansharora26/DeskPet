import AppKit
import Carbon.HIToolbox
import Combine
import DeskPetCore
import SwiftUI

/// Composition root: creates the models and services, wires them together,
/// and handles the app lifecycle.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let loginItem = LoginItemManager()
    private let sound = SoundPlayer()
    private let notifications = NotificationManager()
    private let hotkeys = HotKeyManager()

    private var model: AppModel!
    private var pet: PetViewModel!
    private var chat: ChatModel!
    private var voice: VoiceController!
    private var worlds: WorldsController!
    private var license: LicenseManager!
    private var router: WindowRouter!
    private var behavior: PetBehavior!
    private var scheduler: ReminderScheduler!
    private var petWindow: PetWindowController!
    private var roamer: PetRoamer!
    private var distractionGuard: DistractionGuardController!
    private var statusBar: StatusBarController?
    private var welcomeWindow: AuxWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var menuActions: PetMenu.Actions!

    private let dataDirectory = JSONDocumentStore<DeskPetData>.defaultDirectory()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = settings.appearance.nsAppearance
        MainMenu.install() // routes ⌘X/⌘C/⌘V/⌘A/⌘Z to text fields

        // Models
        model = AppModel(store: JSONDocumentStore(fileURL: dataDirectory.appendingPathComponent("deskpet-data.json")))
        pet = PetViewModel(store: PetStore(directory: dataDirectory), settings: settings, sound: sound)
        chat = ChatModel(model: model, settings: settings, pet: pet,
                         store: JSONDocumentStore(fileURL: dataDirectory.appendingPathComponent("chat.json")))

        voice = VoiceController(chat: chat, settings: settings, pet: pet)
        worlds = WorldsController(model: model, pet: pet, appSettings: settings)

        // Trial & license: gates Focus Worlds, AI chat and voice (everything else is free).
        license = LicenseManager.fromBundle()
        chat.aiLockedReason = { [unowned self] in self.license.lockedReason(.aiChat) }
        voice.lockedReason = { [unowned self] in self.license.lockedReason(.voice) }

        // Windows & behaviour
        router = WindowRouter(model: model, chat: chat, pet: pet, settings: settings)
        router.makeSettingsView = { [unowned self] in AnyView(self.settingsView()) }
        router.makeConversationView = { [unowned self] in
            AnyView(ConversationView(chat: self.chat, pet: self.pet, voice: self.voice, recognizer: self.voice.input,
                                     settings: self.settings, openSettings: { [weak self] t in self?.router.openSettings(t) }))
        }
        // Closing the conversation always turns the microphone off.
        router.onConversationClosed = { [weak self] in self?.voice.cancelListening() }
        router.petFrame = { [weak self] in self?.petWindow.isVisible == true ? self?.petWindow.panel.frame : nil }
        chat.onOpen = { [weak self] d in self?.router.open(d) }
        behavior = PetBehavior(model: model, pet: pet, router: router, notifications: notifications)
        behavior.start(voice: voice)

        menuActions = makeMenuActions()
        buildPetWindow()
        worlds.setDesktopPetHidden = { [weak self] hidden in
            guard let self else { return }
            if hidden { self.petWindow.hide() } else if self.settings.petVisible { self.petWindow.show() }
        }
        router.openFocusWorld = { [weak self] in self?.openWorld() }
        license.onLocked = { [weak self] feature in
            guard let self else { return }
            self.pet.say(self.license.lockedReason(feature) ?? "")
            self.router.openSettings(.license)
        }
        license.start()
        let battery = BatteryMonitor.shared
        battery.isEnabled = { [unowned self] in self.settings.batteryMoodsEnabled }
        battery.onChange = { [weak self] old, new in
            guard let self, self.settings.batteryMoodsEnabled else { return }
            // Stay quiet during focus, except when it's about to run out.
            guard self.pet.mode != .focused || new == .critical else { return }
            if let line = BatteryMood.line(from: old, to: new, level: battery.reading?.level ?? 0, name: self.pet.name) {
                self.pet.say(line)
            }
        }
        battery.start()
        MacTools.shared.showPDFTools = { [weak self] tool, files in self?.router.showPDFTools(tool, files: files) }
        router.pdfModel.onDone = { [weak self] message in self?.pet.say("Done! \(message).") }
        MacTools.shared.configure(
            pet: pet, settings: settings, dataDirectory: dataDirectory,
            hidePet: { [unowned self] in
                guard self.petWindow.isVisible else { return false }
                self.petWindow.hide()
                return true
            },
            showPet: { [unowned self] in if self.settings.petVisible { self.petWindow.show() } },
            saveNote: { [unowned self] text in (try? self.model.addItem(text, kind: .note)) != nil })
        roamer = PetRoamer(window: petWindow, settings: settings, pet: pet,
                           isAllowed: { [unowned self] in self.license.lockedReason(.roaming) == nil })
        roamer.start()
        distractionGuard = DistractionGuardController(
            model: model, pet: pet, settings: settings, notifications: notifications,
            isAllowed: { [unowned self] in self.license.lockedReason(.distractionGuard) == nil },
            isPetVisible: { [unowned self] in self.petWindow.isVisible })
        distractionGuard.start()
        CalendarService.shared.start(
            pet: pet, model: model, settings: settings, notifications: notifications,
            isAllowed: { [unowned self] in self.license.lockedReason(.calendar) == nil },
            isPetVisible: { [unowned self] in self.petWindow.isVisible })
        nudgeIfTrialEndingSoon()
        offerToResumeWorldSession()
        statusBar = StatusBarController(pet: pet, model: model, actions: menuActions)

        // Notifications (optional) & reminders
        notifications.setUp()
        scheduler = ReminderScheduler(model: model, pet: pet, notifications: notifications, settings: settings,
                                      open: { [weak self] d in self?.router.open(d) })
        notifications.onAction = { [weak self] category, action, info in
            self?.handleNotification(category: category, action: action, info: info)
        }
        scheduler.start()

        // Global shortcuts (Carbon hot keys — no keyboard monitoring)
        hotkeys.handler = { [weak self] action in self?.handleHotKey(action) }
        hotkeys.releaseHandler = { [weak self] action in
            if action == .pushToTalk { self?.voice.pressEnded() }
        }
        hotkeys.start()

        // Visibility follows the setting.
        settings.$petVisible
            .removeDuplicates()
            .sink { [weak self] visible in
                guard let self else { return }
                if visible { self.petWindow.show() } else { self.petWindow.hide() }
            }
            .store(in: &cancellables)

        if !settings.hasCompletedWelcome {
            settings.petVisible = true
            showWelcome(isUpgrade: false)
        } else if !settings.hasSeenV2Tour {
            showWelcome(isUpgrade: true)
        }
        if model.recoveredFromCorruptFile {
            pet.say("Some saved data couldn’t be read, so I kept a backup and started fresh.")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        worlds?.audio.stop(fade: 0)
        voice?.cancelListening()
        voice?.stopSpeaking()
        model?.shutdown()
        pet?.shutdown()
    }

    /// Launching DeskPet again while it's running brings the pet back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.petVisible = true
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Pet window

    private func buildPetWindow() {
        let state = PetWindowState(layout: PetLayout(pixel: settings.petSize.pixel))
        let barActions = PetBarActions(
            logWater: { [weak self] in self?.run(.logWater(ml: nil)) },
            toggleFocus: { [weak self] in
                guard let self else { return }
                if let t = self.model.focusTimerState {
                    self.run(t.isRunning ? .pauseFocus : .resumeFocus)
                } else {
                    self.run(.startFocus(minutes: nil, label: nil))
                }
            },
            openFocus: { [weak self] in self?.router.open(.focus) },
            openChat: { [weak self] in self?.router.showConversation() },
            openCapture: { [weak self] in self?.router.open(.capture) },
            screenshot: { MacTools.shared.screenshot() },
            copyText: { MacTools.shared.copyTextFromScreen() },
            pdfTools: { [weak self] in self?.router.showPDFTools() },
            dropFiles: { [weak self] urls in
                guard let self else { return }
                self.pet.say("Ooh, files! Let’s see…")
                self.router.showPDFTools(PDFTool.suggested(for: urls), files: urls)
            },
            enterWorld: { [weak self] in self?.openWorld() },
            moreMenu: { [weak self] in
                guard let self else { return nil }
                return PetMenu.make(pet: self.pet, model: self.model, actions: self.menuActions)
            })
        let view = PetView(
            pet: pet, windowState: state, settings: settings, model: model,
            driver: PetAnimationDriver(pet: pet, windowState: state, settings: settings),
            onDragChanged: { [weak self] in self?.petWindow.dragChanged($0) },
            onDragEnded: { [weak self] in self?.petWindow.dragEnded() },
            contextMenu: { [weak self] in
                guard let self else { return nil }
                return PetMenu.make(pet: self.pet, model: self.model, actions: self.menuActions)
            },
            actions: barActions,
            onKey: { [weak self] event in self?.handlePetKey(event) ?? false })
        petWindow = PetWindowController(settings: settings, state: state, content: view)
    }

    /// Runs a command from the pet/menus. Errors appear as the pet's speech.
    private func run(_ command: AppCommand) {
        let result = CommandExecutor(model: model).run(command)
        if result.style == .error { pet.say(result.message) }
        if case .open(let d) = command { router.open(d) }
    }

    private func makeMenuActions() -> PetMenu.Actions {
        PetMenu.Actions(
            togglePet: { [weak self] in self?.settings.petVisible.toggle() },
            isPetVisible: { [weak self] in self?.petWindow.isVisible ?? false },
            open: { [weak self] d in self?.router.open(d) },
            talk: { [weak self] in self?.router.showConversation() },
            enterWorld: { [weak self] in self?.openWorld() },
            openSettings: { [weak self] t in self?.router.openSettings(t) },
            openWelcome: { [weak self] in self?.showWelcome(isUpgrade: false) },
            resetPosition: { [weak self] in
                self?.settings.petVisible = true
                self?.petWindow.resetPosition()
            },
            keyboardMode: { [weak self] in self?.enterKeyboardMode() },
            run: { [weak self] c in self?.run(c) },
            confirmStopFocus: { [weak self] in self?.confirmStopFocus() })
    }

    private func confirmStopFocus() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Stop the timer?"
        alert.informativeText = "The current session won’t be recorded."
        alert.addButton(withTitle: "Stop")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn { run(.stopFocus) }
    }

    /// After a restart, a world session that's still running is one click away.
    private func offerToResumeWorldSession() {
        guard let t = model.focusTimerState, let w = t.world.flatMap(FocusWorld.init(rawValue:)) else { return }
        pet.show(PetCallout(kind: .focusPhase, symbol: WorldTheme.of(w).symbol,
                            message: "Your \(w.title) session is still \(t.isRunning ? "running" : "paused").",
                            actions: [.init(title: "Return to it", isPrimary: true) { [weak self] in
                                self?.pet.clearCallout(kind: .focusPhase)
                                self?.openWorld(w)
                            }]))
    }

    /// Every way into Focus Worlds goes through here (trial / license gate).
    private func openWorld(_ world: FocusWorld? = nil) {
        guard license.allows(.focusWorlds) else { return }
        worlds.open(world)
    }

    /// A gentle reminder in the last 3 days of the trial, at most once a day.
    private func nudgeIfTrialEndingSoon() {
        guard case .trial(let days) = license.access, days <= 3 else { return }
        let today = model.calendar.dayKey(Date())
        guard UserDefaults.standard.string(forKey: "trialNudgeDay") != today else { return }
        UserDefaults.standard.set(today, forKey: "trialNudgeDay")
        let when = days == 1 ? "ends today" : "ends in \(days) days"
        pet.show(PetCallout(kind: .info, symbol: "sparkles",
                            message: "Your DeskPet trial \(when). Focus Worlds, AI chat and voice need a license after that.",
                            actions: [.init(title: "Buy DeskPet", isPrimary: true) { [weak self] in
                                          self?.pet.clearCallout(kind: .info)
                                          self?.license.openBuyPage()
                                      },
                                      .init(title: "I have a key") { [weak self] in
                                          self?.pet.clearCallout(kind: .info)
                                          self?.router.openSettings(.license)
                                      }]))
    }

    // MARK: - Keyboard

    private func handleHotKey(_ action: HotKeyAction) {
        switch action {
        case .launcher: router.showLauncher()
        case .capture: router.showCapture()
        case .chat: router.showConversation()
        case .focusWorld: worlds.isOpen ? worlds.close() : openWorld()
        case .pushToTalk:
            router.showConversation()
            voice.pressBegan()
        case .logWater: run(.logWater(ml: nil))
        case .togglePet: settings.petVisible.toggle()
        case .keyboardMode: enterKeyboardMode()
        case .screenshot: MacTools.shared.screenshot()
        case .copyText: MacTools.shared.copyTextFromScreen()
        case .clipboard: router.showClipboard()
        }
    }

    private func enterKeyboardMode() {
        settings.petVisible = true
        petWindow.setKeyboardMode(true)
        pet.say("Keyboard mode: arrows move me, Space pets, W water, F focus, Esc exits.")
    }

    /// Keys while the pet has keyboard focus (opt-in keyboard mode only).
    private func handlePetKey(_ event: NSEvent) -> Bool {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 60 : 12
        switch Int(event.keyCode) {
        case kVK_LeftArrow: petWindow.nudge(dx: -step, dy: 0)
        case kVK_RightArrow: petWindow.nudge(dx: step, dy: 0)
        case kVK_UpArrow: petWindow.nudge(dx: 0, dy: step)
        case kVK_DownArrow: petWindow.nudge(dx: 0, dy: -step)
        case kVK_Space, kVK_Return: pet.pet()
        case kVK_ANSI_W: run(.logWater(ml: nil))
        case kVK_ANSI_F:
            if let t = model.focusTimerState { run(t.isRunning ? .pauseFocus : .resumeFocus) }
            else { run(.startFocus(minutes: nil, label: nil)) }
        case kVK_ANSI_C: petWindow.setKeyboardMode(false); router.open(.chat)
        case kVK_ANSI_N: petWindow.setKeyboardMode(false); router.showCapture()
        case kVK_Escape:
            petWindow.setKeyboardMode(false)
            pet.say("Keyboard mode off.")
        default: return false
        }
        return true
    }

    // MARK: - Notifications

    private func handleNotification(category: String, action: String, info: [String: String]) {
        let act = NotificationManager.Action(rawValue: action)
        switch NotificationManager.Category(rawValue: category) {
        case .hydration:
            if let act { scheduler.handleHydration(act) } else { router.open(.water) }
        case .movement:
            if let act { scheduler.handleMovement(act) }
        case .task:
            if let idString = info["id"], let id = UUID(uuidString: idString) {
                if let act { scheduler.handleTask(id, act) } else { router.open(.tasks) }
            }
        case .focus:
            router.open(.focus)
        default:
            router.open(.today)
        }
    }

    // MARK: - Settings & welcome

    private func settingsView() -> some View {
        SettingsView(
            state: router.settingsState, pet: pet, settings: settings, model: model, loginItem: loginItem, license: license,
            notifications: notifications, hotkeys: hotkeys, chat: chat, voice: voice,
            actions: SettingsActions(
                export: { [weak self] in self?.exportData() },
                deleteAll: { [weak self] in self?.deleteAllData() },
                revealData: { [weak self] in
                    guard let self else { return }
                    try? FileManager.default.createDirectory(at: self.dataDirectory, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([self.dataDirectory])
                }))
    }

    private func showWelcome(isUpgrade: Bool) {
        if welcomeWindow == nil {
            let controller = AuxWindowController(title: isUpgrade ? "What’s new in DeskPet" : "Welcome to DeskPet") { [unowned self] in
                AnyView(WelcomeView(pet: self.pet, settings: self.settings, loginItem: self.loginItem, model: self.model,
                                    notifications: self.notifications, isUpgrade: isUpgrade) {
                    self.welcomeWindow?.close()
                })
            }
            // Closing the window any way counts as finishing the welcome.
            controller.onClose = { [weak self] in
                self?.settings.hasCompletedWelcome = true
                self?.settings.hasSeenV2Tour = true
                self?.welcomeWindow = nil
            }
            welcomeWindow = controller
        }
        welcomeWindow?.show()
    }

    // MARK: - Data control

    private func exportData() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose where to save your DeskPet export (JSON + CSV)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let folder = try model.export(to: url, pet: pet.snapshot)
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Export failed"
            alert.runModal()
        }
    }

    private func deleteAllData() {
        chat.clear()
        MacTools.shared.clipboard.clear()
        MacTools.shared.keepAwake.stop(reason: .user)
        KeychainStore.deleteAPIKey()
        notifications.removeAll()
        model.deleteAllData()
        pet.eraseAndStopSaving()
        settings.resetAll()
        UserDefaults.standard.removeObject(forKey: "globalShortcuts")

        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "All DeskPet data was deleted"
        alert.informativeText = "DeskPet will quit now. Open it again to start fresh."
        alert.addButton(withTitle: "Quit DeskPet")
        alert.runModal()
        NSApp.terminate(nil)
    }
}
