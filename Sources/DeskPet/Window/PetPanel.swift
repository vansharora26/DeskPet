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

    /// The panel stays non-key so clicking the pet never steals typing focus from
    /// the user's app. Keyboard mode (opt-in via shortcut/menu) turns this on.
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}
