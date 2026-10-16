import AppKit
import Combine
import DeskPetCore
import SwiftUI

/// Owns the Focus Worlds window and navigation. All timing goes through the
/// single shared timer in AppModel — this controller never keeps its own clock.
@MainActor
final class WorldsController: NSObject, ObservableObject, NSWindowDelegate {
    enum Screen: Equatable {
        case selection
        case world(FocusWorld)
        case summary(UUID)
    }

    @Published private(set) var screen: Screen = .selection
    @Published private(set) var isOpen = false
    /// False while the window is fully covered or minimised (animations pause).
    @Published private(set) var windowVisible = true
    /// The world to go back to after a Recharge break.
    @Published private(set) var returnWorld: FocusWorld?
    /// Short celebration for the in-world pet (milestones, finished sessions).
    @Published var celebrateUntil = Date.distantPast
    /// One-line confirmation shown briefly (e.g. "Thought saved").
    @Published var toast: String?

    let audio = AmbientAudioEngine()
    let model: AppModel
    let pet: PetViewModel
    let appSettings: AppSettings
    /// Temporarily hides/restores the floating desktop pet.
    var setDesktopPetHidden: (Bool) -> Void = { _ in }

    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    init(model: AppModel, pet: PetViewModel, appSettings: AppSettings) {
        self.model = model
        self.pet = pet
        self.appSettings = appSettings
        super.init()
        model.events
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                if case .phaseCompleted(let record, _) = event { self?.sessionFinished(record) }
            }
            .store(in: &cancellables)
    }

    // MARK: Derived state

    var settings: WorldsSettings { model.data.worlds.settings }
    var timer: FocusTimer? { model.focusTimerState }
    var timerWorld: FocusWorld? { timer?.world.flatMap(FocusWorld.init(rawValue:)) }

    var currentWorld: FocusWorld? {
        if case .world(let w) = screen { return w }
        return nil
    }

    /// Motion after accounting for the app-wide animation switch and Reduce Motion.
    var effectiveMotion: MotionLevel {
        if !appSettings.effectiveAnimations { return .still }
        return settings.motion
    }

    func sessionState(for world: FocusWorld) -> WorldSessionState {
        guard let t = timer, world.timerPhase != nil else { return .idle }
        let matches: Bool
        if let w = t.world {
            // A session belongs to the world it was started in (Study breaks stay in Study).
            matches = w == world.rawValue || (world == .recharge && t.phase.isBreak && w == FocusWorld.recharge.rawValue)
        } else {
            // Classic DeskPet timer: focus shows in focus worlds, a break shows in Recharge.
            matches = world == .recharge ? t.phase.isBreak : t.phase == .focus
        }
        guard matches else { return .idle }
        return t.isRunning ? .running : .paused
    }

    /// Starts a break that belongs to a world (e.g. a Study break between sprints).
    @discardableResult
    func startBreak(in world: FocusWorld, minutes: Int) -> String? {
        do {
            try model.startFocus(.shortBreak, minutes: minutes, world: world)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: Window

    /// Opens Focus Worlds. Resumes an in-progress world session, shows a pending
    /// summary, or starts at the mode selection (or the given world).
    func open(_ world: FocusWorld? = nil) {
        makeWindowIfNeeded()
        if let world {
            enter(world)
        } else if let id = model.data.worlds.pendingSummary, let r = model.record(id), Date().timeIntervalSince(r.end) < 3 * 3600 {
            screen = .summary(id)
        } else if let w = timerWorld {
            enter(w)
        } else if !settings.openToLobby {
            enter(settings.defaultWorld)
        } else {
            showSelection()
        }
        guard let window else { return }
        if !isOpen {
            isOpen = true
            if settings.hideDesktopPet { setDesktopPetHidden(true) }
            let animate = effectiveMotion != .still
            window.alphaValue = animate ? 0 : 1
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            if animate {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.45
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().alphaValue = 1
                }
            }
        } else {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
        updateAudio()
    }

    /// Leaves Focus Worlds. The timer keeps running; nothing is lost.
    func close() {
        guard let window, isOpen else { return }
        audio.stop()
        isOpen = false
        let finish = { [weak self] in
            window.orderOut(nil)
            window.alphaValue = 1
            self?.setDesktopPetHidden(false)
        }
        if effectiveMotion != .still && !window.styleMask.contains(.fullScreen) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                window.animator().alphaValue = 0
            }, completionHandler: { MainActor.assumeIsolated { finish() } })
        } else {
            finish()
        }
    }

    func toggleFullScreen() { window?.toggleFullScreen(nil) }

    /// Diagnostics only (`--worlds-probe`): behave as if open without showing the real window.
    func markOpenForProbe() { isOpen = true }
    var isFullScreen: Bool { window?.styleMask.contains(.fullScreen) ?? false }

    private func makeWindowIfNeeded() {
        guard window == nil else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let w = NSWindow(contentRect: frame,
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Focus Worlds"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = false
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 860, height: 580)
        w.collectionBehavior = [.fullScreenPrimary]
        w.backgroundColor = .black
        w.delegate = self
        w.contentView = NSHostingView(rootView: WorldsRootView(controller: self, model: model, pet: pet))
        w.setFrame(frame, display: false)
        window = w
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        close()
        return false
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        windowVisible = window?.occlusionState.contains(.visible) ?? false
    }

    // MARK: Navigation

    func showSelection() {
        screen = .selection
        updateAudio()
    }

    /// Enters a world. A session already running continues — it's never restarted.
    func enter(_ world: FocusWorld) {
        if world == .recharge, let current = currentWorld, current != .recharge {
            returnWorld = current
        }
        if let t = timer, world != .planning, world != .recharge, t.phase == .focus {
            model.adoptTimer(into: world)
        }
        screen = .world(world)
        model.updateWorlds { $0.lastWorld = world }
        updateAudio()
    }

    // MARK: Sessions (all via the shared AppModel timer)

    /// Starts a session in a world. Returns an error message if it couldn't start.
    @discardableResult
    func start(_ world: FocusWorld, minutes: Int, label: String?) -> String? {
        guard let phase = world.timerPhase else { return nil }
        do {
            try model.startFocus(phase, minutes: minutes, label: label, world: world)
            model.updateWorlds { $0.pendingSummary = nil }
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func pause() { try? model.pauseFocus() }
    func resume() { try? model.resumeFocus() }

    /// Ends the session early. It's recorded honestly as "ended early" (not completed)
    /// and shows the summary — no penalties.
    func endEarly() {
        guard timer != nil else { return }
        try? model.skipPhase()
        if let last = model.data.focus.records.last, last.world != nil {
            model.updateWorlds { $0.pendingSummary = last.id }
            screen = .summary(last.id)
            updateAudio()
        }
    }

    /// Discards the current session without recording it.
    func discard() { try? model.stopFocus() }

    private func sessionFinished(_ record: FocusRecord) {
        guard record.world != nil else { return }
        model.updateWorlds { $0.pendingSummary = record.id }
        celebrateUntil = Date().addingTimeInterval(3)
        guard isOpen else { return }
        if settings.sessionEnd == .returnToPet {
            close()
            return
        }
        screen = .summary(record.id)
        updateAudio()
    }

    /// Saves the optional reflection and clears the pending summary.
    func finishSummary(_ recordID: UUID, reflection: String?) {
        model.setReflection(reflection, for: recordID)
        model.updateWorlds { if $0.pendingSummary == recordID { $0.pendingSummary = nil } }
    }

    func celebrate() { celebrateUntil = Date().addingTimeInterval(2.2) }

    func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            if self?.toast == text { self?.toast = nil }
        }
    }

    /// Saves a thought as a DeskPet note without leaving the world.
    func captureThought(_ text: String) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, (try? model.addItem(clean, kind: .note)) != nil else { return false }
        showToast("Saved to Notes — back to it")
        return true
    }

    // MARK: Ambient audio

    func setAmbient(enabled: Bool) {
        model.updateWorlds { $0.settings.ambientEnabled = enabled }
        updateAudio()
    }

    func setSound(_ sound: AmbientSound, for world: FocusWorld) {
        model.updateWorlds { $0.settings.ambientSound[world.rawValue] = sound }
        updateAudio()
    }

    func setVolume(_ v: Double) {
        model.updateWorlds { $0.settings.volume = v }
        audio.setVolume(v)
    }

    /// One source of truth for what should be playing: only inside an audio world,
    /// only if the user opted in. Leaving the world fades it out.
    func updateAudio() {
        if isOpen, let w = currentWorld, settings.ambientEnabled, let sound = settings.sound(for: w) {
            audio.play(sound, volume: settings.volume)
        } else {
            audio.stop()
        }
    }
}
