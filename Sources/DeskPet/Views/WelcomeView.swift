import SwiftUI

/// First-launch introduction. Also reachable later via "Welcome Tour".
struct WelcomeView: View {
    @ObservedObject var pet: PetViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var loginItem: LoginItemManager
    var onFinish: () -> Void

    @State private var name = ""

    var body: some View {
        VStack(spacing: 18) {
            WelcomeCat()
                .offset(x: 9) // centre the body rather than body + tail
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text("Meet your DeskPet")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("A tiny friend who hangs out on your desktop while you work.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Text("Name").foregroundStyle(.secondary)
                TextField("Biscuit", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit(finish)
            }

            VStack(alignment: .leading, spacing: 10) {
                Tip(symbol: "hand.tap.fill", text: "**Click** to pet. **Drag** to move anywhere.")
                Tip(symbol: "cursorarrow.motionlines", text: "**Hover** for Feed, Play, Nap and Settings.")
                Tip(symbol: "contextualmenu.and.cursorarrow", text: "**Right-click** to see how your pet is feeling.")
                Tip(symbol: "pawprint.fill", text: "The **paw** in the menu bar shows or hides your pet.")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.5)))

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Sound effects", isOn: $settings.soundEnabled)
                Toggle("Open at login", isOn: Binding(
                    get: { loginItem.isEnabled || loginItem.needsApproval },
                    set: { loginItem.setEnabled($0) }))
                    .disabled(!loginItem.isSupported)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: finish) {
                Text("Let's go!").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(PixelPalette.stripe)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 400)
        .onAppear { name = pet.name; loginItem.refresh() }
    }

    private func finish() {
        pet.rename(name)
        onFinish()
    }
}

/// Waving hello. Updates only when the pose actually changes, to stay light.
private struct WelcomeCat: View {
    @State private var pose = WelcomeCat.pose(at: Date())
    private let timer = Timer.publish(every: 1.0 / 6.0, tolerance: 0.03, on: .main, in: .common).autoconnect()

    static func pose(at date: Date) -> CatPose {
        let t = date.timeIntervalSinceReferenceDate
        return CatPose(eyes: PetAnimator.isBlinking(t) ? .blink : .happy,
                       mouthOpen: true, blush: true, tailFrame: Int(t / 0.5) % 2)
    }

    var body: some View {
        CatCanvas(pose: pose, pixel: 6)
            .onReceive(timer) { date in
                let next = Self.pose(at: date)
                if next != pose { pose = next }
            }
    }
}

private struct Tip: View {
    var symbol: String
    var text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(PixelPalette.stripe)
            Text(text)
        }
    }
}
