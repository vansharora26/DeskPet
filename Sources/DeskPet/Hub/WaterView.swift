import Charts
import DeskPetCore
import SwiftUI

/// Hydration tracker: one-click logging, editable servings, undo, history,
/// daily/weekly summaries. Targets are personal settings, not medical advice.
struct WaterView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var hub: HubState
    var openSettings: () -> Void
    @State private var customML = ""
    @State private var showAllHistory = false

    var body: some View {
        let s = model.hydrationSettings
        let total = model.todayWaterML
        let progress = Double(total) / Double(max(1, s.dailyTargetML))
        let week = Hydration.week(endingOn: model.now, entries: model.data.hydration.entries,
                                  target: s.dailyTargetML, calendar: model.calendar)

        ScrollView {
            VStack(alignment: .leading, spacing: DP.spacing) {
                Card {
                    HStack(spacing: 16) {
                        ZStack {
                            ProgressRing(progress: progress, tint: DP.water, lineWidth: 10)
                            VStack(spacing: 0) {
                                Text(AppCommand.formatML(total)).font(.system(size: 17, weight: .bold, design: .rounded))
                                Text("of \(AppCommand.formatML(s.dailyTargetML))").font(DP.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 104, height: 104)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(total) of \(s.dailyTargetML) millilitres today")

                        VStack(alignment: .leading, spacing: 8) {
                            Text(encouragement(total: total, target: s.dailyTargetML)).font(DP.body)
                            HStack(spacing: 6) {
                                ForEach(s.servingSizes, id: \.self) { ml in
                                    Button("+\(ml)") { runInHub(.logWater(ml: ml), model: model, hub: hub) }
                                        .buttonStyle(PillButtonStyle(tint: DP.water, filled: ml == s.defaultServingML))
                                        .accessibilityLabel("Log \(ml) millilitres")
                                }
                            }
                            HStack(spacing: 6) {
                                TextField("ml", text: $customML)
                                    .textFieldStyle(.roundedBorder).frame(width: 64)
                                    .onSubmit(logCustom)
                                Button("Log", action: logCustom).buttonStyle(PillButtonStyle(tint: DP.water, filled: false))
                                    .disabled(Int(customML) == nil)
                                Spacer()
                                Button {
                                    runInHub(.undoWater, model: model, hub: hub)
                                } label: { Label("Undo last", systemImage: "arrow.uturn.backward") }
                                    .buttonStyle(.borderless).font(DP.caption)
                                    .disabled(model.todayWaterEntries.isEmpty)
                                    .keyboardShortcut("z", modifiers: .command)
                            }
                        }
                    }
                }

                Card {
                    SectionTitle(text: "Last 7 days", symbol: "chart.bar.fill", tint: DP.water)
                    Chart {
                        ForEach(week.days, id: \.day) { d in
                            BarMark(x: .value("Day", d.day, unit: .day), y: .value("ml", d.ml))
                                .foregroundStyle(d.reachedGoal ? DP.water : DP.water.opacity(0.45))
                                .cornerRadius(4)
                        }
                        RuleMark(y: .value("Goal", s.dailyTargetML))
                            .foregroundStyle(DP.water.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                    .frame(height: 110)
                    .accessibilityLabel("Water per day for the last 7 days")
                    Text("\(AppCommand.formatML(week.totalML)) total · goal met \(week.daysGoalMet) of 7 days · avg \(AppCommand.formatML(week.averagePerLoggedDay)) on days you logged")
                        .font(DP.caption).foregroundStyle(.secondary)
                }

                Card {
                    SectionTitle(text: "Today’s log", symbol: "list.bullet", tint: DP.water,
                                 trailing: AnyView(Button("History") { showAllHistory.toggle() }.buttonStyle(.link).font(DP.caption)))
                    let entries = showAllHistory ? Array(model.data.hydration.entries.reversed().prefix(60)) : model.todayWaterEntries
                    if entries.isEmpty {
                        EmptyState(symbol: "drop", title: "No water logged yet today",
                                   message: "Tap a serving above, or press ⌃⌥W anywhere.")
                    } else {
                        ForEach(entries) { e in
                            HStack {
                                Image(systemName: "drop.fill").foregroundStyle(DP.water).font(.caption)
                                Text("\(e.ml) ml").font(DP.body)
                                Spacer()
                                Text(e.date, format: showAllHistory ? .dateTime.month(.abbreviated).day().hour().minute() : .dateTime.hour().minute())
                                    .font(DP.caption).foregroundStyle(.secondary)
                                Button {
                                    if let removed = model.removeWater(e.id) {
                                        hub.feedback = CommandResult(style: .info, message: "Removed \(removed.ml) ml",
                                                                     undo: { [model] in model.restoreWater(removed) })
                                    }
                                } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                                    .help("Delete entry").accessibilityLabel("Delete \(e.ml) millilitre entry")
                            }
                        }
                    }
                }

                Card {
                    SectionTitle(text: "Reminders", symbol: "bell.fill", tint: DP.water)
                    Toggle("Remind me to drink water", isOn: Binding(
                        get: { s.remindersEnabled },
                        set: { v in model.updateHydrationSettings { $0.remindersEnabled = v } }))
                    if s.remindersEnabled {
                        Stepper("Every \(s.reminderIntervalMinutes) minutes", value: Binding(
                            get: { s.reminderIntervalMinutes },
                            set: { v in model.updateHydrationSettings { $0.reminderIntervalMinutes = v } }),
                                in: HydrationSettings.intervalRange, step: 15)
                    }
                    Button("Servings, goal & quiet hours…", action: openSettings).buttonStyle(.link).font(DP.caption)
                }

                Text("Your goal is a personal setting, not medical advice. DeskPet only knows what you log.")
                    .font(DP.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func logCustom() {
        guard let ml = Int(customML) else { return }
        runInHub(.logWater(ml: ml), model: model, hub: hub)
        if hub.feedback?.style != .error { customML = "" }
    }

    private func encouragement(total: Int, target: Int) -> String {
        if total == 0 { return "Fresh start! A glass whenever you’re ready." }
        if total >= target { return "Goal reached — nicely done! 💧" }
        let left = target - total
        return "\(AppCommand.formatML(left)) to go. Every sip counts."
    }
}
