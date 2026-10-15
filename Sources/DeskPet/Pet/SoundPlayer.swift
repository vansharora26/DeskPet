import AppKit

/// Plays short built-in macOS system sounds. No bundled audio, no microphone.
@MainActor
final class SoundPlayer {
    enum Effect: String {
        case pet = "Purr"
        case feed = "Pop"
        case play = "Tink"
        case sleep = "Blow"
        case wake = "Morse"
        case refuse = "Funk"
    }

    private var cache: [Effect: NSSound] = [:]
    var isEnabled: () -> Bool = { false }

    func play(_ effect: Effect) {
        guard isEnabled() else { return }
        let sound: NSSound
        if let cached = cache[effect] {
            sound = cached
        } else {
            // Missing system sounds are silently skipped rather than crashing.
            guard let s = NSSound(named: NSSound.Name(effect.rawValue)) else { return }
            s.volume = 0.35
            cache[effect] = s
            sound = s
        }
        sound.stop()
        sound.play()
    }
}
