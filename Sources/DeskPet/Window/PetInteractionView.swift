import AppKit
import SwiftUI

/// Transparent AppKit view laid over the cat. Distinguishes a click (pet)
/// from a drag (move the window) and handles right-click for the context menu.
final class PetInteractionNSView: NSView {
    var onClick: () -> Void = {}
    var onDragEnded: () -> Void = {}
    var onDragChanged: (Bool) -> Void = { _ in }
    var contextMenu: () -> NSMenu? = { nil }
    /// Keyboard mode: returns true if the key was handled.
    var onKey: (NSEvent) -> Bool = { _ in false }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if !onKey(event) { super.keyDown(with: event) }
    }

    private var mouseDownScreen: NSPoint?
    private var windowOriginAtDown: NSPoint?
    private var isDragging = false
    private static let dragThreshold: CGFloat = 3

    // The panel is normally never key, so the first click must count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            showMenu(with: event)
            return
        }
        mouseDownScreen = NSEvent.mouseLocation
        windowOriginAtDown = window?.frame.origin
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownScreen, let origin = windowOriginAtDown, let window else { return }
        // Screen-space deltas: stable even though the view itself is moving.
        let now = NSEvent.mouseLocation
        let dx = now.x - start.x, dy = now.y - start.y
        if !isDragging, hypot(dx, dy) >= Self.dragThreshold {
            isDragging = true
            onDragChanged(true)
        }
        if isDragging {
            window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownScreen = nil; windowOriginAtDown = nil; isDragging = false }
        guard mouseDownScreen != nil else { return }
        if isDragging {
            onDragChanged(false)
            onDragEnded()
        } else {
            onClick()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        showMenu(with: event)
    }

    private func showMenu(with event: NSEvent) {
        guard let menu = contextMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

struct PetInteractionView: NSViewRepresentable {
    var onClick: () -> Void
    var onDragChanged: (Bool) -> Void
    var onDragEnded: () -> Void
    var contextMenu: () -> NSMenu?
    var onKey: (NSEvent) -> Bool = { _ in false }

    func makeNSView(context: Context) -> PetInteractionNSView {
        let view = PetInteractionNSView()
        update(view)
        return view
    }

    func updateNSView(_ view: PetInteractionNSView, context: Context) {
        update(view)
    }

    private func update(_ view: PetInteractionNSView) {
        view.onClick = onClick
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        view.contextMenu = contextMenu
        view.onKey = onKey
    }
}
