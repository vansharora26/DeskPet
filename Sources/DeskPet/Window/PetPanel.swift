import AppKit

/// A transparent, chrome-less panel that floats above ordinary windows and
/// never steals focus from the app the user is working in.
final class PetPanel: NSPanel {
    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovable = false // we move it ourselves so clicks vs. drags can be told apart
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
    }

    // Borderless panels can't become key by default; we don't need key status
    // for clicks, and staying non-key keeps focus with the user's app.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
