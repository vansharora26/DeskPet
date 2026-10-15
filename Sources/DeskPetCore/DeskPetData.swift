import Foundation

/// Bookkeeping for the optional daily briefing / end-of-day summary.
public struct BriefingSettings: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        case off, onOpen, atTime
        public var title: String {
            switch self {
            case .off: return "Off"
            case .onOpen: return "When DeskPet opens"
            case .atTime: return "At a set time"
            }
        }
    }

    public var mode: Mode = .atTime
    public var briefingMinute = 9 * 60
    public var endOfDayEnabled = true
    public var endOfDayMinute = 18 * 60
    public var lastBriefingDay: String?
    public var lastEndOfDayDay: String?

    public init() {}
}

extension BriefingSettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        mode = c.value(.mode, default: .atTime)
        briefingMinute = QuietHours.clampMinute(c.value(.briefingMinute, default: 9 * 60))
        endOfDayEnabled = c.value(.endOfDayEnabled, default: true)
        endOfDayMinute = QuietHours.clampMinute(c.value(.endOfDayMinute, default: 18 * 60))
        lastBriefingDay = c.value(.lastBriefingDay, default: nil)
        lastEndOfDayDay = c.value(.lastEndOfDayDay, default: nil)
    }
}

/// Everything DeskPet 2.0 tracks, saved as one local JSON document.
/// (The pet's needs live separately in pet.json, unchanged from 1.0.)
public struct DeskPetData: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version = DeskPetData.currentVersion
    public var hydration = HydrationData()
    public var focus = FocusData()
    public var items = ItemStore()
    public var progression = Progression()
    public var movementReminder = ReminderState()
    /// Times the user marked a movement/stretch reminder as done.
    public var movementBreaks: [Date] = []
    public var briefing = BriefingSettings()

    public init() {}
}

extension DeskPetData {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        version = c.value(.version, default: DeskPetData.currentVersion)
        hydration = c.value(.hydration, default: HydrationData())
        focus = c.value(.focus, default: FocusData())
        items = c.value(.items, default: ItemStore())
        progression = c.value(.progression, default: Progression())
        movementReminder = c.value(.movementReminder, default: ReminderState())
        movementBreaks = c.value(.movementBreaks, default: [])
        briefing = c.value(.briefing, default: BriefingSettings())
    }
}

/// Generic atomic JSON file store with corrupt-file recovery.
public final class JSONDocumentStore<Document: Codable>: @unchecked Sendable {
    public let fileURL: URL
    private let queue = DispatchQueue(label: "DeskPet.JSONDocumentStore")

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeskPet", isDirectory: true)
    }

    public enum LoadResult {
        case loaded(Document)
        case none
        case recovered(backupURL: URL?)
    }

    public func load() -> LoadResult {
        queue.sync {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return .none }
            do {
                let data = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return .loaded(try decoder.decode(Document.self, from: data))
            } catch {
                let backup = fileURL.deletingPathExtension()
                    .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
                let moved = (try? FileManager.default.moveItem(at: fileURL, to: backup)) != nil
                return .recovered(backupURL: moved ? backup : nil)
            }
        }
    }

    public func save(_ document: Document) throws {
        let data = try Self.encode(document)
        try queue.sync {
            do {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                throw PetStoreError.writeFailed(error)
            }
        }
    }

    public func delete() {
        queue.sync { try? FileManager.default.removeItem(at: fileURL) }
    }

    public static func encode(_ document: Document) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }
}
