import AppKit
import DeskPetCore
import SwiftUI

// MARK: - Screenshot preview

/// A small thumbnail in the bottom-right corner after a screenshot: click to open,
/// drag it into any app, or use the buttons. Disappears on its own after a few seconds.
@MainActor
final class ScreenshotPreviewController {
    var copyText: (URL) -> Void = { _ in }
    private var panel: NSPanel?
    private var hideTimer: Timer?
    private var current: (url: URL, isTemporary: Bool)?

    func show(url: URL, isTemporary: Bool) {
        dismiss()
        guard let image = NSImage(contentsOf: url) else { return }
        current = (url, isTemporary)
        let view = ScreenshotPreviewView(
            image: image, url: url, isTemporary: isTemporary,
            onOpen: { [weak self] in NSWorkspace.shared.open(url); self?.dismiss() },
            onReveal: { [weak self] in NSWorkspace.shared.activateFileViewerSelecting([url]); self?.dismiss() },
            onCopyText: { [weak self] in self?.copyText(url); self?.dismiss() },
            onDelete: { [weak self] in
                NSWorkspace.shared.recycle([url])
                self?.current = nil
                self?.dismiss()
            },
            onClose: { [weak self] in self?.dismiss() },
            onHover: { [weak self] hovering in hovering ? self?.hideTimer?.invalidate() : self?.scheduleHide(after: 3) })

        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: view)
        p.contentView = host
        p.setContentSize(host.fittingSize)
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: vf.maxX - p.frame.width - 20, y: vf.minY + 20))
        }
        p.orderFrontRegardless()
        panel = p
        scheduleHide(after: 7)
    }

    private func scheduleHide(after seconds: TimeInterval) {
        hideTimer?.invalidate()
        let t = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        RunLoop.main.add(t, forMode: .common)
        hideTimer = t
    }

    func dismiss() {
        hideTimer?.invalidate()
        hideTimer = nil
        panel?.orderOut(nil)
        panel = nil
        // Unsaved shots (clipboard-only) are removed once the preview goes away —
        // a bit later, so a drag that's still being received can finish.
        if let c = current, c.isTemporary {
            let url = c.url
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { try? FileManager.default.removeItem(at: url) }
        }
        current = nil
    }
}

private struct ScreenshotPreviewView: View {
    let image: NSImage
    let url: URL
    let isTemporary: Bool
    var onOpen: () -> Void
    var onReveal: () -> Void
    var onCopyText: () -> Void
    var onDelete: () -> Void
    var onClose: () -> Void
    var onHover: (Bool) -> Void
    @State private var hovering = false

    var body: some View {
        let size = Self.thumbSize(image.size)
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 2))
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
                .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                .help("Click to open · drag into any app")
                .accessibilityLabel("Screenshot preview. Click to open.")
                .accessibilityAddTraits(.isButton)

            if hovering {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.plain).padding(6).accessibilityLabel("Close preview")

                HStack(spacing: 6) {
                    pill("text.viewfinder", "Copy text", onCopyText)
                    if !isTemporary {
                        pill("folder", "Show in Finder", onReveal)
                        pill("trash", "Delete", onDelete)
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .bottom)
                .padding(.bottom, 8)
            }
        }
        .padding(6)
        .onHover { hovering = $0; onHover($0) }
    }

    private func pill(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 24)
                .background(Capsule().fill(.black.opacity(0.65)))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }

    static func thumbSize(_ s: CGSize) -> CGSize {
        guard s.width > 0, s.height > 0 else { return CGSize(width: 200, height: 120) }
        let scale = min(220 / s.width, 160 / s.height, 1)
        return CGSize(width: max(80, (s.width * scale).rounded()), height: max(60, (s.height * scale).rounded()))
    }
}

// MARK: - Clipboard history

/// ⌃⌥B: search recent copies, ↩ to paste one back.
struct ClipboardHistoryView: View {
    @ObservedObject var monitor: ClipboardMonitor
    @ObservedObject var settings: AppSettings
    var onUse: (ClipEntry) -> Void
    var onClose: () -> Void
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var rows: [ClipEntry] { monitor.history.search(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if settings.clipboardHistoryEnabled { list } else { offState }
        }
        .frame(width: 520)
        .background(.regularMaterial)
        .onExitCommand(perform: onClose)
        .dpPanelStyle()
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "list.clipboard").font(.system(size: 18, weight: .semibold)).foregroundStyle(DP.accent)
                TextField("Search clipboard history…", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 17))
                    .focused($focused)
                    .onSubmit { choose(selection) }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .accessibilityLabel("Search clipboard history")
            }
            .padding(16)
            Divider()
            let items = rows
            if items.isEmpty {
                Text(monitor.history.entries.isEmpty ? "Nothing yet. Copy some text and it’ll show up here." : "No matches.")
                    .font(DP.caption).foregroundStyle(.secondary).padding(16)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, e in
                                row(e, index: i, selected: i == selection).id(e.id)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 340)
                    .onChange(of: selection) { _, s in
                        if let id = items[safe: s]?.id { proxy.scrollTo(id) }
                    }
                }
            }
            Divider()
            HStack {
                Text(settings.clipboardAutoPaste && AXIsProcessTrusted() ? "↩ paste · ↑↓ choose · esc close" : "↩ copy · ↑↓ choose · esc close")
                    .font(DP.caption).foregroundStyle(.tertiary)
                Spacer()
                if !monitor.history.entries.isEmpty {
                    Button("Clear All") { monitor.clear(); selection = 0 }
                        .buttonStyle(.plain).font(DP.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in selection = 0 }
    }

    private func row(_ e: ClipEntry, index: Int, selected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(index < 9 ? "\(index + 1)" : "").font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary).frame(width: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.preview).font(.system(size: 13)).lineLimit(1)
                Text(meta(e)).font(DP.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button { monitor.remove(e) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).opacity(selected ? 1 : 0)
                .help("Remove from history").accessibilityLabel("Remove from history")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? DP.accent.opacity(0.18) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { choose(index) }
        .onHover { if $0 { selection = index } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func meta(_ e: ClipEntry) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        var parts = [f.localizedString(for: e.copiedAt, relativeTo: Date())]
        if let app = e.sourceApp { parts.insert(app, at: 0) }
        if e.lineCount > 1 { parts.append("\(e.lineCount) lines") }
        return parts.joined(separator: " · ")
    }

    private var offState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Clipboard history is off", systemImage: "list.clipboard").font(.system(size: 15, weight: .semibold))
            Text("When it’s on, DeskPet remembers the last \(ClipboardHistory.maxEntries) pieces of text you copy so you can paste them again. It’s stored only on this Mac, and copies from password managers are never kept.")
                .font(DP.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Not now", action: onClose)
                Button("Turn On") { settings.clipboardHistoryEnabled = true }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
    }

    private func move(_ d: Int) {
        let n = rows.count
        guard n > 0 else { return }
        selection = (selection + d + n) % n
    }

    private func choose(_ i: Int) {
        guard let e = rows[safe: i] else { return }
        onClose()
        onUse(e)
    }
}
