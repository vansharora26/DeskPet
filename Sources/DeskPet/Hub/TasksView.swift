import DeskPetCore
import SwiftUI

/// Tasks (Inbox / Today / Upcoming / Completed) and Notes, with search, quick
/// add, inline editing, pinning, and soft delete with undo / recovery.
struct TasksView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var hub: HubState
    @State private var newText = ""
    @State private var editing: Item?
    @State private var showTrash = false
    @FocusState private var addFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("", selection: $hub.showNotes) {
                    Text("Tasks").tag(false)
                    Text("Notes").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                Spacer()
                TextField("Search", text: $hub.search).textFieldStyle(.roundedBorder).frame(width: 150)
                    .accessibilityLabel("Search notes and tasks")
            }
            if !hub.showNotes && hub.search.isEmpty {
                Picker("", selection: $hub.taskFilter) {
                    ForEach(TaskFilter.allCases, id: \.self) { f in
                        Text("\(f.title)\(count(f).map { " \($0)" } ?? "")").tag(f)
                    }
                }
                .pickerStyle(.segmented).labelsHidden()
            }

            HStack {
                TextField(hub.showNotes ? "New note…" : "New task… (try “call Sam tomorrow 5pm”)", text: $newText)
                    .textFieldStyle(.roundedBorder)
                    .focused($addFocused)
                    .onSubmit(add)
                Button(action: add) { Image(systemName: "plus.circle.fill").font(.title3) }
                    .buttonStyle(.plain).foregroundStyle(DP.accent).disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel(hub.showNotes ? "Add note" : "Add task")
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    let list = items
                    if list.isEmpty {
                        EmptyState(symbol: hub.showNotes ? "note.text" : "checkmark.circle",
                                   title: emptyTitle, message: emptyMessage)
                    }
                    ForEach(list) { item in
                        if item.isTask {
                            TaskRow(item: item, model: model, hub: hub, onEdit: { editing = item })
                        } else {
                            NoteRow(item: item, model: model, hub: hub, onEdit: { editing = item })
                        }
                    }
                    if !model.data.items.trash.isEmpty {
                        Button("Recently deleted (\(model.data.items.trash.count))") { showTrash = true }
                            .buttonStyle(.link).font(DP.caption).padding(.top, 8)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 16)
        .sheet(item: $editing) { item in
            ItemEditor(item: item, model: model, onDone: { editing = nil })
        }
        .sheet(isPresented: $showTrash) { TrashView(model: model, onDone: { showTrash = false }) }
    }

    private var items: [Item] {
        if !hub.search.isEmpty {
            return model.data.items.search(hub.search).filter { hub.showNotes ? !$0.isTask : $0.isTask }
        }
        if hub.showNotes { return model.data.items.notes() }
        return model.data.items.tasks(hub.taskFilter, now: model.now, calendar: model.calendar)
    }

    private func count(_ f: TaskFilter) -> Int? {
        guard f != .completed else { return nil }
        let n = model.data.items.tasks(f, now: model.now, calendar: model.calendar).count
        return n > 0 ? n : nil
    }

    private var emptyTitle: String {
        if !hub.search.isEmpty { return "No matches" }
        if hub.showNotes { return "No notes yet" }
        switch hub.taskFilter {
        case .inbox: return "Inbox zero"
        case .today: return "Nothing due today"
        case .upcoming: return "Nothing scheduled"
        case .completed: return "No completed tasks yet"
        }
    }

    private var emptyMessage: String {
        hub.showNotes ? "Capture ideas with ⌃⌥N from anywhere." : "Add one above, or press ⌃⌥N to capture from anywhere."
    }

    private func add() {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            if hub.showNotes {
                let item = try model.addItem(text, kind: .note)
                hub.feedback = CommandResult(style: .success, message: "Note saved", undo: { [model] in try? model.deleteItem(item.id) })
            } else {
                // Natural dates in the text become the deadline.
                var title = text
                var due: Date?
                var hasTime = false
                if let p = NaturalDate.extract(from: text, now: Date(), calendar: model.calendar), !p.remainder.isEmpty {
                    (title, due, hasTime) = (p.remainder, p.date, p.hasTime)
                } else if hub.taskFilter == .today {
                    due = model.calendar.startOfDay(for: Date())
                }
                let item = try model.addItem(title, kind: .task, due: due, dueHasTime: hasTime)
                var msg = "Task added"
                if let due { msg += " · due \(AppCommand.formatDate(due, hasTime: hasTime, calendar: model.calendar))" }
                hub.feedback = CommandResult(style: .success, message: msg, undo: { [model] in try? model.deleteItem(item.id) })
            }
            newText = ""
        } catch {
            hub.feedback = .error((error as? LocalizedError)?.errorDescription ?? "Couldn't save.")
        }
    }
}

