import AppKit
import Combine

enum PetSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    /// Points per sprite pixel.
    var pixel: CGFloat {
        switch self {
        case .small: return 4
        case .medium: return 5
        case .large: return 6
        }
    }
}

/// User preferences, backed by UserDefaults. Pet *state* lives in PetStore, not here.
@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    private enum Key {
        static let sound = "soundEnabled"
        static let animations = "animationsEnabled"
        static let chatty = "chattyEnabled"
        static let size = "petSize"
        static let welcomed = "hasCompletedWelcome"
        static let visible = "petVisible"
        static let origin = "petWindowOrigin"
    }

    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Key.sound) } }
    @Published var animationsEnabled: Bool { didSet { defaults.set(animationsEnabled, forKey: Key.animations) } }
    @Published var chattyEnabled: Bool { didSet { defaults.set(chattyEnabled, forKey: Key.chatty) } }
    @Published var petSize: PetSize { didSet { defaults.set(petSize.rawValue, forKey: Key.size) } }
    @Published var hasCompletedWelcome: Bool { didSet { defaults.set(hasCompletedWelcome, forKey: Key.welcomed) } }
    @Published var petVisible: Bool { didSet { defaults.set(petVisible, forKey: Key.visible) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.sound: false,          // sound is opt-in
            Key.animations: true,
            Key.chatty: true,
            Key.size: PetSize.medium.rawValue,
            Key.welcomed: false,
            Key.visible: true,
        ])
        soundEnabled = defaults.bool(forKey: Key.sound)
        animationsEnabled = defaults.bool(forKey: Key.animations)
        chattyEnabled = defaults.bool(forKey: Key.chatty)
        petSize = PetSize(rawValue: defaults.string(forKey: Key.size) ?? "") ?? .medium
        hasCompletedWelcome = defaults.bool(forKey: Key.welcomed)
        petVisible = defaults.bool(forKey: Key.visible)
    }

    /// Animations also respect the system "Reduce motion" accessibility setting.
    var effectiveAnimations: Bool {
        animationsEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var savedWindowOrigin: CGPoint? {
        get {
            guard let s = defaults.string(forKey: Key.origin) else { return nil }
            let p = NSPointFromString(s)
            return p.x.isFinite && p.y.isFinite ? p : nil
        }
        set {
            if let p = newValue { defaults.set(NSStringFromPoint(p), forKey: Key.origin) }
            else { defaults.removeObject(forKey: Key.origin) }
        }
    }
}
