import Foundation
import Testing
@testable import DeskPetCore

/// A fixed calendar/time zone so day boundaries are deterministic.
private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    c.locale = Locale(identifier: "en_US")
    return c
}()

/// Returns the error thrown by `body`, if any (works with mutating calls).
private func thrown<E: Error & Equatable>(_ type: E.Type, _ body: () throws -> Void) -> E? {
    do { try body(); return nil } catch let e as E { return e } catch { return nil }
}

/// 2026-10-15 (a Thursday) at hh:mm local.
private func at(_ h: Int, _ m: Int = 0, day: Int = 15) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
}

@Suite struct HydrationTests {
    @Test func logAndTotal() throws {
        var h = HydrationData()
        try h.log(250, at: at(9))
        try h.log(500, at: at(13))
        #expect(Hydration.total(on: at(20), in: h.entries, calendar: cal) == 750)
    }

    @Test func rejectsInvalidAmounts() {
        var h = HydrationData()
        let e1 = thrown(HydrationError.self) { try h.log(0, at: at(9)) }
        let e2 = thrown(HydrationError.self) { try h.log(9000, at: at(9)) }
        #expect(e1 == .invalidAmount(0))
        #expect(e2 == .invalidAmount(9000))
        #expect(h.entries.isEmpty)
    }

    @Test func undoRemovesOnlyTodaysLastEntry() throws {
        var h = HydrationData()
        try h.log(300, at: at(22, day: 14))
        try h.log(250, at: at(9))
        try h.log(150, at: at(10))
        let u1 = h.undoLast(now: at(11), calendar: cal)
        let u2 = h.undoLast(now: at(11), calendar: cal)
        let u3 = h.undoLast(now: at(11), calendar: cal)
        #expect(u1?.ml == 150)
        #expect(u2?.ml == 250)
        #expect(u3 == nil) // yesterday's entry is safe
        #expect(h.entries.count == 1)
    }

    @Test func dailyResetFollowsLocalMidnight() throws {
        var h = HydrationData()
        try h.log(400, at: at(23, 50))
        #expect(Hydration.total(on: at(23, 59), in: h.entries, calendar: cal) == 400)
        let justAfterMidnight = at(0, 5, day: 16)
        #expect(Hydration.total(on: justAfterMidnight, in: h.entries, calendar: cal) == 0)
    }

    @Test func weeklySummaryIgnoresUnloggedDaysInAverage() throws {
        var h = HydrationData()
        try h.log(2000, at: at(10, day: 13))
        try h.log(1000, at: at(10, day: 15))
        let w = Hydration.week(endingOn: at(12), entries: h.entries, target: 2000, calendar: cal)
        #expect(w.days.count == 7)
        #expect(w.totalML == 3000)
        #expect(w.daysLogged == 2)
        #expect(w.daysGoalMet == 1)
        #expect(w.averagePerLoggedDay == 1500)
    }

    @Test func settingsAreValidated() {
        var s = HydrationSettings()
        s.dailyTargetML = 50
        s.servingSizes = [250, 250, -5, 99_999]
        s.reminderIntervalMinutes = 1
        let v = s.validated()
        #expect(v.dailyTargetML == HydrationSettings.targetRange.lowerBound)
        #expect(v.servingSizes == [10, 250, 2000])
        #expect(v.reminderIntervalMinutes == 15)
    }

    @Test func persistsAcrossRestart() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONDocumentStore<DeskPetData>(fileURL: dir.appendingPathComponent("data.json"))
        var data = DeskPetData()
        try data.hydration.log(330, at: at(9))
        data.hydration.settings.dailyTargetML = 2500
        try store.save(data)

        let reopened = JSONDocumentStore<DeskPetData>(fileURL: dir.appendingPathComponent("data.json"))
        guard case .loaded(let loaded) = reopened.load() else { Issue.record("not loaded"); return }
        #expect(loaded.hydration.entries.map(\.ml) == [330])
        #expect(loaded.hydration.settings.dailyTargetML == 2500)
    }
}

@Suite struct ReminderTests {
    let config = ReminderPlanner.Config(enabled: true, intervalMinutes: 60, quietHours: QuietHours())

    @Test func dueOneIntervalAfterLastActivity() {
        let s = ReminderState(anchor: at(9), lastSatisfied: at(10))
        #expect(ReminderPlanner.nextDue(config: config, state: s, now: at(10, 5), calendar: cal) == at(11))
    }

