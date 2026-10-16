import DeskPetCore
import SwiftUI

/// The lobby: five worlds, each with its own preview, purpose, duration and audio info.
struct ModeSelectionView: View {
    @ObservedObject var controller: WorldsController
    @ObservedObject var model: AppModel
    @ObservedObject var pet: PetViewModel

    var body: some View {
        let theme = WorldTheme.lobby
        ScrollView {
            VStack(spacing: 22) {
                HStack(alignment: .bottom, spacing: 18) {
                    WorldPet(world: .planning, state: .idle, coat: pet.coat, accessory: pet.accessory,
                             motion: controller.effectiveMotion, pixel: 4, active: controller.windowVisible)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Where would you like to work?").font(theme.display(30, weight: .bold))
                        Text("Pick a world. \(pet.name) will come along — your timer, tasks and water stay in sync with DeskPet.")
                            .font(theme.display(15, weight: .regular)).foregroundStyle(theme.softInk)
                    }
                    Spacer()
                }
                .frame(maxWidth: 1100)

                if let t = controller.timer {
                    BusyNotice(controller: controller, timer: t, theme: theme)
                        .frame(maxWidth: 1100, alignment: .leading)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 420), spacing: 18)], spacing: 18) {
                    ForEach(FocusWorld.allCases) { world in
                        WorldCard(world: world, controller: controller, pet: pet)
                    }
                }
                .frame(maxWidth: 1100)

                Text("Focus Worlds lives in this window — your Mac’s desktop and wallpaper aren’t changed. Exit any time; the timer keeps running.")
                    .font(theme.display(12, weight: .regular)).foregroundStyle(theme.softInk)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(theme.ink)
    }
}

private struct WorldCard: View {
    let world: FocusWorld
    @ObservedObject var controller: WorldsController
    @ObservedObject var pet: PetViewModel
    @State private var hovering = false

    var body: some View {
        let theme = WorldTheme.of(world)
        let minutes = controller.settings.minutes(for: world)
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                WorldScene(world: world, style: controller.settings.scenery, motion: .still)
                WorldPet(world: world, state: .idle, coat: pet.coat, accessory: pet.accessory, motion: .still, pixel: 2.5)
                    .padding(12)
                HStack {
                    Spacer()
                    Label(world.supportsAmbience ? "Ambient sound" : "No audio",
                          systemImage: world.supportsAmbience ? "speaker.wave.2.fill" : "speaker.slash")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.35)))
                        .foregroundStyle(.white)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(10)
            }
            .frame(height: 150)
            .clipped()

            VStack(alignment: .leading, spacing: 8) {
                Label(world.title, systemImage: theme.symbol).font(.system(size: 18, weight: .bold, design: theme.design))
                Text(world.tagline).font(.system(size: 13, design: theme.design)).foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if world.timerPhase != nil {
                        Stepper(value: Binding(
                            get: { minutes },
                            set: { v in controller.model.updateWorlds { $0.settings.setMinutes(v, for: world) } }),
                                in: world.minuteRange, step: world == .recharge ? 1 : 5) {
                            Label("\(minutes) min", systemImage: "timer").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        }
                        .accessibilityLabel("\(world.title) session length \(minutes) minutes")
                    } else {
                        Label("About \(world.suggestedMinutes) min", systemImage: "list.bullet.clipboard")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Spacer()
                    Button(world.primaryAction) { controller.enter(world) }
                        .buttonStyle(WorldButtonStyle(theme: theme))
                }
            }
            .padding(16)
            .foregroundStyle(.white)
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(hovering ? 0.12 : 0.07)))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(hovering ? 0.3 : 0.12)))
        .scaleEffect(hovering && controller.effectiveMotion != .still ? 1.01 : 1)
        .animation(.easeOut(duration: 0.2), value: hovering)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(world.title). \(world.tagline)")
    }
}
