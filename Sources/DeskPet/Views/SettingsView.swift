import AppKit
import DeskPetCore
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, pet, water, focus, voice, shortcuts, ai, privacy
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "General"
        case .pet: return "Pet"
        case .water: return "Water"
        case .focus: return "Focus"
        case .voice: return "Voice"
        case .shortcuts: return "Shortcuts"
        case .ai: return "AI"
        case .privacy: return "Privacy & Data"
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .pet: return "pawprint"
        case .water: return "drop"
        case .focus: return "timer"
        case .voice: return "waveform"
        case .shortcuts: return "command"
        case .ai: return "sparkles"
        case .privacy: return "lock.shield"
        }
    }
}

@MainActor
final class SettingsState: ObservableObject {
    @Published var tab: SettingsTab = .general
}

/// Everything the settings window can do, supplied by the coordinator.
struct SettingsActions {
    var export: () -> Void
    var deleteAll: () -> Void
    var revealData: () -> Void
}

struct SettingsView: View {
    @ObservedObject var state: SettingsState
    @ObservedObject var pet: PetViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: AppModel
    @ObservedObject var loginItem: LoginItemManager
    @ObservedObject var notifications: NotificationManager
    @ObservedObject var hotkeys: HotKeyManager
    @ObservedObject var chat: ChatModel
    @ObservedObject var voice: VoiceController
    var actions: SettingsActions

    var body: some View {
        TabView(selection: $state.tab) {
            GeneralSettings(settings: settings, model: model, loginItem: loginItem, notifications: notifications)
                .tabItem { Label(SettingsTab.general.title, systemImage: SettingsTab.general.symbol) }.tag(SettingsTab.general)
            PetSettings(pet: pet, settings: settings, model: model)
                .tabItem { Label(SettingsTab.pet.title, systemImage: SettingsTab.pet.symbol) }.tag(SettingsTab.pet)
            WaterSettings(model: model)
                .tabItem { Label(SettingsTab.water.title, systemImage: SettingsTab.water.symbol) }.tag(SettingsTab.water)
            FocusSettingsView(model: model)
                .tabItem { Label(SettingsTab.focus.title, systemImage: SettingsTab.focus.symbol) }.tag(SettingsTab.focus)
            VoiceSettings(settings: settings, voice: voice, recognizer: voice.input)
                .tabItem { Label(SettingsTab.voice.title, systemImage: SettingsTab.voice.symbol) }.tag(SettingsTab.voice)
            ShortcutSettings(hotkeys: hotkeys)
                .tabItem { Label(SettingsTab.shortcuts.title, systemImage: SettingsTab.shortcuts.symbol) }.tag(SettingsTab.shortcuts)
            AISettings(settings: settings, chat: chat)
                .tabItem { Label(SettingsTab.ai.title, systemImage: SettingsTab.ai.symbol) }.tag(SettingsTab.ai)
            PrivacySettings(model: model, actions: actions)
                .tabItem { Label(SettingsTab.privacy.title, systemImage: SettingsTab.privacy.symbol) }.tag(SettingsTab.privacy)
        }
        .frame(width: 560, height: 580)
        .dpPanelStyle()
    }
}

// MARK: - Helpers

/// Binds a minutes-since-midnight Int to a Date for time pickers.
private func minuteBinding(_ get: @escaping () -> Int, _ set: @escaping (Int) -> Void) -> Binding<Date> {
    Binding(
        get: { Calendar.current.date(byAdding: .minute, value: get(), to: Calendar.current.startOfDay(for: Date())) ?? Date() },
        set: { set(Calendar.current.minuteOfDay($0)) })
}

private struct Hint: View {
    var text: String
    var body: some View { Text(text).font(DP.caption).foregroundStyle(.secondary) }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: AppModel
    @ObservedObject var loginItem: LoginItemManager
    @ObservedObject var notifications: NotificationManager