    @Test func disabledMeansNoReminder() {
        var c = config
        c.enabled = false
        #expect(ReminderPlanner.nextDue(config: c, state: ReminderState(anchor: at(9)), now: at(9), calendar: cal) == nil)
    }

    @Test func snoozeOverridesInterval() {
        var s = ReminderState(anchor: at(9))
        s.markFired(at: at(10))
        s.snooze(minutes: 15, from: at(10))
        #expect(ReminderPlanner.nextDue(config: config, state: s, now: at(10), calendar: cal) == at(10, 15))
    }

    @Test func dismissWaitsAFullInterval() {
        var s = ReminderState(anchor: at(9))
        s.dismiss(at: at(10, 30))
        #expect(ReminderPlanner.nextDue(config: config, state: s, now: at(10, 30), calendar: cal) == at(11, 30))
    }

    @Test func firingMovesTheScheduleSoItCannotDuplicate() {
        var s = ReminderState(anchor: at(9))
        let first = ReminderPlanner.nextDue(config: config, state: s, now: at(9), calendar: cal)!
        s.markFired(at: first)
        let second = ReminderPlanner.nextDue(config: config, state: s, now: first, calendar: cal)!
        #expect(second > first)
        #expect(second.timeIntervalSince(first) == 3600)
    }

    @Test func quietHoursDeferToMorning() {
        let s = ReminderState(anchor: at(21, 30))
        // 22:30 would be due, but quiet hours (22:00–08:00) push it to 08:00 next day.
        #expect(ReminderPlanner.nextDue(config: config, state: s, now: at(21, 30), calendar: cal) == at(8, day: 16))
    }

    @Test func quietHoursHandleMidnightWrap() {
        let q = QuietHours(enabled: true, startMinute: 22 * 60, endMinute: 7 * 60)
        #expect(q.contains(at(23), calendar: cal))
        #expect(q.contains(at(3), calendar: cal))
        #expect(!q.contains(at(7), calendar: cal))
        #expect(!q.contains(at(12), calendar: cal))
    }

    @Test func notBeforeDefersUntilFocusEnds() {
        let s = ReminderState(anchor: at(9))
        let due = ReminderPlanner.nextDue(config: config, state: s, now: at(9, 30), calendar: cal, notBefore: at(10, 25))
        #expect(due == at(10, 25))
    }

    @Test func loggingWaterSatisfiesTheReminder() throws {
        var h = HydrationData()
        h.reminder = ReminderState(anchor: at(9))
        try h.log(250, at: at(9, 50))
        #expect(ReminderPlanner.nextDue(config: config, state: h.reminder, now: at(9, 50), calendar: cal) == at(10, 50))
    }
}

@Suite struct FocusTests {
    @Test func remainingIsComputedFromAbsoluteTime() throws {
        var f = FocusData()
        try f.start(.focus, minutes: 25, now: at(9))
        #expect(f.timer?.remaining(at: at(9, 10)).rounded() == TimeInterval(15 * 60))
    }

    @Test func pauseFreezesAndResumeContinues() throws {
        var f = FocusData()
        try f.start(.focus, minutes: 25, now: at(9))
        let paused = f.pause(now: at(9, 10))
        #expect(paused)
        #expect(f.timer?.remaining(at: at(11)).rounded() == TimeInterval(15 * 60)) // paused: hours later, still 15 min
        let resumed = f.resume(now: at(11))
        #expect(resumed)
        #expect(f.timer?.endsAt == at(11, 15))
    }

    @Test func surviveRestartViaPersistence() throws {
        var f = FocusData()
        try f.start(.focus, minutes: 30, now: at(9))
        let data = try JSONEncoder().encode(f)
        let restored = try JSONDecoder().decode(FocusData.self, from: data)
        #expect(restored.timer?.remaining(at: at(9, 20)).rounded() == TimeInterval(10 * 60))
    }

    @Test func completesOnTimeAndAutoStartsBreakAtExactEnd() throws {
        var f = FocusData()
        try f.start(.focus, minutes: 25, now: at(9))
        #expect(f.advance(now: at(9, 24)).isEmpty)
        let events = f.advance(now: at(9, 25))
        guard case .completed(let r, let next) = events.first else { Issue.record("no event"); return }
        #expect(r.completed && r.activeSeconds == 25 * 60)
        #expect(next == .shortBreak)
        #expect(f.timer?.phase == .shortBreak)
        #expect(f.timer?.startedAt == at(9, 25))
    }

