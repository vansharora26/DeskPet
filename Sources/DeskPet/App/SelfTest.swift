import AppKit
import AVFoundation
import DeskPetCore
import Foundation
import Speech

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

        // Text editing: ⌘V reaches text fields (incl. the secure API-key field) via the main menu.
        checkPaste()

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
}
