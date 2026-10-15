import DeskPetCore
import SwiftUI

/// First-launch introduction (and a "what's new" for 1.0 users).
struct WelcomeView: View {
    @ObservedObject var pet: PetViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var loginItem: LoginItemManager
    @ObservedObject var model: AppModel
    @ObservedObject var notifications: NotificationManager
    var isUpgrade: Bool
    var onFinish: () -> Void

    @State private var name = ""
    @State private var goal = 2000

    var body: some View {
        VStack(spacing: 16) {
            WelcomeCat(coat: pet.coat)
                .offset(x: 9) // centre the body rather than body + tail
                .padding(.top, 4)

            VStack(spacing: 6) {
                Text(isUpgrade ? "DeskPet 2.0 is here" : "Meet your DeskPet")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(isUpgrade ? "Same \(pet.name), now with water tracking, focus sessions, notes, and an assistant."
                               : "A tiny friend who helps you sip, focus and remember — right on your desktop.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }

            if !isUpgrade {
                HStack {
                    Text("Name").foregroundStyle(.secondary)
                    TextField("Biscuit", text: $name).textFieldStyle(.roundedBorder).frame(width: 180).onSubmit(finish)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Tip(symbol: "hand.tap.fill", text: "**Click** to pet, **drag** to move, **right-click** for everything.")
                Tip(symbol: "drop.fill", text: "**⌃⌥W** logs a glass of water from anywhere.")
                Tip(symbol: "command", text: "**⌃⌥Space** opens the launcher: “focus for 30 minutes”, “remind me to call Sam at 6 pm”.")
                Tip(symbol: "square.and.pencil", text: "**⌃⌥N** captures a note in seconds. **⌃⌥C** opens chat.")
                Tip(symbol: "lock.shield.fill", text: "Everything stays on your Mac. AI is optional and off until you add a key.")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.5)))

            VStack(alignment: .leading, spacing: 6) {
                Stepper("Daily water goal: \(AppCommand.formatML(goal))", value: $goal, in: HydrationSettings.targetRange, step: 250)
                Toggle("Water reminders on the pet", isOn: Binding(
                    get: { model.hydrationSettings.remindersEnabled },
                    set: { v in model.updateHydrationSettings { $0.remindersEnabled = v } }))
                if NotificationManager.isSupported {
                    Toggle("Also use macOS notifications", isOn: Binding(
                        get: { settings.systemNotifications },
                        set: { on in
                            settings.systemNotifications = on
                            if on { Task { _ = await notifications.requestAuthorization() } }
                        }))
                }
                Toggle("Sound effects", isOn: $settings.soundEnabled)
                Toggle("Open at login", isOn: Binding(
                    get: { loginItem.isEnabled || loginItem.needsApproval },
                    set: { loginItem.setEnabled($0) }))
                    .disabled(!loginItem.isSupported)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("The water goal is a personal setting, not medical advice. You can change anything later in Settings.")
                .font(DP.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)

            Button(action: finish) {
                Text("Let’s go!").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(DP.accent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(26)
        .frame(width: 440)
        .onAppear {
            name = pet.name
            goal = model.hydrationSettings.dailyTargetML
            loginItem.refresh()
        }
    }

    private func finish() {
        if !isUpgrade { pet.rename(name) }
        model.updateHydrationSettings { $0.dailyTargetML = goal }
        onFinish()
    }
}

/// Waving hello. Updates only when the pose actually changes, to stay light.
private struct WelcomeCat: View {
    var coat: CoatTheme
    @State private var tick = Date()
    private let timer = Timer.publish(every: 1.0 / 6.0, tolerance: 0.03, on: .main, in: .common).autoconnect()

    private func pose(at date: Date) -> CatPose {
        let t = date.timeIntervalSinceReferenceDate
        return CatPose(eyes: PetAnimator.isBlinking(t) ? .blink : .happy,
                       mouthOpen: true, blush: true, tailFrame: Int(t / 0.5) % 2, coat: coat)
    }

    var body: some View {
        CatCanvas(pose: pose(at: tick), pixel: 5)
            .onReceive(timer) { date in
                if pose(at: date) != pose(at: tick) { tick = date }
            }
    }
}

private struct Tip: View {
    var symbol: String
    var text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).frame(width: 22).foregroundStyle(DP.accent)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
