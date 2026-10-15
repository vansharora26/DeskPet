import Foundation

/// Everything about the pet that survives a relaunch.
public struct PetSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var name: String
    public var stats: PetStats
    public var isSleeping: Bool
    public var lastUpdated: Date
    public var birthday: Date

    public init(
        name: String = "Biscuit",
        stats: PetStats = .fresh,
        isSleeping: Bool = false,
        lastUpdated: Date = Date(),
        birthday: Date = Date()
    ) {
        self.version = Self.currentVersion
        self.name = name
        self.stats = stats
        self.isSleeping = isSleeping
        self.lastUpdated = lastUpdated
        self.birthday = birthday
    }
}

public enum PetStoreError: Error, LocalizedError {
    case directoryUnavailable(Error)
    case writeFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .directoryUnavailable(let e): return "Could not access the DeskPet data folder: \(e.localizedDescription)"
        case .writeFailed(let e): return "Could not save your pet: \(e.localizedDescription)"
        }
    }
}

/// Saves the pet as JSON in Application Support. Writes are atomic so a crash
/// mid-save never leaves a half-written file.
public final class PetStore: @unchecked Sendable {
    public let fileURL: URL
    private let queue = DispatchQueue(label: "DeskPet.PetStore")

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("DeskPet", isDirectory: true)
        self.fileURL = dir.appendingPathComponent("pet.json")
    }

    public enum LoadResult: Sendable {
        case loaded(PetSnapshot)
        case none
        /// The file existed but was unreadable; it was moved aside so it isn't lost.
        case recovered(backupURL: URL?)
    }

    public func load() -> LoadResult {
        queue.sync {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return .none }
            do {
                let data = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                var snapshot = try decoder.decode(PetSnapshot.self, from: data)
                // Guard against clock weirdness (future timestamps).
                if snapshot.lastUpdated > Date() { snapshot.lastUpdated = Date() }
                return .loaded(snapshot)
            } catch {
                let backup = fileURL.deletingLastPathComponent()
                    .appendingPathComponent("pet-corrupt-\(Int(Date().timeIntervalSince1970)).json")
                let moved = (try? FileManager.default.moveItem(at: fileURL, to: backup)) != nil
                return .recovered(backupURL: moved ? backup : nil)
            }
        }
    }

    public func save(_ snapshot: PetSnapshot) throws {
        try queue.sync {
            let dir = fileURL.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                throw PetStoreError.directoryUnavailable(error)
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                let data = try encoder.encode(snapshot)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                throw PetStoreError.writeFailed(error)
            }
        }
    }

    public func delete() {
        queue.sync { try? FileManager.default.removeItem(at: fileURL) }
    }
}
