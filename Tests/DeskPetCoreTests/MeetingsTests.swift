import Foundation
import Testing
@testable import DeskPetCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}()
private func at(_ h: Int, _ m: Int = 0, day: Int = 16) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
}
private func event(_ id: String, _ h: Int, _ m: Int = 0, minutes: Int = 30, allDay: Bool = false) -> CalendarEvent {
    CalendarEvent(id: id, title: id, start: at(h, m), end: at(h, m).addingTimeInterval(TimeInterval(minutes * 60)), isAllDay: allDay)
}

@Suite struct MeetingsTests {
    @Test func announcesOnceWithinTheLeadTime() {
        let events = [event("Standup", 10), event("Lunch", 12), event("Holiday", 0, minutes: 1440, allDay: true)]
        #expect(MeetingHeadsUp.due(events, now: at(9, 50), leadMinutes: 5, announced: []).isEmpty)
        #expect(MeetingHeadsUp.due(events, now: at(9, 55), leadMinutes: 5, announced: []).map(\.id) == ["Standup"])
        #expect(MeetingHeadsUp.due(events, now: at(9, 56), leadMinutes: 5, announced: ["Standup"]).isEmpty)
        // Too late once it's well underway; all-day events never ping.
        #expect(MeetingHeadsUp.due(events, now: at(10, 5), leadMinutes: 5, announced: []).isEmpty)
    }

    @Test func restOfDayListsAllDayFirstAndDropsFinished() {
        let events = [event("Review", 15), event("Standup", 10), event("Holiday", 0, minutes: 1440, allDay: true),
                      CalendarEvent(id: "Tomorrow", title: "Tomorrow", start: at(9, day: 17), end: at(10, day: 17))]
        let rest = MeetingHeadsUp.restOfDay(events, now: at(11), calendar: cal)
        #expect(rest.map(\.id) == ["Holiday", "Review"])
    }

    @Test func findsVideoCallLinks() {
        let url = MeetingHeadsUp.joinURL(in: [nil, "Room 4", "Agenda: https://example.com/doc\nJoin: https://us02web.zoom.us/j/123?pwd=x"])
        #expect(url?.host == "us02web.zoom.us")
        #expect(MeetingHeadsUp.joinURL(in: ["https://meet.google.com/abc-defg-hij"])?.host == "meet.google.com")
        #expect(MeetingHeadsUp.joinURL(in: ["https://notzoom.us.evil.com/j/1"]) == nil)
    }

    @Test func briefingMentionsAnImminentMeeting() {
        let b = Briefing.build(DeskPetData(), now: at(9, 50), calendar: cal, events: [event("Standup", 10)])
        #expect(b.suggestion.contains("Standup") && b.suggestion.contains("10 min"))
        #expect(b.meetings.map(\.id) == ["Standup"])
        #expect(Briefing.build(DeskPetData(), now: at(9, 50), calendar: cal).meetings.isEmpty)
    }
}
