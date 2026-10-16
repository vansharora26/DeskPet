import DeskPetCore
import SwiftUI

/// Study: a warm room. Left: the sprint timer on the desk. Right: a notebook
/// with topic, checklist (optionally linked to real tasks), notes, and today's sprints.
struct StudyView: View {
    @ObservedObject var controller: WorldsController
    @ObservedObject var model: AppModel
    @ObservedObject var pet: PetViewModel
    @State private var sprintMinutes = 25
    @State private var newItem = ""
    @State private var error: String?

    private let world = FocusWorld.study

    var body: some View {
        let theme = WorldTheme.of(world)
        let state = controller.sessionState(for: world)
        let study = model.data.worlds.study
        let today = Worlds.completedSessions(.study, on: model.now, records: model.data.focus.records, calendar: model.calendar)

        HStack(alignment: .top, spacing: 28) {
            // Desk side: timer + pet
            VStack(spacing: 18) {
                Spacer(minLength: 20)
                WorldPanel(theme: theme, padding: 26) {
                    timerCard(state: state, todayCount: today.count, theme: theme)
                }
                .frame(maxWidth: 420)
                Spacer()
                if controller.settings.showPet {
                    WorldPet(world: world, state: state, coat: pet.coat, accessory: pet.accessory,
                             motion: controller.effectiveMotion, pixel: 5, celebrateUntil: controller.celebrateUntil,
                             active: controller.windowVisible)
                        .padding(.bottom, 40)
                }
            }
            .frame(maxWidth: .infinity)

            // Notebook side
            WorldPanel(theme: theme, padding: 22) {
                Text("Study notebook").font(theme.display(13, weight: .semibold)).opacity(0.6)
                TextField("What are you studying?", text: Binding(
                    get: { study.topic }, set: { v in model.updateWorlds { $0.study.topic = String(v.prefix(200)) } }))
                    .textFieldStyle(.plain)
                    .font(theme.display(22, weight: .semibold))
                    .accessibilityLabel("Study topic")

                Divider()
                HStack {
                    Text("Checklist").font(theme.display(14, weight: .semibold))
                    Spacer()
                    if !study.checklist.isEmpty {
                        Text("\(study.checklist.filter(\.done).count) of \(study.checklist.count)")
                            .font(theme.display(12, weight: .regular)).opacity(0.6)
                    }
                }
                if study.checklist.isEmpty {
                    Text("Break the session into small steps — “read 5.2”, “do Q1–6”.")
                        .font(theme.display(12, weight: .regular)).opacity(0.6)
                }
                ForEach(study.checklist) { item in
                    ChecklistRow(item: item, theme: theme, onToggle: { toggle(item) }, onRemove: {
                        model.updateWorlds { $0.study.checklist.removeAll { $0.id == item.id } }
                    })
                }
                HStack {
                    TextField("Add a step", text: $newItem).textFieldStyle(.roundedBorder).onSubmit(addItem)
                    Button("Add", action: addItem).disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                    TaskPickerMenu(model: model, theme: theme, title: "From tasks") { t in
                        model.updateWorlds { w in
                            if !w.study.checklist.contains(where: { $0.taskID == t.id }) {
                                w.study.checklist.append(ChecklistItem(title: t.title, taskID: t.id))
                            }
                        }
                    }
                }

                Divider()
                HStack {
                    Text("Session notes").font(theme.display(14, weight: .semibold))
                    Spacer()
                    Button("Save to Notes") { saveNotes() }
                        .buttonStyle(.link)
                        .disabled(study.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Keep these notes in DeskPet Notes")
                }
                TextEditor(text: Binding(get: { study.notes }, set: { v in model.updateWorlds { $0.study.notes = v } }))
                    .font(.system(size: 14, design: .serif))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(theme.panelInk.opacity(0.05)))
                    .accessibilityLabel("Session notes")

                Divider()
                Text("Today’s study sprints").font(theme.display(14, weight: .semibold))
                if today.isEmpty {
                    Text("None yet — your first one is waiting.").font(theme.display(12, weight: .regular)).opacity(0.6)
                }
                ForEach(today.suffix(6).reversed()) { r in
                    HStack(alignment: .top) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(theme.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(Int((r.activeSeconds / 60).rounded())) min · \(r.end.formatted(date: .omitted, time: .shortened))")
                                .font(theme.display(12, weight: .medium))
                            if let reflection = r.reflection {
                                Text(reflection).font(theme.display(12, weight: .regular)).opacity(0.7).lineLimit(2)
                            }
                        }
                    }
                }
            }
            .frame(width: 420)
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 40)
        .padding(.top, 10)
        .onAppear { sprintMinutes = controller.settings.minutes(for: world) }
    }

    @ViewBuilder
    private func timerCard(state: WorldSessionState, todayCount: Int, theme: WorldTheme) -> some View {
        let t = controller.timer
        if state == .idle {
            if let t {
                Text(t.phase.isBreak ? "A break is running elsewhere" : "A session is running elsewhere")
                    .font(theme.display(16))
                Button("Go to it") { controller.enter(controller.timerWorld ?? .deepFocus) }
                    .buttonStyle(WorldButtonStyle(theme: theme))
            } else {
                Text("Sprint \(todayCount + 1) today").font(theme.display(13, weight: .semibold)).opacity(0.6)
                Text("\(sprintMinutes):00").font(theme.timerFont(64))
                MinutesPicker(minutes: $sprintMinutes, range: world.minuteRange, theme: theme)
                HStack {
                    Button("Start study sprint") { startSprint() }
                        .buttonStyle(WorldButtonStyle(theme: theme, large: true))
                        .keyboardShortcut(.return, modifiers: .command)
                    Button("Break (\(model.focusSettings.shortBreakMinutes) min)") {
                        error = controller.startBreak(in: world, minutes: model.focusSettings.shortBreakMinutes)
                    }
                    .buttonStyle(WorldButtonStyle(theme: theme, prominent: false))
                }
                Stepper("Break length: \(model.focusSettings.shortBreakMinutes) min",
                        value: Binding(get: { model.focusSettings.shortBreakMinutes },
                                       set: { v in model.updateFocusSettings { $0.shortBreakMinutes = v } }),
                        in: FocusSettings.breakRange)
                    .font(theme.display(12, weight: .regular))
                if let error { Text(error).font(theme.display(12)).foregroundStyle(.red) }
            }
        } else if let t {
            let isBreak = t.phase.isBreak
            Text(isBreak ? "Break — stretch, sip, look away" : (t.label ?? "Study sprint"))
                .font(theme.display(15, weight: .semibold)).opacity(0.75).lineLimit(2)
            WorldTimerText(timer: t, theme: theme, size: 64)
                .opacity(state == .paused ? 0.5 : 1)
            WorldProgressBar(timer: t, theme: theme, width: 300)
            HStack {
                if state == .paused {
                    Button("Resume") { controller.resume() }.buttonStyle(WorldButtonStyle(theme: theme))
                        .keyboardShortcut("p", modifiers: .command)
                } else {
                    Button("Pause") { controller.pause() }.buttonStyle(WorldButtonStyle(theme: theme, prominent: false))
                        .keyboardShortcut("p", modifiers: .command)
                }
                Button(isBreak ? "End break" : "End sprint") { controller.endEarly() }
                    .buttonStyle(WorldButtonStyle(theme: theme, prominent: false))
            }
        }
    }

    private func startSprint() {
        let topic = model.data.worlds.study.topic.trimmingCharacters(in: .whitespaces)
        error = controller.start(world, minutes: sprintMinutes, label: topic.isEmpty ? "Study sprint" : topic)
        if error == nil { model.updateWorlds { $0.settings.setMinutes(sprintMinutes, for: world) } }
    }

    private func addItem() {
        let t = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        model.updateWorlds { $0.study.checklist.append(ChecklistItem(title: String(t.prefix(200)))) }
        newItem = ""
    }

    private func toggle(_ item: ChecklistItem) {
        let nowDone = !item.done
        model.updateWorlds { w in
            if let i = w.study.checklist.firstIndex(where: { $0.id == item.id }) { w.study.checklist[i].done = nowDone }
        }
        if let id = item.taskID { try? model.setCompleted(id, nowDone) }
        if nowDone { controller.celebrate() }
    }

    private func saveNotes() {
        let study = model.data.worlds.study
        let body = (study.topic.isEmpty ? "Study notes" : "Study notes — \(study.topic)") + "\n" + study.notes
        if (try? model.addItem(body, kind: .note)) != nil {
            model.updateWorlds { $0.study.notes = "" }
            controller.showToast("Saved to DeskPet Notes")
        }
    }
}

/// A checklist line shared by Study, Work Sprint and Planning.
struct ChecklistRow: View {
    let item: ChecklistItem
    let theme: WorldTheme
    var onToggle: () -> Void
    var onRemove: (() -> Void)?
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(item.done ? theme.accent : theme.panelInk.opacity(0.45))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? "Mark \(item.title) not done" : "Mark \(item.title) done")
            Text(item.title)
                .font(theme.display(14, weight: .regular))
                .strikethrough(item.done)
                .opacity(item.done ? 0.55 : 1)
                .lineLimit(2)
            if item.taskID != nil {
                Image(systemName: "link").font(.system(size: 10)).opacity(0.4).help("Linked to a DeskPet task")
            }
            Spacer(minLength: 0)
            if let trailing { trailing }
            if let onRemove {
                Button(action: onRemove) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain).opacity(0.4)
                    .accessibilityLabel("Remove \(item.title)")
            }
        }
    }
}
