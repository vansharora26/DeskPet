import Foundation

/// Short-term memory for a conversation, so natural follow-ups work:
/// "I've had 300 ml" → "What's my total?" → "Another one" → "Undo that".
/// It remembers only the current topic and last amounts, and forgets after a
/// few minutes of silence.
public struct ConversationContext: Equatable, Sendable {
    public enum Topic: String, Equatable, Sendable { case water, focus, tasks }

    public enum FollowUp: Equatable, Sendable {
        case command(AppCommand)
        /// Undo the most recent action from this conversation.
        case undoLast
    }

    public var topic: Topic?
    public var lastWaterML: Int?
    public var lastFocusMinutes: Int?
    public var updatedAt: Date?

    /// How long a topic stays "current".
    public static let ttl: TimeInterval = 5 * 60

    public init() {}

    public func isFresh(at now: Date) -> Bool {
        guard let updatedAt else { return false }
        return now.timeIntervalSince(updatedAt) < Self.ttl
    }

    /// Records what a successfully executed command was about.
    public mutating func note(_ command: AppCommand, at now: Date, defaultServing: Int, defaultFocus: Int) {
        switch command {
        case .logWater(let ml):
            topic = .water
            lastWaterML = ml ?? defaultServing
        case .undoWater, .setWaterGoal, .waterTotal, .configureReminder(.hydration, _, _):
            topic = .water
        case .startFocus(let m, _):
            topic = .focus
            lastFocusMinutes = m ?? defaultFocus
        case .startBreak, .pauseFocus, .resumeFocus, .stopFocus, .skipPhase, .timerStatus, .summarizeFocus:
            topic = .focus
        case .createTask, .completeTask, .showTasks:
            topic = .tasks
        default:
            return
        }
        updatedAt = now
    }

    public mutating func reset() { self = ConversationContext() }

    /// Resolves short follow-ups that only make sense in context.
    /// Returns nil when the text isn't a follow-up (so normal parsing continues).
    public func resolve(_ raw: String, now: Date) -> FollowUp? {
        let text = raw.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
            .replacingOccurrences(of: "’", with: "'")
        guard !text.isEmpty, text.split(separator: " ").count <= 7 else { return nil }
        let fresh = isFresh(at: now)

        // Undo works even without a topic (the chat keeps its own undo stack).
        if Rx.first(#"^(undo( that| it| the last one)?|never ?mind|scratch that|cancel that|take (that|it) back|oops,? undo( that)?)$"#, in: text) != nil {
            return .undoLast
        }

        // "What's my total?" — water unless we're clearly talking about focus or tasks.
        if Rx.first(#"^(so )?(what'?s|what is|how much is) (my |the )?total( so far)?$|^(my )?total( so far)?$|^how much (so far|is that|have i had)( so far| now)?$|^how much (is )?(left|to go)$"#, in: text) != nil {
            switch fresh ? topic : nil {
            case .focus: return .command(.timerStatus)
            case .tasks: return .command(.showTasks(nil))
            default: return .command(.waterTotal)
            }
        }

        // "Another one" / "same again" repeats the last amount.
        if fresh, Rx.first(#"^(another( one)?|one more|same again|again|and another( one)?)$"#, in: text) != nil {
            switch topic {
            case .water: return .command(.logWater(ml: lastWaterML))
            case .focus: return .command(.startFocus(minutes: lastFocusMinutes, label: nil))
            default: return nil
            }
        }

        // "How am I doing?" follows the topic.
        if fresh, Rx.first(#"^how am i doing( now| so far)?$"#, in: text) != nil {
            switch topic {
            case .water: return .command(.waterTotal)
            case .focus: return .command(.timerStatus)
            default: return nil
            }
        }
        return nil
    }
}