    var body: some View {
        Form {
            Section("Pet window") {
                Toggle("Show pet on desktop", isOn: $settings.petVisible)
                Picker("Size", selection: $settings.petSize) {
                    ForEach(PetSize.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Toggle("Animations", isOn: $settings.animationsEnabled)
                if settings.animationsEnabled && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    Hint(text: "“Reduce motion” is on in System Settings, so animations stay paused.")
                }
                Toggle("Sound effects", isOn: $settings.soundEnabled)
                Toggle("Chatty speech bubbles", isOn: $settings.chattyEnabled)
            }
            Section("Reminders") {
                Toggle("Also show reminders as macOS notifications", isOn: Binding(
                    get: { settings.systemNotifications },
                    set: { on in
                        settings.systemNotifications = on
                        if on { Task { _ = await notifications.requestAuthorization() } }
                    }))
                .disabled(!NotificationManager.isSupported)
                if !NotificationManager.isSupported {
                    Hint(text: "Available when DeskPet runs as an app (scripts/build-app.sh). Reminders still appear on the pet.")
                } else if settings.systemNotifications && notifications.status == .denied {
                    HStack {
                        Hint(text: "Notifications are turned off for DeskPet in System Settings.")
                        Spacer()
                        Button("Open Settings…") { notifications.openSystemSettings() }.controlSize(.small)
                    }
                } else {
                    Hint(text: "Reminders always appear on your pet. This mirrors them into Notification Center.")
                }
            }
            Section("Daily briefing") {
                Picker("Show briefing", selection: Binding(
                    get: { model.data.briefing.mode },
                    set: { v in model.updateBriefing { $0.mode = v } })) {
                    ForEach(BriefingSettings.Mode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if model.data.briefing.mode == .atTime {
                    DatePicker("Time", selection: minuteBinding({ model.data.briefing.briefingMinute },
                                                               { v in model.updateBriefing { $0.briefingMinute = v } }),
                               displayedComponents: .hourAndMinute)
                }
                Toggle("End-of-day summary", isOn: Binding(
                    get: { model.data.briefing.endOfDayEnabled },
                    set: { v in model.updateBriefing { $0.endOfDayEnabled = v } }))
                if model.data.briefing.endOfDayEnabled {
                    DatePicker("Summary time", selection: minuteBinding({ model.data.briefing.endOfDayMinute },
                                                                       { v in model.updateBriefing { $0.endOfDayMinute = v } }),
                               displayedComponents: .hourAndMinute)
                }
                Hint(text: "Built from your DeskPet tasks, water and focus. No calendar access.")
            }
            Section("System") {
                Toggle("Open DeskPet at login", isOn: Binding(
                    get: { loginItem.isEnabled || loginItem.needsApproval },
                    set: { loginItem.setEnabled($0) }))
                .disabled(!loginItem.isSupported)
                if !loginItem.isSupported {
                    Hint(text: "Available when DeskPet runs as an app (scripts/build-app.sh).")
                }
                if loginItem.needsApproval {
                    HStack {
                        Hint(text: "Allow DeskPet in Login Items to finish.")
                        Spacer()
                        Button("Open Login Items…") { loginItem.openSystemSettings() }.controlSize(.small)
                    }
                }
                if let error = loginItem.lastError { Text(error).font(DP.caption).foregroundStyle(DP.danger) }
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refresh(); notifications.refresh() }
    }
}

// MARK: - Pet

private struct PetSettings: View {
    @ObservedObject var pet: PetViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: AppModel
    @State private var name = ""
    @State private var confirmReset = false

    var body: some View {
        let p = model.data.progression
        Form {
            Section("Your pet") {
                HStack(spacing: 14) {
                    CatCanvas(pose: CatPose(eyes: pet.isSleeping ? .closed : .happy, blush: true,
                                            coat: pet.coat, accessory: pet.accessory), pixel: 3)
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Name", text: $name).textFieldStyle(.roundedBorder).onSubmit { pet.rename(name) }
                        Text(PetMenu.statusLine(pet)).font(.callout).foregroundStyle(.secondary)
                    }
                }
                StatRow(title: "Happiness", symbol: "heart.fill", value: pet.stats.happiness, tint: .pink)
                StatRow(title: "Energy", symbol: "bolt.fill", value: pet.stats.energy, tint: .yellow)
                StatRow(title: "Hunger", symbol: "fork.knife", value: pet.stats.hunger, tint: .orange)
            }
            Section("Coat") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
                    ForEach(CoatTheme.allCases) { coat in
                        WardrobeTile(pose: CatPose(eyes: .open, coat: coat, accessory: p.accessory),
                                     title: coat.title, selected: p.coat == coat,
                                     lockedLevel: p.isUnlocked(coat) ? nil : coat.unlockLevel) {
                            model.updateProgression { $0.coat = coat }
                        }
                    }
                }
            }
            Section("Accessory") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
                    WardrobeTile(pose: CatPose(eyes: .open, coat: p.coat), title: "None", selected: p.accessory == nil,
                                 lockedLevel: nil) { model.updateProgression { $0.accessory = nil } }
                    ForEach(Accessory.allCases) { a in
                        WardrobeTile(pose: CatPose(eyes: .open, coat: p.coat, accessory: a), title: a.title,
                                     selected: p.accessory == a, lockedLevel: p.isUnlocked(a) ? nil : a.unlockLevel) {
                            model.updateProgression { $0.accessory = a }
                        }
                    }
                }
            }
            Section("Progress") {
                Toggle("Levels, XP and celebrations", isOn: Binding(
                    get: { p.gamificationEnabled }, set: { v in model.updateProgression { $0.gamificationEnabled = v } }))
                Toggle("Show streaks", isOn: Binding(
                    get: { p.showStreaks }, set: { v in model.updateProgression { $0.showStreaks = v } }))
                    .disabled(!p.gamificationEnabled)
                Hint(text: p.gamificationEnabled
                     ? "Level \(p.level) · \(p.xp) XP. Missing a day never costs you anything."
                     : "Gamification is off, so every coat and accessory is available.")
            }
            Section {
                HStack {
                    Hint(text: "Resets your pet’s happiness, energy and hunger (keeps the name).")
                    Spacer()
                    Button("Reset pet stats…", role: .destructive) { confirmReset = true }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { name = pet.name }
        .onDisappear { pet.rename(name) }
        .confirmationDialog("Reset \(pet.name)’s stats?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { pet.reset() }
        }
    }
}

private struct WardrobeTile: View {
    var pose: CatPose
    var title: String
    var selected: Bool
    var lockedLevel: Int?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                CatCanvas(pose: pose, pixel: 2).opacity(lockedLevel == nil ? 1 : 0.35)
                Text(lockedLevel.map { "Lv \($0)" } ?? title).font(DP.caption)
                    .foregroundStyle(lockedLevel == nil ? .primary : .secondary)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? DP.accent : Color.primary.opacity(0.1),
                                                                        lineWidth: selected ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                if lockedLevel != nil { Image(systemName: "lock.fill").font(.system(size: 9)).padding(4).foregroundStyle(.secondary) }
            }
        }
        .buttonStyle(.plain)
        .disabled(lockedLevel != nil)
        .help(lockedLevel.map { "Unlocks at level \($0)" } ?? title)
        .accessibilityLabel(lockedLevel.map { "\(title), unlocks at level \($0)" } ?? "\(title)\(selected ? ", selected" : "")")
    }
}

