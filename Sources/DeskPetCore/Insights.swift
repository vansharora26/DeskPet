import Foundation

/// A plain-language observation derived only from recorded data, with the
/// calculation behind it spelled out.
public struct Insight: Equatable, Identifiable, Sendable {
    public var id: String
    public var text: String
    /// How it was calculated, shown under the insight.
    public var basis: String
}

public enum Insights {
    /// Simple, transparent weekly rules. Each rule only fires when there's enough data.
    public static func weekly(_ data: DeskPetData, now: Date, calendar: Calendar) -> [Insight] {
        var out: [Insight] = []
        let target = data.hydration.settings.dailyTargetML
        let water = Hydration.week(endingOn: now, entries: data.hydration.entries, target: target, calendar: calendar)
        let focus = Focus.week(endingOn: now, records: data.focus.records, calendar: calendar)

        if water.daysLogged >= 2 {
            out.append(Insight(
                id: "water-days",
                text: "You logged water on \(water.daysLogged) of the last 7 days and reached your goal on \(water.daysGoalMet).",
                basis: "Counted from your water entries since \(shortDay(water.days.first?.day, calendar))."))
            out.append(Insight(
                id: "water-avg",
                text: "On days you logged, you averaged \(AppCommand.formatML(water.averagePerLoggedDay)).",
                basis: "Total \(AppCommand.formatML(water.totalML)) ÷ \(water.daysLogged) logged days. Days without entries aren't counted as zero."))
        }

        let focusDays = focus.filter { $0.focusMinutes > 0 }
        if focusDays.count >= 2, let best = focusDays.max(by: { $0.focusMinutes < $1.focusMinutes }) {
            let f = DateFormatter()
            f.calendar = calendar
            f.dateFormat = "EEEE"
            out.append(Insight(
                id: "focus-best",
                text: "Your most focused day this week was \(f.string(from: best.day)) with \(best.focusMinutes) minutes.",
                basis: "Sum of focus time per day over the last 7 days (pauses excluded)."))
        }

        // Week-over-week task comparison, only when both weeks have data.
        let thisWeek = calendar.recentDays(7, endingOn: now)
        let lastWeekEnd = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let lastWeek = calendar.recentDays(7, endingOn: lastWeekEnd)
        let doneThis = thisWeek.reduce(0) { $0 + data.items.completedCount(on: $1, calendar: calendar) }
        let doneLast = lastWeek.reduce(0) { $0 + data.items.completedCount(on: $1, calendar: calendar) }
        if doneThis > 0 && doneLast > 0 {
            let dir = doneThis == doneLast ? "the same as" : (doneThis > doneLast ? "up from" : "down from")
            out.append(Insight(
                id: "tasks-wow",
                text: "You completed \(doneThis) task\(doneThis == 1 ? "" : "s") this week, \(dir) \(doneLast) the week before.",
                basis: "Tasks marked complete in each 7-day window."))
        }

        // A co-occurrence, explicitly labelled as not causal. Needs ≥3 days in each group.
        let focusedDays = Set(focus.filter { $0.sessionsCompleted >= 2 }.map { calendar.dayKey($0.day) })
        let monthDays = calendar.recentDays(28, endingOn: now)
        let groups = monthDays.map { day -> (Bool, Int) in
            (focusedDays.contains(calendar.dayKey(day))
                || Focus.day(day, records: data.focus.records, calendar: calendar).sessionsCompleted >= 2,
             Hydration.total(on: day, in: data.hydration.entries, calendar: calendar))
        }.filter { $0.1 > 0 }
        let withFocus = groups.filter(\.0).map(\.1)
        let without = groups.filter { !$0.0 }.map(\.1)
        if withFocus.count >= 3 && without.count >= 3 {
            let a = withFocus.reduce(0, +) / withFocus.count
            let b = without.reduce(0, +) / without.count
            if abs(a - b) >= 200 {
                out.append(Insight(
                    id: "focus-water",
                    text: "On days with 2+ focus sessions you logged \(a > b ? "more" : "less") water on average (\(AppCommand.formatML(a)) vs \(AppCommand.formatML(b))).",
                    basis: "Last 28 days, \(withFocus.count) vs \(without.count) days with water logged. This is a pattern in your data, not proof that one causes the other."))
            }
        }
        return out
    }

    static func shortDay(_ d: Date?, _ calendar: Calendar) -> String {
        guard let d else { return "this week" }
        let f = DateFormatter()
        f.calendar = calendar
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}

/// The daily briefing and end-of-day summary, built from local data only.
public struct Briefing: Equatable, Sendable {
    public var dueToday: [Item]
    public var overdue: [Item]
    public var upcoming: [Item]
    public var waterML: Int
    public var waterTarget: Int
    public var focusSessions: Int
    public var focusGoal: Int
    public var focusMinutes: Int
    public var breaks: Int
    public var completedToday: [Item]
    public var suggestion: String

    public static func build(_ data: DeskPetData, now: Date, calendar: Calendar) -> Briefing {
        let today = data.items.tasks(.today, now: now, calendar: calendar)
        let overdue = data.items.overdue(now: now, calendar: calendar)
        let weekAhead = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) ?? now
        let upcoming = data.items.tasks(.upcoming, now: now, calendar: calendar).filter { ($0.due ?? .distantFuture) <= weekAhead }
        let water = Hydration.total(on: now, in: data.hydration.entries, calendar: calendar)
        let focus = Focus.day(now, records: data.focus.records, calendar: calendar)
        let completed = data.items.live.filter { $0.completedAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false }
        let target = data.hydration.settings.dailyTargetML
        let goal = data.focus.settings.dailyGoalSessions

        // One suggested next action, by simple priority.
        let suggestion: String
        if let o = overdue.first {
            suggestion = "Start with “\(o.title)” — it’s past its deadline."
        } else if let t = today.first {
            suggestion = "Knock out “\(t.title)” in a \(data.focus.settings.focusMinutes)-minute focus session."
        } else if water < expectedWater(target: target, now: now, calendar: calendar) {
            suggestion = "Grab a glass of water — a small step toward today’s \(AppCommand.formatML(target)) goal."
        } else if focus.sessionsCompleted < goal {
            suggestion = "Try a focus session: \(focus.sessionsCompleted) of \(goal) done today."
        } else if let inbox = data.items.tasks(.inbox, now: now, calendar: calendar).first {
            suggestion = "Pick something from your inbox, like “\(inbox.title)”."
        } else {
            suggestion = "You’re all caught up. Maybe capture an idea for later?"
        }

        return Briefing(dueToday: today, overdue: overdue, upcoming: upcoming, waterML: water, waterTarget: target,
                        focusSessions: focus.sessionsCompleted, focusGoal: goal, focusMinutes: focus.focusMinutes,
                        breaks: focus.breaksCompleted, completedToday: completed, suggestion: suggestion)
    }

    /// A gentle pace line: the share of the target "expected" by now across 8:00–20:00.
    static func expectedWater(target: Int, now: Date, calendar: Calendar) -> Int {
        let m = calendar.minuteOfDay(now)
        let fraction = Double(min(max(m - 8 * 60, 0), 12 * 60)) / Double(12 * 60)
        return Int(Double(target) * fraction * 0.8)
    }
}
