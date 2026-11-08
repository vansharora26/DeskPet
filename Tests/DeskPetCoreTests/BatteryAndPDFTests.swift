import Foundation
import Testing
@testable import DeskPetCore

@Suite struct BatteryMoodTests {
    func r(_ level: Int, charging: Bool = false, plugged: Bool = false) -> BatteryReading {
        BatteryReading(level: level, isCharging: charging, isPluggedIn: plugged)
    }

    @Test func moodsFromLevels() {
        #expect(BatteryMood.of(nil) == .none)
        #expect(BatteryMood.of(r(80)) == .normal)
        #expect(BatteryMood.of(r(20)) == .low)
        #expect(BatteryMood.of(r(21)) == .normal)
        #expect(BatteryMood.of(r(10)) == .critical)
        #expect(BatteryMood.of(r(5, charging: true, plugged: true)) == .charging)
        #expect(BatteryMood.of(r(100, plugged: true)) == .full)
        #expect(BatteryMood.of(r(80, plugged: true)) == .normal) // optimised charging hold
        #expect(BatteryReading(level: 140, isCharging: false, isPluggedIn: false).level == 100)
    }

    @Test func speechOnlyOnMeaningfulChanges() {
        #expect(BatteryMood.line(from: .normal, to: .low, level: 19, name: "Mochi")?.contains("19%") == true)
        #expect(BatteryMood.line(from: .low, to: .critical, level: 9, name: "Mochi")?.contains("Plug me in") == true)
        #expect(BatteryMood.line(from: .critical, to: .charging, level: 9, name: "Mochi")?.contains("power") == true)
        #expect(BatteryMood.line(from: .charging, to: .full, level: 100, name: "Mochi") != nil)
        #expect(BatteryMood.line(from: .critical, to: .low, level: 11, name: "Mochi") == nil) // no nagging while it recovers
        #expect(BatteryMood.line(from: .none, to: .low, level: 15, name: "Mochi") == nil)     // launch: stay quiet
        #expect(BatteryMood.line(from: .charging, to: .normal, level: 60, name: "Mochi") == nil)
    }

    @Test func drainedCatsAreLazier() {
        #expect(BatteryMood.normal.walkSpeedFactor == 1)
        #expect(BatteryMood.low.walkSpeedFactor < 1)
        #expect(BatteryMood.critical.walkSpeedFactor < BatteryMood.low.walkSpeedFactor)
        #expect(BatteryMood.critical.restFactor > BatteryMood.low.restFactor)
        #expect(BatteryMood.low.isDrained && BatteryMood.critical.isDrained && !BatteryMood.charging.isDrained)
    }
}

@Suite struct PDFCoreTests {
    @Test func pageRanges() throws {
        #expect(try PageRanges.parse("1-3, 5", pageCount: 10) == [0, 1, 2, 4])
        #expect(try PageRanges.parse("8-", pageCount: 10) == [7, 8, 9])
        #expect(try PageRanges.parse("-2", pageCount: 10) == [0, 1])
        #expect(try PageRanges.parse("3–1", pageCount: 10) == [2, 1, 0])
        #expect(try PageRanges.parse("2, 2, 1-2", pageCount: 10) == [1, 0])
        #expect(throws: PageRanges.ParseError.outOfRange(12, pageCount: 10)) { try PageRanges.parse("12", pageCount: 10) }
        #expect(throws: PageRanges.ParseError.empty) { try PageRanges.parse(" , ", pageCount: 10) }
        #expect(throws: PageRanges.ParseError.invalid("abc")) { try PageRanges.parse("abc", pageCount: 10) }
        #expect(throws: PageRanges.ParseError.invalid("-")) { try PageRanges.parse("-", pageCount: 10) }
    }

    @Test func outputNamesNeverOverwrite() {
        let input = URL(fileURLWithPath: "/tmp/Report.docx")
        var taken: Set<String> = ["/tmp/Report.pdf"]
        #expect(PDFFiles.output(for: input, suffix: nil, exists: { taken.contains($0.path) }).lastPathComponent == "Report 2.pdf")
        taken = []
        #expect(PDFFiles.output(for: input, suffix: "merged", exists: { taken.contains($0.path) }).lastPathComponent == "Report (merged).pdf")
    }