struct TaskRow: View {
    var item: Item
    @ObservedObject var model: AppModel
    @ObservedObject var hub: HubState
    var compact = false
    var onEdit: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                try? model.setCompleted(item.id, !item.isCompleted)
                if !item.isCompleted {
                    hub.feedback = CommandResult(style: .success, message: "Completed “\(item.title)”",
                                                 undo: { [model] in try? model.setCompleted(item.id, false) })
                }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16)).foregroundStyle(item.isCompleted ? DP.mint : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "Mark \(item.title) not done" : "Complete \(item.title)")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(DP.body).strikethrough(item.isCompleted).lineLimit(compact ? 1 : 2)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                HStack(spacing: 6) {
                    if let due = item.due {
                        let overdue = !item.isCompleted && (item.dueHasTime ? due < Date() : due < model.calendar.startOfDay(for: Date()))
                        Label(AppCommand.formatDate(due, hasTime: item.dueHasTime, calendar: model.calendar), systemImage: "calendar")
                            .foregroundStyle(overdue ? DP.danger : .secondary)
                    }
                    if let r = item.remindAt, !item.reminderFired, !item.isCompleted {
                        Label(r.formatted(date: .omitted, time: .shortened), systemImage: "alarm").foregroundStyle(.secondary)
                    }
                }
                .font(DP.caption)
            }
            Spacer(minLength: 0)
            if item.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(DP.accent) }
            if !compact { ItemMenu(item: item, model: model, hub: hub, onEdit: onEdit) }
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(compact ? 0 : 0.035)))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onEdit?() }
    }
}

struct NoteRow: View {
    var item: Item
    @ObservedObject var model: AppModel
    @ObservedObject var hub: HubState
    var onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.isPinned ? "pin.fill" : "note.text")
                .foregroundStyle(item.isPinned ? DP.accent : .secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text).font(DP.body).lineLimit(4)
                Text(item.updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(DP.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            ItemMenu(item: item, model: model, hub: hub, onEdit: onEdit)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.035)))
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
    }
}

private struct ItemMenu: View {
    var item: Item
    @ObservedObject var model: AppModel
    @ObservedObject var hub: HubState
    var onEdit: (() -> Void)?

