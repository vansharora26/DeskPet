import Foundation

/// The Claude models DeskPet offers, and how to talk to each.
public struct ClaudeModelInfo: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let blurb: String
    /// Opts into server-side refusal fallback (`fallbacks: "default"`).
    public let refusalFallback: Bool

    public static let all: [ClaudeModelInfo] = [
        ClaudeModelInfo(id: "claude-opus-5-5", name: "Claude Opus 5.5",
                        blurb: "Smartest. Best for planning, writing and tricky questions.", refusalFallback: true),
        ClaudeModelInfo(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5",
                        blurb: "Fast and capable. Great for everyday chat.", refusalFallback: true),
        ClaudeModelInfo(id: "claude-haiku-5-5", name: "Claude Haiku 5.5",
                        blurb: "Fastest and cheapest. Good for quick questions.", refusalFallback: false),
    ]

    public static let defaultID = "claude-opus-5-5"

    public static func find(_ id: String) -> ClaudeModelInfo? { all.first { $0.id == id } }

    /// Saved model IDs from older DeskPet versions → their current successor.
    public static func migrated(_ id: String) -> String {
        if find(id) != nil { return id }
        switch id {
        case "claude-opus-5", "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6": return "claude-opus-5-5"
        case "claude-sonnet-5", "claude-sonnet-4-6": return "claude-sonnet-5-5"
        case "claude-haiku-4-5": return "claude-haiku-5-5"
        default: return defaultID
        }
    }
}

/// Checks on what the user pastes as their Claude API key (before anything is saved or sent).
public enum ClaudeKey {
    public static let consoleKeysURL = URL(string: "https://platform.claude.com/settings/keys")!
    public static let consoleBillingURL = URL(string: "https://platform.claude.com/settings/billing")!

    public enum Problem: Equatable, LocalizedError {
        case empty, notAKey, adminKey, hasSpaces
        public var errorDescription: String? {
            switch self {
            case .empty: return "Copy your API key first, then click Paste & Connect."
            case .notAKey: return "That doesn’t look like a Claude API key. Keys start with “sk-ant-”."
            case .adminKey: return "That’s an Admin key, which can’t chat. Create a regular API key instead."
            case .hasSpaces: return "The key has spaces or line breaks in it. Copy it again from the Console."
            }
        }
    }

    /// Trims surrounding whitespace/quotes and validates the shape. Returns the clean key.
    public static func clean(_ raw: String) throws -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
        guard !key.isEmpty else { throw Problem.empty }
        guard !key.contains(where: { $0.isWhitespace }) else { throw Problem.hasSpaces }
        if key.hasPrefix("sk-ant-admin") { throw Problem.adminKey }
        guard key.hasPrefix("sk-ant-"), key.count >= 40, key.count <= 300 else { throw Problem.notAKey }
        return key
    }

    /// "sk-ant-…a1B2" for display — never the whole key.
    public static func masked(_ key: String) -> String {
        "sk-ant-…" + String(key.suffix(4))
    }
}
