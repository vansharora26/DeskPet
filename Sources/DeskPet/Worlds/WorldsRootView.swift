import DeskPetCore
import SwiftUI

/// The Focus Worlds window: environment, top bar, current screen, overlays.
struct WorldsRootView: View {
    @ObservedObject var controller: WorldsController
    @ObservedObject var model: AppModel
    @ObservedObject var pet: PetViewModel
    @ObservedObject private var audio: AmbientAudioEngine
    @State private var lastActivity = Date()
    @State private var chromeDimmed = false

    init(controller: WorldsController, model: AppModel, pet: PetViewModel) {
        self.controller = controller
        self.model = model
        self.pet = pet
        self.audio = controller.audio
    }

    /// The world whose environment is showing (summaries keep their world's look).
    private var sceneWorld: FocusWorld? {
        switch controller.screen {
        case .selection: return nil
        case .world(let w): return w
        case .summary(let id): return model.record(id)?.world.flatMap(FocusWorld.init(rawValue:)) ?? controller.currentWorld
        }
    }

    var body: some View {
        let world = sceneWorld
        let theme = world.map(WorldTheme.of) ?? .lobby
        let motion = controller.effectiveMotion
        let animated = motion != .still

        ZStack {
            Group {
                if let world {
                    WorldScene(world: world, style: controller.settings.scenery, motion: motion,
                               active: controller.windowVisible && controller.isOpen,
                               raining: world == .deepFocus && audio.isPlaying && audio.current == .rain)
                } else {
                    LobbyBackground(motion: motion, active: controller.windowVisible && controller.isOpen)
                }
            }
            .id(world?.rawValue ?? "lobby")
            .transition(.opacity)

            Group {
                switch controller.screen {
                case .selection:
                    ModeSelectionView(controller: controller, model: model, pet: pet)
                case .world(let w):
                    worldView(w)
                case .summary(let id):
                    SessionSummaryView(controller: controller, model: model, pet: pet, recordID: id)
                }
            }
            .padding(.top, 56)
            .transition(animated ? .opacity.combined(with: .scale(scale: 0.985)) : .opacity)
            .id(screenKey)

            VStack(spacing: 0) {
                WorldChrome(controller: controller, model: model, audio: audio, theme: theme)
                    .opacity(chromeDimmed ? 0.18 : 1)
                    .animation(.easeInOut(duration: 0.6), value: chromeDimmed)
                Spacer()
            }

            // Essential reminders (if not muted for focus) appear here while the desktop pet is hidden.
            if let callout = pet.callout {
                VStack {
                    HStack {
                        Spacer()
                        CalloutBubble(callout: callout, onClose: {
                            callout.onDismiss?()
                            pet.clearCallout(id: callout.id)
                        })
                        .padding(.top, 64).padding(.trailing, 20)
                    }
                    Spacer()
                }
                .transition(.opacity)
            }

            if let toast = controller.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(theme.display(13, weight: .medium))
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .foregroundStyle(theme.panelInk)
                        .background(Capsule().fill(theme.panel))
                        .overlay(Capsule().strokeBorder(theme.panelStroke))
                        .padding(.bottom, 28)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityLabel(toast)
            }
        }
        .foregroundStyle(theme.ink)
        .tint(theme.accent)
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
        .animation(animated ? .easeInOut(duration: 0.55) : nil, value: screenKey)
        .animation(.easeOut(duration: 0.25), value: controller.toast)
        .animation(.easeOut(duration: 0.25), value: pet.callout?.id)
        .onContinuousHover { _ in noteActivity() }
        .task(id: screenKey) { await dimChromeWhenIdle() }
        .background(Color.black)
    }

    private var screenKey: String {
        switch controller.screen {
        case .selection: return "selection"
        case .world(let w): return w.rawValue
        case .summary(let id): return id.uuidString
        }
    }

    @ViewBuilder
    private func worldView(_ w: FocusWorld) -> some View {
        switch w {
        case .deepFocus: DeepFocusView(controller: controller, model: model, pet: pet)
        case .study: StudyView(controller: controller, model: model, pet: pet)
        case .workSprint: WorkSprintView(controller: controller, model: model, pet: pet)
        case .recharge: RechargeView(controller: controller, model: model, pet: pet)
        case .planning: PlanningView(controller: controller, model: model, pet: pet)
        }
    }

    private func noteActivity() {
        lastActivity = Date()
        if chromeDimmed { chromeDimmed = false }
    }

    /// In Deep Focus, the top bar fades back after a few quiet seconds while the timer runs.
    private func dimChromeWhenIdle() async {
        chromeDimmed = false
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            let shouldDim = controller.currentWorld == .deepFocus
                && controller.sessionState(for: .deepFocus) == .running
                && Date().timeIntervalSince(lastActivity) > 5
            if shouldDim != chromeDimmed { chromeDimmed = shouldDim }
        }
    }
}

