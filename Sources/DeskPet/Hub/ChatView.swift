import DeskPetCore
import SwiftUI

/// The chat panel: messages, action chips with Undo, permission cards,
/// a thinking indicator, retry on failure, and a clear-history control.
struct ChatView: View {
    @ObservedObject var chat: ChatModel
    var openSettings: () -> Void
    @State private var input = ""
    @State private var confirmClear = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                let state = chat.aiState
                Circle().fill(state.isReady ? DP.mint : Color.secondary).frame(width: 7, height: 7)
                Text(state.label).font(DP.caption).foregroundStyle(.secondary)
                if !state.isReady {
                    Button("Set up AI", action: openSettings).buttonStyle(.link).font(DP.caption)
                }
                Spacer()
                Button { confirmClear = true } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .disabled(chat.messages.isEmpty).help("Clear chat history")
                    .accessibilityLabel("Clear chat history")
            }
            .padding(.horizontal, 16).padding(.bottom, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if chat.messages.isEmpty { intro }
                        if chat.historyWasReset {
                            Text("Earlier messages are no longer sent to the AI.").font(DP.caption).foregroundStyle(.tertiary)
                        }
                        ForEach(chat.messages) { m in MessageBubble(message: m).id(m.id) }
                        if let p = chat.pending { PendingCard(pending: p, chat: chat).id("pending") }
                        switch chat.status {
                        case .working(let s): ThinkingRow(text: s).id("working")
                        case .failed(let e):
                            HStack(alignment: .top) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DP.danger)
                                Text(e.localizedDescription).font(DP.caption)
                                Spacer()
                                if e.isRetryable { Button("Retry") { chat.retry() }.buttonStyle(PillButtonStyle(tint: DP.danger, filled: false)) }
                                if e.needsSettings {
                                    Button("Settings", action: openSettings).buttonStyle(.link)
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(DP.danger.opacity(0.08)))
                            .id("failed")
                        case .idle: EmptyView()
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                }
                .onChange(of: chat.messages.count) { _, _ in scrollToEnd(proxy) }
                .onChange(of: chat.status) { _, _ in scrollToEnd(proxy) }
                .onChange(of: chat.pending?.id) { _, _ in scrollToEnd(proxy) }
                .onAppear { scrollToEnd(proxy) }
            }

            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                TextField(chat.aiState.isReady ? "Ask anything, or “log 300 ml”…" : "Try “focus for 25 minutes”…",
                          text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
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
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityLabel("Send")
                }
            }
            .padding(12)
        }
        .onAppear { inputFocused = true }
        .confirmationDialog("Clear the chat history?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { chat.clear() }
        } message: { Text("Removes the conversation from this Mac. It can’t be undone.") }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hi! I can chat, plan, draft and summarize — and I can log water, run your focus timer, and save tasks and notes.")
                .font(DP.body)
            Text(chat.aiState.isReady
                 ? "I only read your tasks, notes or stats if you allow it (Settings › AI)."
                 : "Commands work offline. General questions need AI — set it up in Settings › AI.")
                .font(DP.caption).foregroundStyle(.secondary)
            FlowChips(items: chat.aiState.isReady
                      ? ["Help me plan my afternoon", "Break down “launch my side project”", "Log 300 ml of water", "Summarize my focus sessions this week"]
                      : ["Log 300 ml of water", "Start a 25-minute focus session", "Add buy groceries to my tasks", "Show today’s progress"]) { s in
                input = s
                inputFocused = true
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(DP.accent.opacity(0.07)))
    }

    private func send() {
        let text = input
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, !chat.isBusy else { return }
        input = ""
        chat.send(text)
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if chat.pending != nil { proxy.scrollTo("pending", anchor: .bottom) }
            else if case .working = chat.status { proxy.scrollTo("working", anchor: .bottom) }
            else if case .failed = chat.status { proxy.scrollTo("failed", anchor: .bottom) }
            else if let last = chat.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }
}

struct MessageBubble: View {
    let message: ChatModel.Message
    @State private var undone: Set<UUID> = []

    var body: some View {
        let isUser = message.role == .user
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            Text(attributed)
                .font(DP.body)
                .textSelection(.enabled)
                .padding(.horizontal, 11).padding(.vertical, 8)
                .foregroundStyle(isUser ? Color.white : (message.isError ? DP.danger : .primary))
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isUser ? DP.accent : Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isUser ? Color.clear : Color.primary.opacity(0.08)))
            ForEach(message.chips) { chip in
                HStack(spacing: 6) {
                    Image(systemName: chip.style == .error ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(chip.style == .error ? DP.danger : DP.mint)
                    Text(undone.contains(chip.id) ? "Undone" : chip.text).font(DP.caption)
                    if let undo = chip.undo, !undone.contains(chip.id) {
                        Button("Undo") { undo(); undone.insert(chip.id) }.buttonStyle(.link).font(DP.caption)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.05)))
            }
            if message.isLocal && !isUser {
                Text("Handled on your Mac").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(isUser ? .leading : .trailing, 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isUser ? "You" : "DeskPet"): \(message.text)")
    }

    private var attributed: AttributedString {
        (try? AttributedString(markdown: message.text,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message.text)
    }
}

struct PendingCard: View {
    let pending: ChatModel.Pending
    @ObservedObject var chat: ChatModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(pending.title, systemImage: "hand.raised.fill").font(DP.headline).foregroundStyle(DP.accent)
            Text(pending.detail).font(DP.body)
            HStack {
                Button("Allow") { chat.decide(.allow) }.buttonStyle(PillButtonStyle()).keyboardShortcut(.defaultAction)
                if pending.allowAlwaysOption {
                    Button("Always allow") { chat.decide(.allowAlways) }.buttonStyle(PillButtonStyle(filled: false))
                }
                Button("Don’t allow") { chat.decide(.deny) }.buttonStyle(PillButtonStyle(tint: .secondary, filled: false))
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).strokeBorder(DP.accent.opacity(0.5)))
    }
}

struct ThinkingRow: View {
    var text: String
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(0..<3) { i in
                    Circle().fill(DP.accent).frame(width: 6, height: 6).opacity(phase == i ? 1 : 0.3)
                }
            }
            Text(text).font(DP.caption).foregroundStyle(.secondary)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(350))
                phase = (phase + 1) % 3
            }
        }
        .accessibilityLabel(text)
    }
}

/// Wrapping row of suggestion chips.
struct FlowChips: View {
    var items: [String]
    var onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { s in
                Button(s) { onTap(s) }.buttonStyle(PillButtonStyle(filled: false))
            }
        }
    }
}
