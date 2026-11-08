import AppKit
import DeskPetCore
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, pet, water, focus, worlds, voice, shortcuts, ai, license, privacy
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "General"
        case .pet: return "Pet"
        case .water: return "Water"
        case .focus: return "Focus"
        case .voice: return "Voice"
        case .worlds: return "Focus Worlds"
        case .shortcuts: return "Shortcuts"
        case .ai: return "AI"
        case .license: return "License"
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
        case .worlds: return "mountain.2"
        case .shortcuts: return "command"
        case .ai: return "sparkles"
        case .license: return "checkmark.seal"
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
    @ObservedObject var license: LicenseManager
    @ObservedObject var notifications: NotificationManager
    @ObservedObject var hotkeys: HotKeyManager
    @ObservedObject var chat: ChatModel
    @ObservedObject var voice: VoiceController
    var actions: SettingsActions

    var body: some View {
        TabView(selection: $state.tab) {
            GeneralSettings(settings: settings, model: model, loginItem: loginItem, notifications: notifications, license: license)
                .tabItem { Label(SettingsTab.general.title, systemImage: SettingsTab.general.symbol) }.tag(SettingsTab.general)
            PetSettings(pet: pet, settings: settings, model: model, license: license)
                .tabItem { Label(SettingsTab.pet.title, systemImage: SettingsTab.pet.symbol) }.tag(SettingsTab.pet)
            WaterSettings(model: model)
                .tabItem { Label(SettingsTab.water.title, systemImage: SettingsTab.water.symbol) }.tag(SettingsTab.water)
            FocusSettingsView(model: model, settings: settings, license: license)
                .tabItem { Label(SettingsTab.focus.title, systemImage: SettingsTab.focus.symbol) }.tag(SettingsTab.focus)
            WorldsSettingsView(model: model)
                .tabItem { Label(SettingsTab.worlds.title, systemImage: SettingsTab.worlds.symbol) }.tag(SettingsTab.worlds)
            VoiceSettings(settings: settings, voice: voice, recognizer: voice.input)
                .tabItem { Label(SettingsTab.voice.title, systemImage: SettingsTab.voice.symbol) }.tag(SettingsTab.voice)
            ShortcutSettings(hotkeys: hotkeys)
                .tabItem { Label(SettingsTab.shortcuts.title, systemImage: SettingsTab.shortcuts.symbol) }.tag(SettingsTab.shortcuts)
            AISettings(settings: settings, chat: chat)
                .tabItem { Label(SettingsTab.ai.title, systemImage: SettingsTab.ai.symbol) }.tag(SettingsTab.ai)
            LicenseSettings(license: license)
                .tabItem { Label(SettingsTab.license.title, systemImage: SettingsTab.license.symbol) }.tag(SettingsTab.license)
            PrivacySettings(model: model, actions: actions)
                .tabItem { Label(SettingsTab.privacy.title, systemImage: SettingsTab.privacy.symbol) }.tag(SettingsTab.privacy)
        }
        .frame(width: 620, height: 600)
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
    @ObservedObject var license: LicenseManager
    @ObservedObject private var calendar = CalendarService.shared

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
                if BatteryMonitor.shared.reading != nil {
                    Toggle("React to battery (sleepy when low, perky when charging)", isOn: $settings.batteryMoodsEnabled)
                }
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
                Hint(text: settings.calendarEnabled && calendar.hasAccess
                     ? "Built from your DeskPet tasks, water and focus, plus today’s meetings."
                     : "Built from your DeskPet tasks, water and focus.")
            }
            Section("Calendar heads-up") {
                Toggle("Warn me before meetings and show them in Today", isOn: Binding(
                    get: { settings.calendarEnabled },
                    set: { on in
                        settings.calendarEnabled = on
                        if on && calendar.status == .notDetermined { Task { await calendar.requestAccess() } }
                    }))
                Stepper("Heads-up \(settings.meetingLeadMinutes) min before", value: $settings.meetingLeadMinutes,
                        in: MeetingHeadsUp.leadRange)
                    .disabled(!settings.calendarEnabled)
                if !license.access.unlocksPremium {
                    Hint(text: "Calendar heads-up is part of DeskPet Full. Add your license in Settings › License.")
                } else if settings.calendarEnabled && (calendar.status == .denied || calendar.status == .restricted || calendar.status == .writeOnly) {
                    HStack {
                        Hint(text: "DeskPet doesn’t have access to your calendars.")
                        Spacer()
                        Button("Open Settings…") { calendar.openPrivacySettings() }.controlSize(.small)
                    }
                } else {
                    Hint(text: "Reads events from the macOS Calendar app (including accounts added there, like Google or Outlook). Read-only; nothing leaves your Mac. Declined and cancelled events are skipped.")
                }
            }
            MacToolsSettings(settings: settings)
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

