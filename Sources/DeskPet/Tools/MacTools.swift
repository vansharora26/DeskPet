import AppKit
import Carbon.HIToolbox
import DeskPetCore
import IOKit.pwr_mgt
import Vision

/// Everyday Mac utilities the pet can do for you: screenshots, copying text off
/// the screen, keeping the Mac awake, and clipboard history.
@MainActor
final class MacTools: ObservableObject {
    static let shared = MacTools()

    let keepAwake = KeepAwakeController()
    private(set) var clipboard: ClipboardMonitor!

    private weak var pet: PetViewModel?
    private var settings: AppSettings?
    private var hidePet: () -> Bool = { false }
    private var showPet: () -> Void = {}
    private var saveNote: (String) -> Bool = { _ in false }
    private var busy = false
    private let preview = ScreenshotPreviewController()

    enum ScreenshotMode { case area, window, fullScreen }

    /// Set by the app delegate: opens the PDF tools window.
    var showPDFTools: (PDFTool?, [URL]) -> Void = { _, _ in }
    func openPDFTools(_ tool: PDFTool? = nil, files: [URL] = []) { showPDFTools(tool, files) }

    /// Wired once by the app delegate.
    func configure(pet: PetViewModel, settings: AppSettings, dataDirectory: URL,
                   hidePet: @escaping () -> Bool, showPet: @escaping () -> Void,
                   saveNote: @escaping (String) -> Bool) {
        self.pet = pet
        self.settings = settings
        self.hidePet = hidePet
        self.showPet = showPet
        self.saveNote = saveNote
        keepAwake.onEnded = { [weak pet] reason in
            if reason == .timeUp { pet?.say("Time’s up. Your Mac can sleep again.") }
        }
        clipboard = ClipboardMonitor(fileURL: dataDirectory.appendingPathComponent("clipboard.json"), settings: settings)
        preview.copyText = { [weak self] url in self?.recognize(url, deleteAfter: false) }
    }

    // MARK: - Screenshots

    func screenshot(_ mode: ScreenshotMode = .area) {
        guard let settings else { return }
        capture(mode) { [weak self] url in
            guard let self, let url else { return }
            var copied = false
            if settings.screenshotCopyToClipboard, let data = try? Data(contentsOf: url) {
                copied = Self.copyImage(data)
            }
            var final = url
            if settings.screenshotSaveToFile {
                do { final = try Self.moveToScreenshotsFolder(url) } catch {
                    self.pet?.say("I couldn’t save the screenshot file: \(error.localizedDescription)")
                }
            }
            self.preview.show(url: final, isTemporary: !settings.screenshotSaveToFile)
            self.pet?.say(settings.screenshotSaveToFile
                          ? (copied ? "Snap! Copied and saved to Pictures." : "Snap! Saved to Pictures.")
                          : "Snap! It’s on your clipboard.")
        }
    }

    /// Drag over anything on screen; the text in it goes to the clipboard.
    func copyTextFromScreen() {
        capture(.area) { [weak self] url in
            guard let self, let url else { return }
            self.recognize(url, deleteAfter: true)
        }
    }

