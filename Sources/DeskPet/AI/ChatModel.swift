import Combine
import DeskPetCore
import Foundation
import os

/// The chat conversation. Local commands ("log 300 ml", "focus for 25 minutes")
/// run on-device and are never sent anywhere. Everything else goes to Claude,
/// which can act only through the typed tools in AssistantTools.
@MainActor
final class ChatModel: ObservableObject {
    struct Chip: Identifiable {
        let id = UUID()
        var text: String
        var style: CommandResult.Style
        var undo: (@MainActor () -> Void)?
    }

    struct Message: Identifiable {
        enum Role: String, Codable { case user, assistant, notice }
        let id: UUID
        var role: Role
        var text: String
        var chips: [Chip] = []
        var isError = false
        var date = Date()
        /// True for replies produced on-device without AI.
        var isLocal = false
    }

    /// A question the user must answer before the assistant continues.
    struct Pending: Identifiable {
        let id = UUID()
        var title: String
        var detail: String
        var allowAlwaysOption: Bool
        fileprivate var resume: (Decision) -> Void
    }

    enum Decision { case allow, allowAlways, deny }

    enum Status: Equatable {
        case idle
        case working(String)
        case failed(AIError)
    }

    @Published private(set) var messages: [Message] = []
    @Published private(set) var status: Status = .idle
    @Published private(set) var pending: Pending?
    @Published private(set) var historyWasReset = false

    private let model: AppModel
    private let settings: AppSettings
    private let pet: PetViewModel
    private let store: JSONDocumentStore<ChatArchive>
    private let log = Logger(subsystem: "app.deskpet.DeskPet", category: "ai")
    /// Raw API messages (assistant turns replayed unchanged).
    private var history: [JSONValue] = []
    private var task: Task<Void, Never>?

    // Short-term conversation memory (never persisted).
    @Published private(set) var context = ConversationContext()
    private var lastUndo: (summary: String, action: @MainActor () -> Void, at: Date)?
    private var recentLocal: [(user: String, reply: String, at: Date)] = []
    private var lastActivity = Date.distantPast
    /// Whether the message currently being answered was spoken.
    private(set) var currentInputIsVoice = false
    /// Conversation context and AI memory reset after this much silence.
    static let idleReset: TimeInterval = 30 * 60

    /// Called with each *final* reply (after any actions have finished), so the
    /// voice layer can speak it. Interim "working on it" text is never passed here.
    var onReply: (_ text: String, _ inputWasVoice: Bool) -> Void = { _, _ in }
    /// Above this many API messages, start a fresh context (append-only, never edited).
    private let historyLimit = 60

    init(model: AppModel, settings: AppSettings, pet: PetViewModel, store: JSONDocumentStore<ChatArchive>) {
        self.model = model
        self.settings = settings
        self.pet = pet
        self.store = store
        if case .loaded(let archive) = store.load() {
            messages = archive.messages.map {
                Message(id: $0.id, role: $0.role, text: $0.text, isError: $0.isError, date: $0.date, isLocal: $0.isLocal)
            }
            history = archive.history
        }
    }

    // MARK: - Configuration

    enum AIState: Equatable {
        case notConfigured, direct(model: String), proxy(model: String)
        var isReady: Bool { self != .notConfigured }
        var label: String {
            switch self {
            case .notConfigured: return "Local only"
            case .direct(let m): return "AI ready · \(ChatModel.modelName(m))"
            case .proxy(let m): return "AI via proxy · \(ChatModel.modelName(m))"
            }
        }
    }

    var aiState: AIState {
        if proxyURL != nil { return .proxy(model: settings.aiModel) }
        return KeychainStore.hasAPIKey ? .direct(model: settings.aiModel) : .notConfigured
    }