struct StatRow: View {
    var title: String
    var symbol: String
    var value: Double
    var tint: Color

    var body: some View {
        HStack {
            Label(title, systemImage: symbol).frame(width: 110, alignment: .leading)
            ProgressView(value: value, total: 100).tint(tint)
            Text("\(Int(value.rounded()))").monospacedDigit().foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Water

private struct WaterSettings: View {
    @ObservedObject var model: AppModel
    @State private var servings: [String] = []

    var body: some View {
        let s = model.hydrationSettings
        Form {
            Section("Goal") {
                Stepper("Daily goal: \(AppCommand.formatML(s.dailyTargetML))", value: Binding(
                    get: { s.dailyTargetML }, set: { v in model.updateHydrationSettings { $0.dailyTargetML = v } }),
                        in: HydrationSettings.targetRange, step: 250)
                Hint(text: "A personal target you choose — not medical advice. Adjust it to whatever works for you.")
            }
            Section("Servings") {
                HStack {
                    ForEach(servings.indices, id: \.self) { i in
                        TextField("ml", text: $servings[i]).textFieldStyle(.roundedBorder).frame(width: 64)
                            .onSubmit(saveServings)
                    }
                    Button("Save", action: saveServings).controlSize(.small)
                }
                Picker("One-click amount", selection: Binding(
                    get: { s.defaultServingML }, set: { v in model.updateHydrationSettings { $0.defaultServingML = v } })) {
                    ForEach(s.servingSizes, id: \.self) { Text("\($0) ml").tag($0) }
                }
                Hint(text: "Used by the pet’s water button, ⌃⌥W, and “log water”.")
            }
            Section("Reminders") {
                Toggle("Remind me to drink water", isOn: Binding(
                    get: { s.remindersEnabled }, set: { v in model.updateHydrationSettings { $0.remindersEnabled = v } }))
                Stepper("Every \(s.reminderIntervalMinutes) minutes", value: Binding(
                    get: { s.reminderIntervalMinutes }, set: { v in model.updateHydrationSettings { $0.reminderIntervalMinutes = v } }),
                        in: HydrationSettings.intervalRange, step: 15).disabled(!s.remindersEnabled)
                Stepper("Snooze for \(s.snoozeMinutes) minutes", value: Binding(
                    get: { s.snoozeMinutes }, set: { v in model.updateHydrationSettings { $0.snoozeMinutes = v } }),
                        in: HydrationSettings.snoozeRange, step: 5).disabled(!s.remindersEnabled)
                Toggle("Stop reminding once I reach my goal", isOn: Binding(
                    get: { s.pauseAfterGoal }, set: { v in model.updateHydrationSettings { $0.pauseAfterGoal = v } }))
            }
            Section("Quiet hours") {
                Toggle("No water or movement reminders during quiet hours", isOn: Binding(
                    get: { s.quietHours.enabled }, set: { v in model.updateHydrationSettings { $0.quietHours.enabled = v } }))
                if s.quietHours.enabled {
                    DatePicker("From", selection: minuteBinding({ s.quietHours.startMinute },
                                                               { v in model.updateHydrationSettings { $0.quietHours.startMinute = v } }),
                               displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: minuteBinding({ s.quietHours.endMinute },
                                                                { v in model.updateHydrationSettings { $0.quietHours.endMinute = v } }),
                               displayedComponents: .hourAndMinute)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { servings = s.servingSizes.map(String.init) + Array(repeating: "", count: max(0, 4 - s.servingSizes.count)) }
    }

    private func saveServings() {
        let values = servings.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard !values.isEmpty else { return }
        model.updateHydrationSettings { st in
            st.servingSizes = values
            if !values.contains(st.defaultServingML) { st.defaultServingML = values.sorted()[values.count / 2] }
        }
        let s = model.hydrationSettings
        servings = s.servingSizes.map(String.init) + Array(repeating: "", count: max(0, 4 - s.servingSizes.count))
    }
}

// MARK: - Focus

private struct FocusSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let s = model.focusSettings
        func bind<T>(_ kp: WritableKeyPath<FocusSettings, T>) -> Binding<T> {
            Binding(get: { model.focusSettings[keyPath: kp] }, set: { v in model.updateFocusSettings { $0[keyPath: kp] = v } })
        }
        return Form {
            Section("Durations") {
                Stepper("Focus: \(s.focusMinutes) min", value: bind(\.focusMinutes), in: FocusSettings.focusRange, step: 5)
                Toggle("Breaks", isOn: bind(\.breaksEnabled))
                if s.breaksEnabled {
                    Stepper("Short break: \(s.shortBreakMinutes) min", value: bind(\.shortBreakMinutes), in: FocusSettings.breakRange)
                    Stepper("Long break: \(s.longBreakMinutes) min", value: bind(\.longBreakMinutes), in: FocusSettings.breakRange)
                    Stepper("Long break every \(s.longBreakEvery) sessions", value: bind(\.longBreakEvery), in: 2...10)
                    Toggle("Start breaks automatically", isOn: bind(\.autoStartBreaks))
                    Toggle("Start the next focus automatically after a break", isOn: bind(\.autoStartFocus))
                }
            }
            Section("Goal") {
                Stepper("Daily goal: \(s.dailyGoalSessions) sessions", value: bind(\.dailyGoalSessions), in: FocusSettings.goalRange)
            }
            Section("During focus") {
                Toggle("Hold water & movement reminders until the session ends", isOn: bind(\.muteNonessentialDuringFocus))
                Toggle("Notify when a session or break ends", isOn: bind(\.notifyWhenPhaseEnds))
                Hint(text: "Task reminders you set yourself still appear.")
            }
            Section("Movement & eye rest") {
                Toggle("Stretch / eye-rest reminders", isOn: bind(\.movementRemindersEnabled))
                Stepper("Every \(s.movementIntervalMinutes) minutes", value: bind(\.movementIntervalMinutes),
                        in: FocusSettings.movementRange, step: 15).disabled(!s.movementRemindersEnabled)
                Hint(text: "Follows your quiet hours from the Water tab.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Voice

private struct VoiceSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var voice: VoiceController
    @ObservedObject var recognizer: SpeechRecognizerService
    @State private var voices: [SpeechSynthesizerService.VoiceOption] = []

    private static let languages = ["en-US", "en-GB", "en-AU", "en-IN", "en-CA", "es-ES", "es-MX", "fr-FR", "de-DE",
                                    "it-IT", "pt-BR", "ja-JP", "zh-CN", "ko-KR", "hi-IN", "nl-NL", "sv-SE"]

    var body: some View {
        Form {
            Section("Talking to your pet") {
                Toggle("Voice input (push-to-talk)", isOn: $settings.voiceInputEnabled)
                    .disabled(!SpeechRecognizerService.isSupportedBuild)
                Hint(text: "The microphone turns on only while you hold the mic button or ⌃⌥V (or after one tap, until you tap again — 60 seconds max). It is never on in the background.")
                HStack {
                    Text("Permission")
                    Spacer()
                    Text(permissionText).foregroundStyle(.secondary)
                    if recognizer.permission == .denied || recognizer.permission == .restricted {
                        Button("Microphone…") { SpeechRecognizerService.openPrivacySettings(microphone: true) }.controlSize(.small)
                        Button("Speech…") { SpeechRecognizerService.openPrivacySettings(microphone: false) }.controlSize(.small)
                    }
                }
                Picker("Language", selection: $settings.recognitionLocale) {
                    ForEach(languageOptions, id: \.self) { id in
                        Text(Locale.current.localizedString(forIdentifier: id) ?? id).tag(id)
                    }
                }
                Toggle("Keep speech recognition on this Mac", isOn: $settings.onDeviceRecognitionOnly)
                Hint(text: settings.onDeviceRecognitionOnly
                     ? "Audio never leaves your Mac. If on-device recognition isn’t available for the language, voice input stays off and you can type."
                     : "If on-device recognition isn’t available, audio may be sent to Apple for transcription (Apple’s privacy policy applies). DeskPet never stores recordings.")
            }
            Section("Spoken replies") {
                Picker("Read replies aloud", selection: $settings.spokenReplies) {
                    ForEach(SpokenReplies.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Mute", isOn: $settings.voiceMuted)
                Picker("Voice", selection: $settings.voiceIdentifier) {
                    Text("Automatic (best for language)").tag("")
                    ForEach(voices) { v in Text("\(v.name) · \(v.quality)").tag(v.id) }
                }
                HStack {
                    Text("Speed")
                    Slider(value: $settings.speechRate, in: 0...1) { Text("Speed") }
                        .accessibilityLabel("Speaking speed")
                    Button(voice.activity == .speaking ? "Stop" : "Preview") {
                        voice.activity == .speaking ? voice.stopSpeaking() : voice.previewVoice()
                    }
                    .controlSize(.small)
                }
                Hint(text: "Uses the built-in macOS voices. Download higher-quality voices in System Settings › Accessibility › Spoken Content › System Voice › Manage Voices.")
            }
            Section("Text-only") {
                Hint(text: "Everything works by typing, too. Turn off voice input and set replies to “Never” for a text-only conversation.")
            }
        }
        .formStyle(.grouped)
        .onAppear { voices = SpeechSynthesizerService.voices(forLanguage: settings.recognitionLocale) }
        .onChange(of: settings.recognitionLocale) { _, id in
            voices = SpeechSynthesizerService.voices(forLanguage: id)
            if !voices.contains(where: { $0.id == settings.voiceIdentifier }) { settings.voiceIdentifier = "" }
        }
    }

    private var languageOptions: [String] {
        var list = Self.languages
        if !list.contains(settings.recognitionLocale) { list.insert(settings.recognitionLocale, at: 0) }
        return list
    }

    private var permissionText: String {
        switch recognizer.permission {
        case .granted: return "Allowed"
        case .notDetermined: return "Asked the first time you talk"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .unsupported: return "Needs the app bundle"
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutSettings: View {
    @ObservedObject var hotkeys: HotKeyManager

    var body: some View {
        Form {
            Section("Global shortcuts") {
                ForEach(HotKeyAction.allCases) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        ShortcutRecorder(action: action, manager: hotkeys)
                    }
                }
                HStack {
                    Hint(text: "Shortcuts work from any app. They need ⌘, ⌃ or ⌥.")
                    Spacer()
                    Button("Reset to defaults") { hotkeys.resetToDefaults() }.controlSize(.small)
                }
            }
            Section("Keyboard mode") {
                Text("Press the “Control pet with keyboard” shortcut, then:").font(DP.body)
                Hint(text: "Arrows move the pet (⇧ for bigger steps) · Space pets · W logs water · F starts/pauses focus · C chat · N capture · Esc exits")
            }
            Section("Privacy") {
                Hint(text: "DeskPet registers only these specific key combinations with macOS. It doesn’t monitor or record your typing, and needs no Accessibility permission.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - AI

private struct AISettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var chat: ChatModel
    @State private var keyInput = ""
    @State private var hasKey = KeychainStore.hasAPIKey
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("Status") {
                HStack {
                    Circle().fill(chat.aiState.isReady ? DP.mint : Color.secondary).frame(width: 8, height: 8)
                    Text(chat.aiState.isReady ? chat.aiState.label : "Not configured — DeskPet works fully offline")
                    Spacer()
                    if chat.aiState.isReady {
                        Button(testing ? "Testing…" : "Test connection", action: test).disabled(testing).controlSize(.small)
                    }
                }
                if let r = testResult {
                    Label(r.text, systemImage: r.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(DP.caption).foregroundStyle(r.ok ? DP.mint : DP.danger)
                }
                Picker("Model", selection: $settings.aiModel) {
                    ForEach(ChatModel.models, id: \.id) { Text($0.name).tag($0.id) }
                }
                if settings.aiModel == "claude-opus-5" {
                    Hint(text: "Refusal fallback is on: if Claude Opus 5 declines a request, the API retries it on a suitable model.")
                }
            }
            Section("API key (development setup)") {
                if hasKey {
                    HStack {
                        Label("Key saved in your macOS Keychain", systemImage: "key.fill")
                        Spacer()
                        Button("Remove", role: .destructive) {
                            KeychainStore.deleteAPIKey()
                            hasKey = false
                            testResult = nil
                        }.controlSize(.small)
                    }
                } else {
                    HStack {
                        SecureField("sk-ant-…", text: $keyInput).textFieldStyle(.roundedBorder)
                            .onSubmit(saveKey)
                        Button {
                            // Reads the clipboard only when clicked.
                            if let s = NSPasteboard.general.string(forType: .string) {
                                keyInput = s.trimmingCharacters(in: .whitespacesAndNewlines)
                                testResult = nil
                            } else {
                                testResult = (false, "The clipboard doesn’t contain text.")
                            }
                        } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                        .help("Paste the key from the clipboard")
                        Button("Save", action: saveKey)
                            .disabled(keyInput.trimmingCharacters(in: .whitespaces).count < 10)
                    }
                }
                Hint(text: "Stored only in your login Keychain — never in DeskPet’s files, settings, logs or the app itself. Get a key at console.anthropic.com. Usage is billed to your Anthropic account.")
            }
            Section("Production: backend proxy (optional)") {
                TextField("https://your-backend.example.com/v1/messages", text: $settings.aiProxyURL)
                    .textFieldStyle(.roundedBorder)
                Hint(text: "If set, DeskPet sends requests to this HTTPS endpoint instead, without any key. Your server adds the key and forwards to the Claude API. See README › AI setup.")
            }
            Section("What the AI can see") {
                Picker("Reading your tasks, notes & stats", selection: $settings.aiDataAccess) {
                    ForEach(AIDataAccess.allCases) { Text($0.title).tag($0) }
                }
                Hint(text: """
                Sent: the messages you type in Chat (or send from the launcher), your pet’s name, and your local time. \
                Only when allowed: the specific task/note/stats results the assistant asks for. \
                Never sent: your clipboard, screen, files, keystrokes, or anything automatically in the background. \
                Commands like “log 300 ml” run on your Mac and aren’t sent at all.
                """)
            }
            Section("Chat history") {
                HStack {
                    Hint(text: "\(chat.messages.count) messages stored on this Mac.")
                    Spacer()
                    Button("Clear chat history…", role: .destructive) { confirmClear = true }
                        .disabled(chat.messages.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear the chat history?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { chat.clear() }
        }
    }

    private func saveKey() {
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 10 else { return }
        do {
            try KeychainStore.saveAPIKey(key)
            keyInput = ""
            hasKey = true
            testResult = nil
        } catch {
            testResult = (false, error.localizedDescription)
        }
    }

    private func test() {
        testing = true
        testResult = nil
        let url = URL(string: settings.aiProxyURL.trimmingCharacters(in: .whitespaces))
        let client = ClaudeClient(config: .init(model: settings.aiModel, apiKey: KeychainStore.loadAPIKey(),
                                                proxyURL: (url?.scheme == "https" || url?.host == "localhost") ? url : nil))
        var body: [String: JSONValue] = ["model": .string(settings.aiModel), "max_tokens": 64,
                                         "messages": [["role": "user", "content": "Reply with the single word: ready"]]]
        if settings.aiModel != "claude-haiku-4-5" { body["output_config"] = ["effort": "low"] }
        Task {
            do {
                _ = try await client.createMessage(body)
                testResult = (true, "Connected to \(ChatModel.modelName(settings.aiModel)).")
            } catch {
                testResult = (false, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
            testing = false
        }
    }
}

// MARK: - Privacy & data

private struct PrivacySettings: View {
    @ObservedObject var model: AppModel
    var actions: SettingsActions
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section("Your data stays on this Mac") {
                Text("Notes, tasks, water and focus logs, preferences and your pet are stored locally in Application Support. DeskPet has no analytics, no tracking and no account.")
                    .font(DP.body)
                Hint(text: "No screenshots, no keystroke logging, no clipboard monitoring. The only network requests are the AI chats you send (if configured).")
                Button("Show data folder in Finder", action: actions.revealData)
                if let error = model.lastSaveError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(DP.caption).foregroundStyle(DP.danger)
                }
            }
            Section("Export") {
                Text("Exports everything as JSON plus CSV files (water, focus, notes & tasks) you can open in Numbers or Excel.")
                    .font(DP.body)
                Button("Export my data…", action: actions.export)
            }
            Section("Delete") {
                Text("Erase all notes, tasks, logs, progress, chat history, preferences and the saved API key. Your pet starts fresh.")
                    .font(DP.body)
                Button("Delete all DeskPet data…", role: .destructive) { confirmDelete = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete all DeskPet data?", isPresented: $confirmDelete) {
            Button("Delete everything", role: .destructive, action: actions.deleteAll)
        } message: {
            Text("This can’t be undone. Consider exporting first.")
        }
    }
}
