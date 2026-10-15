import Charts
import DeskPetCore
import SwiftUI

/// Habit insights: water, focus, breaks and tasks over the last 7 days, plus
/// rule-based observations that state exactly how they were computed.
struct StatsView: View {
    @ObservedObject var model: AppModel
    var openWardrobe: () -> Void

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openWardrobe = openSettings
    }

    var body: some View {
        let cal = model.calendar
        let target = model.hydrationSettings.dailyTargetML
        let water = Hydration.week(endingOn: model.now, entries: model.data.hydration.entries, target: target, calendar: cal)
        let focus = Focus.week(endingOn: model.now, records: model.data.focus.records, calendar: cal)
        let days = cal.recentDays(7, endingOn: model.now)
        let tasksDone = days.map { model.data.items.completedCount(on: $0, calendar: cal) }
        let movement = days.map { model.movementBreaks(on: $0) }
        let insights = Insights.weekly(model.data, now: model.now, calendar: cal)
        let p = model.data.progression

        ScrollView {
            VStack(alignment: .leading, spacing: DP.spacing) {
                HStack(spacing: DP.spacing) {
                    tile("\(AppCommand.formatML(water.totalML))", "water", DP.water)
                    tile("\(focus.reduce(0) { $0 + $1.sessionsCompleted })", "focus sessions", DP.accent)
                    tile("\(focus.reduce(0) { $0 + $1.breaksCompleted } + movement.reduce(0, +))", "breaks", DP.mint)
                    tile("\(tasksDone.reduce(0, +))", "tasks done", DP.xp)
                }
                Text("Last 7 days").font(DP.caption).foregroundStyle(.secondary)

                Card {
                    SectionTitle(text: "Focus minutes", symbol: "timer")
                    Chart(focus, id: \.day) { d in
                        BarMark(x: .value("Day", d.day, unit: .day), y: .value("Minutes", d.focusMinutes))
                            .foregroundStyle(DP.accent.gradient).cornerRadius(4)
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                    .frame(height: 100)
                    .accessibilityLabel("Focus minutes per day")
                }

                Card {
                    SectionTitle(text: "Tasks completed", symbol: "checkmark.circle.fill", tint: DP.mint)
                    Chart(Array(zip(days, tasksDone)), id: \.0) { pair in
                        BarMark(x: .value("Day", pair.0, unit: .day), y: .value("Tasks", pair.1))
                            .foregroundStyle(DP.mint.gradient).cornerRadius(4)
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                    .frame(height: 80)
                    .accessibilityLabel("Tasks completed per day")
                }

                Card {
                    SectionTitle(text: "Insights", symbol: "lightbulb.fill", tint: DP.xp)
                    if insights.isEmpty {
                        Text("Log a few days of water and focus and I’ll point out patterns here — only from what you’ve actually recorded.")
                            .font(DP.caption).foregroundStyle(.secondary)
                    }
                    ForEach(insights) { i in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(i.text).font(DP.body)
                            Text(i.basis).font(DP.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                if p.gamificationEnabled {
                    Card {
                        SectionTitle(text: "\(model.data.progression.level > 1 ? "Level \(p.level)" : "Level 1") · \(p.xp) XP",
                                     symbol: "star.fill", tint: DP.xp,
                                     trailing: AnyView(Button("Wardrobe", action: openWardrobe).buttonStyle(.link).font(DP.caption)))
                        let prog = p.progressToNextLevel
                        ProgressView(value: Double(prog.current), total: Double(max(1, prog.needed))).tint(DP.xp)
                        Text("\(prog.needed - prog.current) XP to level \(p.level + 1). XP comes from water, focus, breaks and tasks (with daily caps — no grinding needed).")
                            .font(DP.caption).foregroundStyle(.secondary)
                        if p.showStreaks {
                            Text("Current streak: \(p.currentStreak(now: model.now, calendar: cal)) days · best: \(p.bestStreak(calendar: cal))")
                                .font(DP.caption)
                        }
                        if !p.milestones.isEmpty {
                            Text("Milestones: \(p.milestones.count)").font(DP.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Text("Goals are editable in Settings. Insights describe your own logs; they don’t imply cause and effect.")
                    .font(DP.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func tile(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(tint)
                .minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(DP.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.1)))
        .accessibilityElement(children: .combine)
    }
}