    private var proxyURL: URL? {
        let s = settings.aiProxyURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: s), url.scheme == "https" || url.host == "localhost" || url.host == "127.0.0.1" else { return nil }
        return url
    }

    private var client: ClaudeClient {
        ClaudeClient(config: .init(model: settings.aiModel, apiKey: KeychainStore.loadAPIKey(), proxyURL: proxyURL))
    }

    nonisolated static let models: [(id: String, name: String)] = [
        ("claude-opus-5", "Claude Opus 5"),
        ("claude-sonnet-5", "Claude Sonnet 5"),
        ("claude-haiku-4-5", "Claude Haiku 4.5"),
    ]

    nonisolated static func modelName(_ id: String) -> String { models.first { $0.id == id }?.name ?? id }

    // MARK: - Sending

    var isBusy: Bool { if case .working = status { return true }; return pending != nil }

    func send(_ raw: String, viaVoice: Bool = false) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        let now = Date()
        if now.timeIntervalSince(lastActivity) > Self.idleReset { startFreshContext() }
        lastActivity = now
        currentInputIsVoice = viaVoice
        messages.append(Message(id: UUID(), role: .user, text: text))

        // 1. Follow-ups that depend on what we were just talking about.
        if let followUp = context.resolve(text, now: now) {
            switch followUp {
            case .undoLast: undoLastAction()
            case .command(let c): runLocal(c, said: text)
            }
            return
        }
        // 2. Local command? Run it on-device — no network, nothing shared.
        if let command = CommandParser.parse(text, now: now, calendar: model.calendar) {
            runLocal(command, said: text)
            return
        }
        // 3. No AI configured: explain, keep local features working.
        guard aiState.isReady else {
            reply("""
                I can’t answer general questions until AI is connected (Settings › AI). \
                I can still do these right now: “I’ve had 300 ml”, “what’s my total?”, “start a 25-minute focus session”, \
                “add call mom to my tasks”, “remind me to stretch at 3 pm”.
                """, spoken: "I can do DeskPet things like logging water or starting a focus session. For general questions, connect AI in Settings.")
            persist()
            return
        }
        // 4. Ask Claude.
        appendUserTurn(text)
        startLoop()
    }

    /// Adds an on-device assistant message and hands it to the voice layer.
    private func reply(_ text: String, spoken: String? = nil, isError: Bool = false, chips: [Chip] = []) {
        var msg = Message(id: UUID(), role: .assistant, text: text, isError: isError, isLocal: true)
        msg.chips = chips
        messages.append(msg)
        onReply(spoken ?? text, currentInputIsVoice)
    }

    /// Reverses the most recent action from this conversation ("undo that").
    func undoLastAction() {
        guard let u = lastUndo, Date().timeIntervalSince(u.at) < 10 * 60 else {
            reply("There’s nothing recent to undo.")
            persist()
            return
        }
        u.action()
        lastUndo = nil
        reply("Undone: \(u.summary).")
        persist()
    }

    /// Forget the short-term topic and start a new AI context (history is append-only, so we start over).
    private func startFreshContext() {
        context.reset()
        lastUndo = nil
        recentLocal = []
        if !history.isEmpty {
            history = []
            historyWasReset = true
        }
    }

    func retry() {
        guard case .failed = status, let last = history.last, last["role"]?.string == "user" else { return }
        startLoop()
    }

    func cancel() {
        task?.cancel()
        task = nil
        pending?.resume(.deny)
        pending = nil
        status = .idle
    }

    func clear() {
        cancel()
        messages = []
        history = []
        historyWasReset = false
        store.delete()
    }

    func decide(_ decision: Decision) {
        guard let p = pending else { return }
        pending = nil
        p.resume(decision)
    }

    private func runLocal(_ command: AppCommand, said: String) {
        if command.needsConfirmation {
            pending = Pending(title: "Confirm", detail: command.summary(defaultServing: model.hydrationSettings.defaultServingML) + "?",
                              allowAlwaysOption: false) { [weak self] d in
                guard let self else { return }
                if d == .deny {
                    self.reply("Okay, I left it as is.")
                } else {
                    self.finishLocal(command, said: said)
                }
                self.persist()
            }
            return
        }
        finishLocal(command, said: said)
        persist()
    }

    /// Runs the command first; the confirmation is built from the *result*, so
    /// "Logged 300 ml" is only ever said after the entry was actually saved.
    private func finishLocal(_ command: AppCommand, said: String) {
        let result = CommandExecutor(model: model).run(command)
        if let dest = result.destination, case .open = command { onOpen(dest) }
        var text = result.message
        if !result.details.isEmpty { text += "\n" + result.details.map { "• \($0)" }.joined(separator: "\n") }
        var chips: [Chip] = []
        if result.style != .error {
            context.note(command, at: Date(), defaultServing: model.hydrationSettings.defaultServingML,
                         defaultFocus: model.focusSettings.focusMinutes)
            if let undo = result.undo {
                lastUndo = (result.message, undo, Date())
                chips = [Chip(text: "Done", style: result.style, undo: undo)]
            }
        }
        recentLocal.append((said, result.message, Date()))
        if recentLocal.count > 3 { recentLocal.removeFirst() }
        reply(text, spoken: spokenVersion(of: result), isError: result.style == .error, chips: chips)
    }

    /// Lists read better aloud as a count plus the first few items.
    private func spokenVersion(of result: CommandResult) -> String {
        guard !result.details.isEmpty else { return result.message }
        let firstItems = result.details.prefix(3).joined(separator: "; ")
        return result.message + ": " + firstItems + (result.details.count > 3 ? ", and more." : ".")
    }

    /// Set by the coordinator so chat can navigate (e.g. "open settings").
    var onOpen: (Destination) -> Void = { _ in }

    private func appendUserTurn(_ text: String) {
        // Local time lets the model resolve "at 7 PM"; added per message so the
        // system prompt stays constant and history stays append-only.
        let f = DateFormatter()
        f.dateFormat = "EEEE yyyy-MM-dd HH:mm"
        var note = "[Local time: \(f.string(from: Date())) (\(TimeZone.current.identifier))]"
        // Short-term context: what the user just did on-device in this conversation
        // (skipped entirely if they don't share DeskPet data with the AI).
        if settings.aiDataAccess != .never {
            let recent = recentLocal.filter { Date().timeIntervalSince($0.at) < 10 * 60 }
            if !recent.isEmpty {
                note += "\n[Just handled on device: " + recent.map { "“\($0.user)” → \($0.reply)" }.joined(separator: "; ") + "]"
            }
        }
        if currentInputIsVoice {
            note += "\n[Spoken input; your reply will be read aloud: 1–2 short sentences, no lists or markdown.]"
        }
        recentLocal = []
        let blocks: [JSONValue] = [["type": "text", "text": .string(note)], ["type": "text", "text": .string(text)]]
        if history.count >= historyLimit {
            history = []
            historyWasReset = true
        }
        if let last = history.last, last["role"]?.string == "user", let content = last["content"]?.array {
            // Previous attempt failed before a reply: merge so roles keep alternating.
            history[history.count - 1] = ["role": "user", "content": .array(content + blocks)]
        } else {
            history.append(["role": "user", "content": .array(blocks)])
        }
    }

    private func startLoop() {
        task?.cancel()
        task = Task { [weak self] in await self?.loop() }
    }

    private var systemPrompt: String {
        """
        You are \(pet.name), the AI companion inside DeskPet — a pixel-art cat that lives on the user's Mac desktop. \
        Personality: friendly, warm, concise, lightly playful (at most one small cat pun per reply). \
        Keep replies short: usually 1–4 sentences or a tight bulleted list.

        You can: answer general questions; break big tasks into small steps; draft messages; summarize text the user pastes; \
        help plan their time; and use DeskPet tools to log water, run the focus timer, create tasks/notes/reminders, \
        and configure water or movement reminders.

        Rules:
        - Only take actions the user explicitly asked for. If details are missing (amount, time), ask one short question. \
        When you suggest a plan, offer to create the tasks instead of creating them unprompted.
        - Never say an action is done until its tool result confirms success. If a tool returns an error, say so plainly \
        and don't pretend it worked. Keep any text before a tool call to a few words.
        - For "undo that", call the matching tool (e.g. undo_last_water) rather than just saying it's undone.
        - Reading the user's tasks, notes or stats requires a read tool and the user may decline — respect that.
        - Each user message starts with their local time. For due/remind_at, use local ISO 8601 without an offset (e.g. 2026-10-15T19:00).
        - You cannot see the screen, files, clipboard, calendar, email or other apps, and cannot run commands. \
        Never claim otherwise; say briefly what DeskPet can do instead.
        - Water goals are personal preferences, not medical advice. Don't diagnose.
        - Never invent numbers about the user; only report what tools return.
        """
    }

    private func requestBody() -> [String: JSONValue] {
        var body: [String: JSONValue] = [
            "model": .string(settings.aiModel),
            "max_tokens": 16000,
            "system": .string(systemPrompt),
            "tools": .array(AssistantTools.definitions),
            "messages": .array(history),
            "cache_control": ["type": "ephemeral"],
        ]
        if settings.aiModel != "claude-haiku-4-5" {
            body["output_config"] = ["effort": "medium"]
        }
        return body
    }

    private func loop() async {
        status = .working("Thinking…")
        let tools = AssistantTools(model: model, accessToData: { [settings] in settings.aiDataAccess })
        var chips: [Chip] = []

        for _ in 0..<8 {
            let response: JSONValue
            do {
                response = try await client.createMessage(requestBody())
            } catch is CancellationError {
                return
            } catch let e as AIError {
                fail(e)
                return
            } catch {
                fail(.invalidResponse)
                return
            }
            if Task.isCancelled { return }

            let stop = response["stop_reason"]?.string
            guard let content = response["content"]?.array else { fail(.invalidResponse); return }

            if stop == "refusal" {
                // Keep history valid: drop the unanswered user turn.
                if history.last?["role"]?.string == "user" { history.removeLast() }
                messages.append(Message(id: UUID(), role: .assistant, text: "I can’t help with that one, sorry. Anything else?"))
                onReply("I can’t help with that one, sorry.", currentInputIsVoice)
                status = .idle
                persist()
                return
            }

            history.append(["role": "assistant", "content": .array(content)])
            let text = content.filter { $0["type"]?.string == "text" }.compactMap { $0["text"]?.string }
                .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

            if stop == "tool_use" {
                if !text.isEmpty {
                    messages.append(Message(id: UUID(), role: .assistant, text: text))
                }
                var results: [JSONValue] = []
                for block in content where block["type"]?.string == "tool_use" {
                    let (result, chip) = await runTool(block, tools: tools)
                    results.append(result)
                    if let chip { chips.append(chip) }
                }
                // All results go back together in one user message.
                history.append(["role": "user", "content": .array(results)])
                status = .working("Working on it…")
                continue
            }
            if stop == "pause_turn" { continue }

            var finalText = text
            if finalText.isEmpty {
                // No closing words from the model: confirm from the actual tool results.
                finalText = chips.isEmpty ? "Done." : chips.map(\.text).joined(separator: " ")
            }
            if stop == "max_tokens" { finalText += "\n\n(My answer was cut short.)" }
            var msg = Message(id: UUID(), role: .assistant, text: finalText)
            msg.chips = chips
            messages.append(msg)
            status = .idle
            onReply(finalText, currentInputIsVoice)
            persist()
            return
        }
        messages.append(Message(id: UUID(), role: .notice, text: "That took too many steps, so I stopped. Try a simpler request?", isError: true))
        status = .idle
        persist()
    }

    /// Validates, asks permission/confirmation if needed, runs the tool, and
    /// returns the tool_result block (plus a chip for the UI).
    private func runTool(_ block: JSONValue, tools: AssistantTools) async -> (JSONValue, Chip?) {
        let id = block["id"]?.string ?? ""
        let name = block["name"]?.string ?? ""
        func result(_ text: String, error: Bool) -> JSONValue {
            ["type": "tool_result", "tool_use_id": .string(id), "content": .string(text), "is_error": .bool(error)]
        }

        let planned: AssistantTools.Planned
        do {
            planned = try tools.plan(name: name, input: block["input"] ?? .object([:]))
        } catch let e as AssistantTools.InputError {
            return (result("Invalid input: \(e.message)", error: true), nil)
        } catch {
            return (result("Invalid input.", error: true), nil)
        }

        // Reading personal data is the user's call.
        if planned.isDataRead {
            switch settings.aiDataAccess {
            case .never:
                return (result("The user has not allowed DeskPet AI to read their data. Continue without it.", error: true), nil)
            case .ask:
                let d = await ask(title: "Share DeskPet data?", detail: "The assistant wants to \(planned.description). Only this result is sent.", allowAlways: true)
                if d == .deny { return (result("The user declined to share this data. Continue without it.", error: true), nil) }
                if d == .allowAlways { settings.aiDataAccess = .always }
            case .always:
                break
            }
        }
        // Consequential actions need an explicit OK.
        if planned.needsConfirmation {
            let d = await ask(title: "Allow this action?", detail: planned.description + "?", allowAlways: false)
            if d == .deny { return (result("The user declined this action.", error: true), Chip(text: "Declined: \(planned.description)", style: .info)) }
        }

        status = .working(planned.description.prefix(1).uppercased() + planned.description.dropFirst() + "…")
        let outcome = tools.perform(planned)
        var chip: Chip?
        if let r = outcome.result {
            chip = Chip(text: r.message, style: r.style, undo: r.undo)
            if r.style != .error, case .command(let c) = planned.kind {
                context.note(c, at: Date(), defaultServing: model.hydrationSettings.defaultServingML,
                             defaultFocus: model.focusSettings.focusMinutes)
                if let undo = r.undo { lastUndo = (r.message, undo, Date()) }
            }
        }
        return (result(outcome.text, error: outcome.isError), chip)
    }

    private func ask(title: String, detail: String, allowAlways: Bool) async -> Decision {
        await withCheckedContinuation { cont in
            var resumed = false
            pending = Pending(title: title, detail: detail, allowAlwaysOption: allowAlways) { d in
                guard !resumed else { return }
                resumed = true
                cont.resume(returning: d)
            }
        }
    }

    private func fail(_ e: AIError) {
        log.error("AI request failed: \(e.localizedDescription, privacy: .public)")
        status = .failed(e)
        onReply("Sorry, " + (e.errorDescription ?? "something went wrong."), currentInputIsVoice)
        persist()
    }

    // MARK: - Persistence (local only)

    private func persist() {
        let archive = ChatArchive(
            messages: messages.suffix(100).map {
                ChatArchive.Entry(id: $0.id, role: $0.role, text: $0.text, isError: $0.isError, date: $0.date, isLocal: $0.isLocal)
            },
            history: history)
        try? store.save(archive)
    }
}

/// What's saved to disk for chat: the visible transcript and the API history.
struct ChatArchive: Codable {
    struct Entry: Codable {
        var id: UUID
        var role: ChatModel.Message.Role
        var text: String
        var isError: Bool
        var date: Date
        var isLocal: Bool
    }
    var messages: [Entry]
    var history: [JSONValue]
}
