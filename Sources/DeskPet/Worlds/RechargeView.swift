import DeskPetCore
import SwiftUI

/// Recharge: an intentional, low-pressure break. No streaks, scores or warnings.
struct RechargeView: View {
    @ObservedObject var controller: WorldsController
    @ObservedObject var model: AppModel
    @ObservedObject var pet: PetViewModel
    @State private var minutes = 5
    @State private var error: String?

    private let world = FocusWorld.recharge

    private static let suggestions = [
        ("figure.arms.open", "Reach both arms up, then let them drop slowly."),
        ("eye", "Look at something far away for about 20 seconds."),
        ("figure.walk", "Stand up and wander for a minute."),
        ("drop.fill", "Refill your water."),
        ("arrow.triangle.2.circlepath", "Roll your shoulders back a few times."),
        ("hand.raised", "Unclench your jaw and relax your hands."),
        ("sun.max", "If you can, step near a window for some daylight."),
    ]

    var body: some View {
        let theme = WorldTheme.of(world)
        let state = controller.sessionState(for: world)
        ZStack(alignment: .bottomLeading) {
            VStack(spacing: 26) {
                Spacer()
                if controller.settings.breathingGuide {
                    BreathingGuide(theme: theme, motion: controller.effectiveMotion, active: controller.windowVisible)
                } else {
                    Text("Take it easy").font(theme.display(34, weight: .light))
                }

                if state == .idle {
                    if let t = controller.timer, t.phase == .focus {
                        WorldPanel(theme: theme) {
                            Text("Your focus session is still running.").font(theme.display(15))
                            Text("End it to take a proper break, or just breathe here for a moment.")
                                .font(theme.display(13, weight: .regular)).opacity(0.75)
                            HStack {
                                Button("End session & rest") {
                                    controller.endEarly()
                                    controller.enter(.recharge)
                                    _ = controller.start(world, minutes: minutes, label: nil)
                                }
                                .buttonStyle(WorldButtonStyle(theme: theme))
                                if let back = controller.timerWorld {
                                    Button("Back to \(back.title)") { controller.enter(back) }
                                        .buttonStyle(WorldButtonStyle(theme: theme, prominent: false))
                                }
                            }
                        }
                        .frame(maxWidth: 420)
                    } else {
                        HStack(spacing: 14) {
                            MinutesPicker(minutes: $minutes, range: world.minuteRange, theme: theme, step: 1)
                            Button("Start break") {
                                error = controller.start(world, minutes: minutes, label: nil)
                                if error == nil { model.updateWorlds { $0.settings.setMinutes(minutes, for: world) } }
                            }
                            .buttonStyle(WorldButtonStyle(theme: theme, large: true))
                            .keyboardShortcut(.return, modifiers: .command)
                        }
                    }
                } else if let t = controller.timer {
                    VStack(spacing: 10) {
                        WorldTimerText(timer: t, theme: theme, size: 44).opacity(0.85)
                        HStack {
                            if state == .paused {
                                Button("Resume") { controller.resume() }.buttonStyle(WorldButtonStyle(theme: theme, prominent: false))
                            } else {
                                Button("Pause") { controller.pause() }.buttonStyle(WorldButtonStyle(theme: theme, prominent: false))
                            }
                            Button("I’m ready to go back") { controller.endEarly() }
                                .buttonStyle(WorldButtonStyle(theme: theme, prominent: false))
                        }
                    }
                }

                Ticking(every: 20) { ctx in
                    let s = Self.suggestions[Int(ctx.timeIntervalSinceReferenceDate / 20) % Self.suggestions.count]
                    Label(s.1, systemImage: s.0)
                        .font(theme.display(15, weight: .regular))
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(Capsule().fill(theme.panel))
                        .overlay(Capsule().strokeBorder(theme.panelStroke))
                        .transition(.opacity)
                        .id(s.1)
                }
                .animation(.easeInOut(duration: 0.8), value: Int(Date().timeIntervalSinceReferenceDate / 20))

                if let back = controller.returnWorld {
                    Button("Back to \(back.title)") { controller.enter(back) }
                        .buttonStyle(WorldButtonStyle(theme: theme))
                }
                if let error { Text(error).font(theme.display(12)).foregroundStyle(.red) }
                Spacer()
                Text("Suggestions only — do what feels comfortable for you.")
                    .font(theme.display(11, weight: .regular)).foregroundStyle(theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(theme.panel))
                    .padding(.bottom, 18)
            }
            .frame(maxWidth: .infinity)

            if controller.settings.showPet {
                WorldPet(world: world, state: state == .paused ? .idle : state, coat: pet.coat, accessory: pet.accessory,
                         motion: controller.effectiveMotion, pixel: 5, active: controller.windowVisible)
                    .padding(.leading, 70).padding(.bottom, 60)
            }
        }
        .onAppear { minutes = controller.settings.minutes(for: world) }
    }
}

/// A slow 8-second cycle: grow for "breathe in", shrink for "breathe out".
/// With motion off it becomes a static prompt.
private struct BreathingGuide: View {
    let theme: WorldTheme
    let motion: MotionLevel
    let active: Bool

    var body: some View {
        if motion == .still || !active {
            circle(scale: 0.85, label: "Slow breath in… and out")
        } else {
            Ticking(every: 1.0 / 15) { ctx in
                let t = ctx.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8)
                let inhale = t < 4
                let p = inhale ? t / 4 : 1 - (t - 4) / 4
                let eased = 0.5 - 0.5 * cos(p * .pi)
                circle(scale: 0.62 + 0.38 * eased, label: inhale ? "Breathe in" : "Breathe out")
            }
        }
    }

    private func circle(scale: Double, label: String) -> some View {
        ZStack {
            Circle().fill(theme.accent.opacity(0.12)).frame(width: 240, height: 240)
            Circle().fill(RadialGradient(colors: [Color.white.opacity(0.7), theme.accent.opacity(0.45)],
                                         center: .center, startRadius: 0, endRadius: 120))
                .frame(width: 240, height: 240)
                .scaleEffect(scale)
            Text(label).font(theme.display(20, weight: .medium)).foregroundStyle(theme.ink)
        }
        .accessibilityElement()
        .accessibilityLabel("Breathing guide: \(label)")
    }
}
