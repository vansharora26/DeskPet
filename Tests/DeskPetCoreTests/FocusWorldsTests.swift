import Foundation
import Testing
@testable import DeskPetCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}()
private func at(_ h: Int, _ m: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: h, minute: m))!
}

@Suite struct FocusWorldsTests {
    @Test func worldSessionUsesTheSharedTimerAndRecordsOnce() throws {
        var f = FocusData()
        try f.start(.focus, minutes: 50, label: "Write chapter", now: at(9), world: FocusWorld.deepFocus.rawValue)
        #expect(f.timer?.world == "deepFocus")
        // A second start (e.g. from another world) is refused rather than creating a competing timer.
        #expect(throws: FocusError.self) { var g = f; try g.start(.focus, minutes: 25, now: at(9, 5), world: "study") }

        let events = f.advance(now: at(9, 50))
        #expect(events.count == 1)
        #expect(f.records.count == 1)
        #expect(f.records[0].world == "deepFocus" && f.records[0].completed && f.records[0].label == "Write chapter")
        // Advancing again never duplicates the record.
        #expect(f.advance(now: at(9, 51)).isEmpty)
        #expect(f.records.count == 1)
    }

    @Test func worldSessionsDoNotAutoStartBreaks() throws {
        var f = FocusData()
        f.settings.autoStartBreaks = true
        try f.start(.focus, minutes: 25, now: at(9), world: "study")
        guard case .completed(_, let next) = f.advance(now: at(9, 25)).first else { Issue.record("no event"); return }
        #expect(next == nil)
        #expect(f.timer == nil)
        // Classic (non-world) sessions keep their existing auto-break behaviour.
        try f.start(.focus, minutes: 25, now: at(10))
        guard case .completed(_, let classicNext) = f.advance(now: at(10, 25)).first else { Issue.record("no event"); return }
        #expect(classicNext == .shortBreak)
    }

    @Test func pauseSurvivesRestartWithWorldTag() throws {
        var f = FocusData()
        try f.start(.focus, minutes: 30, now: at(9), world: "workSprint")
        f.pause(now: at(9, 10))
        let restored = try JSONDecoder().decode(FocusData.self, from: JSONEncoder().encode(f))
        #expect(restored.timer?.world == "workSprint")
        #expect(restored.timer?.remaining(at: at(15)).rounded() == TimeInterval(20 * 60))
    }

    @Test func endingEarlyIsRecordedAsNotCompleted() throws {
        var f = FocusData()
        try f.start(.focus, minutes: 50, now: at(9), world: "deepFocus")
        let r = f.skip(now: at(9, 20))
        #expect(r?.completed == false && r?.world == "deepFocus")
        #expect(Int((r?.activeSeconds ?? 0) / 60) == 20)
    }

    @Test func reflectionsAttachToTheRightRecord() throws {
        var f = FocusData()
        try f.start(.focus, minutes: 25, now: at(9), world: "study")
        _ = f.advance(now: at(9, 25))
        let id = f.records[0].id
        let set1 = f.setReflection("  Finished the problem set  ", for: id)
        #expect(set1 && f.records[0].reflection == "Finished the problem set")
        let set2 = f.setReflection("   ", for: id)
        #expect(set2 && f.records[0].reflection == nil)
        let missing = f.setReflection("x", for: UUID())
        #expect(!missing)
    }

    @Test func perWorldMinutesAreClamped() {
        var s = WorldsSettings()
        #expect(s.minutes(for: .deepFocus) == 50)
        s.setMinutes(500, for: .deepFocus)
        #expect(s.minutes(for: .deepFocus) == 180)
        s.setMinutes(90, for: .recharge)
        #expect(s.minutes(for: .recharge) == FocusSettings.breakRange.upperBound)
        #expect(s.sound(for: .workSprint) == nil)
        #expect(s.sound(for: .study) == .fireplace)
    }

    @Test func dayPlanAllowsAtMostThreePriorities() {
        var p = DayPlan(dayKey: "2026-10-16")
        let task = UUID()
        let results = [p.addPriority("Ship the release", taskID: task), p.addPriority("Duplicate link", taskID: task),
                       p.addPriority("Gym"), p.addPriority("Call mum"), p.addPriority("A fourth thing")]
        let blank = p.addPriority("   ")
        #expect(results == [true, false, true, true, false])
        #expect(!blank)
        #expect(p.priorities.count == 3)
    }

    @Test func planningEstimate() {
        #expect(Worlds.estimatedSessions(hours: 4, focusMinutes: 50, breakMinutes: 10) == 4)
        #expect(Worlds.estimatedSessions(hours: 1, focusMinutes: 25, breakMinutes: 5) == 2)
        #expect(Worlds.estimatedSessions(hours: 0, focusMinutes: 25, breakMinutes: 5) == 0)
    }

    @Test func plansAreStoredPerDay() {
        var w = WorldsData()
        w.updatePlan(for: "2026-10-16") { $0.addPriority("A") }
        w.updatePlan(for: "2026-10-16") { $0.availableHours = 6 }
        w.updatePlan(for: "2026-10-17") { $0.addPriority("B") }
        #expect(w.plans.count == 2)
        #expect(w.plan(for: "2026-10-16")?.availableHours == 6)
        #expect(w.plan(for: "2026-10-16")?.priorities.map(\.title) == ["A"])
    }

    @Test func oldDataFilesLoadWithDefaults() throws {
        let json = #"{"version":2,"focus":{"records":[{"id":"6F1A2B3C-0000-4000-8000-000000000001","phase":"focus","start":"2026-10-16T13:00:00Z","end":"2026-10-16T13:25:00Z","plannedSeconds":1500,"activeSeconds":1500,"completed":true}]}}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let d = try decoder.decode(DeskPetData.self, from: Data(json.utf8))
        #expect(d.worlds.settings.ambientEnabled == false)   // audio is opt-in
        #expect(d.focus.records.first?.world == nil)          // pre-Worlds sessions stay "classic"
        #expect(Worlds.completedSessions(.study, on: at(12), records: d.focus.records, calendar: cal).isEmpty)
    }
}
