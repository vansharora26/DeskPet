import DeskPetCore
import SwiftUI

/// Daily Planning: choose up to three outcomes from what you already have,
/// size them to your available time, start one, and review at the end of the day.
struct PlanningView: View {
    @ObservedObject var controller: WorldsController
    @ObservedObject var model: AppModel
    @ObservedObject var pet: PetViewModel
    @State private var draft = ""
    @State private var showReview = false
    @State private var reviewText = ""
    @State private var error: String?

    private let world = FocusWorld.planning

    private var dayKey: String { model.calendar.dayKey(model.now) }
    private var plan: DayPlan { model.data.worlds.plan(for: dayKey) ?? DayPlan(dayKey: dayKey) }

    var body: some View {
        let theme = WorldTheme.of(world)
        let p = plan
        let full = p.priorities.count >= DayPlan.maxPriorities
        let focusMin = model.data.worlds.settings.minutes(for: .deepFocus)
        let sessions = Worlds.estimatedSessions(hours: p.availableHours, focusMinutes: focusMin,
                                                breakMinutes: model.focusSettings.shortBreakMinutes)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .bottom, spacing: 16) {
                    if controller.settings.showPet {
                        WorldPet(world: world, state: .idle, coat: pet.coat, accessory: pet.accessory,
                                 motion: controller.effectiveMotion, pixel: 4, celebrateUntil: controller.celebrateUntil,
                                 active: controller.windowVisible)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(theme.display(14, weight: .semibold)).foregroundStyle(theme.accent)
                        Text(p.priorities.isEmpty ? "What matters most today?" : "Today’s plan")
                            .font(theme.display(32, weight: .bold))
                        Text("Pick up to three outcomes. Everything else can wait.")
                            .font(theme.display(14, weight: .regular)).foregroundStyle(theme.softInk)
                    }
                }