    var body: some View {
        Menu {
            if let onEdit { Button("Edit…", action: onEdit) }
            Button(item.isPinned ? "Unpin" : "Pin") { try? model.updateItem(item.id) { $0.isPinned.toggle() } }
            if item.isTask {
                Button("Convert to note") { try? model.updateItem(item.id) { $0.kind = .note; $0.completedAt = nil } }
                Button("Due today") { try? model.updateItem(item.id) { $0.due = model.calendar.startOfDay(for: Date()); $0.dueHasTime = false } }
                Button("Due tomorrow") {
                    try? model.updateItem(item.id) {
                        $0.due = model.calendar.date(byAdding: .day, value: 1, to: model.calendar.startOfDay(for: Date()))
                        $0.dueHasTime = false
                    }
                }
                if item.due != nil { Button("Clear deadline") { try? model.updateItem(item.id) { $0.due = nil; $0.dueHasTime = false } } }
            } else {
                Button("Make it a task") { try? model.updateItem(item.id) { $0.kind = .task } }
            }
            Divider()
            Button("Delete", role: .destructive) {
                try? model.deleteItem(item.id)
                hub.feedback = CommandResult(style: .info, message: "Deleted “\(item.title.prefix(40))”",
                                             undo: { [model] in try? model.restoreItem(item.id) })
            }
        } label: {
            Image(systemName: "ellipsis").frame(width: 20, height: 20)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Options for \(item.title)")
    }
}

/// Edit text, kind, deadline, reminder and pin in one small sheet.
struct ItemEditor: View {
    let item: Item
    @ObservedObject var model: AppModel
    var onDone: () -> Void
    @State private var text = ""
    @State private var isTask = false
    @State private var pinned = false
    @State private var hasDue = false
    @State private var due = Date()
    @State private var dueHasTime = false
    @State private var hasReminder = false
    @State private var remindAt = Date().addingTimeInterval(3600)
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isTask ? "Edit task" : "Edit note").font(DP.title(16))
            TextEditor(text: $text).font(DP.body).frame(minHeight: 90)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
            Toggle("Task", isOn: $isTask)
            Toggle("Pinned", isOn: $pinned)
            if isTask {
                Toggle("Deadline", isOn: $hasDue)
                if hasDue {
                    HStack {
                        DatePicker("", selection: $due, displayedComponents: dueHasTime ? [.date, .hourAndMinute] : [.date]).labelsHidden()
                        Toggle("Time", isOn: $dueHasTime)
                    }
                }
                Toggle("Reminder", isOn: $hasReminder)
                if hasReminder {
                    DatePicker("", selection: $remindAt, in: Date()..., displayedComponents: [.date, .hourAndMinute]).labelsHidden()
                }
            }
            if let error { Text(error).font(DP.caption).foregroundStyle(DP.danger) }
            HStack {
                Spacer()
                Button("Cancel", action: onDone).keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 380)
        .onAppear {
            text = item.text
            isTask = item.isTask
            pinned = item.isPinned
            hasDue = item.due != nil
            due = item.due ?? model.calendar.startOfDay(for: Date())
            dueHasTime = item.dueHasTime
            hasReminder = item.remindAt != nil && !item.reminderFired
            remindAt = item.remindAt ?? Date().addingTimeInterval(3600)
        }
    }

    private func save() {
        if isTask && hasReminder && remindAt <= Date() { error = "Pick a reminder time in the future."; return }
        do {
            try model.updateItem(item.id) { i in
                i.text = text
                i.kind = isTask ? .task : .note
                i.isPinned = pinned
                i.due = isTask && hasDue ? (dueHasTime ? due : model.calendar.startOfDay(for: due)) : nil
                i.dueHasTime = isTask && hasDue && dueHasTime
                i.remindAt = isTask && hasReminder ? remindAt : nil
                if !isTask { i.completedAt = nil }
            }
            onDone()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn't save."
        }
    }
}

/// Recently deleted items: restore or remove permanently. Auto-purged after 30 days.
struct TrashView: View {
    @ObservedObject var model: AppModel
    var onDone: () -> Void
    @State private var confirmEmpty = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recently deleted").font(DP.title(16))
            Text("Items are removed for good after 30 days.").font(DP.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.data.items.trash) { item in
                        HStack {
                            Text(item.title).lineLimit(1)
                            Spacer()
                            Button("Restore") { try? model.restoreItem(item.id) }.buttonStyle(PillButtonStyle(filled: false))
                        }
                    }
                }
            }
            .frame(height: 220)
            HStack {
                Button("Empty trash…", role: .destructive) { confirmEmpty = true }
                    .disabled(model.data.items.trash.isEmpty)
                Spacer()
                Button("Done", action: onDone).keyboardShortcut(.defaultAction)
            }
        }
        .padding(18).frame(width: 380)
        .confirmationDialog("Permanently delete \(model.data.items.trash.count) items?", isPresented: $confirmEmpty) {
            Button("Delete permanently", role: .destructive) { model.emptyTrash() }
        }
    }
}
