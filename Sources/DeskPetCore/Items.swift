import Foundation

/// A captured note or task. Notes and tasks share one type so a note can be
/// turned into a task (and back) without copying data around.
public struct Item: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case note, task }

    public var id: UUID
    public var text: String
    public var kind: Kind
    public var isPinned: Bool
    public var createdAt: Date
    public var updatedAt: Date
    /// Deadline. When `dueHasTime` is false only the day matters.
    public var due: Date?
    public var dueHasTime: Bool
    /// A one-off reminder for this item.
    public var remindAt: Date?
    public var reminderFired: Bool
    public var completedAt: Date?
    /// Soft delete: recoverable from "Recently Deleted" for 30 days.
    public var deletedAt: Date?

    public init(id: UUID = UUID(), text: String, kind: Kind, isPinned: Bool = false, createdAt: Date,
                due: Date? = nil, dueHasTime: Bool = false, remindAt: Date? = nil) {
        self.id = id
        self.text = text
        self.kind = kind
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.due = due
        self.dueHasTime = dueHasTime
        self.remindAt = remindAt
        self.reminderFired = false
        self.completedAt = nil
        self.deletedAt = nil
    }

    /// First line, used as a title in lists.
    public var title: String {
        let first = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return first.trimmingCharacters(in: .whitespaces)
    }

    public var isTask: Bool { kind == .task }
    public var isCompleted: Bool { completedAt != nil }
    public var isDeleted: Bool { deletedAt != nil }
}

extension Item {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let created: Date = c.value(.createdAt, default: Date())
        self.init(
            id: c.value(.id, default: UUID()),
            text: c.value(.text, default: ""),
            kind: c.value(.kind, default: .note),
            isPinned: c.value(.isPinned, default: false),
            createdAt: created,
            due: c.value(.due, default: nil),
            dueHasTime: c.value(.dueHasTime, default: false),
            remindAt: c.value(.remindAt, default: nil)
        )
        updatedAt = c.value(.updatedAt, default: created)
        reminderFired = c.value(.reminderFired, default: false)
        completedAt = c.value(.completedAt, default: nil)
        deletedAt = c.value(.deletedAt, default: nil)
    }
}

public enum TaskFilter: String, CaseIterable, Codable, Sendable {
    case inbox, today, upcoming, completed
    public var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .completed: return "Completed"
        }
    }
}

public enum ItemError: Error, Equatable, LocalizedError {
    case emptyText
    case tooLong
    case notFound

    public var errorDescription: String? {
        switch self {
        case .emptyText: return "There's nothing to save yet."
        case .tooLong: return "That's too long (max 10,000 characters)."
        case .notFound: return "That item doesn't exist anymore."
        }
    }
}

/// Operations and queries over the item list.
public struct ItemStore: Codable, Equatable, Sendable {
    public var items: [Item] = []
    public static let maxLength = 10_000
    public static let trashRetention: TimeInterval = 30 * 86_400

    public init(items: [Item] = []) { self.items = items }

    // MARK: Mutations

