import AVFoundation
import DeskPetCore

/// Spoken replies with the native macOS synthesizer (AVSpeechSynthesizer).
/// Speaks only what it's given, stops instantly when interrupted, and never
/// touches the microphone.
@MainActor
final class SpeechSynthesizerService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    struct VoiceOption: Identifiable, Hashable {
        let id: String
        let name: String
        let language: String
        let quality: String
    }

    /// Voices for the given language, best quality first.
    static func voices(forLanguage languageID: String) -> [VoiceOption] {
        let lang = String(languageID.prefix(2))
        return AVSpeechSynthesisVoice.speechVoices()
            // Skip novelty voices (Albert, Bubbles, Zarvox…) and Personal Voice.
            .filter { $0.language.hasPrefix(lang) && !$0.voiceTraits.contains(.isNoveltyVoice)
                && !$0.voiceTraits.contains(.isPersonalVoice) }
            .sorted { a, b in
                if a.quality != b.quality { return a.quality.rawValue > b.quality.rawValue }
                return a.name < b.name
            }
            .map {
                VoiceOption(id: $0.identifier, name: $0.name,
                            language: Locale.current.localizedString(forIdentifier: $0.language) ?? $0.language,
                            quality: $0.quality == .premium ? "Premium" : ($0.quality == .enhanced ? "Enhanced" : "Default"))
            }
    }

    /// The configured voice, or the best installed voice for the language.
    static func resolveVoice(identifier: String, languageID: String) -> AVSpeechSynthesisVoice? {
        if !identifier.isEmpty, let v = AVSpeechSynthesisVoice(identifier: identifier) { return v }
        // A downloaded premium/enhanced voice if there is one…
        if let best = voices(forLanguage: languageID).first(where: { $0.quality != "Default" }) {
            return AVSpeechSynthesisVoice(identifier: best.id)
        }
        // …otherwise the system's standard voice for the language (e.g. Samantha for en-US).
        let tag = languageID.replacingOccurrences(of: "_", with: "-")
        return AVSpeechSynthesisVoice(language: tag) ?? AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
    }

    /// Maps the 0…1 setting onto a comfortable part of the synthesizer's range.
    static func utteranceRate(_ setting: Double) -> Float {
        let lo = AVSpeechUtteranceMinimumSpeechRate + 0.32 * (AVSpeechUtteranceDefaultSpeechRate - AVSpeechUtteranceMinimumSpeechRate)
        let hi = AVSpeechUtteranceDefaultSpeechRate + 0.35 * (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceDefaultSpeechRate)
        return lo + Float(min(1, max(0, setting))) * (hi - lo)
    }

    static func makeUtterance(_ text: String, voiceID: String, languageID: String, rate: Double) -> AVSpeechUtterance? {
        let spoken = SpokenText.clean(text)
        guard !spoken.isEmpty else { return nil }
        let u = AVSpeechUtterance(string: spoken)
        u.voice = resolveVoice(identifier: voiceID, languageID: languageID)
        u.rate = utteranceRate(rate)
        u.pitchMultiplier = 1.08 // a touch brighter — it's a cat
        u.postUtteranceDelay = 0.05
        return u
    }

    /// Speaks text, replacing anything currently being said.
    func speak(_ text: String, voiceID: String, languageID: String, rate: Double) {
        guard let u = Self.makeUtterance(text, voiceID: voiceID, languageID: languageID, rate: rate) else { return }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        isSpeaking = true
        synthesizer.speak(u)
    }

    /// Interrupts speech immediately.
    func stop() {
        guard synthesizer.isSpeaking || isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    // MARK: AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in if !self.synthesizer.isSpeaking { self.isSpeaking = false } }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in if !self.synthesizer.isSpeaking { self.isSpeaking = false } }
    }
}
