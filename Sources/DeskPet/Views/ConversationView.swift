import DeskPetCore
import SwiftUI

/// Compact "talk to your pet" window: the shared conversation (same history
/// as the hub's Chat tab), with real actions and short-term context.
struct ConversationView: View {
    @ObservedObject var chat: ChatModel
    @ObservedObject var pet: PetViewModel
    @ObservedObject var voice: VoiceController
    @ObservedObject var recognizer: SpeechRecognizerService
    @ObservedObject var settings: AppSettings
    var openSettings: (SettingsTab) -> Void

    @State private var input = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messages
            Divider()
            composer
            if let notice = voice.notice {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text(notice).font(DP.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if recognizer.permission == .denied {
                        Button("Open Settings") { SpeechRecognizerService.openPrivacySettings(microphone: true) }
                            .buttonStyle(.link).font(DP.caption)
                    }
                    Button { voice.notice = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(.tertiary).accessibilityLabel("Dismiss")
                }
                .padding(.horizontal, 12).padding(.bottom, 8)
            }
        }
        .onDisappear { voice.cancelListening() }
        .frame(minWidth: 340, minHeight: 420)
        .onAppear { inputFocused = true }
        .dpPanelStyle()
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            CatCanvas(pose: CatPose(eyes: .open, blush: true, coat: pet.coat, accessory: pet.accessory), pixel: 2)
                .frame(width: 48, height: 46)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(pet.name).font(DP.headline)
                Text(statusText).font(DP.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if voice.activity == .speaking {
                Button { voice.stopSpeaking() } label: { Image(systemName: "stop.fill") }
                    .buttonStyle(.borderless).foregroundStyle(DP.accent)
                    .help("Stop speaking (Esc)").accessibilityLabel("Stop speaking")
                    .keyboardShortcut(.cancelAction)
            }
            Button { settings.voiceMuted.toggle() } label: {
                Image(systemName: settings.voiceMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(.borderless).foregroundStyle(settings.voiceMuted ? .secondary : DP.accent)
            .help(settings.voiceMuted ? "Spoken replies muted — click to unmute" : "Mute spoken replies")
            .accessibilityLabel(settings.voiceMuted ? "Unmute spoken replies" : "Mute spoken replies")
            Button { openSettings(.voice) } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("Voice & conversation settings").accessibilityLabel("Voice settings")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var statusText: String {
        switch voice.activity {
        case .listening: return voice.latched ? "Listening… tap the mic to send" : "Listening… release to send"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking…"
        case .idle:
            if case .failed = chat.status { return "Something went wrong" }
            return chat.aiState.isReady ? chat.aiState.label : "On-device commands · AI not set up"
        }
    }

    // MARK: Messages

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if chat.messages.isEmpty { intro }
                    ForEach(chat.messages.suffix(60)) { m in MessageBubble(message: m).id(m.id) }
                    if let p = chat.pending { PendingCard(pending: p, chat: chat).id("pending") }
                    switch chat.status {
                    case .working(let s): ThinkingRow(text: s).id("working")
                    case .failed(let e):
                        HStack {
                            Text(e.localizedDescription).font(DP.caption).foregroundStyle(DP.danger)
                            Spacer()
                            if e.isRetryable { Button("Retry") { chat.retry() }.buttonStyle(.link) }
                            if e.needsSettings { Button("Settings") { openSettings(.ai) }.buttonStyle(.link) }
                        }
                        .id("failed")
                    case .idle: EmptyView()
                    }
                }
                .padding(12)
            }
            .onChange(of: chat.messages.count) { _, _ in scroll(proxy) }
            .onChange(of: chat.status) { _, _ in scroll(proxy) }
            .onChange(of: chat.pending?.id) { _, _ in scroll(proxy) }
            .onAppear { scroll(proxy) }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Talk to me! I can log water, run your focus timer, and keep track of things.").font(DP.body)
            FlowChips(items: ["I’ve had 300 ml of water", "What’s my total?", "Start a 25-minute focus session"]) { s in
                chat.send(s)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(DP.accent.opacity(0.07)))
    }

