import AppKit

// Pure AppKit entry point: DeskPet is a menu-bar ("agent") app with a custom
// floating panel, so it doesn't use SwiftUI's App/WindowGroup lifecycle.
MainActor.assumeIsolated {
    // Build-time helper: `DeskPet --export-iconset <dir>` writes the app icon and exits.
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--export-iconset"), i + 1 < args.count {
        do {
            try IconRenderer.exportIconset(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Icon export failed: \(error)\n".utf8))
            exit(1)
        }
    }

    if let i = args.firstIndex(of: "--export-previews"), i + 1 < args.count {
        do {
            try IconRenderer.exportPreviews(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Preview export failed: \(error)\n".utf8))
            exit(1)
        }
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // no Dock icon, even when run via `swift run`
    withExtendedLifetime(delegate) {
        app.run()
    }
}