/// Dusk gradient with a few twinkling stars for the lobby.
private struct LobbyBackground: View {
    let motion: MotionLevel
    let active: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: WorldTheme.lobby.gradient, startPoint: .top, endPoint: .bottom)
            Canvas { ctx, s in
                var r = SceneRandom(3)
                for _ in 0..<70 {
                    let p = CGPoint(x: r.next() * s.width, y: r.next() * s.height * 0.6)
                    let d = 0.8 + r.next() * 1.4
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: d, height: d)), with: .color(.white.opacity(0.2 + r.next() * 0.5)))
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Top bar

struct WorldChrome: View {
    @ObservedObject var controller: WorldsController
    @ObservedObject var model: AppModel
    @ObservedObject var audio: AmbientAudioEngine
    let theme: WorldTheme

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Button("All worlds") { controller.showSelection() }.keyboardShortcut("0", modifiers: .command)
                Divider()
                ForEach(Array(FocusWorld.allCases.enumerated()), id: \.element) { i, w in
                    Button { controller.enter(w) } label: { Label(w.title, systemImage: WorldTheme.of(w).symbol) }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: controller.currentWorld.map { WorldTheme.of($0).symbol } ?? "sparkles")
                    Text(controller.currentWorld?.title ?? "Focus Worlds").font(theme.display(14))
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(theme.ink.opacity(0.08)))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Switch world (⌘1–⌘5, ⌘0 for all)")
            .accessibilityLabel("Switch world")

            // A session running in another world stays one click away.
            if let t = controller.timer, controller.currentWorld != (controller.timerWorld ?? (t.phase == .focus ? .deepFocus : .recharge)) {
                let tw = controller.timerWorld ?? (t.phase == .focus ? .deepFocus : .recharge)
                Button { controller.enter(tw) } label: {
                    Ticking(every: 1) { ctx in
                        Label("\(tw.title) · \(CommandExecutor.clock(t.remaining(at: ctx)))", systemImage: "timer")
                            .monospacedDigit()
                    }
                }
                .buttonStyle(WorldButtonStyle(theme: theme, prominent: false))
                .help("Return to your running session")
            }

            Spacer()

            WaterPill(model: model, theme: theme)

            if let w = controller.currentWorld, w.supportsAmbience {
                AmbientControls(controller: controller, audio: audio, world: w, theme: theme)
            }

            Button { controller.toggleFullScreen() } label: {
                Image(systemName: controller.isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(WorldButtonStyle(theme: theme, prominent: false))
            .help("Full screen (⌃⌘F)")
            .accessibilityLabel("Toggle full screen")

            Button { controller.close() } label: { Label("Exit", systemImage: "xmark") }
                .buttonStyle(WorldButtonStyle(theme: theme, prominent: false))
                .help("Return to DeskPet — your timer keeps running (⌘W)")
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)   // clear the window's traffic lights
        .padding(.bottom, 8)
        .foregroundStyle(theme.ink)
    }
}

/// Today's water with one-click logging (the existing hydration tracker).
private struct WaterPill: View {
    @ObservedObject var model: AppModel
    let theme: WorldTheme

    var body: some View {
        Button {
            _ = try? model.logWater(nil)
        } label: {
            Label("\(AppCommand.formatML(model.todayWaterML))", systemImage: "drop.fill")
        }
        .buttonStyle(WorldButtonStyle(theme: theme, prominent: false))
        .help("Log \(model.hydrationSettings.defaultServingML) ml of water")
        .accessibilityLabel("Water today \(model.todayWaterML) millilitres. Log \(model.hydrationSettings.defaultServingML) millilitres")
    }
}

/// Play/pause, sound choice and volume — only shown where audio really exists.
struct AmbientControls: View {
    @ObservedObject var controller: WorldsController
    @ObservedObject var audio: AmbientAudioEngine
    let world: FocusWorld
    let theme: WorldTheme
    @State private var showPopover = false

