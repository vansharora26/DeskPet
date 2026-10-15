import AppKit
import DeskPetCore
import SwiftUI

/// A borderless, Spotlight-style panel that can take keyboard focus without
/// activating DeskPet, and closes itself when focus moves elsewhere.
final class InputPanel: NSPanel, NSWindowDelegate {
    var onClose: () -> Void = {}

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        delegate = self
    }

    override var canBecomeKey: Bool { true }

    func windowDidResignKey(_ notification: Notification) { close() }
    func windowWillClose(_ notification: Notification) { onClose() }

    /// Positions the panel horizontally centred, a third of the way down the active screen.
    func present() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            let size = frame.size
            setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.maxY - vf.height / 3 - size.height / 2 + 80))
        }
        makeKeyAndOrderFront(nil)
    }
}

/// Opens and reuses every DeskPet window: the hub, capture, launcher, settings, welcome.
@MainActor
final class WindowRouter: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let chat: ChatModel
    private let pet: PetViewModel
    private let settings: AppSettings
    let hubState = HubState()
    let settingsState = SettingsState()

    private var hubWindow: NSWindow?
    private var capturePanel: InputPanel?
    private var launcherPanel: InputPanel?
    private var settingsWindow: NSWindow?
    var makeSettingsView: () -> AnyView = { AnyView(EmptyView()) }
    var onKeyboardMode: () -> Void = {}

    init(model: AppModel, chat: ChatModel, pet: PetViewModel, settings: AppSettings) {
        self.model = model
        self.chat = chat
        self.pet = pet
        self.settings = settings
        super.init()
    }

    func open(_ destination: Destination) {
        switch destination {
        case .capture: showCapture()
        case .launcher: showLauncher()
        case .settings: openSettings(.general)
        case .today: showHub(.today)
        case .chat: showHub(.chat)
        case .water: showHub(.water)
        case .focus: showHub(.focus)
        case .stats: showHub(.stats)
        case .tasks:
            hubState.showNotes = false
            showHub(.tasks)
        case .notes:
            hubState.showNotes = true
            showHub(.tasks)
        }
    }

    // MARK: Hub

    func showHub(_ tab: HubTab) {
        hubState.tab = tab
        if hubWindow == nil {
            let view = HubView(state: hubState, model: model, chat: chat, pet: pet, settings: settings,
                               openSettings: { [weak self] t in self?.openSettings(t) })
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.contentView = NSHostingView(rootView: view)
            w.title = "DeskPet"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 460, height: 560)
            w.setFrameAutosaveName("DeskPetHub")
            if !w.setFrameUsingName("DeskPetHub") { w.center() }
            w.delegate = self
            hubWindow = w
        }
        NSApp.activate()
        hubWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        if w === hubWindow { hubWindow = nil }
        if w === settingsWindow { settingsWindow = nil }
    }

    /// Opens an item from the launcher: tasks/notes tab, filtered to it.
    func reveal(_ item: Item) {
        hubState.showNotes = !item.isTask
        hubState.search = item.title
        showHub(.tasks)
    }

    // MARK: Settings

    func openSettings(_ tab: SettingsTab) {
        settingsState.tab = tab
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.contentView = NSHostingView(rootView: makeSettingsView())
            w.title = "DeskPet Settings"
            w.isReleasedWhenClosed = false
            w.center()
            w.delegate = self
            settingsWindow = w
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Capture & launcher

    func showCapture() {
        launcherPanel?.close()
        if let p = capturePanel { p.present(); return }
        let panel = InputPanel()
        let view = QuickCaptureView(model: model, onClose: { [weak panel] in panel?.close() })
        panel.contentView = roundedHost(view)
        panel.setContentSize(panel.contentView!.fittingSize)
        panel.onClose = { [weak self] in self?.capturePanel = nil }
        capturePanel = panel
        panel.present()
    }

    func showLauncher() {
        capturePanel?.close()
        if let p = launcherPanel { p.present(); return }
        let panel = InputPanel()
        let view = LauncherView(
            model: model,
            aiReady: { [weak self] in self?.chat.aiState.isReady ?? false },
            onOpen: { [weak self] d in self?.open(d) },
            onAskAI: { [weak self] q in
                self?.showHub(.chat)
                self?.chat.send(q)
            },
            onOpenItem: { [weak self] item in self?.reveal(item) },
            onClose: { [weak panel] in panel?.close() })
        panel.contentView = roundedHost(view)
        panel.setContentSize(NSSize(width: 600, height: 420))
        panel.onClose = { [weak self] in self?.launcherPanel = nil }
        launcherPanel = panel
        panel.present()
        // Grow/shrink with content.
        DispatchQueue.main.async { [weak panel] in
            guard let panel, let content = panel.contentView else { return }
            let top = panel.frame.maxY
            panel.setContentSize(content.fittingSize)
            panel.setFrameTopLeftPoint(NSPoint(x: panel.frame.minX, y: top))
        }
    }

    private func roundedHost<V: View>(_ view: V) -> NSView {
        let host = NSHostingView(rootView: view
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12))))
        host.sizingOptions = [.preferredContentSize]
        return host
    }
}