                HStack(alignment: .top, spacing: 20) {
                    // Today's three
                    WorldPanel(theme: theme, padding: 20) {
                        Text("Today’s three").font(theme.display(16, weight: .bold))
                        ForEach(Array(p.priorities.enumerated()), id: \.element.id) { i, item in
                            HStack(alignment: .center, spacing: 10) {
                                Text("\(i + 1)").font(theme.display(18, weight: .heavy)).foregroundStyle(theme.accent).frame(width: 18)
                                ChecklistRow(item: item, theme: theme, onToggle: { toggle(item) }, onRemove: { remove(item) },
                                             trailing: item.done ? nil : AnyView(
                                                Button("Start") { startSprint(on: item) }
                                                    .buttonStyle(WorldButtonStyle(theme: theme))
                                                    .help("Start a Work Sprint on this now")))
                            }
                        }
                        if p.priorities.isEmpty {
                            Text("Nothing chosen yet. Add one below, or pick from your tasks.")
                                .font(theme.display(13, weight: .regular)).opacity(0.6)
                        }
                        if full {
                            Label("Three is plenty. Finish one before adding more.", systemImage: "sparkles")
                                .font(theme.display(12, weight: .medium)).foregroundStyle(theme.accent)
                        } else {
                            HStack {
                                TextField("Add an outcome for today", text: $draft).textFieldStyle(.roundedBorder).onSubmit(addDraft)
                                Button("Add", action: addDraft).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        if let error { Text(error).font(theme.display(12)).foregroundStyle(.red) }
                    }
                    .frame(maxWidth: 440)

                    VStack(spacing: 20) {
                        // Time available
                        WorldPanel(theme: theme, padding: 20) {
                            Text("Your time").font(theme.display(16, weight: .bold))
                            HStack {
                                Slider(value: Binding(get: { p.availableHours },
                                                      set: { v in update { $0.availableHours = (v * 2).rounded() / 2 } }),
                                       in: 0.5...12)
                                    .accessibilityLabel("Hours available for focused work")
                                Text(String(format: "%.1f h", p.availableHours)).font(theme.display(14, weight: .semibold)).monospacedDigit()
                                    .frame(width: 50)
                            }
                            Text("≈ \(sessions) focus session\(sessions == 1 ? "" : "s") of \(focusMin) min, with \(model.focusSettings.shortBreakMinutes)-min breaks.")
                                .font(theme.display(13, weight: .regular)).opacity(0.75)
                            if p.priorities.count > sessions && sessions > 0 {
                                Text("That’s a full day — consider trimming a priority.")
                                    .font(theme.display(12, weight: .medium)).foregroundStyle(theme.accent)
                            }
                        }
                        // Notes
                        WorldPanel(theme: theme, padding: 20) {
                            Text("Notes for today").font(theme.display(16, weight: .bold))
                            TextEditor(text: Binding(get: { p.notes }, set: { v in update { $0.notes = v } }))
                                .font(theme.display(13, weight: .regular))
                                .scrollContentBackground(.hidden)
                                .frame(height: 80)
                                .padding(4)
                                .background(RoundedRectangle(cornerRadius: 8).fill(theme.panelInk.opacity(0.04)))
                                .accessibilityLabel("Notes for today")
                        }
                    }
                    .frame(maxWidth: 360)
                }

                // Existing tasks & deadlines
                WorldPanel(theme: theme, padding: 20) {
                    HStack {
                        Text("From your tasks").font(theme.display(16, weight: .bold))
                        Spacer()
                        Text("No calendar access — deadlines come from your DeskPet tasks.")
                            .font(theme.display(11, weight: .regular)).opacity(0.55)
                    }
                    let candidates = taskCandidates
                    if candidates.isEmpty {
                        Text("No open tasks. Add outcomes above — they’ll be saved as tasks due today.")
                            .font(theme.display(13, weight: .regular)).opacity(0.6)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 10, alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(candidates) { t in
                            HStack {
                                Button { addTask(t) } label: { Image(systemName: "plus.circle.fill").font(.system(size: 16)) }
                                    .buttonStyle(.plain).foregroundStyle(full ? theme.panelInk.opacity(0.3) : theme.accent)
                                    .disabled(full || p.priorities.contains { $0.taskID == t.id })
                                    .accessibilityLabel("Add \(t.title) to today's three")
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(t.title).font(theme.display(13, weight: .medium)).lineLimit(1)
                                    if let due = t.due {
                                        let overdue = t.dueHasTime ? due < Date() : due < model.calendar.startOfDay(for: Date())
                                        Text(overdue ? "Overdue · \(AppCommand.formatDate(due, hasTime: t.dueHasTime, calendar: model.calendar))"
                                                     : "Due \(AppCommand.formatDate(due, hasTime: t.dueHasTime, calendar: model.calendar))")
                                            .font(theme.display(11, weight: .regular))
                                            .foregroundStyle(overdue ? .red : theme.panelInk.opacity(0.6))
                                    }
                                }
                            }
                        }
                    }
                }

                // End-of-day review
                WorldPanel(theme: theme, padding: 20) {
                    HStack {
                        Text("End-of-day review").font(theme.display(16, weight: .bold))
                        Spacer()
                        if let at = p.reviewedAt {
                            Text("Reviewed \(at.formatted(date: .omitted, time: .shortened))").font(theme.display(11, weight: .regular)).opacity(0.6)
                        }
                        Button(showReview ? "Hide" : "Review my day") {
                            showReview.toggle()
                            reviewText = p.review ?? ""
                        }
                        .buttonStyle(WorldButtonStyle(theme: theme, prominent: !showReview))
                    }
                    if showReview {
                        let done = p.priorities.filter { isDone($0) }.count
                        let focus = Focus.day(model.now, records: model.data.focus.records, calendar: model.calendar)
                        Text("\(done) of \(p.priorities.count) priorities done · \(focus.sessionsCompleted) focus sessions (\(focus.focusMinutes) min) · \(AppCommand.formatML(model.todayWaterML)) water")
                            .font(theme.display(13, weight: .medium))
                        ForEach(p.priorities) { item in
                            Label(item.title, systemImage: isDone(item) ? "checkmark.circle.fill" : "circle")
                                .font(theme.display(13, weight: .regular))
                                .foregroundStyle(isDone(item) ? theme.accent : theme.panelInk.opacity(0.7))
                        }
                        TextField("Anything to carry into tomorrow? (optional)", text: $reviewText, axis: .vertical)
                            .textFieldStyle(.roundedBorder).lineLimit(1...4)
                        Button("Save review") {
                            update { $0.review = reviewText.trimmingCharacters(in: .whitespacesAndNewlines); $0.reviewedAt = Date() }
                            controller.showToast("Review saved. Good work today.")
                            showReview = false
                        }
                        .buttonStyle(WorldButtonStyle(theme: theme))
                    }
                }
            }
            .frame(maxWidth: 840, alignment: .leading)
            .padding(.horizontal, 40).padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(theme.ink)
    }

    // MARK: Data

    private var taskCandidates: [Item] {
        let items = model.data.items
        let overdue = items.overdue(now: Date(), calendar: model.calendar)
        let today = items.tasks(.today, now: Date(), calendar: model.calendar)
        let upcoming = items.tasks(.upcoming, now: Date(), calendar: model.calendar)
        let inbox = items.tasks(.inbox, now: Date(), calendar: model.calendar)
        // Already-chosen priorities aren't offered again.
        var seen = Set(plan.priorities.compactMap(\.taskID))
        return (overdue + today + upcoming.prefix(6) + inbox.prefix(6)).filter { seen.insert($0.id).inserted }
    }

    private func update(_ change: (inout DayPlan) -> Void) {
        model.updateWorlds { $0.updatePlan(for: dayKey, change) }
    }

    private func isDone(_ item: ChecklistItem) -> Bool {
        if let id = item.taskID, let t = model.data.items.item(id) { return t.isCompleted }
        return item.done
    }

    /// Free-text outcomes become real DeskPet tasks due today, so they show up everywhere.
    private func addDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, plan.priorities.count < DayPlan.maxPriorities else { return }
        do {
            let task = try model.addItem(text, kind: .task, due: model.calendar.startOfDay(for: Date()))
            update { _ = $0.addPriority(task.title, taskID: task.id) }
            draft = ""
            error = nil
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn’t add that."
        }
    }

    private func addTask(_ t: Item) {
        update { _ = $0.addPriority(t.title, taskID: t.id) }
    }

    private func toggle(_ item: ChecklistItem) {
        let nowDone = !isDone(item)
        if let id = item.taskID { try? model.setCompleted(id, nowDone) }
        update { p in if let i = p.priorities.firstIndex(where: { $0.id == item.id }) { p.priorities[i].done = nowDone } }
        if nowDone { controller.celebrate() }
    }

    private func remove(_ item: ChecklistItem) {
        update { $0.priorities.removeAll { $0.id == item.id } }
    }

    /// Starts a Work Sprint on a priority immediately.
    private func startSprint(on item: ChecklistItem) {
        model.updateWorlds { $0.sprint = SprintPlan(objective: item.title, taskID: item.taskID, createdAt: Date()) }
        controller.enter(.workSprint)
        if let msg = controller.start(.workSprint, minutes: controller.settings.minutes(for: .workSprint), label: item.title) {
            controller.showToast(msg)
        }
    }
}
