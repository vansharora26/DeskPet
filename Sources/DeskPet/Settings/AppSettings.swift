import AppKit
import Combine
import DeskPetCore

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

/// When the pet reads replies aloud.
enum SpokenReplies: String, CaseIterable, Identifiable {
    case whenISpeak, always, never
    var id: String { rawValue }
    var title: String {
        switch self {
        case .whenISpeak: return "When I talk to it"
        case .always: return "Always"
        case .never: return "Never (text only)"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// How the AI may read local DeskPet data (tasks, notes, stats) when it asks.
enum AIDataAccess: String, CaseIterable, Identifiable {
    case ask, always, never
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ask: return "Ask each time"
        case .always: return "Always allow"
        case .never: return "Never"
        }
    }
}

/// User preferences, backed by UserDefaults. Pet and habit *data* live in JSON files, not here.
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
        static let systemNotifications = "systemNotificationsEnabled"
        static let appearance = "appearance"
        static let aiModel = "aiModel"
        static let aiDataAccess = "aiDataAccess"
        static let aiProxyURL = "aiProxyURL"
        static let seenV2 = "hasSeenDeskPet2Tour"
        static let voiceInput = "voiceInputEnabled"
        static let spokenReplies = "spokenReplies"
        static let voiceMuted = "voiceMuted"
        static let voiceID = "ttsVoiceIdentifier"
        static let speechRate = "ttsRate"
        static let recognitionLocale = "recognitionLocale"
        static let onDeviceOnly = "onDeviceRecognitionOnly"
        static let roaming = "roamingEnabled"
        static let roamChase = "roamChaseCursor"
        static let roamClimb = "roamClimbWindows"
        static let roamNap = "roamNapWhenIdle"
        static let guardOn = "distractionGuardEnabled"
        static let guardApps = "distractingApps"
        static let guardSites = "distractingSites"
        static let guardCheckSites = "distractionGuardChecksSites"
        static let calendar = "calendarHeadsUpEnabled"
        static let meetingLead = "meetingLeadMinutes"
        static let shotCopy = "screenshotCopyToClipboard"
        static let shotSave = "screenshotSaveToFile"
        static let shotHidePet = "screenshotHidePet"
        static let clipHistory = "clipboardHistoryEnabled"
        static let clipAutoPaste = "clipboardAutoPaste"
        static let batteryMoods = "batteryMoodsEnabled"
    }

    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Key.sound) } }
    @Published var animationsEnabled: Bool { didSet { defaults.set(animationsEnabled, forKey: Key.animations) } }
    @Published var chattyEnabled: Bool { didSet { defaults.set(chattyEnabled, forKey: Key.chatty) } }
    @Published var petSize: PetSize { didSet { defaults.set(petSize.rawValue, forKey: Key.size) } }
    @Published var hasCompletedWelcome: Bool { didSet { defaults.set(hasCompletedWelcome, forKey: Key.welcomed) } }
    @Published var petVisible: Bool { didSet { defaults.set(petVisible, forKey: Key.visible) } }
    /// Also show reminders as macOS notifications (needs permission). In-pet reminders always work.
    @Published var systemNotifications: Bool { didSet { defaults.set(systemNotifications, forKey: Key.systemNotifications) } }
    @Published var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance); NSApp.appearance = appearance.nsAppearance }
    }
    @Published var aiModel: String { didSet { defaults.set(aiModel, forKey: Key.aiModel) } }
    @Published var aiDataAccess: AIDataAccess { didSet { defaults.set(aiDataAccess.rawValue, forKey: Key.aiDataAccess) } }
    /// Optional backend proxy that holds the API key server-side (production setup).
    /// A URL that looks like it carries a secret is never written to preferences.
    @Published var aiProxyURL: String {
        didSet { defaults.set(ClaudeClient.proxyURLProblem(aiProxyURL) == nil ? aiProxyURL : "", forKey: Key.aiProxyURL) }
    }
    @Published var hasSeenV2Tour: Bool { didSet { defaults.set(hasSeenV2Tour, forKey: Key.seenV2) } }
    /// Master switch for push-to-talk (off = text-only conversation).
    @Published var voiceInputEnabled: Bool { didSet { defaults.set(voiceInputEnabled, forKey: Key.voiceInput) } }
    @Published var spokenReplies: SpokenReplies { didSet { defaults.set(spokenReplies.rawValue, forKey: Key.spokenReplies) } }
    /// Quick mute from the conversation window (overrides spoken replies).
    @Published var voiceMuted: Bool { didSet { defaults.set(voiceMuted, forKey: Key.voiceMuted) } }
    /// AVSpeechSynthesisVoice identifier; empty = best available voice for the language.
    @Published var voiceIdentifier: String { didSet { defaults.set(voiceIdentifier, forKey: Key.voiceID) } }
    /// 0…1 relative speed (mapped onto the synthesizer's range).
    @Published var speechRate: Double { didSet { defaults.set(speechRate, forKey: Key.speechRate) } }
    @Published var recognitionLocale: String { didSet { defaults.set(recognitionLocale, forKey: Key.recognitionLocale) } }
    /// Keep speech recognition on this Mac (no audio sent to Apple).
    @Published var onDeviceRecognitionOnly: Bool { didSet { defaults.set(onDeviceRecognitionOnly, forKey: Key.onDeviceOnly) } }
    /// The pet wanders the screen on its own (DeskPet Full).
    @Published var roamingEnabled: Bool { didSet { defaults.set(roamingEnabled, forKey: Key.roaming) } }
    @Published var roamChaseCursor: Bool { didSet { defaults.set(roamChaseCursor, forKey: Key.roamChase) } }
    @Published var roamClimbWindows: Bool { didSet { defaults.set(roamClimbWindows, forKey: Key.roamClimb) } }
    @Published var roamNapWhenIdle: Bool { didSet { defaults.set(roamNapWhenIdle, forKey: Key.roamNap) } }
    /// Nudges you back when you open a distracting app or site during focus (DeskPet Full).
    @Published var distractionGuardEnabled: Bool { didSet { defaults.set(distractionGuardEnabled, forKey: Key.guardOn) } }
    /// Bundle identifiers.
    @Published var distractingApps: [String] { didSet { defaults.set(distractingApps, forKey: Key.guardApps) } }
    /// Domains, e.g. "youtube.com".
    @Published var distractingSites: [String] { didSet { defaults.set(distractingSites, forKey: Key.guardSites) } }
    /// Reading the browser's tab address needs Automation permission, so it's a separate switch.
    @Published var distractionGuardChecksSites: Bool { didSet { defaults.set(distractionGuardChecksSites, forKey: Key.guardCheckSites) } }

    /// Meeting heads-up from macOS Calendar (DeskPet Full; needs Calendar access).
    @Published var calendarEnabled: Bool { didSet { defaults.set(calendarEnabled, forKey: Key.calendar) } }
    @Published var meetingLeadMinutes: Int { didSet { defaults.set(meetingLeadMinutes, forKey: Key.meetingLead) } }

    /// Mac tools.
    @Published var screenshotCopyToClipboard: Bool { didSet { defaults.set(screenshotCopyToClipboard, forKey: Key.shotCopy) } }
    @Published var screenshotSaveToFile: Bool { didSet { defaults.set(screenshotSaveToFile, forKey: Key.shotSave) } }
    @Published var screenshotHidePet: Bool { didSet { defaults.set(screenshotHidePet, forKey: Key.shotHidePet) } }
    /// Off until the user turns it on (it reads what they copy).
    @Published var clipboardHistoryEnabled: Bool { didSet { defaults.set(clipboardHistoryEnabled, forKey: Key.clipHistory) } }
    /// The cat reacts to the Mac's battery (sad and lazy when low, perky when charging).
    @Published var batteryMoodsEnabled: Bool { didSet { defaults.set(batteryMoodsEnabled, forKey: Key.batteryMoods) } }
    /// Paste straight into the front app after choosing (needs Accessibility).
    @Published var clipboardAutoPaste: Bool { didSet { defaults.set(clipboardAutoPaste, forKey: Key.clipAutoPaste) } }

    var distractionRules: DistractionRules {
        DistractionRules(apps: distractingApps, sites: distractionGuardChecksSites ? distractingSites : [])
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.sound: false,          // sound is opt-in
            Key.animations: true,
            Key.chatty: true,
            Key.size: PetSize.medium.rawValue,
            Key.welcomed: false,
            Key.visible: true,
            Key.systemNotifications: false,
            Key.appearance: AppearanceMode.system.rawValue,
            Key.aiModel: ClaudeModelInfo.defaultID,
            Key.aiDataAccess: AIDataAccess.ask.rawValue,
            Key.aiProxyURL: "",
            Key.seenV2: false,
            Key.voiceInput: true,
            Key.spokenReplies: SpokenReplies.whenISpeak.rawValue,
            Key.voiceMuted: false,
            Key.voiceID: "",
            Key.speechRate: 0.5,
            Key.recognitionLocale: Locale.current.identifier,
            Key.onDeviceOnly: true,
            Key.roaming: true,
            Key.roamChase: true,
            Key.roamClimb: true,
            Key.roamNap: true,
            Key.guardOn: false,
            Key.guardApps: [String](),
            Key.guardSites: DistractionRules.suggestedSites,
            Key.guardCheckSites: true,
            Key.calendar: false,
            Key.meetingLead: 5,
            Key.shotCopy: true,
            Key.shotSave: true,
            Key.shotHidePet: true,
            Key.clipHistory: false,
            Key.clipAutoPaste: false,
            Key.batteryMoods: true,
        ])
        soundEnabled = defaults.bool(forKey: Key.sound)
        animationsEnabled = defaults.bool(forKey: Key.animations)
        chattyEnabled = defaults.bool(forKey: Key.chatty)
        petSize = PetSize(rawValue: defaults.string(forKey: Key.size) ?? "") ?? .medium
        hasCompletedWelcome = defaults.bool(forKey: Key.welcomed)
        petVisible = defaults.bool(forKey: Key.visible)
        systemNotifications = defaults.bool(forKey: Key.systemNotifications)
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        // Older versions saved model IDs that have since been replaced.
        aiModel = ClaudeModelInfo.migrated(defaults.string(forKey: Key.aiModel) ?? ClaudeModelInfo.defaultID)
        aiDataAccess = AIDataAccess(rawValue: defaults.string(forKey: Key.aiDataAccess) ?? "") ?? .ask
        aiProxyURL = defaults.string(forKey: Key.aiProxyURL) ?? ""
        hasSeenV2Tour = defaults.bool(forKey: Key.seenV2)
        voiceInputEnabled = defaults.bool(forKey: Key.voiceInput)
        spokenReplies = SpokenReplies(rawValue: defaults.string(forKey: Key.spokenReplies) ?? "") ?? .whenISpeak
        voiceMuted = defaults.bool(forKey: Key.voiceMuted)
        voiceIdentifier = defaults.string(forKey: Key.voiceID) ?? ""
        speechRate = min(1, max(0, defaults.double(forKey: Key.speechRate)))
        recognitionLocale = defaults.string(forKey: Key.recognitionLocale) ?? Locale.current.identifier
        onDeviceRecognitionOnly = defaults.bool(forKey: Key.onDeviceOnly)
        roamingEnabled = defaults.bool(forKey: Key.roaming)
        roamChaseCursor = defaults.bool(forKey: Key.roamChase)
        roamClimbWindows = defaults.bool(forKey: Key.roamClimb)
        roamNapWhenIdle = defaults.bool(forKey: Key.roamNap)
        distractionGuardEnabled = defaults.bool(forKey: Key.guardOn)
        distractingApps = defaults.stringArray(forKey: Key.guardApps) ?? []
        distractingSites = defaults.stringArray(forKey: Key.guardSites) ?? DistractionRules.suggestedSites
        distractionGuardChecksSites = defaults.bool(forKey: Key.guardCheckSites)
        calendarEnabled = defaults.bool(forKey: Key.calendar)
        meetingLeadMinutes = min(MeetingHeadsUp.leadRange.upperBound,
                                 max(MeetingHeadsUp.leadRange.lowerBound, defaults.integer(forKey: Key.meetingLead)))
        screenshotCopyToClipboard = defaults.bool(forKey: Key.shotCopy)
        screenshotSaveToFile = defaults.bool(forKey: Key.shotSave)
        screenshotHidePet = defaults.bool(forKey: Key.shotHidePet)
        clipboardHistoryEnabled = defaults.bool(forKey: Key.clipHistory)
        clipboardAutoPaste = defaults.bool(forKey: Key.clipAutoPaste)
        batteryMoodsEnabled = defaults.bool(forKey: Key.batteryMoods)
    }

    /// Removes every DeskPet preference (used by "Delete all data").
    func resetAll() {
        if let domain = Bundle.main.bundleIdentifier { defaults.removePersistentDomain(forName: domain) }
        for key in [Key.sound, Key.animations, Key.chatty, Key.size, Key.welcomed, Key.visible, Key.origin,
                    Key.systemNotifications, Key.appearance, Key.aiModel, Key.aiDataAccess, Key.aiProxyURL, Key.seenV2,
                    Key.voiceInput, Key.spokenReplies, Key.voiceMuted, Key.voiceID, Key.speechRate,
                    Key.recognitionLocale, Key.onDeviceOnly, Key.roaming, Key.roamChase, Key.roamClimb, Key.roamNap,
                    Key.guardOn, Key.guardApps, Key.guardSites, Key.guardCheckSites, Key.calendar, Key.meetingLead,
                    Key.shotCopy, Key.shotSave, Key.shotHidePet, Key.clipHistory, Key.clipAutoPaste, Key.batteryMoods] {
            defaults.removeObject(forKey: key)
        }
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
