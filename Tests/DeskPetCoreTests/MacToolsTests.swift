import Foundation
import Testing
@testable import DeskPetCore

@Suite struct ClipboardHistoryTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func newestFirstAndDeduplicated() {
        var h = ClipboardHistory()
        h.record("alpha", at: t0, sourceApp: "Notes")
        h.record("beta", at: t0.addingTimeInterval(1), sourceApp: "Safari")
        h.record("alpha", at: t0.addingTimeInterval(2), sourceApp: nil)
        #expect(h.entries.map(\.text) == ["alpha", "beta"])
        #expect(h.entries[0].copiedAt == t0.addingTimeInterval(2))
        #expect(h.entries[0].sourceApp == "Notes") // kept when the new copy has no source
    }

    @Test func capsAtMaximum() {
        var h = ClipboardHistory()
        for i in 0..<(ClipboardHistory.maxEntries + 5) { h.record("item \(i)", at: t0, sourceApp: nil) }
        #expect(h.entries.count == ClipboardHistory.maxEntries)
        #expect(h.entries.first?.text == "item \(ClipboardHistory.maxEntries + 4)")
    }

    @Test func skipsBlankAndHugeCopies() {
        var h = ClipboardHistory()
        let blank = h.record("   \n ", at: t0, sourceApp: nil)
        let huge = h.record(String(repeating: "x", count: ClipboardHistory.maxLength + 1), at: t0, sourceApp: nil)
        #expect(!blank && !huge)
        #expect(h.entries.isEmpty)
    }

    @Test func passwordManagerCopiesAreIgnored() {
        #expect(ClipboardHistory.shouldIgnore(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"], sourceBundleID: nil))
        #expect(ClipboardHistory.shouldIgnore(types: ["public.utf8-plain-text"], sourceBundleID: "com.1password.1password"))
        #expect(!ClipboardHistory.shouldIgnore(types: ["public.utf8-plain-text"], sourceBundleID: "com.apple.Safari"))
    }

    @Test func searchMatchesAllWordsIgnoringCase() {
        var h = ClipboardHistory()
        h.record("Meeting link: https://zoom.us/j/123", at: t0, sourceApp: nil)
        h.record("Café address", at: t0, sourceApp: nil)
        #expect(h.search("ZOOM meeting").count == 1)
        #expect(h.search("cafe").count == 1)
        #expect(h.search("zoom cafe").isEmpty)
        #expect(h.search("  ").count == 2)
    }

    @Test func removeAndClear() {
        var h = ClipboardHistory()
        h.record("a", at: t0, sourceApp: nil)
        h.record("b", at: t0, sourceApp: nil)
        h.remove(id: h.entries[0].id)
        #expect(h.entries.map(\.text) == ["a"])
        h.clear()
        #expect(h.entries.isEmpty)
    }

    @Test func previewUsesFirstNonEmptyLine() {
        let e = ClipEntry(text: "\n\n   hello    world  \nsecond", copiedAt: t0, sourceApp: nil)
        #expect(e.preview == "hello world")
        #expect(e.lineCount == 2)
    }

    @Test func roundTripsThroughJSON() throws {
        var h = ClipboardHistory()
        h.record("saved", at: t0, sourceApp: "Mail")
        let back = try JSONDecoder().decode(ClipboardHistory.self, from: JSONEncoder().encode(h))
        #expect(back == h)
    }
}

@Suite struct MacToolCommandTests {
    func parse(_ s: String) -> AppCommand? { CommandParser.parse(s, now: Date(), calendar: .current) }

    @Test func keepAwakeDurations() {
        #expect(parse("keep awake") == .keepAwake(minutes: nil))
        #expect(parse("keep my mac awake for 2 hours") == .keepAwake(minutes: 120))
        #expect(parse("Keep awake for 30 minutes") == .keepAwake(minutes: 30))
        #expect(parse("caffeinate for an hour") == .keepAwake(minutes: 60))
        #expect(parse("keep the screen awake for 1.5 hours") == .keepAwake(minutes: 90))
        #expect(parse("don't let my mac sleep") == .keepAwake(minutes: nil))
        #expect(parse("keep awake until I turn it off") == .keepAwake(minutes: nil))
        #expect(parse("keep awake for 100 hours") == .keepAwake(minutes: KeepAwake.maxMinutes))
    }

    @Test func stopKeepAwake() {
        #expect(parse("stop keeping my mac awake") == .stopKeepAwake)
        #expect(parse("keep awake off") == .stopKeepAwake)
        #expect(parse("let my mac sleep") == .stopKeepAwake)
        #expect(parse("turn off caffeinate") == .stopKeepAwake)
    }

    @Test func toolsOpen() {
        #expect(parse("screenshot") == .open(.screenshot))
        #expect(parse("take a screenshot") == .open(.screenshot))
        #expect(parse("copy text from screen") == .open(.copyText))
        #expect(parse("OCR") == .open(.copyText))
        #expect(parse("clipboard history") == .open(.clipboard))
        #expect(parse("show my clipboard") == .open(.clipboard))
    }

    @Test func existingCommandsUnaffected() {
        #expect(parse("focus for 30 minutes") == .startFocus(minutes: 30, label: nil))
        #expect(parse("new note") == .open(.capture))
    }

    @Test func keepAwakeTitles() {
        #expect(KeepAwake.title(minutes: 30) == "30 minutes")
        #expect(KeepAwake.title(minutes: 60) == "1 hour")
        #expect(KeepAwake.title(minutes: 120) == "2 hours")
        #expect(KeepAwake.title(minutes: 90) == "1 h 30 min")
        #expect(KeepAwake.title(minutes: nil) == "Until turned off")
        #expect(KeepAwake.remaining(65 * 60) == "1 h 5 min left")
        #expect(KeepAwake.remaining(20) == "1 min left")
    }
}
