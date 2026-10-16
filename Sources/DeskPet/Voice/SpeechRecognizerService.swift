import AppKit
import AVFoundation
import Speech

/// Push-to-talk speech recognition with Apple's Speech framework.
///
/// Privacy rules enforced here:
/// - The microphone runs **only** between `start()` and `stop()`/`cancel()`;
///   nothing listens in the background, and a hard cap ends any session.
/// - On-device recognition is required by default, so audio stays on the Mac.
///   Server-based recognition (Apple) is used only if the user opts in.
/// - Permission is requested on first use, never at launch.
@MainActor
final class SpeechRecognizerService: ObservableObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        /// Mic is off; waiting briefly for the final transcript.
        case finishing
    }

    enum Permission: Equatable {
        case notDetermined, granted, denied, restricted
        /// This build can't ask (e.g. run without an app bundle / usage descriptions).
        case unsupported
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""
    /// 0…1 input level, for the listening meter.
    @Published private(set) var level: Float = 0

    /// Final text when a session ends (may be empty if nothing was heard).
    var onFinished: (String) -> Void = { _ in }
    /// A user-presentable problem (permission, no mic, unsupported language…).
    var onError: (String) -> Void = { _ in }
    /// Friendly status (e.g. "voice is ready").
    var onNotice: (String) -> Void = { _ in }

    /// Hard limit for one push-to-talk session.
    static let maxDuration: TimeInterval = 60

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var capTimer: Timer?
    private var finishTimer: Timer?
    private var sessionID = UUID()

    // MARK: Availability & permission

    /// Speech & mic APIs crash if the app lacks usage descriptions, so only
    /// offer voice when they're present (i.e. the real .app bundle).
    static var isSupportedBuild: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        return info["NSMicrophoneUsageDescription"] != nil && info["NSSpeechRecognitionUsageDescription"] != nil
    }

    var permission: Permission {
        guard Self.isSupportedBuild else { return .unsupported }
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        let speech = SFSpeechRecognizer.authorizationStatus()
        if mic == .denied || speech == .denied { return .denied }
        if mic == .restricted || speech == .restricted { return .restricted }
        if mic == .authorized && speech == .authorized { return .granted }
        return .notDetermined
    }

    static var hasMicrophone: Bool { AVCaptureDevice.default(for: .audio) != nil }

    /// Asks for microphone + speech recognition access (system prompts). Only call from a user action.
    func requestPermission() async -> Bool {
        guard Self.isSupportedBuild else { return false }
        let speechOK: Bool = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        guard speechOK else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    static func openPrivacySettings(microphone: Bool) {
        let anchor = microphone ? "Privacy_Microphone" : "Privacy_SpeechRecognition"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Session

    /// Starts listening. Requests permission first if it was never asked.
    func start(localeID: String, onDeviceOnly: Bool, hints: [String]) async {
        guard state == .idle else { return }
        guard Self.isSupportedBuild else {
            onError("Voice input needs the DeskPet app bundle (scripts/build-app.sh). You can still type.")
            return
        }
        guard Self.hasMicrophone else {
            onError("No microphone found. You can still type.")
            return
        }
        switch permission {
        case .denied, .restricted, .unsupported:
            onError("Microphone or speech recognition access is off for DeskPet. Turn it on in System Settings › Privacy & Security, or type instead.")
            return
        case .notDetermined:
            state = .requestingPermission
            let ok = await requestPermission()
            state = .idle
            guard ok else {
                onError("Without microphone and speech recognition access, voice is off — typing still works.")
                return
            }
            // The button was released while the prompt was up; never start listening silently afterwards.
            onNotice("Voice is ready — hold the mic button (or ⌃⌥V) while you talk.")
            return
        case .granted:
            break
        }

        let locale = Locale(identifier: localeID)
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            onError("Speech recognition isn’t available right now. You can still type.")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        request.contextualStrings = hints
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else if onDeviceOnly {
            onError("On-device recognition isn’t available for \(locale.localizedString(forIdentifier: localeID) ?? localeID) on this Mac. Allow Apple’s server recognition in Settings › Voice, or type instead.")
            return
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            onError("The microphone isn’t delivering audio. Check your input device in System Settings › Sound.")
            return
        }
        let id = UUID()
        sessionID = id
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let level = Self.rms(buffer)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.sessionID == id else { return }
                    self.level = self.level * 0.6 + level * 0.4
                }
            }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            onError("Couldn’t start the microphone: \(error.localizedDescription)")
            return
        }

        self.engine = engine
        self.request = request
        transcript = ""
        state = .listening
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let nsError = error as NSError?
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.sessionID == id else { return }
                    if let text { self.transcript = text }
                    if isFinal { self.complete() }
                    else if let nsError { self.handle(nsError) }
                }
            }
        }

        let cap = Timer(timeInterval: Self.maxDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        RunLoop.main.add(cap, forMode: .common)
        capTimer = cap
    }

    /// Turns the mic off and delivers the final transcript shortly after.
    func stop() {
        guard state == .listening else { return }
        state = .finishing
        stopAudio()
        request?.endAudio()
        // Don't wait forever for the recognizer's final pass.
        let t = Timer(timeInterval: 2.0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.complete() }
        }
        RunLoop.main.add(t, forMode: .common)
        finishTimer = t
    }

    /// Turns the mic off and discards anything heard.
    func cancel() {
        guard state == .listening || state == .finishing else { return }
        sessionID = UUID()
        task?.cancel()
        teardown()
        transcript = ""
        state = .idle
    }

    private func complete() {
        guard state == .listening || state == .finishing else { return }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        sessionID = UUID()
        task?.finish()
        teardown()
        state = .idle
        onFinished(text)
    }

    private func handle(_ error: NSError) {
        // "No speech detected" / cancellations end the session quietly with whatever we have.
        if state == .finishing || error.code == 1110 || error.code == 216 || error.code == 301 {
            complete()
            return
        }
        let message = error.localizedDescription
        cancel()
        onError("Speech recognition stopped: \(message)")
    }

    private func stopAudio() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        level = 0
    }

    private func teardown() {
        stopAudio()
        capTimer?.invalidate(); capTimer = nil
        finishTimer?.invalidate(); finishTimer = nil
        request = nil
        task = nil
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        // Map roughly -50…0 dB to 0…1.
        let db = 20 * log10(max(sqrt(sum / Float(n)), 1e-6))
        return max(0, min(1, (db + 50) / 50))
    }
}
