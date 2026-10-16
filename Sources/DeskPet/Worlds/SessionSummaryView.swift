import DeskPetCore
import SwiftUI

/// End-of-session screen: what happened, an optional reflection, and next steps.
/// Ending early is reported plainly, never as a failure.
struct SessionSummaryView: View {
    @ObservedObject var controller: WorldsController
    @ObservedObject var model: AppModel
    @ObservedObject var pet: PetViewModel
    let recordID: UUID
    @State private var reflection = ""
    @State private var markDone = true

    var body: some View {
        if let record = model.record(recordID) {
            content(record)
        } else {
            VStack(spacing: 12) {
                Text("That session isn’t available anymore.")
                Button("Back to worlds") { controller.showSelection() }
            }
        }
    }

    @ViewBuilder
    private func content(_ r: FocusRecord) -> some View {
        let world = r.world.flatMap(FocusWorld.init(rawValue:)) ?? .deepFocus
        let theme = WorldTheme.of(world)
        let minutes = Int((r.activeSeconds / 60).rounded())
        let planned = Int((r.plannedSeconds / 60).rounded())
        let linkedTask = linkedTask(for: r, world: world)

        VStack(spacing: 22) {
            Spacer()
            if controller.settings.showPet {
                WorldPet(world: world, state: r.completed ? .completed : .idle, coat: pet.coat, accessory: pet.accessory,
                         motion: controller.effectiveMotion, pixel: 5, active: controller.windowVisible)
            }
            WorldPanel(theme: theme, padding: 26) {
                Text(title(r, world)).font(theme.display(26, weight: .bold))
                Text(subtitle(r)).font(theme.display(14, weight: .regular)).opacity(0.75)

                HStack(spacing: 28) {
                    stat("\(minutes) min", r.phase.isBreak ? "rested" : "focused", theme)
                    stat("\(planned) min", "planned", theme)
                    if world == .workSprint, let sprint = model.data.worlds.sprint, !sprint.milestones.isEmpty {
                        stat("\(sprint.milestonesDone)/\(sprint.milestones.count)", "milestones", theme)
                    }
                    if world == .study {
                        let today = Worlds.completedSessions(.study, on: Date(), records: model.data.focus.records, calendar: model.calendar)
                        stat("\(today.count)", "study sprints today", theme)
                    }
                }
                .padding(.vertical, 4)

                if let label = r.label {
                    Label(label, systemImage: "scope").font(theme.display(15, weight: .medium))
                }

                if !r.phase.isBreak {
                    Text("What did you accomplish? (optional)").font(theme.display(13, weight: .medium)).opacity(0.8)
                    TextField("A sentence is plenty", text: $reflection, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .accessibilityLabel("What did you accomplish")
                }

                if let task = linkedTask, !task.isCompleted {
                    Toggle("Mark “\(task.title)” complete", isOn: $markDone).toggleStyle(.checkbox)
                }

                HStack(spacing: 10) {
                    if r.phase.isBreak {
                        if let back = (world != .recharge ? world : controller.returnWorld) {
                            Button("Back to \(back.title)") { done(r, task: linkedTask) { controller.enter(back) } }
                                .buttonStyle(WorldButtonStyle(theme: theme))
                        }
                        if world == .recharge {
                            Button("Another break") { done(r, task: linkedTask) { controller.enter(.recharge) } }
                                .buttonStyle(WorldButtonStyle(theme: theme, prominent: controller.returnWorld == nil))
                        }
                    } else {
                        let suggestBreak = controller.settings.sessionEnd == .summaryThenBreak
                        Button("Take a break") { done(r, task: linkedTask) { controller.enter(.recharge) } }
                            .buttonStyle(WorldButtonStyle(theme: theme, prominent: suggestBreak))
                        Button("Start another session") { done(r, task: linkedTask) { controller.enter(world) } }
                            .buttonStyle(WorldButtonStyle(theme: theme, prominent: !suggestBreak))
                    }
                    Spacer()
                    Button("Return to DeskPet") { done(r, task: linkedTask) { controller.close() } }
                        .buttonStyle(WorldButtonStyle(theme: theme, prominent: false))
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: 620)
            Spacer()
        }
        .padding(.horizontal, 32)
        .onAppear { reflection = r.reflection ?? "" }
    }

    private func title(_ r: FocusRecord, _ world: FocusWorld) -> String {
        if r.phase.isBreak { return r.completed ? "Break complete" : "Break ended" }
        if world == .workSprint, let f = model.data.worlds.sprint?.finishedAt, f >= r.start { return "Sprint goal finished!" }
        return r.completed ? "\(world.title) session complete" : "Session ended"
    }

    private func subtitle(_ r: FocusRecord) -> String {
        if r.phase.isBreak { return "Welcome back. Ready when you are." }
        return r.completed ? "Nicely done. Take a moment before the next thing."
                           : "You stopped early — that’s fine. Every focused minute counts."
    }

    private func stat(_ value: String, _ label: String, _ theme: WorldTheme) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(theme.display(22, weight: .bold)).monospacedDigit()
            Text(label).font(theme.display(12, weight: .regular)).opacity(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    /// The real DeskPet task behind this session, if any (sprint objective or matching title).
    private func linkedTask(for r: FocusRecord, world: FocusWorld) -> Item? {
        if world == .workSprint, let id = model.data.worlds.sprint?.taskID, let t = model.data.items.item(id), !t.isDeleted {
            return t
        }
        guard let label = r.label else { return nil }
        return model.data.items.openTasks().first { $0.title.caseInsensitiveCompare(label) == .orderedSame }
    }

    private func done(_ r: FocusRecord, task: Item?, then next: () -> Void) {
        controller.finishSummary(r.id, reflection: reflection)
        if let task, !task.isCompleted, markDone, r.completed || !r.phase.isBreak {
            try? model.setCompleted(task.id, true)
            if model.data.worlds.sprint?.taskID == task.id { model.updateWorlds { $0.sprint = nil } }
        }
        next()
    }
}
