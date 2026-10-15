import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A key combination stored in Carbon terms (what RegisterEventHotKey needs).
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String

    static func from(event: NSEvent) -> Shortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Require ⌘, ⌃ or ⌥ so plain typing never triggers DeskPet.
        guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) else { return nil }
        var mods: UInt32 = 0
        var text = ""
        if flags.contains(.control) { mods |= UInt32(controlKey); text += "⌃" }
        if flags.contains(.option) { mods |= UInt32(optionKey); text += "⌥" }
        if flags.contains(.shift) { mods |= UInt32(shiftKey); text += "⇧" }
        if flags.contains(.command) { mods |= UInt32(cmdKey); text += "⌘" }
        return Shortcut(keyCode: UInt32(event.keyCode), carbonModifiers: mods, display: text + keyName(event))
    }

    private static func keyName(_ event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}

/// Global actions that can have a keyboard shortcut.
enum HotKeyAction: String, CaseIterable, Codable, Identifiable {
    case launcher, capture, chat, logWater, togglePet, keyboardMode
    var id: String { rawValue }

    var title: String {
        switch self {
        case .launcher: return "Command launcher"
        case .capture: return "Quick capture"
        case .chat: return "Chat"
        case .logWater: return "Log a glass of water"
        case .togglePet: return "Show / hide pet"
        case .keyboardMode: return "Control pet with keyboard"
        }
    }

    var defaultShortcut: Shortcut {
        let mods = UInt32(controlKey | optionKey)
        switch self {
        case .launcher: return Shortcut(keyCode: UInt32(kVK_Space), carbonModifiers: mods, display: "⌃⌥Space")
        case .capture: return Shortcut(keyCode: UInt32(kVK_ANSI_N), carbonModifiers: mods, display: "⌃⌥N")
        case .chat: return Shortcut(keyCode: UInt32(kVK_ANSI_C), carbonModifiers: mods, display: "⌃⌥C")
        case .logWater: return Shortcut(keyCode: UInt32(kVK_ANSI_W), carbonModifiers: mods, display: "⌃⌥W")
        case .togglePet: return Shortcut(keyCode: UInt32(kVK_ANSI_H), carbonModifiers: mods, display: "⌃⌥H")
        case .keyboardMode: return Shortcut(keyCode: UInt32(kVK_ANSI_P), carbonModifiers: mods, display: "⌃⌥P")
        }
    }
}

/// Registers system-wide shortcuts with Carbon's RegisterEventHotKey. This
/// only receives the registered combinations — it is not a keyboard monitor
/// and needs no Accessibility permission.
@MainActor
final class HotKeyManager: ObservableObject {
    @Published private(set) var shortcuts: [HotKeyAction: Shortcut] = [:]
    /// Actions whose shortcut couldn't be registered (already taken by another app).
    @Published private(set) var conflicts: Set<HotKeyAction> = []
    var handler: (HotKeyAction) -> Void = { _ in }

    private var refs: [HotKeyAction: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private let defaultsKey = "globalShortcuts"
    private static let signature: OSType = 0x4450_4554 // "DPET"

    init() {
        load()
    }

    func start() {
        installHandler()
        registerAll()
    }

    func set(_ action: HotKeyAction, _ shortcut: Shortcut?) {
        unregister(action)
        if let shortcut {
            // Steal the combo from any other DeskPet action first.
            for (other, s) in shortcuts where other != action && s == shortcut {
                unregister(other)
                shortcuts[other] = nil
            }
            shortcuts[action] = shortcut
            register(action)
        } else {
            shortcuts[action] = nil
            conflicts.remove(action)
        }
        save()
    }

    func resetToDefaults() {
        for a in HotKeyAction.allCases { unregister(a) }
        shortcuts = Dictionary(uniqueKeysWithValues: HotKeyAction.allCases.map { ($0, $0.defaultShortcut) })
        save()
        registerAll()
    }

    /// Temporarily disable while recording a new shortcut.
    func suspend() { for a in HotKeyAction.allCases { unregister(a) } }
    func resume() { registerAll() }

    // MARK: Carbon plumbing

    private func installHandler() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hk = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard status == noErr else { return status }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            let id = hk.id
            DispatchQueue.main.async { MainActor.assumeIsolated { manager.fire(id) } }
            return noErr
        }, 1, &spec, selfPtr, &eventHandler)
    }

    private func fire(_ id: UInt32) {
        guard let action = HotKeyAction.allCases.first(where: { Self.numericID($0) == id }) else { return }
        handler(action)
    }

    private static func numericID(_ a: HotKeyAction) -> UInt32 {
        UInt32(HotKeyAction.allCases.firstIndex(of: a)! + 1)
    }

    private func registerAll() {
        for a in HotKeyAction.allCases { register(a) }
    }

    private func register(_ action: HotKeyAction) {
        unregister(action)
        guard let s = shortcuts[action] else { return }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(s.keyCode, s.carbonModifiers,
                                         EventHotKeyID(signature: Self.signature, id: Self.numericID(action)),
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[action] = ref
            conflicts.remove(action)
        } else {
            conflicts.insert(action)
        }
    }

    private func unregister(_ action: HotKeyAction) {
        if let ref = refs.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let stored = try? JSONDecoder().decode([String: Shortcut?].self, from: data) {
            for a in HotKeyAction.allCases {
                if let entry = stored[a.rawValue] { shortcuts[a] = entry } else { shortcuts[a] = a.defaultShortcut }
            }
        } else {
            shortcuts = Dictionary(uniqueKeysWithValues: HotKeyAction.allCases.map { ($0, $0.defaultShortcut) })
        }
    }

    private func save() {
        var out: [String: Shortcut?] = [:]
        for a in HotKeyAction.allCases { out[a.rawValue] = shortcuts[a] }
        if let data = try? JSONEncoder().encode(out) { UserDefaults.standard.set(data, forKey: defaultsKey) }
    }
}

/// Click, then press a key combination. Esc cancels, ⌫ clears.
struct ShortcutRecorder: View {
    var action: HotKeyAction
    @ObservedObject var manager: HotKeyManager
    @State private var recording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Type shortcut…" : (manager.shortcuts[action]?.display ?? "None"))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(minWidth: 100)
            }
            .buttonStyle(.bordered)
            .tint(recording ? DP.accent : nil)
            .accessibilityLabel("\(action.title) shortcut: \(manager.shortcuts[action]?.display ?? "none"). Click to change.")
            if manager.shortcuts[action] != nil && !recording {
                Button { manager.set(action, nil) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove shortcut")
                    .accessibilityLabel("Remove \(action.title) shortcut")
            }
            if manager.conflicts.contains(action) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DP.danger)
                    .help("Another app is already using this shortcut. Pick a different one.")
            }
            if let hint { Text(hint).font(DP.caption).foregroundStyle(.secondary) }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        hint = "Use ⌘, ⌃ or ⌥"
        manager.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            if event.keyCode == UInt16(kVK_Delete) { manager.set(action, nil); stop(); return nil }
            if let s = Shortcut.from(event: event) {
                manager.set(action, s)
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { manager.resume() }
        recording = false
        hint = nil
    }
}
