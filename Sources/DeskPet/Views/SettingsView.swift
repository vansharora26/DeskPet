import DeskPetCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var pet: PetViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var loginItem: LoginItemManager

    @State private var name = ""
    @State private var confirmingReset = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    CatCanvas(pose: CatPose(eyes: pet.isSleeping ? .closed : .happy, blush: true), pixel: 3)
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .focused($nameFocused)
                            .onSubmit { pet.rename(name) }
                        Text(PetMenu.statusLine(pet))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                StatRow(title: "Happiness", symbol: "heart.fill", value: pet.stats.happiness, tint: .pink)
                StatRow(title: "Energy", symbol: "bolt.fill", value: pet.stats.energy, tint: .yellow)
                StatRow(title: "Hunger", symbol: "fork.knife", value: pet.stats.hunger, tint: .orange)
            } header: {
                Text("Your Pet")
            }

            Section("Behaviour") {
                Toggle("Show pet on desktop", isOn: $settings.petVisible)
                Picker("Size", selection: $settings.petSize) {
                    ForEach(PetSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Animations", isOn: $settings.animationsEnabled)
                if settings.animationsEnabled && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    Text("“Reduce motion” is on in System Settings, so animations stay paused.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Sound effects", isOn: $settings.soundEnabled)
                Toggle("Chatty speech bubbles", isOn: $settings.chattyEnabled)
            }

            Section("System") {
                Toggle("Open DeskPet at login", isOn: Binding(
                    get: { loginItem.isEnabled || loginItem.needsApproval },
                    set: { loginItem.setEnabled($0) }
                ))
                .disabled(!loginItem.isSupported)
                if !loginItem.isSupported {
                    Text("Available when DeskPet is run as an app (use scripts/build-app.sh).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if loginItem.needsApproval {
                    HStack {
                        Text("Allow DeskPet in Login Items to finish.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items…") { loginItem.openSystemSettings() }
                            .controlSize(.small)
                    }
                }
                if let error = loginItem.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Data") {
                if let error = pet.lastSaveError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Text("Stored only on this Mac. DeskPet never collects personal data.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Start Over…", role: .destructive) { confirmingReset = true }
                }
            }

            Section {
                Text("DeskPet \(Self.version)")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            name = pet.name
            loginItem.refresh()
        }
        .onChange(of: nameFocused) { _, focused in if !focused { pet.rename(name) } }
        .onDisappear { pet.rename(name) }
        .confirmationDialog("Start over with a fresh pet?", isPresented: $confirmingReset) {
            Button("Start Over", role: .destructive) { pet.reset() }
        } message: {
            Text("\(pet.name)'s stats will reset. The name is kept.")
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let b = info?["CFBundleVersion"] as? String
        return b.map { "\(v) (\($0))" } ?? v
    }
}

private struct StatRow: View {
    var title: String
    var symbol: String
    var value: Double
    var tint: Color

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
                .frame(width: 110, alignment: .leading)
            ProgressView(value: value, total: 100)
                .tint(tint)
            Text("\(Int(value.rounded()))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