    @Test func suggestedToolForDroppedFiles() {
        func u(_ names: String...) -> [URL] { names.map { URL(fileURLWithPath: "/tmp/\($0)") } }
        #expect(PDFTool.suggested(for: u("a.docx", "b.rtf")) == .toPDF)
        #expect(PDFTool.suggested(for: u("a.png", "b.HEIC")) == .images)
        #expect(PDFTool.suggested(for: u("a.pdf", "b.pdf")) == .merge)
        #expect(PDFTool.suggested(for: u("a.pdf")) == .compress)
        #expect(PDFTool.suggested(for: u("a.pdf", "b.png")) == .merge)
    }

    @Test func launcherPhrases() {
        func parse(_ s: String) -> AppCommand? { CommandParser.parse(s, now: Date(), calendar: .current) }
        #expect(parse("word to pdf") == .pdfTool(.toPDF))
        #expect(parse("convert docx to pdf") == .pdfTool(.toPDF))
        #expect(parse("merge pdfs") == .pdfTool(.merge))
        #expect(parse("combine pdf files") == .pdfTool(.merge))
        #expect(parse("images to pdf") == .pdfTool(.images))
        #expect(parse("split pdf") == .pdfTool(.split))
        #expect(parse("compress pdf") == .pdfTool(.compress))
        #expect(parse("rotate pdf") == .pdfTool(.rotate))
        #expect(parse("password protect pdf") == .pdfTool(.protect))
        #expect(parse("remove pdf password") == .pdfTool(.unlock))
        #expect(parse("pdf to images") == .pdfTool(.toImages))
        #expect(parse("extract text from pdf") == .pdfTool(.toText))
        #expect(parse("pdf tools") == .open(.pdfTools))
        #expect(parse("pdf") == .open(.pdfTools))
    }
}

@Suite struct ClaudeConnectTests {
    @Test func oldSavedModelsMoveToCurrentOnes() {
        #expect(ClaudeModelInfo.migrated("claude-opus-5") == "claude-opus-5-5")
        #expect(ClaudeModelInfo.migrated("claude-sonnet-5") == "claude-sonnet-5-5")
        #expect(ClaudeModelInfo.migrated("claude-haiku-4-5") == "claude-haiku-5-5")
        #expect(ClaudeModelInfo.migrated("claude-sonnet-5-5") == "claude-sonnet-5-5")
        #expect(ClaudeModelInfo.migrated("something-else") == ClaudeModelInfo.defaultID)
        #expect(ClaudeModelInfo.find(ClaudeModelInfo.defaultID) != nil)
        #expect(ClaudeModelInfo.find("claude-haiku-5-5")?.refusalFallback == false)
    }

    @Test func pastedKeysAreCleanedAndChecked() throws {
        let real = "sk-ant-api03-" + String(repeating: "a", count: 40)
        #expect(try ClaudeKey.clean("  \(real)\n") == real)
        #expect(try ClaudeKey.clean("\"\(real)\"") == real)
        #expect(throws: ClaudeKey.Problem.empty) { try ClaudeKey.clean("  ") }
        #expect(throws: ClaudeKey.Problem.notAKey) { try ClaudeKey.clean("hello") }
        #expect(throws: ClaudeKey.Problem.notAKey) { try ClaudeKey.clean("sk-ant-short") }
        #expect(throws: ClaudeKey.Problem.adminKey) { try ClaudeKey.clean("sk-ant-admin01-" + String(repeating: "b", count: 40)) }
        #expect(throws: ClaudeKey.Problem.hasSpaces) { try ClaudeKey.clean("sk-ant-api03 " + String(repeating: "c", count: 40)) }
        #expect(ClaudeKey.masked(real) == "sk-ant-…aaaa")
    }
}