    private func recognize(_ url: URL, deleteAfter: Bool) {
        pet?.say("Reading…")
        Task { [weak self] in
            let text = (try? await Self.recognizeText(in: url)) ?? ""
            if deleteAfter { try? FileManager.default.removeItem(at: url) }
            guard let self else { return }
            guard !text.isEmpty else {
                self.pet?.say("I couldn’t find any text there.")
                return
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            let lines = text.split(whereSeparator: \.isNewline).count
            let first = ClipEntry(text: text, copiedAt: Date(), sourceApp: nil).preview
            let short = first.count > 48 ? String(first.prefix(48)) + "…" : first
            self.pet?.show(PetCallout(
                kind: .tool, symbol: "text.viewfinder",
                message: "Copied \(lines == 1 ? "1 line" : "\(lines) lines"): “\(short)”",
                actions: [.init(title: "Save as note") { [weak self] in
                    self?.pet?.clearCallout(kind: .tool)
                    if self?.saveNote(text) == true { self?.pet?.say("Saved to Notes.") }
                }]))
        }
    }

    /// Runs macOS's own `screencapture` (native selection UI: drag for an area,
    /// Space to switch to window mode, Esc to cancel). `done(nil)` when cancelled.
    private func capture(_ mode: ScreenshotMode, done: @escaping (URL?) -> Void) {
        guard !busy else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            pet?.show(PetCallout(
                kind: .tool, symbol: "camera.viewfinder",
                message: "macOS needs Screen Recording permission for this. Turn on DeskPet, then try again.",
                actions: [.init(title: "Open Settings", isPrimary: true) { [weak self] in
                    self?.pet?.clearCallout(kind: .tool)
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }]))
            return
        }
        busy = true
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DeskPet-\(UUID().uuidString).png")
        var args = ["-x", "-t", "png"]
        switch mode {
        case .area: args.append("-i")
        case .window: args += ["-i", "-W"]
        case .fullScreen:
            if let index = Self.displayIndexUnderMouse() { args += ["-D", "\(index)"] } else { args.append("-m") }
        }
        args.append(url.path)

        let wasShown = (settings?.screenshotHidePet ?? true) ? hidePet() : false
        // Give the window server a moment to remove the pet before the shot.
        DispatchQueue.main.asyncAfter(deadline: .now() + (wasShown ? 0.15 : 0)) { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = args
            p.terminationHandler = { _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.busy = false
                    if wasShown { self.showPet() }
                    done(FileManager.default.fileExists(atPath: url.path) ? url : nil)
                }
            }
            do { try p.run() } catch {
                self?.busy = false
                if wasShown { self?.showPet() }
                self?.pet?.say("Screenshots aren’t available: \(error.localizedDescription)")
            }
        }
    }

    /// 1-based index into the active display list, as `screencapture -D` expects.
    private static func displayIndexUnderMouse() -> Int? {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.firstIndex(of: id).map { $0 + 1 }
    }

    @discardableResult
    static func copyImage(_ png: Data) -> Bool {
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.writeObjects([item])
    }

    nonisolated static var screenshotsFolder: URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        return pictures.appendingPathComponent("DeskPet Screenshots", isDirectory: true)
    }

    static func moveToScreenshotsFolder(_ url: URL, now: Date = Date(), folder: URL = screenshotsFolder) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "Screenshot \(f.string(from: now))"
        var dest = folder.appendingPathComponent(base + ".png")
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = folder.appendingPathComponent("\(base) (\(n)).png")
            n += 1
        }
        try FileManager.default.moveItem(at: url, to: dest)
        return dest
    }

    func openScreenshotsFolder() {
        try? FileManager.default.createDirectory(at: Self.screenshotsFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Self.screenshotsFolder)
    }

    // MARK: - Text recognition (on-device)

    nonisolated static func recognizeText(in url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                do {
                    try VNImageRequestHandler(url: url).perform([request])
                    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                    cont.resume(returning: lines.joined(separator: "\n"))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Keep awake

    func setKeepAwake(minutes: Int?) {
        guard keepAwake.start(minutes: minutes) else {
            pet?.say("macOS didn’t let me keep the Mac awake.")
            return
        }
        pet?.say(minutes.map { "I’ll keep your Mac awake for \(KeepAwake.title(minutes: $0))." }
                 ?? "I’ll keep your Mac awake until you turn it off.")
    }

    func stopKeepAwake() {
        guard keepAwake.isActive else { return }
        keepAwake.stop(reason: .user)
        pet?.say("Okay, your Mac can sleep normally again.")
    }

    // MARK: - Clipboard

    /// Copies an entry back to the clipboard and, if allowed, pastes it into the app in front.
    func use(_ entry: ClipEntry) {
        clipboard.copy(entry)
        guard settings?.clipboardAutoPaste == true, AXIsProcessTrusted() else { return }
        // Let the panel close and focus settle on the user's app first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { Self.sendPaste() }
    }

    private static func sendPaste() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_V)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
            e?.flags = .maskCommand
            e?.post(tap: .cghidEventTap)
        }
    }

    /// Opens the Accessibility prompt (needed only for auto-paste).
    static func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}

