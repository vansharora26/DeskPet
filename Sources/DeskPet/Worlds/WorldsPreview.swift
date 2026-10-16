import AppKit
import DeskPetCore
import SwiftUI

/// `DeskPet --export-worlds <dir>`: renders the real Focus Worlds window (our own
/// view hierarchy, offscreen) to PNGs for design QA and screenshots. Uses a
/// temporary data folder; never reads the screen or touches the user's data.
@MainActor
enum WorldsPreview {
    static func export(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("DeskPetWorldsPreview-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let model = AppModel(store: JSONDocumentStore(fileURL: tmp.appendingPathComponent("data.json")))
        let settings = AppSettings(defaults: UserDefaults(suiteName: "DeskPetWorldsPreview-\(UUID().uuidString)")!)
        let pet = PetViewModel(store: PetStore(directory: tmp.appendingPathComponent("pet")), settings: settings, sound: SoundPlayer())
        defer { pet.eraseAndStopSaving() }
        let worlds = WorldsController(model: model, pet: pet, appSettings: settings)

        // Sample content so screens aren't empty.
        _ = try? model.addItem("Finish the quarterly report", kind: .task, due: Calendar.current.startOfDay(for: Date()))
        _ = try? model.addItem("Review pull request #42", kind: .task)
        _ = try? model.addItem("Book dentist appointment", kind: .task,
                               due: Calendar.current.date(byAdding: .day, value: 2, to: Date()))
        _ = try? model.logWater(500)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.borderless],
                              backing: .buffered, defer: false)

        func snap(_ name: String) throws {
            let host = NSHostingView(rootView: WorldsRootView(controller: worlds, model: model, pet: pet))
            host.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: dir.appendingPathComponent("\(name).png"))
        }

        worlds.showSelection()
        try snap("0-lobby")
        worlds.enter(.deepFocus)
        try snap("1-deep-focus-setup")
        _ = worlds.start(.deepFocus, minutes: 50, label: "Write chapter 3 of the thesis")
        try snap("2-deep-focus-running")
        worlds.endEarly()
        try snap("3-summary-ended-early")
        model.updateWorlds { $0.study.topic = "Linear algebra — eigenvalues"
            $0.study.checklist = [ChecklistItem(title: "Read section 5.2", done: true), ChecklistItem(title: "Problem set 3, Q1–6")]
        }
        worlds.enter(.study)
        _ = worlds.start(.study, minutes: 25, label: "Linear algebra — eigenvalues")
        try snap("4-study")
        worlds.discard()
        model.updateWorlds {
            $0.sprint = SprintPlan(objective: "Ship the onboarding redesign",
                                   milestones: [ChecklistItem(title: "Finalize copy", done: true), ChecklistItem(title: "Wire up analytics opt-in"),
                                                ChecklistItem(title: "QA on small screens")], createdAt: Date())
        }
        worlds.enter(.workSprint)
        _ = worlds.start(.workSprint, minutes: 45, label: "Ship the onboarding redesign")
        try snap("5-work-sprint")
        worlds.discard()
        worlds.enter(.recharge)
        _ = worlds.start(.recharge, minutes: 5, label: nil)
        try snap("6-recharge")
        worlds.discard()
        let key = Calendar.current.dayKey(Date())
        model.updateWorlds { $0.updatePlan(for: key) { p in
            p.addPriority("Finish the quarterly report"); p.addPriority("Gym at 6"); p.availableHours = 5 } }
        worlds.enter(.planning)
        try snap("7-planning")
        window.contentView = nil
    }

    /// `DeskPet --worlds-probe <world> <seconds>`: renders a live, animating world in a
    /// window placed off-screen (nothing appears on the display), so CPU use can be measured.
    static func probe(world: FocusWorld, seconds: Double, still: Bool = false) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("DeskPetWorldsProbe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let model = AppModel(store: JSONDocumentStore(fileURL: tmp.appendingPathComponent("data.json")))
        let settings = AppSettings(defaults: UserDefaults(suiteName: "DeskPetWorldsProbe-\(UUID().uuidString)")!)
        let pet = PetViewModel(store: PetStore(directory: tmp.appendingPathComponent("pet")), settings: settings, sound: SoundPlayer())
        defer { pet.eraseAndStopSaving() }
        let worlds = WorldsController(model: model, pet: pet, appSettings: settings)
        worlds.markOpenForProbe()
        if still { model.updateWorlds { $0.settings.motion = .still } }
        worlds.enter(world)
        if world.timerPhase != nil { _ = worlds.start(world, minutes: world == .recharge ? 5 : 25, label: "Probe session") }
        let window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 1440, height: 900), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: WorldsRootView(controller: worlds, model: model, pet: pet))
        window.orderFrontRegardless()
        print("probe: \(world.title) rendering off-screen for \(Int(seconds))s (pid \(ProcessInfo.processInfo.processIdentifier))")
        fflush(stdout)
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        window.orderOut(nil)
        worlds.discard()
    }
}