// MARK: - Mac tools

private struct MacToolsSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var keepAwake = MacTools.shared.keepAwake
    @State private var screenAccess = CGPreflightScreenCaptureAccess()
    @State private var axTrusted = AXIsProcessTrusted()

    var body: some View {
        Section("Screenshots & copy text") {
            Toggle("Copy screenshots to the clipboard", isOn: $settings.screenshotCopyToClipboard)
            Toggle("Save screenshots to Pictures › DeskPet Screenshots", isOn: $settings.screenshotSaveToFile)
            Toggle("Hide the pet while taking a screenshot", isOn: $settings.screenshotHidePet)
            if !screenAccess {
                HStack {
                    Hint(text: "Needs Screen Recording permission (macOS asks the first time).")
                    Spacer()
                    Button("Open Settings…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                    }.controlSize(.small)
                }
            } else {
                Hint(text: "⌃⌥S: drag over an area (Space switches to a window, Esc cancels). ⌃⌥T copies the text in an area instead — recognised on this Mac, nothing is uploaded.")
            }
        }
        Section("Clipboard history") {
            Toggle("Remember the last \(ClipboardHistory.maxEntries) things I copy (text only)", isOn: $settings.clipboardHistoryEnabled)
            Toggle("Paste right away when I pick one", isOn: Binding(
                get: { settings.clipboardAutoPaste },
                set: { on in
                    settings.clipboardAutoPaste = on
                    if on { axTrusted = MacTools.requestAccessibility() }
                }))
                .disabled(!settings.clipboardHistoryEnabled)
            if settings.clipboardAutoPaste && !axTrusted {
                Hint(text: "Pasting for you needs Accessibility permission (System Settings › Privacy & Security › Accessibility). Until then, picking an item copies it and you press ⌘V.")
            }
            HStack {
                Hint(text: "⌃⌥B opens it. Stored only on this Mac; password-manager copies are never kept.")
                Spacer()
                Button("Clear History") { MacTools.shared.clipboard.clear() }.controlSize(.small)
                    .disabled(MacTools.shared.clipboard.history.entries.isEmpty)
            }
        }
        Section("Keep awake") {
            if let status = keepAwake.statusText {
                HStack {
                    Label(status, systemImage: "sun.max.fill")
                    Spacer()
                    Button("Turn Off") { MacTools.shared.stopKeepAwake() }.controlSize(.small)
                }
            } else {
                HStack {
                    Text("Keep my Mac awake for")
                    Spacer()
                    ForEach(KeepAwake.presets, id: \.self) { m in
                        Button(m.map { KeepAwake.title(minutes: $0).replacingOccurrences(of: "minutes", with: "min") } ?? "Until off") {
                            MacTools.shared.setKeepAwake(minutes: m)
                        }.controlSize(.small)
                    }
                }
            }
            Hint(text: "Stops the display and Mac from sleeping when idle. Closing the lid still sleeps. The pet wears sunglasses while it’s on.")
        }
        .onAppear { screenAccess = CGPreflightScreenCaptureAccess(); axTrusted = AXIsProcessTrusted() }
    }
}

// MARK: - Pet

private struct PetSettings: View {
    @ObservedObject var pet: PetViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: AppModel
    @ObservedObject var license: LicenseManager
    @State private var name = ""
    @State private var confirmReset = false