    @discardableResult
    public mutating func add(_ text: String, kind: Item.Kind, due: Date? = nil, dueHasTime: Bool = false,
                             remindAt: Date? = nil, pinned: Bool = false, now: Date) throws -> Item {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw ItemError.emptyText }
        guard clean.count <= Self.maxLength else { throw ItemError.tooLong }
        let item = Item(text: clean, kind: kind, isPinned: pinned, createdAt: now,
                        due: due, dueHasTime: dueHasTime, remindAt: remindAt)
        items.append(item)
        return item
    }

    public func item(_ id: UUID) -> Item? { items.first { $0.id == id } }

    /// Applies `change` to the item and bumps `updatedAt`.
    @discardableResult
    public mutating func update(_ id: UUID, now: Date, _ change: (inout Item) -> Void) throws -> Item {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { throw ItemError.notFound }
        var item = items[idx]
        change(&item)
        item.text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.text.isEmpty else { throw ItemError.emptyText }
        guard item.text.count <= Self.maxLength else { throw ItemError.tooLong }
        if item.remindAt != items[idx].remindAt { item.reminderFired = false }
        item.updatedAt = now
        items[idx] = item
        return item
    }

    public mutating func setCompleted(_ id: UUID, _ done: Bool, now: Date) throws {
        try update(id, now: now) { item in
            item.kind = .task
            item.completedAt = done ? now : nil
        }
    }

    public mutating func softDelete(_ id: UUID, now: Date) throws {
        try update(id, now: now) { $0.deletedAt = now }
    }

    public mutating func restore(_ id: UUID, now: Date) throws {
        try update(id, now: now) { $0.deletedAt = nil }
    }

    /// Permanently removes items deleted more than 30 days ago.
    public mutating func purgeTrash(now: Date) {
        items.removeAll { ($0.deletedAt.map { now.timeIntervalSince($0) > Self.trashRetention }) ?? false }
    }

    public mutating func emptyTrash() {
        items.removeAll(where: \.isDeleted)
    }

    // MARK: Queries

    public var live: [Item] { items.filter { !$0.isDeleted } }
    public var trash: [Item] { items.filter(\.isDeleted).sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) } }

    public func tasks(_ filter: TaskFilter, now: Date, calendar: Calendar) -> [Item] {
        let endOfToday = calendar.startOfNextDay(after: now)
        let tasks = live.filter(\.isTask)
        switch filter {
        case .inbox:
            return tasks.filter { !$0.isCompleted && $0.due == nil }.sorted(by: Self.pinnedThenNewest)
        case .today:
            // Includes overdue tasks so nothing silently disappears.
            return tasks.filter { !$0.isCompleted && ($0.due.map { $0 < endOfToday } ?? false) }
                .sorted { ($0.due ?? .distantPast) < ($1.due ?? .distantPast) }
        case .upcoming:
            return tasks.filter { !$0.isCompleted && ($0.due.map { $0 >= endOfToday } ?? false) }
                .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        case .completed:
            return tasks.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        }
    }

    public func openTasks() -> [Item] { live.filter { $0.isTask && !$0.isCompleted } }

    public func overdue(now: Date, calendar: Calendar) -> [Item] {
        let startOfToday = calendar.startOfDay(for: now)
        return openTasks().filter { task in
            guard let due = task.due else { return false }
            return task.dueHasTime ? due < now : due < startOfToday
        }
    }

    public func notes() -> [Item] {
        live.filter { $0.kind == .note }.sorted(by: Self.pinnedThenNewest)
    }

    /// Case- and diacritic-insensitive search across live notes and tasks.
    public func search(_ query: String) -> [Item] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return live.sorted(by: Self.pinnedThenNewest) }
        let terms = q.split(separator: " ").map(String.init)
        return live.filter { item in
            terms.allSatisfy { item.text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }.sorted(by: Self.pinnedThenNewest)
    }

    /// Open tasks whose text matches; used to resolve "complete X".
    public func matchOpenTasks(_ query: String) -> [Item] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let open = openTasks()
        if let exact = open.filter({ $0.title.compare(q, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }).first {
            return [exact]
        }
        return open.filter { $0.text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// Reminders that are due and haven't fired yet.
    public func dueReminders(now: Date) -> [Item] {
        live.filter { !$0.isCompleted && !$0.reminderFired && ($0.remindAt.map { $0 <= now } ?? false) }
    }

    public func nextReminderDate() -> Date? {
        live.filter { !$0.isCompleted && !$0.reminderFired }.compactMap(\.remindAt).min()
    }

    public func completedCount(on day: Date, calendar: Calendar) -> Int {
        live.filter { $0.completedAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false }.count
    }

    static func pinnedThenNewest(_ a: Item, _ b: Item) -> Bool {
        if a.isPinned != b.isPinned { return a.isPinned }
        return a.updatedAt > b.updatedAt
    }
}

extension ItemStore {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(items: c.value(.items, default: []))
    }
}
