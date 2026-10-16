import AppKit
import Combine
import DeskPetCore

/// Ties push-to-talk recognition, the conversation, and spoken replies together.
///
/// The microphone is only ever on while the user is holding the talk button
/// or shortcut (or after an explicit tap to latch it on, until tapped again
/// or 60 s pass). Speaking stops immediately when the user starts talking.
@MainActor
final class VoiceController: ObservableObject {
    enum Activity: Equatable { case idle, listening, thinking, speaking }

    @Published private(set) var activity: Activity = .idle
    /// Latched (tap) mode: listening continues after the button is released.
    @Published private(set) var latched = false
    /// Last voice problem or notice, shown under the composer.
    @Published var notice: String?

    let input = SpeechRecognizerService()
    let output = SpeechSynthesizerService()
    private let chat: ChatModel
    private let settings: AppSettings
    private let pet: PetViewModel
    private var cancellables = Set<AnyCancellable>()
    private var pressStarted: Date?
    private var sleepObserver: NSObjectProtocol?

    init(chat: ChatModel, settings: AppSettings, pet: PetViewModel) {
        self.chat = chat
        self.settings = settings
        self.pet = pet

        input.onFinished = { [weak self] text in self?.finished(text) }
        input.onError = { [weak self] message in
            self?.latched = false
            self?.notice = message
        }
        input.onNotice = { [weak self] message in self?.notice = message }

        // Speak final replies (never interim "working on it" text).
        chat.onReply = { [weak self] text, fromVoice in self?.replyArrived(text, fromVoice: fromVoice) }

        Publishers.CombineLatest3(input.$state, chat.$status, output.$isSpeaking)
            .receive(on: RunLoop.main)
            .sink { [weak self] state, status, speaking in
                guard let self else { return }
                let next: Activity
                if state == .listening || state == .finishing { next = .listening }
                else if case .working = status { next = .thinking }
                else if speaking { next = .speaking }
                else { next = .idle }
                if self.activity != next { self.activity = next }
            }
            .store(in: &cancellables)

        // Muting mid-sentence stops speech right away.
        settings.$voiceMuted.dropFirst().filter { $0 }.sink { [weak self] _ in self?.output.stop() }.store(in: &cancellables)
        settings.$voiceInputEnabled.dropFirst().filter { !$0 }.sink { [weak self] _ in self?.cancelListening() }.store(in: &cancellables)

        // Never leave the mic on across sleep / screen lock.
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cancelListening()
                self?.output.stop()
            }
        }
    }

    // MARK: Availability

    var voiceInputAvailable: Bool {
        settings.voiceInputEnabled && SpeechRecognizerService.isSupportedBuild
    }

    var unavailableReason: String? {
        if !settings.voiceInputEnabled { return "Voice input is off in Settings › Voice." }
        if !SpeechRecognizerService.isSupportedBuild { return "Voice needs the DeskPet app bundle. Typing works." }
        switch input.permission {
        case .denied, .restricted: return "Microphone or speech access is off in System Settings."
        default: return nil
        }
    }

    var isListening: Bool { activity == .listening }

    // MARK: Push-to-talk

    /// Button/shortcut pressed: interrupt speech and start listening.
    func pressBegan() {
        notice = nil
        output.stop()                       // barge-in
        if latched || input.state == .listening {
            // Second tap in latched mode ends the turn.
            latched = false
            input.stop()
            return
        }
        guard voiceInputAvailable else {
            notice = unavailableReason
            return
        }
        guard !chat.isBusy else {
            notice = "One moment — I’m still working on the last message."
            return
        }
        pressStarted = Date()
        if settings.soundEnabled { NSSound(named: "Tink")?.play() }
        Task {
            await input.start(localeID: settings.recognitionLocale,
                              onDeviceOnly: settings.onDeviceRecognitionOnly,
                              hints: ["millilitres", "ml", "focus session", "total", pet.name])
        }
    }

    /// Button/shortcut released: a short tap latches; a hold ends the turn.
    func pressEnded() {
        guard let started = pressStarted else { return }
        pressStarted = nil
        if Date().timeIntervalSince(started) < 0.35 && input.state == .listening {
            latched = true
            notice = "Listening — tap the mic again when you’re done."
            return
        }
        input.stop()
    }

    /// Discards the current utterance and turns the mic off.
    func cancelListening() {
        latched = false
        pressStarted = nil
        input.cancel()
    }

    func stopSpeaking() { output.stop() }

    private func finished(_ text: String) {
        latched = false
        if settings.soundEnabled { NSSound(named: "Pop")?.play() }
        guard !text.isEmpty else {
            notice = "I didn’t catch that. Hold the mic and try again, or type."
            return
        }
        notice = nil
        chat.send(text, viaVoice: true)
    }

    // MARK: Spoken replies

    private func replyArrived(_ text: String, fromVoice: Bool) {
        guard shouldSpeak(fromVoice: fromVoice) else { return }
        output.speak(text, voiceID: settings.voiceIdentifier, languageID: settings.recognitionLocale,
                     rate: settings.speechRate)
    }

    func shouldSpeak(fromVoice: Bool) -> Bool {
        guard !settings.voiceMuted else { return false }
        switch settings.spokenReplies {
        case .never: return false
        case .always: return true
        case .whenISpeak: return fromVoice
        }
    }

    /// Plays a sample with the current voice settings (Settings › Voice).
    func previewVoice() {
        output.speak("Hi! I’m \(pet.name). You’ve had 1.2 L of water today — nice work!",
                     voiceID: settings.voiceIdentifier, languageID: settings.recognitionLocale, rate: settings.speechRate)
    }
}
