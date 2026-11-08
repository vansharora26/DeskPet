import Foundation

/// The PDF tools DeskPet offers. Pure metadata; the work happens in the app layer (PDFKit).
public enum PDFTool: String, CaseIterable, Identifiable, Codable, Sendable {
    case toPDF, merge, images, split, compress, rotate, protect, unlock, toImages, toText
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .toPDF: return "Word to PDF"
        case .merge: return "Merge PDFs"
        case .images: return "Images to PDF"
        case .split: return "Split / Extract"
        case .compress: return "Compress"
        case .rotate: return "Rotate"
        case .protect: return "Add Password"
        case .unlock: return "Remove Password"
        case .toImages: return "PDF to Images"
        case .toText: return "PDF to Text"
        }
    }

    public var subtitle: String {
        switch self {
        case .toPDF: return "Word, RTF, OpenDocument, HTML or text files become PDFs."
        case .merge: return "Combine PDFs (and images) into one file, in the order you choose."
        case .images: return "Turn photos and screenshots into a single PDF, one page each."
        case .split: return "Pull out some pages, or save every page as its own PDF."
        case .compress: return "Shrink PDFs by re-compressing their images."
        case .rotate: return "Turn every page, or just some, the right way up."
        case .protect: return "Lock a PDF so it needs a password to open."
        case .unlock: return "Save an unlocked copy of a PDF you know the password for."
        case .toImages: return "Save each page as a PNG image."
        case .toText: return "Pull out all the text, saved as a .txt file and copied."
        }
    }

    public var symbol: String {
        switch self {
        case .toPDF: return "doc.richtext"
        case .merge: return "square.stack.3d.down.right"
        case .images: return "photo.on.rectangle"
        case .split: return "scissors"
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .rotate: return "rotate.right"
        case .protect: return "lock.doc"
        case .unlock: return "lock.open"
        case .toImages: return "photo.stack"
        case .toText: return "text.alignleft"
        }
    }

    /// File extensions the tool accepts (lowercase).
    public var acceptedExtensions: Set<String> {
        switch self {
        case .toPDF: return PDFFiles.documentExtensions
        case .merge: return PDFFiles.imageExtensions.union(["pdf"])
        case .images: return PDFFiles.imageExtensions
        default: return ["pdf"]
        }
    }

    /// Whether the tool needs at least two inputs, works per file, or takes exactly one.
    public var minimumFiles: Int { self == .merge ? 2 : 1 }

    /// Best tool for files dropped on the cat.
    public static func suggested(for urls: [URL]) -> PDFTool {
        let exts = urls.map { $0.pathExtension.lowercased() }
        guard !exts.isEmpty else { return .merge }
        if exts.allSatisfy({ PDFFiles.documentExtensions.contains($0) }) { return .toPDF }
        if exts.allSatisfy({ PDFFiles.imageExtensions.contains($0) }) { return .images }
        if exts.allSatisfy({ $0 == "pdf" }) { return exts.count >= 2 ? .merge : .compress }
        return .merge
    }
}

public enum PDFFiles {
    public static let documentExtensions: Set<String> = ["docx", "doc", "rtf", "rtfd", "odt", "txt", "text", "md", "html", "htm", "webarchive"]
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"]

    /// "Report.docx" + "merged" → "Report (merged).pdf" beside it, numbered if taken.
    public static func output(for input: URL, suffix: String?, ext: String = "pdf", exists: (URL) -> Bool) -> URL {
        let folder = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        let stem = suffix.map { "\(base) (\($0))" } ?? base
        var url = folder.appendingPathComponent(stem).appendingPathExtension(ext)
        var n = 2
        while exists(url) {
            url = folder.appendingPathComponent("\(stem) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return url
    }

    /// Human-readable file size.
    public static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Page selections like "1-3, 5, 8-" (1-based, inclusive; open ends allowed).
public enum PageRanges {
    public enum ParseError: Error, Equatable, LocalizedError {
        case empty, invalid(String), outOfRange(Int, pageCount: Int)
        public var errorDescription: String? {
            switch self {
            case .empty: return "Type the pages you want, like 1-3, 5."
            case .invalid(let part): return "“\(part)” isn’t a page or range. Use numbers like 2, 4-6 or 8-."
            case .outOfRange(let p, let count): return "Page \(p) doesn’t exist — this PDF has \(count) page\(count == 1 ? "" : "s")."
            }
        }
    }

    /// Returns 0-based page indexes in the order written, without duplicates.
    public static func parse(_ text: String, pageCount: Int) throws -> [Int] {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { throw ParseError.empty }
        var out: [Int] = []
        var seen = Set<Int>()
        func add(_ p: Int) throws {
            guard p >= 1, p <= pageCount else { throw ParseError.outOfRange(p, pageCount: pageCount) }
            if seen.insert(p - 1).inserted { out.append(p - 1) }
        }
        for part in parts {
            let cleaned = part.replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: " ", with: "")
            if !cleaned.hasPrefix("-"), let p = Int(cleaned) { try add(p); continue }
            let ends = cleaned.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            guard ends.count == 2 else { throw ParseError.invalid(part) }
            let lo = ends[0].isEmpty ? 1 : Int(ends[0])
            let hi = ends[1].isEmpty ? pageCount : Int(ends[1])
            guard let lo, let hi, !(ends[0].isEmpty && ends[1].isEmpty) else { throw ParseError.invalid(part) }
            let range = lo <= hi ? Array(lo...hi) : Array((hi...lo).reversed())
            for p in range { try add(p) }
        }
        return out
    }
}
