import DeskPetCore
import SwiftUI

/// Keyboard-first command palette. Understands natural language locally;
/// shows exactly what will happen before it runs; hands open questions to AI.
struct LauncherView: View {
    @ObservedObject var model: AppModel
    var aiReady: () -> Bool
    var onOpen: (Destination) -> Void
    var onAskAI: (String) -> Void
    var onOpenItem: (Item) -> Void
    var onClose: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @State private var result: CommandResult?
    @State private var armedConfirm: String?
    @FocusState private var focused: Bool

    private struct Row: Identifiable {
        enum Kind { case command(AppCommand), template(String), item(Item), askAI(String), setupAI, choice(Item) }
        let id: String
        var kind: Kind
        var symbol: String
        var title: String
        var subtitle: String?
    }

    private static let templates: [(String, String)] = [
        ("drop.fill", "Water 250 ml"), ("timer", "Focus for 25 minutes"), ("checklist", "Add  to my tasks"),
        ("alarm", "Remind me to  at 5 pm"), ("square.and.pencil", "Save this idea: "),
        ("chart.bar.fill", "Show today’s progress"), ("cup.and.saucer.fill", "Take a 5 minute break"),
        ("gearshape", "Open settings"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "pawprint.fill").foregroundStyle(DP.accent).font(.system(size: 18))
                TextField("Water 250 ml · Focus for 30 minutes · Ask anything…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($focused)
                    .onSubmit { activate(selection) }
                    .accessibilityLabel("Command")
            }
            .padding(16)

            if let result {
                Divider()
                FeedbackBanner(result: result, onUndo: result.undo.map { u in { u(); self.result = nil; onClose() } })
                    .padding(12)
                if !result.choices.isEmpty { rowsList }
            } else if !rows.isEmpty {
                Divider()
                rowsList
            }
        }
        .frame(width: 600)
        .background(.regularMaterial)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in selection = 0; result = nil; armedConfirm = nil }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.tab) {
            if case .template(let t) = currentRows[safe: selection]?.kind { query = t; return .handled }
            return .ignored
        }
        .onExitCommand(perform: onClose)
        .dpPanelStyle()
    }

    private var rowsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(currentRows.enumerated()), id: \.element.id) { idx, row in
                        HStack(spacing: 10) {
                            Image(systemName: row.symbol).frame(width: 20).foregroundStyle(idx == selection ? .white : DP.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                if let s = row.subtitle {
                                    Text(s).font(DP.caption).lineLimit(1)
                                        .foregroundStyle(idx == selection ? Color.white.opacity(0.85) : .secondary)
                                }
                            }
                            Spacer()
                            if idx == selection { Text("↩").font(DP.caption).foregroundStyle(.white.opacity(0.8)) }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .foregroundStyle(idx == selection ? Color.white : .primary)
                        .background(RoundedRectangle(cornerRadius: 8).fill(idx == selection ? DP.accent : .clear))
                        .contentShape(Rectangle())
                        .onTapGesture { selection = idx; activate(idx) }
                        .id(idx)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(idx == selection ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 320)
            .onChange(of: selection) { _, s in proxy.scrollTo(s) }
        }
    }

    // MARK: - Rows

    private var currentRows: [Row] {
        if let result, !result.choices.isEmpty {
            return result.choices.map { Row(id: "c\($0.id)", kind: .choice($0), symbol: "circle", title: $0.title, subtitle: "Mark complete") }
        }
        return rows
    }

    private var rows: [Row] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            return Self.templates.map { Row(id: $0.1, kind: .template($0.1), symbol: $0.0, title: $0.1, subtitle: "Tab to fill in") }
        }
        var out: [Row] = []
        if let cmd = CommandParser.parse(q, now: Date(), calendar: model.calendar) {
            let summary = cmd.summary(defaultServing: model.hydrationSettings.defaultServingML, calendar: model.calendar)
            let confirm = cmd.needsConfirmation
            out.append(Row(id: "cmd", kind: .command(cmd), symbol: symbol(for: cmd),
                           title: armedConfirm == summary ? "Press ↩ again to confirm: \(summary)" : summary,
                           subtitle: confirm ? "Needs confirmation · runs in DeskPet" : "Runs in DeskPet"))
        }
        // Matching templates help discover what's possible.
        for (sym, t) in Self.templates where t.lowercased().hasPrefix(q.lowercased()) && t.lowercased() != q.lowercased() {
            out.append(Row(id: "t\(t)", kind: .template(t), symbol: sym, title: t, subtitle: "Tab to fill in"))
        }
        for item in model.data.items.search(q).prefix(5) {
            out.append(Row(id: "i\(item.id)", kind: .item(item), symbol: item.isTask ? "checkmark.circle" : "note.text",
                           title: item.title, subtitle: item.isTask ? "Task · open" : "Note · open"))
        }
        if out.first.map({ if case .command = $0.kind { return false }; return true }) ?? true {
            if aiReady() {
                out.append(Row(id: "ai", kind: .askAI(q), symbol: "sparkles", title: "Ask DeskPet AI: “\(q)”",
                               subtitle: "Sends this text to Claude"))
            } else {
                out.append(Row(id: "setup", kind: .setupAI, symbol: "sparkles", title: "Not a DeskPet command",
                               subtitle: "General questions need AI — open Settings › AI"))
            }
        }
        return out
    }

    private func symbol(for c: AppCommand) -> String {
        switch c {
        case .logWater, .undoWater, .setWaterGoal: return "drop.fill"
        case .startFocus, .pauseFocus, .resumeFocus, .stopFocus, .skipPhase: return "timer"
        case .startBreak: return "cup.and.saucer.fill"
        case .createTask, .completeTask, .showTasks: return "checklist"
        case .createNote: return "square.and.pencil"
        case .showStats, .summarizeFocus: return "chart.bar.fill"
        case .configureReminder: return "bell.fill"
        case .open: return "arrow.up.forward.app"
        }
    }

    private func move(_ d: Int) {
        let n = currentRows.count
        guard n > 0 else { return }
        selection = (selection + d + n) % n
    }

    private func activate(_ idx: Int) {
        guard let row = currentRows[safe: idx] else { return }
        switch row.kind {
        case .template(let t):
            query = t
        case .command(let c):
            let summary = c.summary(defaultServing: model.hydrationSettings.defaultServingML, calendar: model.calendar)
            if c.needsConfirmation && armedConfirm != summary {
                armedConfirm = summary
                return
            }
            if case .open(let d) = c { onClose(); onOpen(d); return }
            let r = CommandExecutor(model: model).run(c)
            result = r
            query = ""
            selection = 0
            let isView: Bool
            switch c { case .showTasks, .showStats, .summarizeFocus: isView = true; default: isView = false }
            // Successful actions close quickly; summaries, choices and errors stay so you can read them.
            if r.style == .success && !isView && r.choices.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { if result?.message == r.message { onClose() } }
            }
        case .choice(let item):
            try? model.setCompleted(item.id, true)
            result = CommandResult(style: .success, message: "Completed “\(item.title)”",
                                   undo: { [model] in try? model.setCompleted(item.id, false) })
        case .item(let item):
            onClose()
            onOpenItem(item)
        case .askAI(let q):
            onClose()
            onAskAI(q)
        case .setupAI:
            onClose()
            onOpen(.settings)
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
