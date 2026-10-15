import DeskPetCore
import SwiftUI

/// Spotlight-style capture: type, press Return. Notes by default; ⌘T makes it
/// a task, and dates in the text ("tomorrow 5pm") become the deadline.
struct QuickCaptureView: View {
    @ObservedObject var model: AppModel
    var onClose: () -> Void
    @State private var text = ""
    @State private var asTask = false
    @State private var pinned = false
    @State private var ignoreDate = false
    @State private var saved: String?
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        let detected = asTask && !ignoreDate ? NaturalDate.extract(from: text, now: Date(), calendar: model.calendar) : nil

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: asTask ? "checkmark.circle" : "square.and.pencil")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(DP.accent)
                TextField(asTask ? "New task…" : "Capture an idea…", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .lineLimit(1...6)
                    .focused($focused)
                    .onSubmit(save)
                    .accessibilityLabel(asTask ? "New task" : "New note")
            }
            HStack(spacing: 6) {
                Toggle(isOn: $asTask) { Text("Task") }.toggleStyle(.button).keyboardShortcut("t", modifiers: .command)
                Toggle(isOn: $pinned) { Image(systemName: "pin") }.toggleStyle(.button).keyboardShortcut("p", modifiers: .command)
                    .help("Pin (⌘P)").accessibilityLabel("Pin")
                if let d = detected, !d.remainder.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        Text("Due \(AppCommand.formatDate(d.date, hasTime: d.hasTime, calendar: model.calendar))")
                        Button { ignoreDate = true } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                            .accessibilityLabel("Ignore detected date")
                    }
                    .font(DP.caption).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(DP.accent.opacity(0.12)))
                }
                Spacer()
                if let saved {
                    Label(saved, systemImage: "checkmark.circle.fill").font(DP.caption).foregroundStyle(DP.mint)
                } else if let error {
                    Text(error).font(DP.caption).foregroundStyle(DP.danger)
                } else {
                    Text("↩ save · ⌘T task · esc close").font(DP.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(16)
        .frame(width: 520)
        .background(.regularMaterial)
        .onAppear { focused = true }
        .onExitCommand(perform: onClose)
        .onChange(of: text) { _, _ in error = nil; ignoreDate = false }
        .dpPanelStyle()
    }

    private func save() {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { onClose(); return }
        do {
            if asTask {
                var title = raw, due: Date?, hasTime = false
                if !ignoreDate, let d = NaturalDate.extract(from: raw, now: Date(), calendar: model.calendar), !d.remainder.isEmpty {
                    (title, due, hasTime) = (d.remainder, d.date, d.hasTime)
                }
                _ = try model.addItem(title, kind: .task, due: due, dueHasTime: hasTime, pinned: pinned)
                saved = "Task saved"
            } else {
                _ = try model.addItem(raw, kind: .note, pinned: pinned)
                saved = "Note saved"
            }
            text = ""
            pinned = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                saved = nil
                onClose()
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn't save."
        }
    }
}