    @Test func longGapCompletesButDoesNotAutoStart() throws {
        var f = FocusData()
        try f.start(.focus, minutes: 25, now: at(9))
        let events = f.advance(now: at(14)) // app was closed
        guard case .completed(let r, let next) = events.first else { Issue.record("no event"); return }
        #expect(r.end == at(9, 25))
        #expect(next == nil)
        #expect(f.timer == nil)
    }

    @Test func longBreakEveryFourth() throws {
        var f = FocusData()
        f.settings.autoStartBreaks = false
        var t = at(9)
        var lastNext: FocusPhase?
        for _ in 0..<4 {
            try f.start(.focus, minutes: 1, now: t)
            t = t.addingTimeInterval(60)
            _ = f.advance(now: t)
            lastNext = f.suggestedNextPhase(now: t)
        }
        #expect(lastNext == .longBreak)
    }

    @Test func skipRecordsPartialTime() throws {
        var f = FocusData()
        try f.start(.focus, minutes: 25, now: at(9))
        let r = f.skip(now: at(9, 10))
        #expect(r?.completed == false)
        #expect(r?.activeSeconds == 600)
        #expect(f.timer == nil)
    }

    @Test func resetDiscardsWithoutRecord() throws {
        var f = FocusData()
        try f.start(.focus, minutes: 25, now: at(9))
        f.reset()
        #expect(f.timer == nil && f.records.isEmpty)
    }

    @Test func validatesDurationAndConflicts() throws {
        var f = FocusData()
        let e1 = thrown(FocusError.self) { try f.start(.focus, minutes: 0, now: at(9)) }
        #expect(e1 == .invalidMinutes(0))
        try f.start(.focus, minutes: 10, now: at(9))
        let e2 = thrown(FocusError.self) { try f.start(.focus, minutes: 10, now: at(9)) }
        #expect(e2 == .timerAlreadyActive)
    }

    @Test func dailySummary() throws {
        var f = FocusData()
        f.settings.autoStartBreaks = false
        try f.start(.focus, minutes: 25, now: at(9))
        _ = f.advance(now: at(9, 25))
        try f.start(.shortBreak, now: at(9, 30))
        _ = f.advance(now: at(9, 35))
        let d = Focus.day(at(12), records: f.records, calendar: cal)
        #expect(d.sessionsCompleted == 1 && d.focusMinutes == 25 && d.breaksCompleted == 1)
    }
}

@Suite struct ItemTests {
    @Test func createEditSearchComplete() throws {
        var s = ItemStore()
        let a = try s.add("Buy groceries", kind: .task, now: at(9))
        _ = try s.add("Idea: café app for students", kind: .note, now: at(9))
        try s.update(a.id, now: at(10)) { $0.text = "Buy groceries and coffee" }
        #expect(s.search("cafe").count == 1) // diacritic-insensitive
        #expect(s.search("GROCERIES coffee").map(\.id) == [a.id])
        try s.setCompleted(a.id, true, now: at(11))
        #expect(s.tasks(.completed, now: at(12), calendar: cal).map(\.id) == [a.id])
        #expect(s.tasks(.inbox, now: at(12), calendar: cal).isEmpty)
    }

    @Test func filters() throws {
        var s = ItemStore()
        let inbox = try s.add("Inbox", kind: .task, now: at(9))
        let today = try s.add("Today", kind: .task, due: at(17), dueHasTime: true, now: at(9))
        let overdue = try s.add("Overdue", kind: .task, due: at(0, day: 13), now: at(9))
        let later = try s.add("Later", kind: .task, due: at(9, day: 18), now: at(9))
        #expect(s.tasks(.inbox, now: at(12), calendar: cal).map(\.id) == [inbox.id])
        #expect(Set(s.tasks(.today, now: at(12), calendar: cal).map(\.id)) == [today.id, overdue.id])
        #expect(s.tasks(.upcoming, now: at(12), calendar: cal).map(\.id) == [later.id])
        #expect(s.overdue(now: at(12), calendar: cal).map(\.id) == [overdue.id])
    }

    @Test func pinnedFirst() throws {
        var s = ItemStore()
        _ = try s.add("old", kind: .note, now: at(9))
        let pinned = try s.add("pinned", kind: .note, pinned: true, now: at(8))
        _ = try s.add("new", kind: .note, now: at(10))
        #expect(s.notes().first?.id == pinned.id)
    }

    @Test func softDeleteRestoreAndPurge() throws {
        var s = ItemStore()
        let a = try s.add("Temp", kind: .note, now: at(9))
        try s.softDelete(a.id, now: at(9))
        #expect(s.notes().isEmpty && s.trash.count == 1)
        try s.restore(a.id, now: at(10))
        #expect(s.notes().count == 1)
        try s.softDelete(a.id, now: at(10))
        s.purgeTrash(now: at(10).addingTimeInterval(31 * 86_400))
        #expect(s.items.isEmpty)
    }

