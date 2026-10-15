import DeskPetCore
import SwiftUI

/// Focus timer: start / pause / resume / skip / reset, breaks, history.
/// The display reads remaining time from absolute dates; the 1-second
/// timeline is only for redrawing while this view is visible.
struct FocusView: View {
    @ObservedObject var model: AppModel
    var openSettings: () -> Void
    @State private var minutes: Int = 25
    @State private var label = ""
    @State private var confirmReset = false
    @State private var error: String?

    var body: some View {
        let s = model.focusSettings
        let today = model.todayFocus

        ScrollView {
            VStack(alignment: .leading, spacing: DP.spacing) {
                Card {
                    if let t = model.focusTimerState {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            activeTimer(t, now: ctx.date)
                        }
                    } else {
                        idle(s)
                    }
                    if let error { Text(error).font(DP.caption).foregroundStyle(DP.danger) }
                }

                Card {
                    SectionTitle(text: "Today", symbol: "chart.bar.fill")
                    HStack(spacing: 18) {
                        stat("\(today.sessionsCompleted)/\(s.dailyGoalSessions)", "sessions")
                        stat("\(today.focusMinutes)", "minutes")
                        stat("\(today.breaksCompleted + model.movementBreaks(on: model.now))", "breaks")
                    }
                }

                Card {
                    SectionTitle(text: "Recent sessions", symbol: "clock.arrow.circlepath")
                    let recent = model.data.focus.records.suffix(12).reversed()
                    if recent.isEmpty {
                        EmptyState(symbol: "timer", title: "No sessions yet",
                                   message: "Start a focus session — I’ll wear my focus headband and keep quiet.")
                    } else {
                        ForEach(Array(recent)) { r in
                            HStack {
                                Image(systemName: r.phase.isBreak ? "cup.and.saucer.fill" : "timer")
                                    .foregroundStyle(r.phase.isBreak ? DP.mint : DP.accent).frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.label ?? r.phase.title).font(DP.body).lineLimit(1)
                                    Text(r.end, format: .dateTime.weekday(.abbreviated).hour().minute())
                                        .font(DP.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(Int((r.activeSeconds / 60).rounded())) min").font(DP.caption).monospacedDigit()
                                Image(systemName: r.completed ? "checkmark.circle.fill" : "forward.end.circle")
                                    .foregroundStyle(r.completed ? DP.mint : .secondary)
                                    .help(r.completed ? "Completed" : "Ended early")
                            }
                        }
                    }
                }

                Card {
                    SectionTitle(text: "While focusing", symbol: "bell.slash.fill")
                    Toggle("Hold water & movement reminders until the session ends", isOn: Binding(
                        get: { s.muteNonessentialDuringFocus },
                        set: { v in model.updateFocusSettings { $0.muteNonessentialDuringFocus = v } }))
                    Toggle("Notify me when a session or break ends", isOn: Binding(
                        get: { s.notifyWhenPhaseEnds },
                        set: { v in model.updateFocusSettings { $0.notifyWhenPhaseEnds = v } }))
                    Button("Durations, breaks & goal…", action: openSettings).buttonStyle(.link).font(DP.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .onAppear { minutes = s.focusMinutes }
        .confirmationDialog("Reset the timer?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { try? model.stopFocus() }
        } message: { Text("The current session won’t be saved.") }
    }

    @ViewBuilder
    private func activeTimer(_ t: FocusTimer, now: Date) -> some View {
        let tint = t.phase.isBreak ? DP.mint : DP.accent
        VStack(spacing: 12) {
            ZStack {
                ProgressRing(progress: t.progress(at: now), tint: tint, lineWidth: 12)
                VStack(spacing: 2) {
                    Text(CommandExecutor.clock(t.remaining(at: now)))
                        .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(t.isRunning ? (t.label ?? t.phase.title) : "Paused")
                        .font(DP.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(width: 170, height: 170)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(t.phase.title) \(t.isRunning ? "running" : "paused"), \(CommandExecutor.clock(t.remaining(at: now))) left")

            if t.phase.isBreak {
                Text(breakTip).font(DP.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }

            HStack(spacing: 8) {
                if t.isRunning {
                    Button { act { try model.pauseFocus() } } label: { Label("Pause", systemImage: "pause.fill") }
                        .buttonStyle(PillButtonStyle(tint: tint)).keyboardShortcut(.space, modifiers: [])
                } else {
                    Button { act { try model.resumeFocus() } } label: { Label("Resume", systemImage: "play.fill") }
                        .buttonStyle(PillButtonStyle(tint: tint)).keyboardShortcut(.space, modifiers: [])
                }
                Button { act { try model.skipPhase() } } label: { Label("Skip", systemImage: "forward.end.fill") }
                    .buttonStyle(PillButtonStyle(tint: tint, filled: false))
                Button { confirmReset = true } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(PillButtonStyle(tint: .secondary, filled: false))
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func idle(_ s: FocusSettings) -> some View {
        let suggested = model.data.focus.suggestedNextPhase(now: model.now)
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Start a session", symbol: "play.circle.fill")
            HStack {
                Stepper("\(minutes) minutes", value: $minutes, in: FocusSettings.focusRange, step: 5)
                    .font(DP.headline)
                Spacer()
                ForEach([15, 25, 45], id: \.self) { m in
                    Button("\(m)") { minutes = m }.buttonStyle(PillButtonStyle(filled: minutes == m))
                }
            }
            TextField("What are you focusing on? (optional)", text: $label).textFieldStyle(.roundedBorder)
            HStack {
                Button { act { try model.startFocus(.focus, minutes: minutes, label: label) ; label = "" } } label: {
                    Label("Start focus", systemImage: "timer")
                }
                .buttonStyle(PillButtonStyle()).keyboardShortcut(.return, modifiers: .command)
                if s.breaksEnabled {
                    Button { act { try model.startFocus(suggested == .longBreak ? .longBreak : .shortBreak) } } label: {
                        Label(suggested == .longBreak ? "Long break" : "Short break", systemImage: "cup.and.saucer.fill")
                    }
                    .buttonStyle(PillButtonStyle(tint: DP.mint, filled: suggested != .focus))
                }
            }
        }
    }

    private var breakTip: String {
        ["Stand up, stretch, look out a window.", "Refill your water — I’ll wait.",
         "Eye rest: focus on something far away.", "Roll your shoulders and breathe out slowly."][
            Int(model.now.timeIntervalSince1970 / 300) % 4]
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded))
            Text(label).font(DP.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func act(_ f: () throws -> Void) {
        do { try f(); error = nil } catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }
}
