import AppKit
import Combine
import SwiftUI

/// Window-level state the SwiftUI pet view observes (separate from pet *needs*).
@MainActor
final class PetWindowState: ObservableObject {
    @Published var layout: PetLayout
    /// Cursor is over the cat (or recently was) — shows the action bar.
    @Published var isHovered = false
    @Published var isDragging = false
    /// Lets the animation timeline pause entirely while hidden.
    @Published var isVisible = false

    init(layout: PetLayout) { self.layout = layout }
}

/// Owns the floating panel: showing/hiding, positioning, screen clamping, and
/// making the transparent parts of the window click-through.
@MainActor
final class PetWindowController {
    let panel: PetPanel
    let state: PetWindowState
    private let settings: AppSettings

    private var pollTimer: Timer?
    private var lastInsideAt = Date.distantPast
    private var cancellables = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?

    /// How long the action bar lingers after the cursor leaves the pet.
    private static let hoverLinger: TimeInterval = 1.2

    init<Content: View>(settings: AppSettings, state: PetWindowState, content: Content) {
        self.settings = settings
        self.state = state
        panel = PetPanel(size: state.layout.windowSize)
        let host = PetHostingView(rootView: content)
        host.frame = NSRect(origin: .zero, size: state.layout.windowSize)
        host.autoresizingMask = [.width, .height]
        host.sizingOptions = [] // size is fixed by PetLayout; skip per-frame constraint updates
        panel.contentView = host
        panel.ignoresMouseEvents = true // until the cursor is actually over the cat

        let size = state.layout.windowSize
        panel.setFrameOrigin(settings.savedWindowOrigin ?? Self.defaultOrigin(for: size))
        clampToScreen(animate: false)

        // Re-layout when the user changes pet size.
        settings.$petSize
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] size in self?.applyLayout(PetLayout(pixel: size.pixel)) }
            .store(in: &cancellables)

        // Displays added/removed/rearranged: make sure the pet is still reachable.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.clampToScreen(animate: true) }
        }
    }

    // MARK: - Visibility

    var isVisible: Bool { panel.isVisible }

    func show() {
        clampToScreen(animate: false)
        panel.orderFrontRegardless()
        state.isVisible = true
        startPolling()
    }

    func hide() {
        stopPolling()
        state.isHovered = false
        state.isVisible = false
        panel.orderOut(nil)
    }

    /// Moves the pet back to its default corner of the main screen.
    func resetPosition() {
        panel.setFrameOrigin(Self.defaultOrigin(for: state.layout.windowSize))
        clampToScreen(animate: false)
        saveOrigin()
    }

    // MARK: - Dragging

    func dragChanged(_ dragging: Bool) {
        state.isDragging = dragging
    }

    func dragEnded() {
        clampToScreen(animate: true)
        saveOrigin()
    }

    // MARK: - Layout & positioning

    private func applyLayout(_ layout: PetLayout) {
        let old = panel.frame
        let oldCat = state.layout.catFrame
        // Keep the cat's feet planted (bottom-centre of the body) while resizing.
        let anchorX = old.minX + oldCat.minX + 9 * state.layout.pixel
        let anchorY = old.maxY - oldCat.maxY
        state.layout = layout
        let size = layout.windowSize
        let origin = NSPoint(
            x: anchorX - (layout.catFrame.minX + 9 * layout.pixel),
            y: anchorY - (size.height - layout.catFrame.maxY)
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        clampToScreen(animate: false)
        saveOrigin()
    }

    /// Cat's rectangle in screen coordinates.
    private func catScreenRect(for frame: NSRect) -> NSRect {
        let cat = state.layout.catFrame
        return NSRect(x: frame.minX + cat.minX, y: frame.maxY - cat.maxY, width: cat.width, height: cat.height)
    }

    /// Ensures the whole cat is inside some screen's visible area (menu bar & Dock excluded).
    func clampToScreen(animate: Bool) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        var frame = panel.frame
        let cat = catScreenRect(for: frame)

        let target = screens.max { a, b in
            a.visibleFrame.intersection(cat).area < b.visibleFrame.intersection(cat).area
        }.flatMap { $0.visibleFrame.intersection(cat).area > 0 ? $0 : nil }
            ?? screens.min { a, b in a.frame.center.distance(to: cat.center) < b.frame.center.distance(to: cat.center) }
            ?? screens[0]

        let visible = target.visibleFrame
        var dx: CGFloat = 0, dy: CGFloat = 0
        if cat.minX < visible.minX { dx = visible.minX - cat.minX }
        if cat.maxX > visible.maxX { dx = visible.maxX - cat.maxX }
        if cat.minY < visible.minY { dy = visible.minY - cat.minY }
        if cat.maxY > visible.maxY { dy = visible.maxY - cat.maxY }
        guard dx != 0 || dy != 0 else { return }
        frame.origin.x += dx
        frame.origin.y += dy
        panel.setFrame(frame, display: true, animate: animate)
        saveOrigin()
    }

    private func saveOrigin() {
        settings.savedWindowOrigin = panel.frame.origin
    }

    static func defaultOrigin(for size: CGSize) -> NSPoint {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: visible.maxX - size.width - 32, y: visible.minY)
    }

    // MARK: - Click-through

    // A borderless window receives clicks over its whole rectangle, including
    // transparent pixels. We watch only the cursor *position* (no clicks, no
    // keys, no screen contents) and let events pass through unless the cursor
    // is over the cat or its action bar.
    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollCursor() }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollCursor() {
        let mouse = NSEvent.mouseLocation
        let f = panel.frame
        let p = CGPoint(x: mouse.x - f.minX, y: f.maxY - mouse.y) // window-local, top-left origin
        let layout = state.layout

        let overCat = f.contains(mouse) && layout.catHitRects.contains { $0.contains(p) }
        let overBar = state.isHovered && layout.barFrame.insetBy(dx: -4, dy: -4).contains(p)
        let now = Date()
        if overCat || overBar { lastInsideAt = now }

        let hovered = overCat || overBar || state.isDragging || now.timeIntervalSince(lastInsideAt) < Self.hoverLinger
        if state.isHovered != hovered { state.isHovered = hovered }

        let interactive = overCat || overBar || state.isDragging
        if panel.ignoresMouseEvents == interactive { panel.ignoresMouseEvents = !interactive }
    }
}

/// Hosting view that accepts the first click even though the panel is never key.
final class PetHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
}
