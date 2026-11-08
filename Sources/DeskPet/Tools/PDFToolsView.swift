import AppKit
import DeskPetCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// State for the PDF Tools window (kept while the window is reopened).
@MainActor
final class PDFToolsModel: ObservableObject {
    @Published var tool: PDFTool = .toPDF { didSet { if tool != oldValue { toolChanged() } } }
    @Published var files: [URL] = []
    @Published var password = ""
    @Published var pages = ""
    @Published var eachPage = false
    @Published var rotation = 90
    @Published private(set) var busy = false
    @Published private(set) var result: PDFEngine.Output?
    @Published var error: String?
    @Published var note: String?
    var onDone: (String) -> Void = { _ in }

    /// Adds files the current tool can use; reports any it skipped.
    func add(_ urls: [URL]) {
        let accepted = tool.acceptedExtensions
        var skipped = 0
        for url in urls {
            if url.hasDirectoryPath { skipped += 1; continue }
            guard accepted.contains(url.pathExtension.lowercased()) else { skipped += 1; continue }
            if !files.contains(url) { files.append(url) }
        }
        result = nil
        error = nil
        note = skipped > 0 ? "Skipped \(skipped) file\(skipped == 1 ? "" : "s") that \(tool.title) can’t use." : nil
    }

    func remove(_ url: URL) { files.removeAll { $0 == url }; result = nil }

    func move(_ url: URL, by d: Int) {
        guard let i = files.firstIndex(of: url) else { return }
        let j = i + d
        guard files.indices.contains(j) else { return }
        files.swapAt(i, j)
        result = nil
    }

    private func toolChanged() {
        files = files.filter { tool.acceptedExtensions.contains($0.pathExtension.lowercased()) }
        result = nil
        error = nil
        note = nil
        password = ""
    }

    var canRun: Bool {
        guard !busy, files.count >= tool.minimumFiles else { return false }
        switch tool {
        case .split: return files.count == 1 && !pages.trimmingCharacters(in: .whitespaces).isEmpty
        case .protect, .unlock: return !password.isEmpty
        default: return true
        }
    }

    var actionTitle: String {
        let n = files.count
        switch tool {
        case .toPDF: return n > 1 ? "Convert \(n) Files" : "Convert to PDF"
        case .merge: return n >= 2 ? "Merge \(n) Files" : "Merge"
        case .images: return n > 1 ? "Make PDF from \(n) Images" : "Make PDF"
        case .split: return eachPage ? "Save Pages Separately" : "Extract Pages"
        case .compress: return "Compress"
        case .rotate: return "Rotate"
        case .protect: return "Lock with Password"
        case .unlock: return "Save Unlocked Copy"
        case .toImages: return "Save as Images"
        case .toText: return "Extract Text"
        }
    }

