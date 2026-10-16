import Foundation
import Testing
@testable import DeskPetCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}()
private let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 14))!

@Suite struct VoicePhrasingTests {
    func parse(_ s: String) -> AppCommand? { CommandParser.parse(s, now: now, calendar: cal) }

    @Test func spokenWaterLogs() {
        #expect(parse("I've had 300 ml of water") == .logWater(ml: 300))
        #expect(parse("I’ve had 300 ml") == .logWater(ml: 300))           // curly apostrophe from dictation
        #expect(parse("I just drank 500 milliliters") == .logWater(ml: 500))
        #expect(parse("had half a litre") == nil || parse("had 0.5 l") == .logWater(ml: 500))
        #expect(parse("I've had 300 mL of coffee") == nil)                  // not water — leave it
        #expect(parse("how much water should I drink?") == nil)
    }

    @Test func totalsAndTimer() {
        #expect(parse("How much water have I had today?") == .waterTotal)
        #expect(parse("what's my water total") == .waterTotal)
        #expect(parse("How much time is left?") == .timerStatus)
        #expect(parse("how long left") == .timerStatus)
        #expect(parse("Start a 25-minute focus session") == .startFocus(minutes: 25, label: nil))
    }
}

@Suite struct ConversationContextTests {
    @Test func totalDefaultsToWater() {
        let ctx = ConversationContext()
        #expect(ctx.resolve("What's my total?", now: now) == .command(.waterTotal))
    }

    @Test func totalFollowsTheTopic() {
        var ctx = ConversationContext()
        ctx.note(.startFocus(minutes: 25, label: nil), at: now, defaultServing: 250, defaultFocus: 25)
        #expect(ctx.resolve("what's my total", now: now.addingTimeInterval(30)) == .command(.timerStatus))
        // After the topic expires, "total" means water again.
        #expect(ctx.resolve("what's my total", now: now.addingTimeInterval(ConversationContext.ttl + 1)) == .command(.waterTotal))
    }

    @Test func anotherOneRepeatsTheLastAmount() {
        var ctx = ConversationContext()
        ctx.note(.logWater(ml: 300), at: now, defaultServing: 250, defaultFocus: 25)
        #expect(ctx.resolve("Another one!", now: now.addingTimeInterval(60)) == .command(.logWater(ml: 300)))
        ctx.note(.logWater(ml: nil), at: now, defaultServing: 250, defaultFocus: 25)
        #expect(ctx.resolve("one more", now: now) == .command(.logWater(ml: 250)))
    }

    @Test func anotherOneNeedsFreshContext() {
        var ctx = ConversationContext()
        #expect(ctx.resolve("another one", now: now) == nil)
        ctx.note(.logWater(ml: 300), at: now, defaultServing: 250, defaultFocus: 25)
        #expect(ctx.resolve("another one", now: now.addingTimeInterval(ConversationContext.ttl + 1)) == nil)
    }

    @Test func undoPhrases() {
        let ctx = ConversationContext()
        for s in ["undo that", "Undo.", "never mind", "scratch that", "take that back"] {
            #expect(ctx.resolve(s, now: now) == .undoLast, "\(s)")
        }
    }

    @Test func ignoresOrdinarySentences() {
        let ctx = ConversationContext()
        #expect(ctx.resolve("what's the total population of France", now: now) == nil)
        #expect(ctx.resolve("tell me a joke", now: now) == nil)
    }

    @Test func failedCommandsAreNotRecordedByCaller() {
        // The chat only calls note() after success; an untouched context has no topic.
        let ctx = ConversationContext()
        #expect(ctx.topic == nil && !ctx.isFresh(at: now))
    }
}
