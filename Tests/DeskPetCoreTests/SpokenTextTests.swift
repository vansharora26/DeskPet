import Testing
@testable import DeskPetCore

@Suite struct SpokenTextTests {
    @Test func unitsReadAsWords() {
        #expect(SpokenText.clean("Logged 300 ml · 1.2 L of 2.0 L today") ==
                "Logged 300 millilitres, 1.2 litres of 2.0 litres today.")
        #expect(SpokenText.clean("Focus started: 25 min") == "Focus started: 25 minutes.")
        #expect(SpokenText.clean("1 min left") == "1 minute left.")
    }

    @Test func stripsMarkdownAndEmoji() {
        #expect(SpokenText.clean("**Great job!** 🎉 You hit your goal 💧") == "Great job! You hit your goal.")
        #expect(SpokenText.clean("Try [the docs](https://example.com) — or not") == "Try the docs, or not.")
    }

    @Test func listsBecomeSentences() {
        let text = "3 unfinished tasks\n• Call Sam — Today\n• Buy milk\n- Book flights"
        #expect(SpokenText.clean(text) == "3 unfinished tasks. Call Sam, Today. Buy milk. Book flights.")
    }

    @Test func longRepliesAreCappedAtASentence() {
        let long = String(repeating: "This is a sentence about water. ", count: 30)
        let spoken = SpokenText.clean(long)
        #expect(spoken.count <= SpokenText.maxCharacters + 40)
        #expect(spoken.hasSuffix("The rest is in the chat window."))
    }

    @Test func emptyStaysEmpty() {
        #expect(SpokenText.clean("🎉✨").isEmpty)
        #expect(SpokenText.clean("   ").isEmpty)
    }
}
