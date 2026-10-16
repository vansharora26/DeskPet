import DeskPetCore
import SwiftUI

/// Work Sprint: everything revolves around one question —
/// "What am I trying to finish?" — with milestones and a clear end.
struct WorkSprintView: View {
    @ObservedObject var controller: WorldsController
    @ObservedObject var model: AppModel
    @ObservedObject var pet: PetViewModel
    @State private var objective = ""
    @State private var linkedTask: UUID?
    @State private var minutes = 45
    @State private var useDeadline = false
    @State private var deadline = Date().addingTimeInterval(3600)
    @State private var milestoneDraft = ""
    @State private var draftMilestones: [ChecklistItem] = []
    @State private var error: String?

    private let world = FocusWorld.workSprint

    var body: some View {
        let theme = WorldTheme.of(world)
        let state = controller.sessionState(for: world)
        ZStack(alignment: .topTrailing) {
            Group {
                if state == .idle {
                    if let t = controller.timer {
                        VStack { Spacer(); BusyNotice(controller: controller, timer: t, theme: theme); Spacer() }
                    } else {
                        setup(theme)
                    }
                } else if let t = controller.timer {
                    running(t, state: state, theme: theme)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if controller.settings.showPet {
                WorldPet(world: world, state: state, coat: pet.coat, accessory: pet.accessory,
                         motion: controller.effectiveMotion, pixel: 4, celebrateUntil: controller.celebrateUntil,
                         active: controller.windowVisible)
                    .padding(.trailing, 40).padding(.top, 8)
            }
        }
        .onAppear {
            minutes = controller.settings.minutes(for: world)
            if let s = model.data.worlds.sprint, s.finishedAt == nil, objective.isEmpty {
                objective = s.objective
                linkedTask = s.taskID
                draftMilestones = s.milestones
            }
        }
    }

    // MARK: Setup

    @ViewBuilder
    private func setup(_ theme: WorldTheme) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("WORK SPRINT").font(.system(size: 12, weight: .heavy)).tracking(3).foregroundStyle(theme.accent)
                Text("What are you trying to finish?").font(.system(size: 38, weight: .heavy))
                TextField("e.g. Send the client proposal", text: $objective)
                    .textFieldStyle(.plain)
                    .font(.system(size: 26, weight: .semibold))
                    .padding(.vertical, 10)
                    .overlay(Rectangle().frame(height: 2).foregroundStyle(theme.accent.opacity(0.6)), alignment: .bottom)
                    .onChange(of: objective) { _, v in
                        if let id = linkedTask, model.data.items.item(id)?.title != v { linkedTask = nil }
                    }
                    .accessibilityLabel("Sprint objective")
                TaskPickerMenu(model: model, theme: theme, title: "Use one of your tasks") { t in
                    objective = t.title
                    linkedTask = t.id
                }

                HStack(alignment: .top, spacing: 24) {
                    WorldPanel(theme: theme) {
                        Text("Time").font(.system(size: 14, weight: .bold))
                        Picker("", selection: $useDeadline) {
                            Text("Duration").tag(false)
                            Text("Finish by").tag(true)
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        if useDeadline {
                            DatePicker("Finish by", selection: $deadline, in: Date()..., displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Text("≈ \(deadlineMinutes) min sprint").font(.system(size: 12)).foregroundStyle(theme.softInk)
                        } else {
                            MinutesPicker(minutes: $minutes, range: world.minuteRange, theme: theme)
                        }
                    }
                    .frame(width: 300)

                    WorldPanel(theme: theme) {
                        Text("Milestones (optional)").font(.system(size: 14, weight: .bold))
                        ForEach(draftMilestones) { m in
                            ChecklistRow(item: m, theme: theme, onToggle: {}, onRemove: {
                                draftMilestones.removeAll { $0.id == m.id }
                            })
                        }
                        HStack {
                            TextField("Add a milestone", text: $milestoneDraft).textFieldStyle(.roundedBorder).onSubmit(addMilestone)
                            Button("Add", action: addMilestone).disabled(milestoneDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }

                Button {
                    start()
                } label: {
                    Label("Start sprint", systemImage: "bolt.fill")
                }
                .buttonStyle(WorldButtonStyle(theme: theme, large: true))
                .disabled(objective.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                if objective.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Name the one thing you want finished — that’s the whole point of a sprint.")
                        .font(.system(size: 12)).foregroundStyle(theme.softInk)
                }
                if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 40).padding(.vertical, 30)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(theme.ink)
    }

    private var deadlineMinutes: Int {
        min(world.minuteRange.upperBound, max(world.minuteRange.lowerBound, Int(deadline.timeIntervalSinceNow / 60)))
    }

    private func addMilestone() {
        let t = milestoneDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        draftMilestones.append(ChecklistItem(title: String(t.prefix(200))))
        milestoneDraft = ""
    }

    private func start() {
        let goal = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else { return }
        let length = useDeadline ? deadlineMinutes : minutes
        model.updateWorlds {
            $0.sprint = SprintPlan(objective: goal, taskID: linkedTask, milestones: draftMilestones,
                                   deadline: useDeadline ? deadline : nil, createdAt: Date())
        }
        error = controller.start(world, minutes: length, label: goal)
        if error == nil, !useDeadline { model.updateWorlds { $0.settings.setMinutes(minutes, for: world) } }
    }

    // MARK: Running

    @ViewBuilder
    private func running(_ t: FocusTimer, state: WorldSessionState, theme: WorldTheme) -> some View {
        let sprint = model.data.worlds.sprint
        VStack(alignment: .leading, spacing: 24) {
            Text("FINISHING").font(.system(size: 12, weight: .heavy)).tracking(3).foregroundStyle(theme.accent)
            Text(t.label ?? sprint?.objective ?? "Your sprint")
                .font(.system(size: 40, weight: .heavy)).lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 24) {
                WorldPanel(theme: theme, padding: 22) {
                    Text("Time left").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.softInk)
                    WorldTimerText(timer: t, theme: theme, size: 72)
                        .opacity(state == .paused ? 0.5 : 1)
                    WorldProgressBar(timer: t, theme: theme, width: 280)
                    Ticking(every: 30) { ctx in
                        Text("\(Int(t.activeSeconds(at: ctx) / 60)) min spent\(sprint?.deadline.map { " · finish by \($0.formatted(date: .omitted, time: .shortened))" } ?? "")")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(theme.softInk)
                    }
                    HStack {
                        if state == .paused {
                            Button("Resume") { controller.resume() }.buttonStyle(WorldButtonStyle(theme: theme))
                                .keyboardShortcut("p", modifiers: .command)
                        } else {
                            Button("Pause") { controller.pause() }.buttonStyle(WorldButtonStyle(theme: theme, prominent: false))
                                .keyboardShortcut("p", modifiers: .command)
                        }
                        Button("End sprint") { controller.endEarly() }.buttonStyle(WorldButtonStyle(theme: theme, prominent: false))
                    }
                    Button {
                        model.updateWorlds { $0.sprint?.finishedAt = Date() }
                        controller.celebrate()
                        controller.endEarly()
                    } label: { Label("I finished it!", systemImage: "flag.checkered") }
                    .buttonStyle(WorldButtonStyle(theme: theme))
                    .help("Wrap up now and see your summary")
                }
                .frame(width: 340)

                WorldPanel(theme: theme, padding: 22) {
                    let milestones = sprint?.milestones ?? []
                    HStack {
                        Text("Milestones").font(.system(size: 14, weight: .bold))
                        Spacer()
                        if !milestones.isEmpty {
                            Text("\(milestones.filter(\.done).count) of \(milestones.count)")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.softInk)
                        }
                    }
                    if !milestones.isEmpty {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(theme.accent.opacity(0.12))
                                Capsule().fill(Color(red: 0.45, green: 0.85, blue: 0.35))
                                    .frame(width: g.size.width * CGFloat(milestones.filter(\.done).count) / CGFloat(milestones.count))
                            }
                        }
                        .frame(height: 8)
                        .animation(.spring(response: 0.4), value: milestones.filter(\.done).count)
                    }
                    if milestones.isEmpty {
                        Text("No milestones — just the one goal. Add steps if it helps.")
                            .font(.system(size: 12)).foregroundStyle(theme.softInk)
                    }
                    ForEach(milestones) { m in
                        ChecklistRow(item: m, theme: theme, onToggle: { toggleMilestone(m) })
                    }
                    HStack {
                        TextField("Add a milestone", text: $milestoneDraft).textFieldStyle(.roundedBorder)
                            .onSubmit(addLiveMilestone)
                        Button("Add", action: addLiveMilestone).disabled(milestoneDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .frame(maxWidth: 420)
            }
            ThoughtCapture(controller: controller, theme: theme)
        }
        .frame(maxWidth: 820, alignment: .leading)
        .padding(.horizontal, 40)
        .foregroundStyle(theme.ink)
    }

    private func toggleMilestone(_ m: ChecklistItem) {
        let nowDone = !m.done
        model.updateWorlds { w in
            if let i = w.sprint?.milestones.firstIndex(where: { $0.id == m.id }) { w.sprint?.milestones[i].done = nowDone }
        }
        if nowDone {
            controller.celebrate()
            controller.showToast("Milestone done: \(m.title)")
        }
    }

    private func addLiveMilestone() {
        let t = milestoneDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        model.updateWorlds { $0.sprint?.milestones.append(ChecklistItem(title: String(t.prefix(200)))) }
        milestoneDraft = ""
    }
}
