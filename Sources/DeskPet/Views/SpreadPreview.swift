import AppKit
import DeskPetCore
import SwiftUI

/// `DeskPet --export-spread <dir>`: renders the real pet window with the hover spread
/// open (both layouts, light and dark, plus a mid-animation frame) to PNG, off-screen.
@MainActor
enum SpreadPreview {
    static func export(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("DeskPetSpread-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let model = AppModel(store: JSONDocumentStore(fileURL: tmp.appendingPathComponent("data.json")))
        let settings = AppSettings(defaults: UserDefaults(suiteName: "DeskPetSpread-\(UUID().uuidString)")!)
        let pet = PetViewModel(store: PetStore(directory: tmp.appendingPathComponent("pet")), settings: settings, sound: SoundPlayer())
        defer { pet.eraseAndStopSaving() }
        let actions = PetBarActions(logWater: {}, toggleFocus: {}, openFocus: {}, openChat: {}, openCapture: {},
                                    screenshot: {}, copyText: {}, enterWorld: {}, moreMenu: { nil })

        func shot(_ name: String, mode: SpreadMode, dark: Bool, midway: Bool = false) throws {
            let state = PetWindowState(layout: PetLayout(pixel: settings.petSize.pixel))
            state.spread = mode
            state.isHovered = !midway
            let view = PetView(pet: pet, windowState: state, settings: settings, model: model,
                               driver: PetAnimationDriver(pet: pet, windowState: state, settings: settings),
                               onDragChanged: { _ in }, onDragEnded: {}, contextMenu: { nil }, actions: actions, onKey: { _ in false })
            let size = state.layout.windowSize
            let backdrop = ZStack(alignment: .topLeading) {
                LinearGradient(colors: dark ? [Color(white: 0.16), Color(white: 0.26)] : [Color(red: 0.86, green: 0.9, blue: 0.96), Color(red: 0.95, green: 0.93, blue: 0.9)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                view
            }
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, dark ? .dark : .light)
            let window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: size.width, height: size.height),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let host = NSHostingView(rootView: backdrop)
            window.contentView = host
            window.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            if midway {
                state.isHovered = true
                RunLoop.main.run(until: Date().addingTimeInterval(0.12))
            }
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
            window.orderOut(nil)
        }
        // Settings › AI, not connected and connected (never reads or writes the real key).
        let chat = ChatModel(model: model, settings: settings, pet: pet,
                             store: JSONDocumentStore(fileURL: tmp.appendingPathComponent("chat.json")))
        chat.forceLocalOnly = true
        for connected in [false, true] {
            let view = aiSettingsPreview(settings: settings, chat: chat, connected: connected)
                .frame(width: 620, height: 600).background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, .light)
            let window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 620, height: 600), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            let host = NSHostingView(rootView: view)
            window.contentView = host
            window.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(connected ? "ai-connected.png" : "ai-connect.png"))
            }
            window.orderOut(nil)
        }

        // PDF tools window with a couple of real files and a finished result.
        for dark in [false, true] {
            let docs = tmp.appendingPathComponent("docs")
            try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            let a = docs.appendingPathComponent("Invoice March.pdf"), b = docs.appendingPathComponent("Receipts.pdf")
            for u in [a, b] where !FileManager.default.fileExists(atPath: u.path) {
                try "Sample \(u.lastPathComponent)".write(to: docs.appendingPathComponent("s.txt"), atomically: true, encoding: .utf8)
                let out = try PDFEngine.convertToPDF([docs.appendingPathComponent("s.txt")]).urls[0]
                try FileManager.default.moveItem(at: out, to: u)
            }
            let m = PDFToolsModel()
            m.tool = .merge
            m.add([a, b])
            if dark { m.run(); RunLoop.main.run(until: Date().addingTimeInterval(0.3)) }
            let view = PDFToolsView(model: m).frame(width: 820, height: 580)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light)
            let window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 820, height: 580), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let host = NSHostingView(rootView: view)
            window.contentView = host
            window.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(dark ? "pdf-tools-dark.png" : "pdf-tools-light.png"))
            }
            window.orderOut(nil)
        }
        try shot("spread-split-light.png", mode: .split, dark: false)
        try shot("spread-split-dark.png", mode: .split, dark: true)
        try shot("spread-right-light.png", mode: .rightOnly, dark: false)
        try shot("spread-opening.png", mode: .split, dark: false, midway: true)
    }
}
