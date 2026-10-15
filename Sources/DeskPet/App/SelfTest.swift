import DeskPetCore
import Foundation

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

        // Export & delete.
        do {
            let folder = try model.export(to: dir, pet: nil)
            let names = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            check("export writes JSON + CSVs", names == ["deskpet.json", "water.csv", "focus.csv", "notes-and-tasks.csv"],
                  names.sorted().joined(separator: ", "))
            let csv = (try? String(contentsOf: folder.appendingPathComponent("water.csv"), encoding: .utf8)) ?? ""
            check("water CSV has rows", csv.split(separator: "\r\n").count == 3)
        } catch {
            check("export", false, error.localizedDescription)
        }
        model.deleteAllData()
        check("delete all data", model.data.items.items.isEmpty && model.data.hydration.entries.isEmpty)

        print(failures == 0 ? "\nAll self-tests passed." : "\n\(failures) self-test(s) FAILED.")
        return failures == 0 ? 0 : 1
    }
}