// MARK: - Keep awake

/// Holds an IOKit power assertion that stops idle display (and so system) sleep.
@MainActor
final class KeepAwakeController: ObservableObject {
    enum EndReason { case user, timeUp }

    @Published private(set) var isActive = false
    /// nil while active = until turned off.
    @Published private(set) var endsAt: Date?
    var onEnded: (EndReason) -> Void = { _ in }

    private var assertion: IOPMAssertionID = 0
    private var timer: Timer?

    @discardableResult
    func start(minutes: Int?) -> Bool {
        if isActive { release() }
        var id: IOPMAssertionID = 0
        let ok = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                             IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                             "DeskPet keep awake" as CFString, &id) == kIOReturnSuccess
        guard ok else { return false }
        assertion = id
        isActive = true
        if let m = minutes {
            let end = Date().addingTimeInterval(TimeInterval(m * 60))
            endsAt = end
            let t = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop(reason: .timeUp) }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else {
            endsAt = nil
        }
        return true
    }

    func stop(reason: EndReason) {
        guard isActive else { return }
        release()
        onEnded(reason)
    }

    private func release() {
        timer?.invalidate()
        timer = nil
        if assertion != 0 { IOPMAssertionRelease(assertion) }
        assertion = 0
        isActive = false
        endsAt = nil
    }

    var statusText: String? {
        guard isActive else { return nil }
        guard let endsAt else { return "Keeping your Mac awake" }
        return "Keeping your Mac awake · \(KeepAwake.remaining(endsAt.timeIntervalSinceNow))"
    }
}

// MARK: - Clipboard history

/// Watches the clipboard (text only) while enabled. Polls the change count —
/// no keyboard monitoring, no permissions. History is stored only on this Mac.
@MainActor
final class ClipboardMonitor: ObservableObject {
    @Published private(set) var history = ClipboardHistory()
    private let fileURL: URL
    private let settings: AppSettings
    private var timer: Timer?
    private var lastChange = NSPasteboard.general.changeCount
    private var observation: Any?

    init(fileURL: URL, settings: AppSettings) {
        self.fileURL = fileURL
        self.settings = settings
        load()
        observation = settings.$clipboardHistoryEnabled.removeDuplicates().sink { [weak self] on in
            on ? self?.start() : self?.stopWatching()
        }
    }

    var isEnabled: Bool { settings.clipboardHistoryEnabled }

    private func start() {
        guard timer == nil else { return }
        lastChange = NSPasteboard.general.changeCount // don't import what was copied before turning on
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        t.tolerance = 0.25
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    func poll() {
        let pb = NSPasteboard.general
        guard isEnabled, pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        let types = (pb.types ?? []).map(\.rawValue)
        let front = NSWorkspace.shared.frontmostApplication
        guard !ClipboardHistory.shouldIgnore(types: types, sourceBundleID: front?.bundleIdentifier),
              let text = pb.string(forType: .string) else { return }
        if history.record(text, at: Date(), sourceApp: front?.localizedName) { save() }
    }

    func copy(_ entry: ClipEntry) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(entry.text, forType: .string)
        history.record(entry.text, at: Date(), sourceApp: entry.sourceApp)
        lastChange = pb.changeCount
        save()
    }

    func remove(_ entry: ClipEntry) {
        history.remove(id: entry.id)
        save()
    }

    func clear() {
        history.clear()
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let h = try? JSONDecoder().decode(ClipboardHistory.self, from: data) else { return }
        history = h
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(history).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {}
    }
}
