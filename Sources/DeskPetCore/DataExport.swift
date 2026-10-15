import Foundation

/// Builds the user's data export: one complete JSON file plus CSVs that open
/// in any spreadsheet app.
public enum DataExport {
    public struct Bundle: Codable {
        public var exportedAt: Date
        public var app: String
        public var data: DeskPetData
        public var pet: PetSnapshot?
    }

    public static func json(data: DeskPetData, pet: PetSnapshot?, now: Date) throws -> Data {
        try JSONDocumentStore<Bundle>.encode(Bundle(exportedAt: now, app: "DeskPet", data: data, pet: pet))
    }

    public static func waterCSV(_ data: DeskPetData) -> String {
        csv(["date", "ml"], data.hydration.entries.map { [iso($0.date), String($0.ml)] })
    }

    public static func focusCSV(_ data: DeskPetData) -> String {
        csv(["phase", "start", "end", "planned_minutes", "active_minutes", "completed", "label"],
            data.focus.records.map {
                [$0.phase.rawValue, iso($0.start), iso($0.end), minutes($0.plannedSeconds),
                 minutes($0.activeSeconds), $0.completed ? "yes" : "no", $0.label ?? ""]
            })
    }

    public static func itemsCSV(_ data: DeskPetData) -> String {
        csv(["kind", "text", "pinned", "created", "due", "remind_at", "completed", "deleted"],
            data.items.items.map {
                [$0.kind.rawValue, $0.text, $0.isPinned ? "yes" : "no", iso($0.createdAt),
                 $0.due.map(iso) ?? "", $0.remindAt.map(iso) ?? "", $0.completedAt.map(iso) ?? "",
                 $0.deletedAt.map(iso) ?? ""]
            })
    }

    /// RFC 4180: quote fields containing commas, quotes or newlines; double inner quotes.
    public static func csv(_ header: [String], _ rows: [[String]]) -> String {
        func field(_ s: String) -> String {
            // Neutralise spreadsheet formula injection.
            var v = s
            if let f = v.first, "=+-@".contains(f) { v = "'" + v }
            if v.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
                return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return v
        }
        return ([header] + rows).map { $0.map(field).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    static func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }
    static func minutes(_ s: TimeInterval) -> String { String(format: "%.1f", s / 60) }
}
