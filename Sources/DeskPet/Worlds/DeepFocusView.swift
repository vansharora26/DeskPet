import DeskPetCore
import SwiftUI

/// Deep Focus: a dark, quiet scene, one intention, one big timer.
/// Minimal UI; the top bar fades away while the timer runs.
struct DeepFocusView: View {
    @ObservedObject var controller: WorldsController
    @ObservedObject var model: AppModel
    @ObservedObject var pet: PetViewModel
    @State private var intention = ""
    @State private var minutes = 50
    @State private var error: String?

    private let world = FocusWorld.deepFocus

    var body: some View {
        let theme = WorldTheme.of(world)
        let state = controller.sessionState(for: world)

        ZStack(alignment: .bottomLeading) {
            VStack(spacing: 26) {
                Spacer()
                switch state {
                case .idle:
                    if let t = controller.timer {
                        BusyNotice(controller: controller, timer: t, theme: theme)
                    } else {
                        setup(theme)
                    }
                case .running, .paused, .completed:
                    if let t = controller.timer { running(t, state: state, theme: theme) }
                }
                Spacer()
                ThoughtCapture(controller: controller, theme: theme)
                    .padding(.bottom, 36)
            }
            .frame(maxWidth: .infinity)

            if controller.settings.showPet {
                WorldPet(world: world, state: state, coat: pet.coat, accessory: pet.accessory,
                         motion: controller.effectiveMotion, pixel: 5,
                         celebrateUntil: controller.celebrateUntil, active: controller.windowVisible)
                    .padding(.leading, 48).padding(.bottom, 24)
            }
        }
        .onAppear { minutes = controller.settings.minutes(for: world) }
    }

    @ViewBuilder
    private func setup(_ theme: WorldTheme) -> some View {
        VStack(spacing: 20) {
            Text("What will you focus on?")
                .font(theme.display(16, weight: .regular)).foregroundStyle(theme.softInk)
            TextField("One thing", text: $intention)
                .textFieldStyle(.plain)
                .font(theme.display(30, weight: .light))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
                .onSubmit(start)
                .accessibilityLabel("Your focus for this session")
            TaskPickerMenu(model: model, theme: theme, title: "or pick one of your tasks") { intention = $0.title }
            Text("\(minutes):00").font(theme.timerFont(110)).foregroundStyle(theme.ink.opacity(0.92))
            MinutesPicker(minutes: $minutes, range: world.minuteRange, theme: theme)
            Button("Begin deep focus", action: start)
                .buttonStyle(WorldButtonStyle(theme: theme, large: true))
                .keyboardShortcut(.return, modifiers: .command)
            HStack(spacing: 16) {
                Toggle("Notify me when it ends", isOn: Binding(
                    get: { model.focusSettings.notifyWhenPhaseEnds },
                    set: { v in model.updateFocusSettings { $0.notifyWhenPhaseEnds = v } }))
                Toggle("Hold water reminders until it ends", isOn: Binding(
                    get: { model.focusSettings.muteNonessentialDuringFocus },
                    set: { v in model.updateFocusSettings { $0.muteNonessentialDuringFocus = v } }))
            }
            .toggleStyle(.checkbox)
            .font(theme.display(12, weight: .regular))
            .foregroundStyle(theme.softInk)
            if let error { Text(error).font(theme.display(12)).foregroundStyle(.orange) }
        }
    }

    @ViewBuilder
    private func running(_ t: FocusTimer, state: WorldSessionState, theme: WorldTheme) -> some View {
        VStack(spacing: 18) {
            Text(t.label ?? "Deep focus")
                .font(theme.display(18, weight: .regular)).foregroundStyle(theme.softInk)
                .lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: 620)
            WorldTimerText(timer: t, theme: theme, size: 128)
                .opacity(state == .paused ? 0.55 : 0.95)
            WorldProgressBar(timer: t, theme: theme)
            HStack(spacing: 12) {
                if state == .paused {
                    Button("Resume") { controller.resume() }.buttonStyle(WorldButtonStyle(theme: theme))
                        .keyboardShortcut("p", modifiers: .command)
                } else {
                    Button("Pause") { controller.pause() }.buttonStyle(WorldButtonStyle(theme: theme, prominent: false))
                        .keyboardShortcut("p", modifiers: .command)
                }
                Button("End session") { controller.endEarly() }.buttonStyle(WorldButtonStyle(theme: theme, prominent: false))
                Menu {
                    Button("Discard without saving", role: .destructive) { controller.discard() }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("More session options")
            }
            .padding(.top, 6)
        }
    }

    private func start() {
        error = controller.start(world, minutes: minutes, label: intention.isEmpty ? nil : intention)
        if error == nil { model.updateWorlds { $0.settings.setMinutes(minutes, for: world) } }
    }
}