    @Test func rejectsEmpty() {
        var s = ItemStore()
        let e = thrown(ItemError.self) { _ = try s.add("   ", kind: .note, now: at(9)) }
        #expect(e == .emptyText)
    }

    @Test func remindersFireOnce() throws {
        var s = ItemStore()
        let a = try s.add("Call", kind: .task, remindAt: at(19), now: at(9))
        #expect(s.dueReminders(now: at(18)).isEmpty)
        #expect(s.dueReminders(now: at(19)).map(\.id) == [a.id])
        try s.update(a.id, now: at(19)) { $0.reminderFired = true }
        #expect(s.dueReminders(now: at(20)).isEmpty)
        #expect(s.nextReminderDate() == nil)
    }
}

@Suite struct CommandParserTests {
    func parse(_ s: String, now: Date = at(14)) -> AppCommand? { CommandParser.parse(s, now: now, calendar: cal) }

    @Test func exampleCommands() {
        #expect(parse("Log 300 ml of water.") == .logWater(ml: 300))
        #expect(parse("Water 250 ml") == .logWater(ml: 250))
        #expect(parse("water 1.5 l") == .logWater(ml: 1500))
        #expect(parse("drank a glass of water") == .logWater(ml: nil))
        #expect(parse("Start a 40-minute focus session.") == .startFocus(minutes: 40, label: nil))
        #expect(parse("Focus for 30 minutes") == .startFocus(minutes: 30, label: nil))
        #expect(parse("focus on the report for 1 hour") == .startFocus(minutes: 60, label: "the report"))
        #expect(parse("Add buy groceries to my tasks") == .createTask(title: "Buy groceries", due: nil, dueHasTime: false, remindAt: nil))
        #expect(parse("Save this idea: a desktop pet for students.") == .createNote(text: "a desktop pet for students"))
        #expect(parse("Show me my unfinished tasks.") == .showTasks(nil))
        #expect(parse("Summarize my focus sessions this week.") == .summarizeFocus(.week))
        #expect(parse("Show today's progress") == .showStats(.today))
    }

    @Test func reminderAtSevenPM() {
        guard case .createTask(let title, let due, let hasTime, let remind) = parse("Remind me to call my friend at 7 PM.") else {
            Issue.record("not a task"); return
        }
        #expect(title == "Call my friend")
        #expect(remind == at(19) && due == at(19) && hasTime)
    }

    @Test func reminderTimeAlreadyPassedRollsToTomorrow() {
        guard case .createTask(_, _, _, let remind) = parse("remind me to stretch at 9am", now: at(14)) else {
            Issue.record("not a task"); return
        }
        #expect(remind == at(9, day: 16))
    }

    @Test func relativeAndWeekdayDates() {
        guard case .createTask(_, _, _, let r1) = parse("remind me to check the oven in 20 minutes") else { Issue.record("1"); return }
        #expect(r1 == at(14, 20))
        guard case .createTask(let t2, let d2, let h2, _) = parse("add task submit report by friday") else { Issue.record("2"); return }
        #expect(t2 == "Submit report" && d2 == at(0, day: 16) && !h2)
        guard case .createTask(_, let d3, _, _) = parse("todo: dentist tomorrow at 9:30am") else { Issue.record("3"); return }
        #expect(d3 == at(9, 30, day: 16))
    }

    @Test func timerControls() {
        #expect(parse("pause") == .pauseFocus)
        #expect(parse("resume timer") == .resumeFocus)
        #expect(parse("stop focus") == .stopFocus)
        #expect(parse("take a 10 minute break") == .startBreak(minutes: 10))
        #expect(parse("skip break") == .skipPhase)
    }

    @Test func remindersConfiguration() {
        #expect(parse("remind me to drink water every 45 minutes") == .configureReminder(kind: .hydration, enabled: true, intervalMinutes: 45))
        #expect(parse("turn off water reminders") == .configureReminder(kind: .hydration, enabled: false, intervalMinutes: nil))
        #expect(parse("stretch reminders every hour") == .configureReminder(kind: .movement, enabled: true, intervalMinutes: 60))
        #expect(parse("set my water goal to 2.5 l") == .setWaterGoal(ml: 2500))
    }

