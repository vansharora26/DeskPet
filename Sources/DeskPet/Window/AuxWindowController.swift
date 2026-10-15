import AppKit
import SwiftUI

/// Hosts a regular titled SwiftUI window (Settings, Welcome). Reuses the
/// window if it's already open and brings the app forward so text fields work.
@MainActor
final class AuxWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let title: String
    private let makeContent: () -> AnyView
    var onClose: () -> Void = {}

    init(title: String, makeContent: @escaping () -> AnyView) {
        self.title = title
        self.makeContent = makeContent
    }

    var isOpen: Bool { window?.isVisible ?? false }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: makeContent())
            let w = NSWindow(contentViewController: hosting)
            w.title = title
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Drop the window so the next open starts fresh (and frees memory).
        window = nil
        onClose()
    }
}