    var body: some View {
        let p = model.data.progression
        Form {
            Section("Your pet") {
                HStack(spacing: 14) {
                    CatCanvas(pose: CatPose(eyes: pet.isSleeping ? .closed : .happy, blush: true,
                                            coat: pet.coat, accessory: pet.accessory, eyeColor: pet.eyeColor), pixel: 3)
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Name", text: $name).textFieldStyle(.roundedBorder).onSubmit { pet.rename(name) }
                        Text(PetMenu.statusLine(pet)).font(.callout).foregroundStyle(.secondary)
                    }
                }
                StatRow(title: "Happiness", symbol: "heart.fill", value: pet.stats.happiness, tint: .pink)
                StatRow(title: "Energy", symbol: "bolt.fill", value: pet.stats.energy, tint: .yellow)
                StatRow(title: "Hunger", symbol: "fork.knife", value: pet.stats.hunger, tint: .orange)
            }
            Section("Roaming") {
                Toggle("Let \(pet.name) wander around the screen", isOn: $settings.roamingEnabled)
                Group {
                    Toggle("Hop onto the tops of windows", isOn: $settings.roamClimbWindows)
                    Toggle("Chase the cursor now and then", isOn: $settings.roamChaseCursor)
                    Toggle("Nap when I’m away for a few minutes", isOn: $settings.roamNapWhenIdle)
                }
                .disabled(!settings.roamingEnabled)
                if license.access.unlocksPremium {
                    Hint(text: "Stays still while you hover, drag, focus, talk or have a reminder open. Only window positions are read — never titles or contents.")
                } else {
                    Hint(text: "Roaming is part of DeskPet Full. Add your license in Settings › License to bring it back.")
                }
                if !settings.effectiveAnimations {
                    Hint(text: "Roaming is paused because animations are off (or macOS Reduce Motion is on).")
                }
            }
            Section("Coat") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
                    ForEach(CoatTheme.allCases) { coat in
                        WardrobeTile(pose: CatPose(eyes: .open, coat: coat, accessory: p.accessory, eyeColor: p.eyeColor),
                                     title: coat.title, selected: p.coat == coat,
                                     lockedLevel: p.isUnlocked(coat) ? nil : coat.unlockLevel) {
                            model.updateProgression { $0.coat = coat }
                        }
                    }
                }
            }
            Section("Eyes") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
                    WardrobeTile(pose: CatPose(eyes: .open, coat: p.coat), title: "Natural", selected: p.eyeColor == nil,
                                 lockedLevel: nil) { model.updateProgression { $0.eyeColor = nil } }
                    ForEach(EyeColor.allCases) { eye in
                        WardrobeTile(pose: CatPose(eyes: .open, coat: p.coat, eyeColor: eye), title: eye.title,
                                     selected: p.eyeColor == eye, lockedLevel: nil) {
                            model.updateProgression { $0.eyeColor = eye }
                        }
                    }
                }
            }
            Section("Accessory") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
                    WardrobeTile(pose: CatPose(eyes: .open, coat: p.coat, eyeColor: p.eyeColor), title: "None", selected: p.accessory == nil,
                                 lockedLevel: nil) { model.updateProgression { $0.accessory = nil } }
                    ForEach(Accessory.allCases) { a in
                        WardrobeTile(pose: CatPose(eyes: .open, coat: p.coat, accessory: a, eyeColor: p.eyeColor), title: a.title,
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
    @ObservedObject var settings: AppSettings
    @ObservedObject var license: LicenseManager

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
            DistractionGuardSection(settings: settings, licensed: license.access.unlocksPremium)
        }
        .formStyle(.grouped)
    }
}

/// Apps and sites that earn a gentle nudge during focus sessions.
private struct DistractionGuardSection: View {
    @ObservedObject var settings: AppSettings
    var licensed: Bool
    @State private var newSite = ""

    var body: some View {
        Section("Distraction guard") {
            Toggle("Nudge me when I open a distracting app or site during focus", isOn: $settings.distractionGuardEnabled)
            if !licensed {
                Hint(text: "The distraction guard is part of DeskPet Full. Add your license in Settings › License.")
            }
            Group {
                LabeledContent("Apps") {
                    Menu("Add app") {
                        ForEach(runningApps, id: \.bundleID) { app in
                            Button(app.name) { add(app: app.bundleID) }
                        }
                        if !runningApps.isEmpty { Divider() }
                        Button("Choose from Applications…", action: chooseApp)
                    }
                    .fixedSize()
                }
                ForEach(settings.distractingApps, id: \.self) { id in
                    HStack {
                        Image(nsImage: AppInfo.icon(id)).resizable().frame(width: 18, height: 18)
                        Text(AppInfo.name(id))
                        Spacer()
                        removeButton { settings.distractingApps.removeAll { $0 == id } }
                    }
                }
                Toggle("Also check websites in Safari, Chrome, Edge, Brave, Arc, Vivaldi and Opera",
                       isOn: $settings.distractionGuardChecksSites)
                if settings.distractionGuardChecksSites {
                    ForEach(settings.distractingSites, id: \.self) { site in
                        HStack {
                            Image(systemName: "globe").foregroundStyle(.secondary)
                            Text(site)
                            Spacer()
                            removeButton { settings.distractingSites.removeAll { $0 == site } }
                        }
                    }
                    HStack {
                        TextField("Add a site, e.g. news.ycombinator.com", text: $newSite).onSubmit(addSite)
                        Button("Add", action: addSite).disabled(DistractionGuard.normalizedSite(newSite) == nil)
                    }
                }
            }
            .disabled(!settings.distractionGuardEnabled)
            Hint(text: "Only during focus sessions, after 10 seconds on a distraction, and at most every few minutes. DeskPet checks which app is in front and — for sites — asks your browser for the current tab’s address (macOS will ask you once). Nothing is saved or sent. Firefox can’t be checked.")
        }
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove")
    }