    @Test func navigationAndCompletion() {
        #expect(parse("settings") == .open(.settings))
        #expect(parse("open focus") == .open(.focus))
        #expect(parse("mark buy milk as done") == .completeTask(query: "buy milk"))
        #expect(parse("undo last water") == .undoWater)
    }

    @Test func leavesQuestionsForAI() {
        #expect(parse("Help me plan my afternoon") == nil)
        #expect(parse("What is the capital of France?") == nil)
        #expect(parse("I need to buy water bottles for the trip next month") == nil)
        #expect(parse("how much water should a person drink?") == nil)
    }
}

@Suite struct ProgressionTests {
    @Test func levelsAndDailyCaps() {
        var p = Progression()
        for _ in 0..<20 { p.earn(.water, on: at(9), calendar: cal) }
        #expect(p.xp == XPSource.water.dailyCap) // capped
        p.earn(.water, on: at(9, day: 16), calendar: cal)
        #expect(p.xp == XPSource.water.dailyCap + 5) // new day, new cap
        #expect(p.level == 1)
        let award = p.earn(.focusSession, on: at(10, day: 16), calendar: cal)
        #expect(award.leveledUpTo == 2)
        #expect(p.isUnlocked(.bow) && !p.isUnlocked(.crown))
    }

    @Test func disablingGamificationUnlocksEverything() {
        var p = Progression()
        p.gamificationEnabled = false
        #expect(Accessory.allCases.allSatisfy { p.isUnlocked($0) })
    }

    @Test func streaksAreForgiving() {
        var p = Progression()
        for d in [10, 11, 12, 14, 15] { p.earn(.petting, on: at(9, day: d), calendar: cal) }
        #expect(p.currentStreak(now: at(20), calendar: cal) == 2)
        #expect(p.bestStreak(calendar: cal) == 3)
        // Today not yet active doesn't zero the streak.
        #expect(p.currentStreak(now: at(9, day: 16), calendar: cal) == 2)
    }

    @Test func milestonesOnce() {
        var p = Progression()
        let first = p.reach("first-water", title: "First sip")
        let second = p.reach("first-water", title: "First sip")
        #expect(first != nil)
        #expect(second == nil)
    }
}

@Suite struct BriefingAndExportTests {
    @Test func briefingSuggestsOverdueFirst() throws {
        var d = DeskPetData()
        _ = try d.items.add("Taxes", kind: .task, due: at(0, day: 10), now: at(9))
        _ = try d.items.add("Email", kind: .task, due: at(16), dueHasTime: true, now: at(9))
        let b = Briefing.build(d, now: at(10), calendar: cal)
        #expect(b.overdue.count == 1)
        #expect(b.suggestion.contains("Taxes"))
    }

    @Test func insightsOnlyFromRealData() throws {
        let empty = Insights.weekly(DeskPetData(), now: at(12), calendar: cal)
        #expect(empty.isEmpty)
        var d = DeskPetData()
        try d.hydration.log(1000, at: at(9, day: 14))
        try d.hydration.log(2000, at: at(9, day: 15))
        let insights = Insights.weekly(d, now: at(12), calendar: cal)
        #expect(insights.contains { $0.id == "water-avg" && $0.text.contains("1.5 L") })
    }

    @Test func csvEscapesAndNeutralisesFormulas() {
        let out = DataExport.csv(["a", "b"], [["hello, world", "=SUM(A1)"], ["say \"hi\"", "x"]])
        #expect(out == "a,b\r\n\"hello, world\",'=SUM(A1)\r\n\"say \"\"hi\"\"\",x\r\n")
    }

    @Test func jsonExportRoundTrips() throws {
        var d = DeskPetData()
        try d.hydration.log(250, at: at(9))
        let json = try DataExport.json(data: d, pet: nil, now: at(12))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(DataExport.Bundle.self, from: json)
        #expect(bundle.data.hydration.entries.count == 1)
    }

    @Test func tolerantDecodingOfOldOrPartialFiles() throws {
        let json = #"{"version":2,"hydration":{"settings":{"dailyTargetML":3000}},"unknownField":true}"#
        let d = try JSONDecoder().decode(DeskPetData.self, from: Data(json.utf8))
        #expect(d.hydration.settings.dailyTargetML == 3000)
        #expect(d.hydration.settings.servingSizes == [150, 250, 500])
        #expect(d.items.items.isEmpty)
    }

    @Test func deleteRemovesFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dp-\(UUID().uuidString).json")
        let store = JSONDocumentStore<DeskPetData>(fileURL: url)
        try store.save(DeskPetData())
        store.delete()
        guard case .none = store.load() else { Issue.record("still exists"); return }
    }
}
