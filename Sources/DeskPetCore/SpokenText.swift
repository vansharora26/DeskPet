import Foundation

/// Converts chat text into something pleasant to hear: no markdown symbols,
/// no emoji, units read as words, lists as sentences, and a length cap so long
/// answers aren't read out in full (the full text stays on screen).
public enum SpokenText {
    public static let maxCharacters = 420

    public static func clean(_ text: String) -> String {
        var s = text

        // Links: [label](url) → label; bare URLs → "a link".
        s = s.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"https?://\S+"#, with: "a link", options: .regularExpression)
        // Code, emphasis, headings, quotes.
        s = s.replacingOccurrences(of: "```[\\s\\S]*?```", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[`*_#>~]+"#, with: "", options: .regularExpression)
        // Bullets / numbered items → sentences.
        s = s.replacingOccurrences(of: #"(?m)^\s*(?:[•\-–]|\d+[.)])\s+"#, with: "", options: .regularExpression)
        s = s.split(separator: "\n").map { line -> String in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard let last = t.last else { return "" }
            return ".!?:;,".contains(last) ? t : t + "."
        }.filter { !$0.isEmpty }.joined(separator: " ")

        // Units and symbols, read naturally.
        s = s.replacingOccurrences(of: #"(\d)\s?ml\b"#, with: "$1 millilitres", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"(\d(?:\.\d)?)\s?L\b"#, with: "$1 litres", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\b1 litres\b"#, with: "1 litre", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\d)\s?min\b"#, with: "$1 minutes", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\b1 minutes\b"#, with: "1 minute", options: .regularExpression)
        s = s.replacingOccurrences(of: " · ", with: ", ")
        s = s.replacingOccurrences(of: "—", with: ", ").replacingOccurrences(of: "–", with: " to ")
        s = s.replacingOccurrences(of: "&", with: " and ")
        s = s.replacingOccurrences(of: "“", with: "").replacingOccurrences(of: "”", with: "")

        // Emoji and pictographs are read out as names ("party popper") — drop them.
        s = String(String.UnicodeScalarView(s.unicodeScalars.filter { scalar in
            !(scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && scalar.value > 0x2000 && scalar.value != 0x2122))
                && scalar.value != 0xFE0F && scalar.value != 0x200D
        }))

        s = s.replacingOccurrences(of: #"\s+([,.!?])"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"([,.])\1+"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Nothing pronounceable left (e.g. emoji-only) → say nothing.
        guard s.rangeOfCharacter(from: .alphanumerics) != nil else { return "" }
        return truncate(s)
    }

    /// Cuts at a sentence boundary under the cap and says where the rest is.
    static func truncate(_ s: String) -> String {
        guard s.count > maxCharacters else { return s }
        let prefix = String(s.prefix(maxCharacters))
        if let end = prefix.lastIndex(where: { ".!?".contains($0) }), prefix.distance(from: prefix.startIndex, to: end) > 80 {
            return String(prefix[...end]) + " The rest is in the chat window."
        }
        return prefix.trimmingCharacters(in: .whitespaces) + "… The rest is in the chat window."
    }
}