    private var runningApps: [(name: String, bundleID: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in app.bundleIdentifier.map { (app.localizedName ?? $0, $0) } }
            .filter { !settings.distractingApps.contains($0.bundleID) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func add(app id: String) {
        if !settings.distractingApps.contains(id) { settings.distractingApps.append(id) }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { if let id = Bundle(url: url)?.bundleIdentifier { add(app: id) } }
    }

    private func addSite() {
        guard let site = DistractionGuard.normalizedSite(newSite) else { return }
        if !settings.distractingSites.contains(site) { settings.distractingSites.append(site) }
        newSite = ""
    }
}

/// Display name and icon for an app bundle identifier.
private enum AppInfo {
    static func url(_ id: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }
    static func name(_ id: String) -> String {
        url(id).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? id
    }
    static func icon(_ id: String) -> NSImage {
        url(id).map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
    }
}

// MARK: - Focus Worlds

private struct WorldsSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let s = model.data.worlds.settings
        func bind<T>(_ kp: WritableKeyPath<WorldsSettings, T>) -> Binding<T> {
            Binding(get: { model.data.worlds.settings[keyPath: kp] }, set: { v in model.updateWorlds { $0.settings[keyPath: kp] = v } })
        }
        return Form {
            Section("Opening Focus Worlds") {
                Picker("Open to", selection: Binding(
                    get: { s.openToLobby ? nil : s.defaultWorld },
                    set: { v in model.updateWorlds { if let v { $0.settings.openToLobby = false; $0.settings.defaultWorld = v } else { $0.settings.openToLobby = true } } })) {
                    Text("All worlds").tag(FocusWorld?.none)
                    ForEach(FocusWorld.allCases) { Text($0.title).tag(FocusWorld?.some($0)) }
                }
                Hint(text: "A running session always reopens in its own world. Shortcut: ⌃⌥F (Shortcuts tab).")
            }
            Section("Session length") {
                ForEach(FocusWorld.allCases.filter { $0.timerPhase != nil }) { w in
                    Stepper("\(w.title): \(s.minutes(for: w)) min", value: Binding(
                        get: { s.minutes(for: w) }, set: { v in model.updateWorlds { $0.settings.setMinutes(v, for: w) } }),
                            in: w.minuteRange, step: w == .recharge ? 1 : 5)
                }
            }
            Section("Ambient sound") {
                Toggle("Play ambient sound in Deep Focus, Study and Recharge", isOn: bind(\.ambientEnabled))
                ForEach(FocusWorld.allCases.filter(\.supportsAmbience)) { w in
                    Picker(w.title, selection: Binding(
                        get: { s.sound(for: w) ?? w.ambientSounds[0] },
                        set: { v in model.updateWorlds { $0.settings.ambientSound[w.rawValue] = v } })) {
                        ForEach(w.ambientSounds) { Text($0.title).tag($0) }
                    }
                    .disabled(!s.ambientEnabled)
                }
                HStack {
                    Text("Volume")
                    Slider(value: bind(\.volume), in: 0...1).accessibilityLabel("Ambient volume")
                }
                .disabled(!s.ambientEnabled)
                Hint(text: "Sounds are generated on your Mac — no recordings or downloads. Off by default; fades out when you leave a world.")
            }
            Section("Look & motion") {
                Picker("Motion", selection: bind(\.motion)) {
                    ForEach(MotionLevel.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Background", selection: bind(\.scenery)) {
                    ForEach(SceneryStyle.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show your pet inside worlds", isOn: bind(\.showPet))
                Toggle("Hide the desktop pet while a world is open", isOn: bind(\.hideDesktopPet))
                Toggle("Breathing guide in Recharge", isOn: bind(\.breathingGuide))
                Hint(text: "“Still” stops all scene and pet animation. Animations also pause when the window is hidden, and follow DeskPet’s Animations setting and macOS Reduce Motion.")
            }
            Section("When a session ends") {
                Picker("Then", selection: bind(\.sessionEnd)) {
                    ForEach(SessionEndBehavior.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Notify me (macOS notification, if enabled in General)", isOn: Binding(
                    get: { model.focusSettings.notifyWhenPhaseEnds },
                    set: { v in model.updateFocusSettings { $0.notifyWhenPhaseEnds = v } }))
                Toggle("Hold water & movement reminders during sessions", isOn: Binding(
                    get: { model.focusSettings.muteNonessentialDuringFocus },
                    set: { v in model.updateFocusSettings { $0.muteNonessentialDuringFocus = v } }))
                Hint(text: "Task reminders you set yourself always come through.")
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
    @State private var savedKeyHint = KeychainStore.loadAPIKey().map(ClaudeKey.masked)
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?
    @State private var showManualEntry = false
    @State private var showAdvanced = false
    @State private var confirmClear = false
    @State private var confirmDisconnect = false
    /// Previews only: show a fixed state without touching the Keychain.
    var previewConnected: Bool?

    private var showsConnected: Bool { previewConnected ?? (hasKey || chat.aiState.isReady) }

    var body: some View {
        Form {
            if showsConnected { connectedSection } else { connectSection }
            Section("Model") {
                Picker("Claude model", selection: $settings.aiModel) {
                    ForEach(ClaudeModelInfo.all) { Text($0.name).tag($0.id) }
                }
                if let info = ClaudeModelInfo.find(settings.aiModel) {
                    Hint(text: info.blurb + (info.refusalFallback
                        ? " If it declines a request, the API retries it on a suitable model automatically." : ""))
                }
            }
            Section("What Claude can see") {
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
            Section {
                DisclosureGroup("Advanced: company or team proxy", isExpanded: $showAdvanced) {
                    TextField("https://your-backend.example.com/v1/messages", text: $settings.aiProxyURL)
                        .textFieldStyle(.roundedBorder)
                    if let problem = ClaudeClient.proxyURLProblem(settings.aiProxyURL) {
                        Label(problem, systemImage: "exclamationmark.triangle.fill").font(DP.caption).foregroundStyle(DP.danger)
                    }
                    Hint(text: "Only if your organisation runs a server that holds the key. DeskPet then sends requests there instead, without any key. See README › AI setup.")
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear the chat history?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { chat.clear() }
        }
        .confirmationDialog("Disconnect your Claude account?", isPresented: $confirmDisconnect) {
            Button("Disconnect", role: .destructive) { disconnect() }
        } message: {
            Text("The key is removed from this Mac’s Keychain. It still exists in your Claude Console — delete it there too if you won’t use it again.")
        }
    }

    // MARK: Not connected

    private var connectSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.system(size: 22, weight: .semibold)).foregroundStyle(DP.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connect your Claude").font(.system(size: 15, weight: .semibold))
                        Text("Chat with your pet using your own Claude account. About a minute to set up.")
                            .font(DP.caption).foregroundStyle(.secondary)
                    }
                }
                step(1, "Open the Claude Console and sign in (or create a free account).") {
                    Button("Open Claude Console") { NSWorkspace.shared.open(ClaudeKey.consoleKeysURL) }
                }
                step(2, "Click “Create Key”, name it “DeskPet”, then click Copy.") { EmptyView() }
                step(3, "Come back here and connect. DeskPet checks the key right away.") {
                    Button {
                        connect(from: NSPasteboard.general.string(forType: .string) ?? "")
                    } label: {
                        Label(testing ? "Connecting…" : "Paste & Connect", systemImage: "link")
                    }
                    .buttonStyle(.borderedProminent).tint(DP.accent).disabled(testing)
                }
                if showManualEntry {
                    HStack {
                        SecureField("sk-ant-…", text: $keyInput).textFieldStyle(.roundedBorder)
                            .onSubmit { connect(from: keyInput) }
                        Button("Connect") { connect(from: keyInput) }.disabled(testing)
                    }
                } else {
                    Button("Type the key instead") { showManualEntry = true }.buttonStyle(.link).font(DP.caption)
                }
                if let r = testResult { resultLabel(r) }
            }
            .padding(.vertical, 4)
            Hint(text: "Claude API usage is billed by Anthropic to your Console account, separately from a Claude Pro or Max plan — add a little credit under Billing first. The key is stored only in your Mac’s Keychain; DeskPet never sees your password and never sends the key anywhere except to Anthropic.")
        }
    }

    private func step<Accessory: View>(_ n: Int, _ text: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(n)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Circle().fill(DP.accent))
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            accessory()
        }
    }

    // MARK: Connected

    private var connectedSection: some View {
        Section("Your Claude account") {
            HStack {
                Circle().fill(DP.mint).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(chat.aiState.isReady || previewConnected == true ? "Connected · \(ChatModel.modelName(settings.aiModel))" : "Key saved").font(.system(size: 13, weight: .semibold))
                    if case .proxy = chat.aiState {
                        Text("Using your organisation’s proxy").font(DP.caption).foregroundStyle(.secondary)
                    } else if let hint = previewConnected == true ? "sk-ant-…x7Qe" : savedKeyHint {
                        Text("Key \(hint) · in your Mac’s Keychain").font(DP.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(testing ? "Checking…" : "Check connection", action: test).disabled(testing).controlSize(.small)
                if hasKey {
                    Button("Disconnect", role: .destructive) { confirmDisconnect = true }.controlSize(.small)
                }
            }
            if let r = testResult { resultLabel(r) }
            HStack(spacing: 14) {
                Button("Usage & billing") { NSWorkspace.shared.open(ClaudeKey.consoleBillingURL) }.buttonStyle(.link)
                Button("Manage keys") { NSWorkspace.shared.open(ClaudeKey.consoleKeysURL) }.buttonStyle(.link)
            }
            .font(DP.caption)
        }
    }

    @ViewBuilder private func resultLabel(_ r: (ok: Bool, text: String)) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(r.text, systemImage: r.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(DP.caption).foregroundStyle(r.ok ? DP.mint : DP.danger)
                .fixedSize(horizontal: false, vertical: true)
            if !r.ok && r.text.contains("credits") {
                Button("Open Billing") { NSWorkspace.shared.open(ClaudeKey.consoleBillingURL) }.buttonStyle(.link).font(DP.caption)
            }
        }
    }

    // MARK: Actions

    /// Validates the pasted key, saves it to the Keychain, and checks it with one tiny request.
    /// A key Anthropic rejects is removed again, so a bad paste never lingers.
    private func connect(from raw: String) {
        testResult = nil
        let key: String
        do { key = try ClaudeKey.clean(raw) } catch {
            testResult = (false, (error as? LocalizedError)?.errorDescription ?? "That key couldn’t be used.")
            if raw.isEmpty || !(raw.hasPrefix("sk-ant")) { showManualEntry = true }
            return
        }
        do { try KeychainStore.saveAPIKey(key) } catch {
            testResult = (false, error.localizedDescription)
            return
        }
        keyInput = ""
        hasKey = true
        savedKeyHint = ClaudeKey.masked(key)
        check(key: key) { ok, message in
            if ok {
                testResult = (true, "Connected! Say hi to your pet in Chat.")
                showManualEntry = false
            } else {
                testResult = (false, message)
                if message == AIError.unauthorized.errorDescription {
                    KeychainStore.deleteAPIKey()
                    hasKey = false
                    savedKeyHint = nil
                    testResult = (false, "Anthropic rejected that key. Copy it again from the Console (or create a new one).")
                }
            }
        }
    }

    private func test() {
        testResult = nil
        check(key: KeychainStore.loadAPIKey()) { ok, message in
            testResult = (ok, ok ? "Connected to \(ChatModel.modelName(settings.aiModel))." : message)
        }
    }

    private func check(key: String?, done: @escaping (Bool, String) -> Void) {
        testing = true
        let client = ClaudeClient(config: .init(model: settings.aiModel, apiKey: key,
                                                proxyURL: ClaudeClient.proxyURL(from: settings.aiProxyURL)))
        let body: [String: JSONValue] = ["model": .string(settings.aiModel), "max_tokens": 64,
                                         "output_config": ["effort": "low"],
                                         "messages": [["role": "user", "content": "Reply with the single word: ready"]]]
        Task {
            do {
                _ = try await client.createMessage(body)
                done(true, "")
            } catch {
                done(false, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
            testing = false
        }
    }

    private func disconnect() {
        KeychainStore.deleteAPIKey()
        hasKey = false
        savedKeyHint = nil
        testResult = nil
    }
}

/// For `--export-spread`: the AI tab in a fixed state.
@MainActor func aiSettingsPreview(settings: AppSettings, chat: ChatModel, connected: Bool) -> AnyView {
    AnyView(AISettings(settings: settings, chat: chat, previewConnected: connected))
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
                Hint(text: "No screenshots, no keystroke logging, no clipboard monitoring. The only network requests are the AI chats you send (if configured) and license checks for an activated key (Settings › License).")
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
                Text("Erase all notes, tasks, logs, progress, chat history, preferences and the saved API key. Your pet starts fresh. Your license stays activated; deactivate it in Settings › License first if you’re moving to another Mac.")
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

// MARK: - License

private struct LicenseSettings: View {
    @ObservedObject var license: LicenseManager
    @State private var keyInput = ""
    @State private var confirmDeactivate = false

    var body: some View {
        Form {
            Section("Status") {
                statusRow
                if license.environment == .testMode {
                    Hint(text: "Test mode: only Dodo Payments test keys work in this build.")
                }
            }
            if let r = license.record {
                Section("This Mac") {
                    LabeledContent("Key", value: r.maskedKey)
                    LabeledContent("Activated", value: r.activatedAt.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("Last checked", value: r.lastValidatedAt.formatted(date: .abbreviated, time: .shortened))
                    HStack {
                        Button("Check now") { Task { await license.revalidateIfNeeded(force: true) } }
                        Spacer()
                        Button("Deactivate on this Mac…", role: .destructive) { confirmDeactivate = true }
                    }
                    .disabled(license.isWorking)
                }
            } else {
                Section("Enter your license key") {
                    HStack {
                        TextField("Paste the key from your purchase email", text: $keyInput)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(activate)
                        Button {
                            if let s = NSPasteboard.general.string(forType: .string) { keyInput = LicensePolicy.normalizedKey(s) }
                        } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                        .help("Paste the key from the clipboard")
                        Button(license.isWorking ? "Activating…" : "Activate", action: activate)
                            .keyboardShortcut(.defaultAction)
                            .disabled(license.isWorking || keyInput.trimmingCharacters(in: .whitespaces).count < 8)
                    }
                    HStack {
                        Text("Don’t have one yet?").font(DP.body)
                        Button("Buy DeskPet…") { license.openBuyPage() }
                    }
                }
            }
            if let s = license.status {
                Label(s.text, systemImage: s.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(DP.caption).foregroundStyle(s.ok ? DP.mint : DP.danger)
            }
            Section("What’s included") {
                Text("Free forever: your pet, water tracking, the focus timer, notes, tasks and reminders.").font(DP.body)
                Text("DeskPet Full (one-time purchase): \(PremiumFeature.allCases.map(\.title).joined(separator: ", ")).").font(DP.body)
                Hint(text: "Activating sends your key and this Mac’s name (“\(LicenseManager.deviceName)”) to Dodo Payments, DeskPet’s payment provider. After that, the key is re-checked about once a week; it keeps working offline for up to 30 days. The key is stored in your macOS Keychain.")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Deactivate DeskPet on this Mac?", isPresented: $confirmDeactivate) {
            Button("Deactivate", role: .destructive) { Task { await license.deactivate() } }
        } message: {
            Text("This frees the key so you can use it on another Mac. Focus Worlds, AI chat and voice will lock here until you activate again.")
        }
    }

    @ViewBuilder private var statusRow: some View {
        switch license.access {
        case .licensed:
            Label("DeskPet Full: thank you!", systemImage: "checkmark.seal.fill").foregroundStyle(DP.mint)
        case .needsCheck:
            Label("License needs a check: connect to the internet and click Check now.", systemImage: "wifi.exclamationmark")
                .foregroundStyle(DP.danger)
        case .trial(let days):
            Label(days == 1 ? "Free trial: last day" : "Free trial: \(days) days left", systemImage: "hourglass")
        case .trialEnded:
            Label("Trial ended. Focus Worlds, AI chat and voice need a license.", systemImage: "lock.fill")
                .foregroundStyle(DP.danger)
        }
    }

    private func activate() {
        let key = keyInput
        Task {
            await license.activate(key)
            if license.record != nil { keyInput = "" }
        }
    }
}
