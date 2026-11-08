import AppKit
import DeskPetCore
import PDFKit
import Quartz

/// The PDF tools' actual work, using Apple's PDFKit and AppKit text system.
/// Everything stays on this Mac. Outputs are written next to the first input.
@MainActor
enum PDFEngine {
    struct Output {
        var urls: [URL]
        var message: String
    }

    enum Failure: LocalizedError {
        case unreadable(String)
        case locked(String)
        case wrongPassword(String)
        case convertFailed(String, String)
        case writeFailed(String)
        case needsMore(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let n): return "“\(n)” couldn’t be opened as a PDF."
            case .locked(let n): return "“\(n)” is password-protected. Use Remove Password first."
            case .wrongPassword(let n): return "That password doesn’t open “\(n)”."
            case .convertFailed(let n, let why): return "Couldn’t convert “\(n)”: \(why)"
            case .writeFailed(let n): return "Couldn’t save “\(n)”. Check that the folder can be written to."
            case .needsMore(let why): return why
            }
        }
    }

    private static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    private static func out(_ input: URL, _ suffix: String?, _ ext: String = "pdf") -> URL {
        PDFFiles.output(for: input, suffix: suffix, ext: ext, exists: exists)
    }

    static func open(_ url: URL, allowLocked: Bool = false) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else { throw Failure.unreadable(url.lastPathComponent) }
        if doc.isLocked && !allowLocked { throw Failure.locked(url.lastPathComponent) }
        return doc
    }

    private static func write(_ doc: PDFDocument, to url: URL, options: [PDFDocumentWriteOption: Any] = [:]) throws {
        guard doc.write(to: url, withOptions: options) else { throw Failure.writeFailed(url.lastPathComponent) }
    }

    private static func pages(_ n: Int) -> String { n == 1 ? "1 page" : "\(n) pages" }

    // MARK: Documents → PDF

    static func convertToPDF(_ urls: [URL]) throws -> Output {
        var outs: [URL] = []
        for url in urls {
            let text = try readDocument(url)
            let dest = out(url, nil)
            try render(text, to: dest, name: url.lastPathComponent)
            outs.append(dest)
        }
        return Output(urls: outs, message: outs.count == 1 ? "Converted to \(outs[0].lastPathComponent)" : "Converted \(outs.count) files to PDF")
    }

    static func readDocument(_ url: URL) throws -> NSAttributedString {
        let ext = url.pathExtension.lowercased()
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
        switch ext {
        case "docx": options[.documentType] = NSAttributedString.DocumentType.officeOpenXML
        case "doc": options[.documentType] = NSAttributedString.DocumentType.docFormat
        case "odt": options[.documentType] = NSAttributedString.DocumentType.openDocument
        case "rtf": options[.documentType] = NSAttributedString.DocumentType.rtf
        case "rtfd": options[.documentType] = NSAttributedString.DocumentType.rtfd
        case "html", "htm": options[.documentType] = NSAttributedString.DocumentType.html
        case "webarchive": options[.documentType] = NSAttributedString.DocumentType.webArchive
        default:
            options[.documentType] = NSAttributedString.DocumentType.plain
            options[.characterEncoding] = String.Encoding.utf8.rawValue
        }
        do {
            let s = try NSAttributedString(url: url, options: options, documentAttributes: nil)
            guard s.length > 0 else { throw Failure.convertFailed(url.lastPathComponent, "the document is empty.") }
            if options[.documentType] as? NSAttributedString.DocumentType == .plain {
                return NSAttributedString(string: s.string, attributes: [.font: NSFont.systemFont(ofSize: 12)])
            }
            return s
        } catch let f as Failure {
            throw f
        } catch {
            throw Failure.convertFailed(url.lastPathComponent, "macOS couldn’t read this kind of file.")
        }
    }

    /// Lays text out on A4 (US Letter in the US) with normal margins and saves it as a PDF.
    static func render(_ source: NSAttributedString, to url: URL, name: String) throws {
        let usesLetter = Locale.current.region?.identifier == "US" || Locale.current.region?.identifier == "CA"
        let paper = usesLetter ? NSSize(width: 612, height: 792) : NSSize(width: 595, height: 842)
        let margin: CGFloat = 56
        let info = NSPrintInfo()
        info.paperSize = paper
        info.topMargin = margin; info.bottomMargin = margin; info.leftMargin = margin; info.rightMargin = margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        // Documents without explicit colours would otherwise print in the UI's text colour (white in Dark Mode).
        let text = NSMutableAttributedString(attributedString: source)
        text.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if value == nil { text.addAttribute(.foregroundColor, value: NSColor.black, range: range) }
        }

        let width = paper.width - 2 * margin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        view.appearance = NSAppearance(named: .aqua)
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        view.textStorage?.setAttributedString(text)
        if let lm = view.layoutManager, let tc = view.textContainer {
            lm.ensureLayout(for: tc)
            view.setFrameSize(NSSize(width: width, height: max(10, lm.usedRect(for: tc).height + 4)))
        }
        let op = NSPrintOperation(view: view, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        guard op.run(), exists(url) else { throw Failure.convertFailed(name, "the PDF couldn’t be written.") }
    }

    // MARK: Merge & images

    static func merge(_ urls: [URL]) throws -> Output {
        guard urls.count >= 2 else { throw Failure.needsMore("Add at least two files to merge.") }
        let doc = PDFDocument()
        for url in urls { try append(url, to: doc) }
        let dest = out(urls[0], "merged")
        try write(doc, to: dest)
        return Output(urls: [dest], message: "Merged \(urls.count) files · \(pages(doc.pageCount))")
    }

    static func imagesToPDF(_ urls: [URL]) throws -> Output {
        let doc = PDFDocument()
        for url in urls { try append(url, to: doc) }
        let dest = out(urls[0], "images")
        try write(doc, to: dest)
        return Output(urls: [dest], message: "Made a \(pages(doc.pageCount)) PDF")
    }

    private static func append(_ url: URL, to doc: PDFDocument) throws {
        if url.pathExtension.lowercased() == "pdf" {
            let src = try open(url)
            for i in 0..<src.pageCount {
                if let page = src.page(at: i)?.copy() as? PDFPage { doc.insert(page, at: doc.pageCount) }
            }
        } else {
            guard let image = NSImage(contentsOf: url), let page = imagePage(image) else {
                throw Failure.unreadable(url.lastPathComponent)
            }
            doc.insert(page, at: doc.pageCount)
        }
    }

    /// One image on an A4-sized page (portrait or landscape to match), scaled to fit.
    static func imagePage(_ image: NSImage) -> PDFPage? {
        let landscape = image.size.width > image.size.height
        let box = landscape ? CGRect(x: 0, y: 0, width: 842, height: 595) : CGRect(x: 0, y: 0, width: 595, height: 842)
        return PDFPage(image: image, options: [.mediaBox: box, .upscaleIfSmaller: false])
    }

    // MARK: Pages

    static func split(_ url: URL, ranges: String, eachPage: Bool) throws -> Output {
        let src = try open(url)
        let indexes = try PageRanges.parse(ranges, pageCount: src.pageCount)
        func doc(_ idx: [Int]) -> PDFDocument {
            let d = PDFDocument()
            for i in idx { if let p = src.page(at: i)?.copy() as? PDFPage { d.insert(p, at: d.pageCount) } }
            return d
        }
        if eachPage {
            var outs: [URL] = []
            for i in indexes {
                let dest = out(url, "page \(i + 1)")
                try write(doc([i]), to: dest)
                outs.append(dest)
            }
            return Output(urls: outs, message: "Saved \(pages(outs.count)) as separate PDFs")
        }
        let dest = out(url, "pages \(ranges.replacingOccurrences(of: " ", with: ""))")
        try write(doc(indexes), to: dest)
        return Output(urls: [dest], message: "Extracted \(pages(indexes.count))")
    }

    static func rotate(_ urls: [URL], degrees: Int, ranges: String) throws -> Output {
        var outs: [URL] = []
        for url in urls {
            let doc = try open(url)
            let trimmed = ranges.trimmingCharacters(in: .whitespaces)
            let which = trimmed.isEmpty ? Array(0..<doc.pageCount) : try PageRanges.parse(trimmed, pageCount: doc.pageCount)
            for i in which {
                guard let p = doc.page(at: i) else { continue }
                p.rotation = ((p.rotation + degrees) % 360 + 360) % 360
            }
            let dest = out(url, "rotated")
            try write(doc, to: dest)
            outs.append(dest)
        }
        return Output(urls: outs, message: outs.count == 1 ? "Rotated and saved \(outs[0].lastPathComponent)" : "Rotated \(outs.count) PDFs")
    }

    // MARK: Size & security

    static func compress(_ urls: [URL]) throws -> Output {
        var outs: [URL] = []
        var before: Int64 = 0, after: Int64 = 0
        for url in urls {
            let doc = try open(url)
            let dest = out(url, "compressed")
            // Two approaches; keep whichever is smaller: PDFKit's JPEG re-encoding, and
            // macOS's own "Reduce File Size" Quartz filter (the one Preview uses).
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("DeskPet-\(UUID().uuidString).pdf")
            defer { try? FileManager.default.removeItem(at: tmp) }
            try write(doc, to: dest, options: [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true])
            if let filter = QuartzFilter(url: URL(fileURLWithPath: "/System/Library/Filters/Reduce File Size.qfilter")),
               doc.write(to: tmp, withOptions: [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter]),
               fileSize(tmp) > 0, fileSize(tmp) < fileSize(dest) {
                _ = try? FileManager.default.replaceItemAt(dest, withItemAt: tmp)
            }
            let a = fileSize(url), b = fileSize(dest)
            if b >= a * 98 / 100 {
                try? FileManager.default.removeItem(at: dest) // nothing worth gaining; keep the original only
                continue
            }
            before += a; after += b
            outs.append(dest)
        }
        guard !outs.isEmpty else {
            throw Failure.needsMore(urls.count == 1 ? "This PDF is already as small as it gets — compressing wouldn’t help."
                                                    : "These PDFs are already as small as they get.")
        }
        let saved = before > 0 ? Int((1 - Double(after) / Double(before)) * 100) : 0
        return Output(urls: outs, message: "\(PDFFiles.size(before)) → \(PDFFiles.size(after)) (\(saved)% smaller)")
    }

    static func protect(_ urls: [URL], password: String) throws -> Output {
        guard !password.isEmpty else { throw Failure.needsMore("Type a password first.") }
        var outs: [URL] = []
        for url in urls {
            let doc = try open(url)
            let dest = out(url, "locked")
            try write(doc, to: dest, options: [.userPasswordOption: password, .ownerPasswordOption: password])
            outs.append(dest)
        }
        return Output(urls: outs, message: outs.count == 1 ? "Locked copy saved — it needs the password to open" : "Saved \(outs.count) locked copies")
    }

    static func unlock(_ urls: [URL], password: String) throws -> Output {
        var outs: [URL] = []
        for url in urls {
            let src = try open(url, allowLocked: true)
            if src.isEncrypted || src.isLocked {
                guard src.unlock(withPassword: password) else { throw Failure.wrongPassword(url.lastPathComponent) }
            }
            // Copy pages into a fresh document so no encryption carries over.
            let doc = PDFDocument()
            for i in 0..<src.pageCount { if let p = src.page(at: i)?.copy() as? PDFPage { doc.insert(p, at: doc.pageCount) } }
            let dest = out(url, "unlocked")
            try write(doc, to: dest)
            outs.append(dest)
        }
        return Output(urls: outs, message: outs.count == 1 ? "Unlocked copy saved" : "Saved \(outs.count) unlocked copies")
    }

    // MARK: Export

    static func toImages(_ urls: [URL], scale: CGFloat = 2) throws -> Output {
        var folders: [URL] = []
        var total = 0
        for url in urls {
            let doc = try open(url)
            let folder = PDFFiles.output(for: url, suffix: "pages", ext: "", exists: exists)
            let dir = URL(fileURLWithPath: folder.path.hasSuffix(".") ? String(folder.path.dropLast()) : folder.path, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let digits = String(doc.pageCount).count
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let rotated = page.rotation % 180 != 0
                let size = NSSize(width: (rotated ? bounds.height : bounds.width) * scale,
                                  height: (rotated ? bounds.width : bounds.height) * scale)
                let img = page.thumbnail(of: size, for: .mediaBox)
                guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { continue }
                let name = "Page " + String(repeating: "0", count: digits - String(i + 1).count) + "\(i + 1).png"
                do { try png.write(to: dir.appendingPathComponent(name)) } catch { throw Failure.writeFailed(name) }
                total += 1
            }
            folders.append(dir)
        }
        return Output(urls: folders, message: "Saved \(total) page image\(total == 1 ? "" : "s")")
    }

    static func toText(_ urls: [URL]) throws -> Output {
        var outs: [URL] = []
        var all: [String] = []
        for url in urls {
            let doc = try open(url)
            let text = (doc.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw Failure.needsMore("“\(url.lastPathComponent)” has no selectable text (it may be scanned). Open it and use Copy Text from Screen instead.")
            }
            let dest = out(url, nil, "txt")
            do { try text.write(to: dest, atomically: true, encoding: .utf8) } catch { throw Failure.writeFailed(dest.lastPathComponent) }
            outs.append(dest)
            all.append(text)
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(all.joined(separator: "\n\n"), forType: .string)
        return Output(urls: outs, message: "Text saved and copied to the clipboard")
    }

    static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
    }

    static func pageCount(_ url: URL) -> Int? {
        guard url.pathExtension.lowercased() == "pdf", let doc = PDFDocument(url: url) else { return nil }
        return doc.isLocked ? nil : doc.pageCount
    }
}
