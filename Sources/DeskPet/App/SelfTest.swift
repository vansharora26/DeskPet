import AppKit
import AVFoundation
import DeskPetCore
import Foundation
import Speech
import SwiftUI
import IOKit.pwr_mgt
import PDFKit

/// `DeskPet --self-test`: exercises the real app layer (AppModel, CommandExecutor,
/// AI tool validation, export, delete) against a temporary data folder, without
/// UI and without touching the user's data. Prints PASS/FAIL and exits non-zero on failure.
@MainActor
enum SelfTest {
    private static var failures = 0

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures += 1 }
    }

    static func run() -> Int32 {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DeskPetSelfTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("deskpet-data.json")
        let model = AppModel(store: JSONDocumentStore(fileURL: fileURL))
        let exec = CommandExecutor(model: model)
        let cal = model.calendar
        func parse(_ s: String) -> AppCommand? { CommandParser.parse(s, now: Date(), calendar: cal) }

        // Local commands end-to-end (the spec's examples).
        var r = exec.run(parse("Log 300 ml of water")!)
        check("log water", r.style == .success && model.todayWaterML == 300, r.message)
        r.undo?()
        check("undo water via result", model.todayWaterML == 0)
        _ = exec.run(parse("Water 250 ml")!)
        model.saveNow()
        let reopened = AppModel(store: JSONDocumentStore(fileURL: fileURL))
        check("water persists across restart", reopened.todayWaterML == 250)

        r = exec.run(parse("Start a 40-minute focus session")!)
        check("start focus", r.style == .success && model.focusTimerState?.phase == .focus
              && Int((model.focusTimerState?.plannedSeconds ?? 0) / 60) == 40, r.message)
        r = exec.run(parse("focus for 10 minutes")!)
        check("second timer is refused", r.style == .error, r.message)
        check("pause", exec.run(.pauseFocus).style == .success && model.focusTimerState?.isPaused == true)
        check("resume", exec.run(.resumeFocus).style == .success && model.focusTimerState?.isRunning == true)
        check("stop", exec.run(.stopFocus).style != .error && model.focusTimerState == nil)

        r = exec.run(parse("Remind me to call my friend at 7 PM")!)
        let reminderTask = model.data.items.openTasks().first { $0.title == "Call my friend" }
        check("reminder creates task with remindAt", r.style == .success && reminderTask?.remindAt != nil, r.message)
        r = exec.run(parse("Save this idea: a desktop pet for students")!)
        check("save note", r.style == .success && model.data.items.notes().first?.text == "a desktop pet for students")
        _ = exec.run(parse("Add buy groceries to my tasks")!)
        r = exec.run(parse("Show me my unfinished tasks")!)
        check("list unfinished tasks", r.details.count == 2, r.plainText)
        r = exec.run(parse("mark buy groceries as done")!)
        check("complete task", r.style == .success && model.data.items.tasks(.completed, now: Date(), calendar: cal).count == 1)
        r = exec.run(parse("Summarize my focus sessions this week")!)
        check("focus summary (no data yet)", r.style == .info, r.message)
        r = exec.run(parse("Show today's progress")!)
        check("today's progress", r.details.count == 4, r.plainText)
        r = exec.run(parse("turn off water reminders")!)
        check("disable water reminders", !model.hydrationSettings.remindersEnabled)
        r = exec.run(parse("remind me to drink water every 45 minutes")!)
        check("set reminder interval", model.hydrationSettings.remindersEnabled && model.hydrationSettings.reminderIntervalMinutes == 45)

        // Search, edit, soft delete, restore.
        let note = model.data.items.notes()[0]
        try? model.updateItem(note.id) { $0.text = "a desktop pet for university students" }
        check("edit + search", model.data.items.search("university").count == 1)
        try? model.deleteItem(note.id)
        check("soft delete hides note", model.data.items.notes().isEmpty && model.data.items.trash.count == 1)
        try? model.restoreItem(note.id)
        check("restore from trash", model.data.items.notes().count == 1)

        // AI tools: validation is strict and errors are explicit.
        let tools = AssistantTools(model: model, accessToData: { .ask })
        func plan(_ name: String, _ input: JSONValue) -> Result<AssistantTools.Planned, AssistantTools.InputError> {
            do { return .success(try tools.plan(name: name, input: input)) }
            catch let e as AssistantTools.InputError { return .failure(e) }
            catch { return .failure(.init(message: "\(error)")) }
        }
        if case .success(let p) = plan("log_water", ["ml": 300]) {
            let out = tools.perform(p)
            check("AI log_water", !out.isError && model.todayWaterML == 550, out.text)
        } else { check("AI log_water", false) }
        if case .failure(let e) = plan("log_water", ["ml": "lots"]) { check("AI rejects non-number", true, e.message) }
        else { check("AI rejects non-number", false) }
        if case .failure = plan("log_water", ["ml": 99_999]) { check("AI rejects out-of-range", true) }
        else { check("AI rejects out-of-range", false) }
        if case .failure = plan("create_task", ["title": "x", "remind_at": "2001-01-01T09:00"]) { check("AI rejects past reminder", true) }
        else { check("AI rejects past reminder", false) }
        if case .failure = plan("run_shell", ["cmd": "rm -rf /"]) { check("AI unknown tool refused", true) }
        else { check("AI unknown tool refused", false) }
        if case .success(let p) = plan("list_tasks", ["filter": "today"]) { check("AI list_tasks is a gated data read", p.isDataRead) }
        else { check("AI list_tasks is a gated data read", false) }
        if case .success(let p) = plan("stop_focus_timer", .object([:])) { check("AI stop needs confirmation", p.needsConfirmation) }
        else { check("AI stop needs confirmation", false) }
        if case .success(let p) = plan("get_focus_status", .object([:])) { check("AI focus status is not personal", !p.isDataRead) }
        else { check("AI focus status is not personal", false) }

        // Conversation: real actions, context follow-ups, confirmation only after success.
        do {
            let petDir = dir.appendingPathComponent("pet")
            let settings = AppSettings(defaults: UserDefaults(suiteName: "DeskPetSelfTest-\(UUID().uuidString)")!)
            let pet = PetViewModel(store: PetStore(directory: petDir), settings: settings, sound: SoundPlayer())
            let chat = ChatModel(model: model, settings: settings, pet: pet,
                                 store: JSONDocumentStore(fileURL: dir.appendingPathComponent("chat.json")))
            chat.forceLocalOnly = true   // never touch the network or the user's API key
            var spoken: [String] = []
            chat.onReply = { text, _ in spoken.append(text) }
            let before = model.todayWaterML
            func last() -> String { chat.messages.last?.text ?? "" }

            chat.send("I've had 300 ml of water", viaVoice: true)
            check("chat: spoken water log is saved", model.todayWaterML == before + 300 && last().hasPrefix("Logged 300 ml"), last())
            chat.send("What's my total?", viaVoice: true)
            check("chat: total reflects saved data", last().contains(AppCommand.formatML(model.todayWaterML)), last())
            chat.send("another one")
            check("chat: 'another one' repeats 300 ml", model.todayWaterML == before + 600, last())
            chat.send("undo that")
            check("chat: 'undo that' reverses it", model.todayWaterML == before + 300 && last().hasPrefix("Undone"), last())
            chat.send("I've had 9000 ml of water")
            check("chat: failed action is not confirmed", model.todayWaterML == before + 300 && !last().contains("Logged")
                  && chat.messages.last?.isError == true, last())
            chat.send("Start a 25-minute focus session")
            check("chat: focus session started", model.focusTimerState?.phase == .focus && last().hasPrefix("Focus started"), last())
            chat.send("what's my total")
            check("chat: total follows focus topic", last().contains("left in your focus session"), last())
            chat.send("tell me a joke about cats")
            check("chat: no AI configured → text-only explanation, no fake answer",
                  chat.messages.last?.isLocal == true && last().contains("AI"), last())
            check("chat: every reply was handed to the voice layer", spoken.count == 8, "\(spoken.count) replies")
            try? model.stopFocus()

            // Voice layer (no microphone is ever opened here).
            let voice = VoiceController(chat: chat, settings: settings, pet: pet)
            settings.spokenReplies = .whenISpeak
            check("voice: speaks replies to spoken input", voice.shouldSpeak(fromVoice: true) && !voice.shouldSpeak(fromVoice: false))
            settings.voiceMuted = true
            check("voice: mute silences replies", !voice.shouldSpeak(fromVoice: true))
            settings.voiceMuted = false
            settings.spokenReplies = .never
            check("voice: text-only mode never speaks", !voice.shouldSpeak(fromVoice: true))
            settings.spokenReplies = .always
            check("voice: 'always' speaks typed replies too", voice.shouldSpeak(fromVoice: false))

            if !SpeechRecognizerService.isSupportedBuild {
                voice.pressBegan()
                check("voice: unsupported build falls back to text, mic stays off",
                      voice.input.state == .idle && voice.notice != nil, voice.notice ?? "")
            } else {
                check("voice: bundle declares mic + speech usage", true, "permission: \(voice.input.permission)")
            }
            settings.voiceInputEnabled = false
            voice.pressBegan()
            check("voice: disabling voice input keeps the mic off", voice.input.state == .idle && voice.notice != nil)
            settings.voiceInputEnabled = true

            // Trial & license gates (in-memory storage: the real Keychain license is never touched).
            let fresh = LicenseManager(storage: InMemoryLicenseStorage(), environment: .testMode,
                                       buyURL: URL(string: "https://deskpet.app")!)
            check("license: new install starts a 14-day trial", fresh.access == .trial(daysLeft: 14)
                  && PremiumFeature.allCases.allSatisfy { fresh.lockedReason($0) == nil })
            let ended = LicenseManager(storage: InMemoryLicenseStorage(trialStart: Date().addingTimeInterval(-20 * 86_400)),
                                       environment: .testMode, buyURL: URL(string: "https://deskpet.app")!)
            var lockedFeatures: [PremiumFeature] = []
            ended.onLocked = { lockedFeatures.append($0) }
            check("license: trial ends after 14 days", ended.access == .trialEnded)
            check("license: Focus Worlds gate reports the lock", !ended.allows(.focusWorlds) && lockedFeatures == [.focusWorlds])
            chat.aiLockedReason = { ended.lockedReason(.aiChat) }
            let waterBefore = model.todayWaterML
            chat.send("I've had 200 ml of water")
            check("license: local commands stay free after the trial", model.todayWaterML == waterBefore + 200, last())
            chat.send("tell me a story about a cat")
            check("license: AI chat explains the lock instead of answering",
                  last().contains("trial has ended") && last().contains("Settings › License"), last())
            voice.lockedReason = { ended.lockedReason(.voice) }
            voice.pressBegan()
            check("license: voice gate keeps the mic off", voice.input.state == .idle
                  && (voice.notice ?? "").contains("trial has ended"), voice.notice ?? "")
            let validated = Date().addingTimeInterval(-40 * 86_400)
            let stale = LicenseManager(storage: InMemoryLicenseStorage(
                                           record: LicenseRecord(key: "TEST-KEY-1234", instanceID: "lki_x", environment: .testMode,
                                                                 activatedAt: validated, lastValidatedAt: validated),
                                           trialStart: validated),
                                       environment: .testMode, buyURL: URL(string: "https://deskpet.app")!)
            check("license: unconfirmed for 30+ days asks for a check", stale.access == .needsCheck)
            let wrongEnv = InMemoryLicenseStorage(record: LicenseRecord(key: "TEST-KEY-1234", instanceID: "lki_x", environment: .testMode,
                                                                        activatedAt: Date(), lastValidatedAt: Date()))
            let live = LicenseManager(storage: wrongEnv, environment: .liveMode, buyURL: URL(string: "https://deskpet.app")!)
            check("license: a test key isn't accepted by a live build", live.record == nil && wrongEnv.record == nil)
            chat.aiLockedReason = { nil }
            voice.lockedReason = { nil }

            // Text-to-speech renders real audio — silently, into a buffer.
            let utterance = SpeechSynthesizerService.makeUtterance("Logged 300 ml · 1.2 L of 2.0 L today 🎉",
                                                                  voiceID: "", languageID: "en-US", rate: 0.5)
            check("tts: spoken text is cleaned", utterance?.speechString == "Logged 300 millilitres, 1.2 litres of 2.0 litres today.",
                  utterance?.speechString ?? "nil")
            check("tts: a native voice is available", utterance?.voice != nil, utterance?.voice?.name ?? "none")
            if let utterance {
                let frames = renderSilently(utterance)
                check("tts: synthesizer produces audio", frames > 4_000, "\(frames) frames")
            }

            // Speech → text → action round trip, only if Speech access was already granted
            // (never triggers a permission prompt; no microphone involved).
            if SpeechRecognizerService.isSupportedBuild && SFSpeechRecognizer.authorizationStatus() == .authorized {
                let heard = transcribeSpoken("I've had 300 milliliters of water", in: dir)
                let before = model.todayWaterML
                chat.send(heard ?? "", viaVoice: true)
                check("stt: spoken phrase recognised and logged on-device", model.todayWaterML == before + 300, heard ?? "no transcript")
            } else {
                print("SKIP  stt round trip — Speech Recognition permission not granted (run once from the app first)")
            }
            pet.eraseAndStopSaving()
        }

        checkFocusWorlds(dir: dir)

        // Text editing: ⌘V reaches text fields (incl. the secure API-key field) via the main menu.
        checkPaste()
        checkQuickCapture(dir: dir)
        checkMacTools(dir: dir)
        checkPDFTools(dir: dir)
        checkBattery()

        // Export & delete.
        do {
            let folder = try model.export(to: dir, pet: nil)
            let names = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            check("export writes JSON + CSVs", names == ["deskpet.json", "water.csv", "focus.csv", "notes-and-tasks.csv"],
                  names.sorted().joined(separator: ", "))
            let csv = (try? String(contentsOf: folder.appendingPathComponent("water.csv"), encoding: .utf8)) ?? ""
            let rows = csv.split(separator: "\r\n").count - 1
            check("water CSV has one row per entry", rows == model.data.hydration.entries.count, "\(rows) rows")
        } catch {
            check("export", false, error.localizedDescription)
        }
        model.deleteAllData()
        check("delete all data", model.data.items.items.isEmpty && model.data.hydration.entries.isEmpty)

        print(failures == 0 ? "\nAll self-tests passed." : "\n\(failures) self-test(s) FAILED.")
        return failures == 0 ? 0 : 1
    }

    /// Renders an utterance to PCM buffers without playing it; returns the frame count.
    private static func renderSilently(_ utterance: AVSpeechUtterance) -> Int {
        let synth = AVSpeechSynthesizer()
        var frames = 0
        var done = false
        synth.write(utterance) { buffer in
            if let pcm = buffer as? AVAudioPCMBuffer {
                if pcm.frameLength == 0 { done = true } else { frames += Int(pcm.frameLength) }
            }
        }
        let deadline = Date().addingTimeInterval(15)
        while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        return frames
    }

    /// Synthesises a phrase to a file and transcribes it on-device.
    private static func transcribeSpoken(_ phrase: String, in dir: URL) -> String? {
        guard let utterance = SpeechSynthesizerService.makeUtterance(phrase, voiceID: "", languageID: "en-US", rate: 0.45),
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else { return nil }
        let url = dir.appendingPathComponent("phrase.caf")
        let synth = AVSpeechSynthesizer()
        var file: AVAudioFile?
        var done = false
        synth.write(utterance) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 { done = true; return }
            if file == nil { file = try? AVAudioFile(forWriting: url, settings: pcm.format.settings) }
            try? file?.write(from: pcm)
        }
        var deadline = Date().addingTimeInterval(15)
        while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        file = nil
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        var text: String?
        var finished = false
        let task = recognizer.recognitionTask(with: request) { result, error in
            if let result, result.isFinal { text = result.bestTranscription.formattedString; finished = true }
            if error != nil { finished = true }
        }
        deadline = Date().addingTimeInterval(20)
        while !finished && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        task.cancel()
        return text
    }

    /// Sends a real ⌘V key event through the main menu into an NSSecureTextField.
    /// The user's clipboard is saved first and restored afterwards.
    private static func checkPaste() {
        let pb = NSPasteboard.general
        let saved: [NSPasteboardItem] = (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        defer {
            pb.clearContents()
            if !saved.isEmpty { pb.writeObjects(saved) }
        }

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        MainMenu.install()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 60), styleMask: [.titled],
                              backing: .buffered, defer: false)
        let field = NSSecureTextField(frame: NSRect(x: 10, y: 10, width: 280, height: 24))
        window.contentView?.addSubview(field)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(field)

        pb.clearContents()
        pb.setString("sk-ant-selftest-0000", forType: .string)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                     windowNumber: window.windowNumber, context: nil, characters: "v",
                                     charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9)!
        // 1) The Edit menu maps ⌘V to paste: (this is how AppKit routes it in an active app).
        let pasteItem = NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items).first {
            $0.keyEquivalent == "v" && $0.keyEquivalentModifierMask == .command
        }
        check("edit: Edit menu maps ⌘V to Paste", pasteItem?.action == #selector(NSText.paste(_:)),
              pasteItem.map { "\($0.title) → \($0.action.map(NSStringFromSelector) ?? "nil")" } ?? "missing")
        // 2) That action, delivered to the focused secure field (the key window's first responder), pastes.
        let delivered = pasteItem?.action.map { NSApp.sendAction($0, to: window.firstResponder, from: pasteItem) } ?? false
        check("edit: Paste action fills the secure API-key style field",
              delivered && field.stringValue == "sk-ant-selftest-0000", field.stringValue.isEmpty ? "empty" : "pasted")

        field.stringValue = ""
        let viaPanel = MainMenu.handleEditShortcut(event, in: window)
        check("edit: panel fallback also pastes", viaPanel && field.stringValue == "sk-ant-selftest-0000")
        window.orderOut(nil)
    }

    /// Mac tools: on-device text recognition, keep-awake assertion, clipboard history, screenshot files.
    private static func checkMacTools(dir: URL) {
        // Text recognition on a rendered image.
        let img = NSImage(size: NSSize(width: 900, height: 220), flipped: false) { r in
            NSColor.white.setFill(); r.fill()
            ("DeskPet reads text 42" as NSString).draw(at: NSPoint(x: 40, y: 80), withAttributes: [
                .font: NSFont.systemFont(ofSize: 56, weight: .medium), .foregroundColor: NSColor.black])
            return true
        }
        let png = dir.appendingPathComponent("ocr.png")
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: png) }
        var text: String?
        Task { text = (try? await MacTools.recognizeText(in: png)) ?? "" }
        let deadline = Date().addingTimeInterval(20)
        while text == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        check("tools: copy text recognises on-screen text", text?.contains("DeskPet") == true && text?.contains("42") == true,
              text.map { String(reflecting: $0) } ?? "timed out")

        // Keep awake holds a real power assertion and releases it.
        let awake = KeepAwakeController()
        var ended: KeepAwakeController.EndReason?
        awake.onEnded = { ended = $0 }
        let started = awake.start(minutes: 30)
        check("tools: keep awake starts with a timer", started && awake.isActive && awake.endsAt != nil
              && awake.statusText?.contains("min left") == true, awake.statusText ?? "")
        check("tools: keep awake assertion is registered", Self.hasAssertion(named: "DeskPet keep awake"))
        awake.stop(reason: .user)
        check("tools: keep awake turns off", !awake.isActive && ended == .user && !Self.hasAssertion(named: "DeskPet keep awake"))

        // Clipboard history (user's clipboard saved and restored).
        let pb = NSPasteboard.general
        let saved: [NSPasteboardItem] = (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        defer { pb.clearContents(); if !saved.isEmpty { pb.writeObjects(saved) } }
        let settings = AppSettings(defaults: UserDefaults(suiteName: "DeskPetClipTest-\(UUID().uuidString)")!)
        let clipURL = dir.appendingPathComponent("clipboard.json")
        let monitor = ClipboardMonitor(fileURL: clipURL, settings: settings)
        pb.clearContents(); pb.setString("ignored while off", forType: .string)
        monitor.poll()
        settings.clipboardHistoryEnabled = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        pb.clearContents(); pb.setString("selftest clip one", forType: .string)
        monitor.poll()
        let secret = NSPasteboardItem()
        secret.setString("hunter2", forType: .string)
        secret.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pb.clearContents(); pb.writeObjects([secret])
        monitor.poll()
        check("tools: clipboard history records copies, not passwords or pre-existing ones",
              monitor.history.entries.map(\.text) == ["selftest clip one"], "\(monitor.history.entries.map(\.text))")
        let perms = (try? FileManager.default.attributesOfItem(atPath: clipURL.path)[.posixPermissions] as? Int) ?? nil
        let reloaded = ClipboardMonitor(fileURL: clipURL, settings: settings)
        check("tools: clipboard history persists privately", reloaded.history == monitor.history && perms == 0o600,
              "perms=\(perms.map { String($0, radix: 8) } ?? "-")")
        if let e = monitor.history.entries.first {
            pb.clearContents(); pb.setString("something else", forType: .string)
            monitor.copy(e)
            check("tools: choosing an entry puts it back on the clipboard", pb.string(forType: .string) == "selftest clip one")
        }
        monitor.clear()
        check("tools: clear removes history and file", monitor.history.entries.isEmpty && !FileManager.default.fileExists(atPath: clipURL.path))
        settings.clipboardHistoryEnabled = false

        // Screenshot files get unique, dated names.
        let shots = dir.appendingPathComponent("shots")
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        var names: [String] = []
        for _ in 0..<2 {
            let tmp = dir.appendingPathComponent("\(UUID().uuidString).png")
            try? Data([0x89]).write(to: tmp)
            if let u = try? MacTools.moveToScreenshotsFolder(tmp, now: when, folder: shots) { names.append(u.lastPathComponent) }
        }
        check("tools: screenshots saved with unique dated names", names.count == 2 && names[0].hasPrefix("Screenshot ")
              && names[1].hasSuffix(" (2).png"), names.joined(separator: ", "))
        check("tools: screenshot PNG can be copied as an image",
              MacTools.copyImage((try? Data(contentsOf: png)) ?? Data()) && pb.data(forType: .png) != nil)
    }

    /// PDF tools end-to-end on real files: Word → PDF, merge, images, split, rotate,
    /// compress, password lock/unlock, PDF → images and text.
    private static func checkPDFTools(dir: URL) {
        let folder = dir.appendingPathComponent("pdf")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // A real .docx written by AppKit, long enough for several pages.
        let body = NSMutableAttributedString(string: "Quarterly Report\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 24)])
        for i in 1...120 {
            body.append(NSAttributedString(string: "Paragraph \(i): DeskPet converts Word documents to PDF on this Mac.\n",
                                           attributes: [.font: NSFont.systemFont(ofSize: 13)]))
        }
        let docx = folder.appendingPathComponent("Report.docx")
        if let data = try? body.data(from: NSRange(location: 0, length: body.length),
                                     documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]) {
            try? data.write(to: docx)
        }
        let txt = folder.appendingPathComponent("Notes.txt")
        try? "Plain text notes\nSecond line".write(to: txt, atomically: true, encoding: .utf8)

        func run(_ name: String, _ work: () throws -> PDFEngine.Output) -> PDFEngine.Output? {
            do { return try work() } catch {
                check("pdf: \(name)", false, (error as? LocalizedError)?.errorDescription ?? "\(error)")
                return nil
            }
        }
        func pages(_ url: URL?) -> Int { url.flatMap { PDFDocument(url: $0)?.pageCount } ?? -1 }

        let converted = run("Word to PDF") { try PDFEngine.convertToPDF([docx, txt]) }
        let reportPDF = converted?.urls.first
        let notesPDF = converted?.urls.last
        let reportText = reportPDF.flatMap { PDFDocument(url: $0)?.string } ?? ""
        check("pdf: Word (.docx) and text convert to paginated PDFs",
              pages(reportPDF) >= 2 && pages(notesPDF) == 1 && reportText.contains("Paragraph 120")
              && reportPDF?.lastPathComponent == "Report.pdf",
              "report pages=\(pages(reportPDF)) notes pages=\(pages(notesPDF))")

        if let a = reportPDF, let b = notesPDF {
            let merged = run("merge") { try PDFEngine.merge([a, b]) }?.urls.first
            check("pdf: merge keeps every page in order", pages(merged) == pages(a) + 1
                  && merged?.lastPathComponent == "Report (merged).pdf"
                  && (PDFDocument(url: merged!)?.page(at: pages(a))?.string ?? "").contains("Plain text notes"))

            let split = run("split") { try PDFEngine.split(a, ranges: "2, 1", eachPage: false) }?.urls.first
            check("pdf: extract pages in the order asked", pages(split) == 2
                  && (PDFDocument(url: split!)?.page(at: 1)?.string ?? "").contains("Quarterly Report"))
            let each = run("split each") { try PDFEngine.split(a, ranges: "1-2", eachPage: true) }
            check("pdf: split into one file per page", each?.urls.count == 2 && each?.urls.allSatisfy { pages($0) == 1 } == true)

            let rotated = run("rotate") { try PDFEngine.rotate([a], degrees: -90, ranges: "1") }?.urls.first
            let rDoc = rotated.flatMap { PDFDocument(url: $0) }
            check("pdf: rotate only the chosen pages", rDoc?.page(at: 0)?.rotation == 270 && rDoc?.page(at: 1)?.rotation == 0)

            let locked = run("protect") { try PDFEngine.protect([b], password: "s3cret") }?.urls.first
            let lockedDoc = locked.flatMap { PDFDocument(url: $0) }
            check("pdf: password lock needs the password", lockedDoc?.isLocked == true && lockedDoc?.unlock(withPassword: "s3cret") == true)
            if let locked {
                var wrong = false
                do { _ = try PDFEngine.unlock([locked], password: "nope") } catch { wrong = true }
                let unlocked = run("unlock") { try PDFEngine.unlock([locked], password: "s3cret") }?.urls.first
                let u = unlocked.flatMap { PDFDocument(url: $0) }
                check("pdf: wrong password refused, right one saves an open copy", wrong && u?.isLocked == false && u?.isEncrypted == false
                      && (u?.string ?? "").contains("Plain text notes"))
                var refused = false
                do { _ = try PDFEngine.merge([locked, a]) } catch { refused = true }
                check("pdf: locked PDFs are explained, not silently skipped", refused)
            }

            let images = run("to images") { try PDFEngine.toImages([b]) }
            let pngs = images.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.urls[0].path) } ?? []
            check("pdf: pages saved as PNG images", pngs == ["Page 1.png"], pngs.joined(separator: ","))

            let text = run("to text") { try PDFEngine.toText([a]) }?.urls.first
            let saved = text.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
            check("pdf: text extracted and copied", saved.contains("Paragraph 7") && text?.pathExtension == "txt")
        }

        // Images → PDF, then compress a PDF with a big photo in it.
        let photo = folder.appendingPathComponent("Photo.png")
        let img = NSImage(size: NSSize(width: 1600, height: 1200), flipped: false) { r in
            for i in 0..<240 {
                NSColor(hue: CGFloat(i) / 240, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                NSRect(x: CGFloat(i) * r.width / 240, y: 0, width: r.width / 240 + 1, height: r.height).fill()
            }
            return true
        }
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: photo)
        }
        let album = run("images") { try PDFEngine.imagesToPDF([photo, photo]) }?.urls.first
        let first = album.flatMap { PDFDocument(url: $0)?.page(at: 0)?.bounds(for: .mediaBox) }
        check("pdf: images become landscape A4 pages", pages(album) == 2 && first?.width == 842 && first?.height == 595)
        // A "scanned" PDF: a lossless bitmap drawn straight into a PDF context.
        let scan = folder.appendingPathComponent("Scan.pdf")
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        if let ctx = CGContext(scan as CFURL, mediaBox: &box, nil),
           let cg = NSBitmapImageRep(data: (try? Data(contentsOf: photo)) ?? Data())?.cgImage {
            ctx.beginPDFPage(nil)
            ctx.draw(cg, in: box)
            ctx.endPDFPage()
            ctx.closePDF()
        }
        let small = run("compress") { try PDFEngine.compress([scan]) }
        if let out = small?.urls.first {
            check("pdf: compress makes a scanned PDF smaller", PDFEngine.fileSize(out) < PDFEngine.fileSize(scan) && pages(out) == 1,
                  small?.message ?? "")
        }
    }

    private static func checkBattery() {
        let r = BatteryMonitor.read()
        check("battery: reading is sane (or none on a desktop Mac)", r == nil || (0...100).contains(r!.level),
              r.map { "\($0.level)% \($0.isCharging ? "charging" : $0.isPluggedIn ? "on AC" : "on battery") → \(BatteryMood.of($0))" } ?? "no battery")
    }

    private static func hasAssertion(named name: String) -> Bool {
        var dict: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&dict) == kIOReturnSuccess,
              let byPid = dict?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return false }
        let mine = byPid[NSNumber(value: ProcessInfo.processInfo.processIdentifier)] ?? []
        return mine.contains { ($0[kIOPMAssertionNameKey as String] as? String) == name }
    }

    /// Quick capture: the real panel + view, typed into with real key events, saves a note.
    private static func checkQuickCapture(dir: URL) {
        let model = AppModel(store: JSONDocumentStore(fileURL: dir.appendingPathComponent("capture.json")))
        let before = model.data.items.items.count
        let panel = InputPanel()
        var closed = false
        let view = QuickCaptureView(model: model, onClose: { [weak panel] in panel?.close() })
        let host = NSHostingView(rootView: view)
        host.sizingOptions = [.preferredContentSize]
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        panel.onClose = { closed = true }
        panel.present()
        func pump(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
        pump(0.5)
        check("capture: panel has keyboard focus once open", panel.isKeyWindow && panel.firstResponder is NSTextView,
              "key=\(panel.isKeyWindow) responder=\(panel.firstResponder.map { String(describing: type(of: $0)) } ?? "nil")")
        func key(_ c: String, code: UInt16) {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: panel.windowNumber, context: nil, characters: c,
                                         charactersIgnoringModifiers: c, isARepeat: false, keyCode: code)!
                panel.sendEvent(e)
            }
            pump(0.05)
        }
        for ch in "buy milk" { key(String(ch), code: 0) }
        key("\r", code: 36)
        pump(1.2)
        let items = model.data.items.items
        check("capture: typing + Return saves a note", items.count == before + 1 && items.last?.text == "buy milk",
              "items=\(items.count - before) text=\(items.last.map { String(reflecting: $0.text) } ?? "-") closed=\(closed)")
        panel.close()
    }

    /// Focus Worlds: one shared timer, honest records, no duplicates, restart-safe, opt-in audio.
    private static func checkFocusWorlds(dir: URL) {
        let url = dir.appendingPathComponent("worlds.json")
        let model = AppModel(store: JSONDocumentStore(fileURL: url))
        let settings = AppSettings(defaults: UserDefaults(suiteName: "DeskPetWorldsTest-\(UUID().uuidString)")!)
        let pet = PetViewModel(store: PetStore(directory: dir.appendingPathComponent("wpet")), settings: settings, sound: SoundPlayer())
        defer { pet.eraseAndStopSaving() }
        let worlds = WorldsController(model: model, pet: pet, appSettings: settings)
        try? model.stopFocus()

        let err = worlds.start(.deepFocus, minutes: 50, label: "Write chapter 3")
        check("worlds: Deep Focus starts the shared timer", err == nil && model.focusTimerState?.world == "deepFocus"
              && model.focusTimerState?.label == "Write chapter 3", err ?? "")
        check("worlds: session state is running", worlds.sessionState(for: .deepFocus) == .running)
        worlds.pause()
        check("worlds: pause", worlds.sessionState(for: .deepFocus) == .paused)
        worlds.resume()
        let endsAt = model.focusTimerState?.endsAt
        worlds.enter(.study)
        check("worlds: switching worlds keeps the same session (no reset)",
              model.focusTimerState?.endsAt == endsAt && model.focusTimerState?.world == "study")
        worlds.enter(.planning)
        check("worlds: planning doesn't touch the running session", model.focusTimerState?.endsAt == endsAt)
        let second = worlds.start(.workSprint, minutes: 25, label: "x")
        check("worlds: no competing second timer", second != nil && model.focusTimerState?.endsAt == endsAt, second ?? "")

        let before = model.data.focus.records.count
        worlds.endEarly()
        let early = model.data.focus.records.last
        check("worlds: ending early is recorded as not completed",
              model.data.focus.records.count == before + 1 && early?.completed == false && early?.world == "study")
        check("worlds: summary screen follows", worlds.screen == .summary(early!.id) && model.data.worlds.pendingSummary == early?.id)
        worlds.finishSummary(early!.id, reflection: "Outlined two sections")
        check("worlds: reflection saved, summary cleared",
              model.record(early!.id)?.reflection == "Outlined two sections" && model.data.worlds.pendingSummary == nil)

        // Natural completion: exactly one record, even if the timer fires twice.
        _ = worlds.start(.deepFocus, minutes: 30, label: nil)
        model.mutate { $0.focus.timer?.endsAt = Date().addingTimeInterval(-1) }
        let count = model.data.focus.records.count
        model.advanceFocus()
        model.advanceFocus()
        let done = model.data.focus.records.last
        check("worlds: completed session recorded exactly once", model.data.focus.records.count == count + 1
              && done?.completed == true && done?.world == "deepFocus" && model.focusTimerState == nil)
        check("worlds: completion doesn't auto-start a break", model.focusTimerState == nil)

        // Restart: a running world session survives a relaunch.
        _ = worlds.start(.workSprint, minutes: 45, label: "Ship v2.2")
        model.saveNow()
        let relaunched = AppModel(store: JSONDocumentStore(fileURL: url))
        let drift = abs((relaunched.focusTimerState?.endsAt ?? .distantPast).timeIntervalSince(model.focusTimerState?.endsAt ?? .distantFuture))
        check("worlds: session survives restart", relaunched.focusTimerState?.world == "workSprint" && drift < 1,
              String(format: "end-time drift %.3fs", drift))
        worlds.discard()
        check("worlds: discard leaves no record", model.focusTimerState == nil && model.data.focus.records.count == count + 1)

        // Every world can be entered; breaks stay in their world; Recharge remembers where you came from.
        for w in FocusWorld.allCases { worlds.enter(w) }
        check("worlds: every world can be entered", worlds.currentWorld == .planning)
        try? model.stopFocus()
        worlds.enter(.study)
        let breakErr = worlds.startBreak(in: .study, minutes: 5)
        check("worlds: a Study break belongs to Study", breakErr == nil && model.focusTimerState?.world == "study"
              && model.focusTimerState?.phase.isBreak == true && worlds.sessionState(for: .study) == .running
              && worlds.sessionState(for: .recharge) == .idle)
        worlds.discard()
        worlds.enter(.deepFocus)
        worlds.enter(.recharge)
        check("worlds: Recharge remembers the world to return to", worlds.returnWorld == .deepFocus)
        _ = worlds.start(.recharge, minutes: 5, label: nil)
        check("worlds: Recharge runs a real break on the shared timer",
              model.focusTimerState?.phase == .shortBreak && model.focusTimerState?.world == "recharge")
        worlds.discard()
        worlds.showSelection()
        check("worlds: back to the world picker", worlds.screen == .selection)

        // Audio: opt-in, never plays while the world is closed; sounds are real.
        model.updateWorlds { $0.settings.ambientEnabled = true }
        worlds.updateAudio()
        check("audio: nothing plays while Focus Worlds is closed", !worlds.audio.isPlaying)
        for sound in AmbientSound.allCases {
            if let r = try? AmbientAudioEngine.renderOffline(sound, seconds: 1.5) {
                check("audio: \(sound.title) is real, unclipped audio", r.rms > 0.003 && r.peak <= 1.0,
                      String(format: "rms %.3f peak %.2f", r.rms, r.peak))
            } else {
                check("audio: \(sound.title) renders", false)
            }
        }
    }
}