    // MARK: Composer

    /// One persistent mic button (so a held press always gets its release),
    /// next to either the text field or the live transcript.
    private var composer: some View {
        HStack(alignment: .center, spacing: 8) {
            MicButton(voice: voice, available: voice.voiceInputAvailable)
            if voice.isListening || recognizer.state == .requestingPermission {
                listeningContent
            } else {
                typingContent
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var typingContent: some View {
            TextField("Message \(pet.name)…", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit(send)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
                .accessibilityLabel("Message")
            if case .working = chat.status {
                Button { chat.cancel() } label: { Image(systemName: "stop.circle.fill").font(.title2) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Stop").accessibilityLabel("Stop")
            } else {
                Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .buttonStyle(.plain).foregroundStyle(DP.accent)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || chat.isBusy)
                    .accessibilityLabel("Send")
            }
    }

    /// Shown instead of the text field while the mic is on.
    @ViewBuilder
    private var listeningContent: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(recognizer.state == .requestingPermission ? "Waiting for permission…"
                     : (recognizer.transcript.isEmpty ? "Listening…" : recognizer.transcript))
                    .font(DP.body)
                    .foregroundStyle(recognizer.transcript.isEmpty ? .secondary : .primary)
                    .lineLimit(3)
                    .accessibilityLabel("Heard so far: \(recognizer.transcript)")
                LevelMeter(level: recognizer.level)
            }
            Spacer(minLength: 0)
            Button { voice.cancelListening() } label: { Image(systemName: "xmark.circle.fill").font(.title3) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Cancel — discard what was heard").accessibilityLabel("Cancel listening")
                .keyboardShortcut(.cancelAction)
    }

    private func send() {
        let text = input
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, !chat.isBusy else { return }
        input = ""
        voice.stopSpeaking()
        chat.send(text)
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if chat.pending != nil { proxy.scrollTo("pending", anchor: .bottom) }
            else if case .working = chat.status { proxy.scrollTo("working", anchor: .bottom) }
            else if case .failed = chat.status { proxy.scrollTo("failed", anchor: .bottom) }
            else if let last = chat.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }
}

/// Push-to-talk: hold to talk and release to send, or tap once to start and
/// tap again to send. The mic is never on unless this (or the shortcut) is used.
struct MicButton: View {
    @ObservedObject var voice: VoiceController
    var available: Bool
    @State private var pressing = false

    var body: some View {
        let listening = voice.isListening
        ZStack {
            Circle()
                .fill(listening ? Color.red : (available ? DP.accent.opacity(0.14) : Color.primary.opacity(0.06)))
                .frame(width: 34, height: 34)
                .scaleEffect(listening ? 1.08 : 1)
                .animation(listening ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default, value: listening)
            Image(systemName: listening ? "mic.fill" : (available ? "mic" : "mic.slash"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(listening ? Color.white : (available ? DP.accent : .secondary))
        }
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !pressing else { return }
                pressing = true
                voice.pressBegan()
            }
            .onEnded { _ in
                pressing = false
                voice.pressEnded()
            })
        .help(available ? "Hold to talk (or tap to start, tap again to send) · ⌃⌥V anywhere"
                        : (voice.unavailableReason ?? "Voice unavailable"))
        .accessibilityElement()
        .accessibilityLabel(listening ? "Stop listening and send" : "Talk")
        .accessibilityHint("Starts the microphone. Activate again to send.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            voice.pressBegan()
            voice.pressEnded()
        }
    }
}

/// Small live input-level bar so it's obvious the mic hears you.
private struct LevelMeter: View {
    var level: Float

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(Color.red.opacity(0.7))
                    .frame(width: max(4, g.size.width * CGFloat(level)))
                    .animation(.linear(duration: 0.08), value: level)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}