    func run() {
        guard canRun else { return }
        busy = true
        error = nil
        result = nil
        let tool = tool, files = files
        // Let the spinner draw before the (synchronous) work starts.
        DispatchQueue.main.async { [self] in
            defer { busy = false }
            do {
                let out: PDFEngine.Output
                switch tool {
                case .toPDF: out = try PDFEngine.convertToPDF(files)
                case .merge: out = try PDFEngine.merge(files)
                case .images: out = try PDFEngine.imagesToPDF(files)
                case .split: out = try PDFEngine.split(files[0], ranges: pages, eachPage: eachPage)
                case .compress: out = try PDFEngine.compress(files)
                case .rotate: out = try PDFEngine.rotate(files, degrees: rotation, ranges: pages)
                case .protect: out = try PDFEngine.protect(files, password: password)
                case .unlock: out = try PDFEngine.unlock(files, password: password)
                case .toImages: out = try PDFEngine.toImages(files)
                case .toText: out = try PDFEngine.toText(files)
                }
                result = out
                if tool == .protect || tool == .unlock { password = "" }
                onDone(out.message)
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = tool.acceptedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.message = "Choose files for \(tool.title)"
        NSApp.activate()
        if panel.runModal() == .OK { add(panel.urls) }
    }
}

struct PDFToolsView: View {
    @ObservedObject var model: PDFToolsModel
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(minWidth: 760, minHeight: 540)
        .dpPanelStyle()
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(PDFTool.allCases) { t in
                    Button { model.tool = t } label: {
                        HStack(spacing: 9) {
                            Image(systemName: t.symbol).font(.system(size: 13, weight: .semibold))
                                .frame(width: 20).foregroundStyle(model.tool == t ? .white : DP.accent)
                            Text(t.title).font(.system(size: 13, weight: .medium))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(model.tool == t ? DP.accent : .clear))
                        .foregroundStyle(model.tool == t ? .white : .primary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.tool == t ? .isSelected : [])
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 34) // clear of the window's traffic-light buttons
            .padding(.bottom, 10)
        }
        .frame(width: 200)
        .background(Color.primary.opacity(0.03))
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label(model.tool.title, systemImage: model.tool.symbol).font(.system(size: 20, weight: .bold, design: .rounded))
                Text(model.tool.subtitle).font(DP.caption).foregroundStyle(.secondary)
            }
            dropZone
            if !model.files.isEmpty { fileList }
            options
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 22)
        .padding(.top, 30)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            loadURLs(providers) { model.add($0) }
            return true
        }
    }

    private var dropZone: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.down.doc").font(.system(size: 22, weight: .semibold)).foregroundStyle(DP.accent)
            Text("Drop files here").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 4) {
                Text("or").foregroundStyle(.secondary)
                Button("Choose Files…") { model.chooseFiles() }.buttonStyle(.link)
            }.font(DP.caption)
            Text(acceptedHint).font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, model.files.isEmpty ? 28 : 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(dropTargeted ? DP.accent.opacity(0.12) : Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(dropTargeted ? DP.accent : Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
    }

    private var acceptedHint: String {
        model.tool.acceptedExtensions.sorted().map { $0.uppercased() }.joined(separator: " · ")
    }

    private var fileList: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Array(model.files.enumerated()), id: \.element) { i, url in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                            Text(details(url)).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if model.tool == .merge || model.tool == .images {
                            Button { model.move(url, by: -1) } label: { Image(systemName: "chevron.up") }
                                .buttonStyle(.plain).disabled(i == 0).help("Move up").accessibilityLabel("Move \(url.lastPathComponent) up")
                            Button { model.move(url, by: 1) } label: { Image(systemName: "chevron.down") }
                                .buttonStyle(.plain).disabled(i == model.files.count - 1).help("Move down").accessibilityLabel("Move \(url.lastPathComponent) down")
                        }
                        Button { model.remove(url) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove").accessibilityLabel("Remove \(url.lastPathComponent)")
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                }
            }
        }
        .frame(maxHeight: 170)
    }

    private func details(_ url: URL) -> String {
        var parts = [PDFFiles.size(PDFEngine.fileSize(url))]
        if let n = PDFEngine.pageCount(url) { parts.append(n == 1 ? "1 page" : "\(n) pages") }
        else if url.pathExtension.lowercased() == "pdf", PDFDocument(url: url)?.isLocked == true { parts.append("locked") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var options: some View {
        switch model.tool {
        case .split:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Pages")
                    TextField("e.g. 1-3, 5, 8-", text: $model.pages).textFieldStyle(.roundedBorder).frame(width: 200)
                    if model.files.count > 1 { Text("Uses the first file only.").font(DP.caption).foregroundStyle(.secondary) }
                }
                Toggle("Save each page as its own PDF", isOn: $model.eachPage)
            }
        case .rotate:
            HStack {
                Picker("Turn", selection: $model.rotation) {
                    Text("Right 90°").tag(90); Text("Left 90°").tag(-90); Text("180°").tag(180)
                }.pickerStyle(.segmented).frame(width: 280)
                TextField("All pages (or e.g. 2, 4-6)", text: $model.pages).textFieldStyle(.roundedBorder).frame(width: 200)
            }
        case .protect:
            VStack(alignment: .leading, spacing: 4) {
                SecureField("Password", text: $model.password).textFieldStyle(.roundedBorder).frame(width: 260)
                Text("You’ll need this password to open the new copy. DeskPet doesn’t store it.").font(DP.caption).foregroundStyle(.secondary)
            }
        case .unlock:
            SecureField("Current password", text: $model.password).textFieldStyle(.roundedBorder).frame(width: 260)
                .onSubmit { model.run() }
        case .toPDF:
            Text("Text, headings, lists and basic formatting carry over. Complex Word layouts (columns, text boxes) may differ.")
                .font(DP.caption).foregroundStyle(.secondary)
        case .compress:
            Text("Images are re-saved as JPEG at screen resolution. Text stays sharp. Originals are never changed.")
                .font(DP.caption).foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(DP.caption).foregroundStyle(DP.danger)
            } else if let note = model.note {
                Text(note).font(DP.caption).foregroundStyle(.secondary)
            }
            if let r = model.result {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(DP.mint).font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.message).font(.system(size: 12, weight: .semibold))
                        Text(r.urls.count == 1 ? r.urls[0].lastPathComponent : "\(r.urls.count) files next to the original")
                            .font(DP.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    if r.urls.count == 1 { Button("Open") { NSWorkspace.shared.open(r.urls[0]) } }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(r.urls) }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(DP.mint.opacity(0.12)))
            }
            HStack {
                Text("Saved next to the original. Nothing leaves your Mac.").font(DP.caption).foregroundStyle(.tertiary)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button(model.actionTitle) { model.run() }
                    .buttonStyle(.borderedProminent)
                    .tint(DP.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canRun)
                    .controlSize(.large)
            }
        }
    }
}

/// Resolves dropped item providers to file URLs (on the main actor).
func loadURLs(_ providers: [NSItemProvider], _ done: @escaping @MainActor ([URL]) -> Void) {
    let group = DispatchGroup()
    let lock = NSLock()
    var urls: [(Int, URL)] = []
    for (i, p) in providers.enumerated() where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        group.enter()
        _ = p.loadObject(ofClass: URL.self) { url, _ in
            if let url { lock.lock(); urls.append((i, url)); lock.unlock() }
            group.leave()
        }
    }
    group.notify(queue: .main) {
        let ordered = urls.sorted { $0.0 < $1.0 }.map(\.1)
        MainActor.assumeIsolated { done(ordered) }
    }
}