    var body: some View {
        let on = controller.settings.ambientEnabled
        HStack(spacing: 4) {
            Button { controller.setAmbient(enabled: !on) } label: {
                Image(systemName: on ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
            .help(on ? "Pause ambient sound" : "Play ambient sound")
            .accessibilityLabel(on ? "Pause ambient sound" : "Play ambient sound")
            Button { showPopover.toggle() } label: {
                Text(controller.settings.sound(for: world)?.title ?? "").font(theme.display(12, weight: .medium))
            }
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ambient sound").font(.headline)
                    Picker("Sound", selection: Binding(
                        get: { controller.settings.sound(for: world) ?? world.ambientSounds[0] },
                        set: { controller.setSound($0, for: world) })) {
                        ForEach(world.ambientSounds) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.radioGroup)
                    HStack {
                        Image(systemName: "speaker.fill").font(.caption)
                        Slider(value: Binding(get: { controller.settings.volume }, set: { controller.setVolume($0) }), in: 0...1)
                            .frame(width: 160)
                            .accessibilityLabel("Volume")
                        Image(systemName: "speaker.wave.3.fill").font(.caption)
                    }
                    Text("Generated live on your Mac — no recordings.").font(.caption).foregroundStyle(.secondary)
                    if let e = audio.lastError { Text(e).font(.caption).foregroundStyle(.red) }
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(theme.ink.opacity(0.08)))
    }
}

// MARK: - Shared pieces

/// Large timer numerals; reads from the shared timer's absolute end time.
struct WorldTimerText: View {
    let timer: FocusTimer
    let theme: WorldTheme
    var size: CGFloat = 120

    var body: some View {
        Ticking(every: 1) { ctx in
            Text(CommandExecutor.clock(timer.remaining(at: ctx)))
                .font(theme.timerFont(size))
                .contentTransition(.numericText())
                .accessibilityLabel("\(CommandExecutor.spokenDuration(timer.remaining(at: ctx))) remaining")
        }
    }
}

struct WorldProgressBar: View {
    let timer: FocusTimer
    let theme: WorldTheme
    var width: CGFloat = 260

    var body: some View {
        Ticking(every: 5) { ctx in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.ink.opacity(0.12))
                Capsule().fill(theme.accent).frame(width: max(4, width * timer.progress(at: ctx)))
            }
            .frame(width: width, height: 4)
        }
        .accessibilityHidden(true)
    }
}

/// − 50 min + stepper for choosing a session length before starting.
struct MinutesPicker: View {
    @Binding var minutes: Int
    let range: ClosedRange<Int>
    let theme: WorldTheme
    var step = 5

    var body: some View {
        HStack(spacing: 14) {
            Button { minutes = max(range.lowerBound, minutes - step) } label: { Image(systemName: "minus") }
                .buttonStyle(WorldButtonStyle(theme: theme, prominent: false))
                .accessibilityLabel("Shorter")
            Text("\(minutes) min").font(theme.display(20)).monospacedDigit().frame(minWidth: 90)
            Button { minutes = min(range.upperBound, minutes + step) } label: { Image(systemName: "plus") }
                .buttonStyle(WorldButtonStyle(theme: theme, prominent: false))
                .accessibilityLabel("Longer")
        }
    }
}

/// Inline "capture a thought" — saves to DeskPet Notes without leaving the world.
struct ThoughtCapture: View {
    @ObservedObject var controller: WorldsController
    let theme: WorldTheme
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb").foregroundStyle(theme.softInk)
            TextField("Capture a thought… (⌘N)", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit {
                    if controller.captureThought(text) { text = ""; focused = false }
                }
                .accessibilityLabel("Capture a thought")
            Button("Focus field") { focused = true }.keyboardShortcut("n", modifiers: .command).hidden().frame(width: 0)
        }
        .font(theme.display(14, weight: .regular))
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: 440)
        .background(Capsule().fill(theme.ink.opacity(0.07)))
        .overlay(Capsule().strokeBorder(theme.ink.opacity(0.12)))
    }
}

/// When a different kind of timer is already running, explain instead of failing silently.
struct BusyNotice: View {
    @ObservedObject var controller: WorldsController
    let timer: FocusTimer
    let theme: WorldTheme

    var body: some View {
        WorldPanel(theme: theme) {
            Text(timer.phase.isBreak ? "A break is running" : "A focus session is running")
                .font(theme.display(15))
            Ticking(every: 1) { ctx in
                Text("\(CommandExecutor.clock(timer.remaining(at: ctx))) left\(timer.label.map { " · \($0)" } ?? "")")
                    .font(theme.display(13, weight: .regular)).opacity(0.75).monospacedDigit()
            }
            HStack {
                let w = controller.timerWorld ?? (timer.phase.isBreak ? .recharge : .deepFocus)
                Button("Go to it") { controller.enter(w) }.buttonStyle(WorldButtonStyle(theme: theme))
                Button(timer.phase.isBreak ? "End break" : "End session") { controller.endEarly() }
                    .buttonStyle(WorldButtonStyle(theme: theme, prominent: false))
            }
        }
        .frame(maxWidth: 380)
    }
}

/// Picks an open DeskPet task to use as the session's intention.
struct TaskPickerMenu: View {
    @ObservedObject var model: AppModel
    let theme: WorldTheme
    var title = "Choose a task"
    let onPick: (Item) -> Void

    var body: some View {
        let tasks = model.data.items.openTasks()
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            .prefix(15)
        Menu {
            if tasks.isEmpty { Text("No open tasks") }
            ForEach(Array(tasks)) { t in Button(t.title) { onPick(t) } }
        } label: {
            Label(title, systemImage: "checklist").font(theme.display(13, weight: .medium))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .foregroundStyle(theme.softInk)
    }
}
