import Foundation

/// What Flix Files learned on this Mac: which kinds of file go to which app, and which folders
/// get opened at which time of day. Plain counts, persisted in `memory.json`; Settings' **Forget**
/// empties it.
///
/// Pure value type: the provider (`FlixDragMemoryProvider`) owns it, saves it, and turns it into
/// localized text.
nonisolated struct FlixDragMemory: Codable, Equatable, Sendable {
    /// A part of the day, as a bit in ``opens``.
    nonisolated enum DayPart: Int, CaseIterable, Sendable {
        case morning = 1, afternoon = 2, evening = 4

        init?(hour: Int) {
            switch hour {
            case 5..<12: self = .morning
            case 12..<18: self = .afternoon
            case 18..<24: self = .evening
            default: return nil
            }
        }
    }

    /// Drops by file kind (``kindClass(of:)``), then by destination app (bundle identifier).
    var drops: [String: [String: Int]] = [:]
    /// Destination names as macOS supplied them, for the notice.
    var destinationNames: [String: String] = [:]
    /// Patterns already announced, as `kind>destination`.
    var noticed: Set<String> = []
    /// Opens by working folder, then by day (`yyyy-MM-dd`), as a mask of ``DayPart`` bits.
    var opens: [String: [String: Int]] = [:]
    /// The last open date counted per item, so one open is counted once.
    var countedOpens: [String: Date] = [:]
    /// Filter tips already offered; each is offered once.
    var offeredTips: Set<String> = []

    /// Drops of one kind to one app before Flix Files says it noticed.
    static let noticeAfter = 3
    /// A folder opened in one part of the day on this many different days earns a tip.
    static let tipAfterDays = 3
    static let tipWindowDays = 14

    init() {}

    // MARK: Drops

    /// The kind of file drag memory counts by: "pdf", "image", "spreadsheet", and so on.
    static func kindClass(of item: FlixItem) -> String {
        let ext = item.fileExtension.lowercased()
        switch item.kind {
        case .image, .screenshot: return "image"
        case .folder: return "folder"
        case .app: return "app"
        case .link: return "link"
        case .document, .other:
            if ext == "pdf" { return "pdf" }
            if ["xlsx", "xls", "numbers", "csv", "ods"].contains(ext) { return "spreadsheet" }
            if ["key", "pptx", "ppt", "odp"].contains(ext) { return "presentation" }
            if ["zip", "dmg", "gz", "tar", "7z", "rar"].contains(ext) { return "archive" }
            return item.kind == .document ? "document" : "file"
        }
    }

    func count(kind: String, destination: String) -> Int { drops[kind]?[destination] ?? 0 }

    /// Counts a drop of `items` on `destination`. Returns the kinds noticed for the first time.
    mutating func recordDrop(of items: [FlixItem], destination: String, name: String?) -> [String] {
        if let name { destinationNames[destination] = name }
        var newlyNoticed: [String] = []
        for kind in Set(items.map(Self.kindClass)) {
            let count = (drops[kind]?[destination] ?? 0) + 1
            drops[kind, default: [:]][destination] = count
            let key = kind + ">" + destination
            if count >= Self.noticeAfter, noticed.insert(key).inserted { newlyNoticed.append(kind) }
        }
        return newlyNoticed.sorted()
    }

    /// The kind most often dropped on `destination`, if any.
    func usualKind(for destination: String) -> String? {
        var best: (kind: String, count: Int)?
        for (kind, destinations) in drops {
            guard let count = destinations[destination] else { continue }
            if let current = best, current.count > count || (current.count == count && current.kind < kind) { continue }
            best = (kind, count)
        }
        return best?.kind
    }

    // MARK: Opens

    /// Counts items opened since they were last counted, by working folder and part of the day.
    mutating func observeOpens(_ items: [FlixItem], calendar: Calendar = .current) -> Bool {
        var changed = false
        for item in items where item.activity == .opened && item.kind != .app {
            guard let path = item.path, countedOpens[item.id.uuidString].map({ $0 < item.date }) ?? true,
                  let part = DayPart(hour: calendar.component(.hour, from: item.date)) else { continue }
            countedOpens[item.id.uuidString] = item.date
            let folder = item.kind == .folder ? path : (path as NSString).deletingLastPathComponent
            let day = Self.dayKey(item.date, calendar: calendar)
            opens[folder, default: [:]][day, default: 0] |= part.rawValue
            changed = true
        }
        return changed
    }

    /// The folder opened in the same part of the day on the most days of the last two weeks, with
    /// that part, when it reaches ``tipAfterDays`` and no tip for it was offered.
    func tipCandidate(now: Date, calendar: Calendar = .current, excluding: Set<String>) -> (folder: String, part: DayPart)? {
        let oldest = Self.dayKey(calendar.date(byAdding: .day, value: -Self.tipWindowDays, to: now) ?? now, calendar: calendar)
        var best: (String, DayPart, Int)?
        for (folder, days) in opens where !excluding.contains(folder) {
            for part in DayPart.allCases where !offeredTips.contains(Self.tipID(folder: folder, part: part)) {
                let count = days.filter { $0.key >= oldest && $0.value & part.rawValue != 0 }.count
                if count >= Self.tipAfterDays, count > best?.2 ?? 0 { best = (folder, part, count) }
            }
        }
        return best.map { (folder: $0.0, part: $0.1) }
    }

    static func tipID(folder: String, part: DayPart) -> String { "tip:\(part.rawValue):" + folder }

    /// Drops open counts older than the tip window and counted opens of items no longer listed.
    mutating func prune(now: Date, keeping ids: Set<String>, calendar: Calendar = .current) {
        let oldest = Self.dayKey(calendar.date(byAdding: .day, value: -Self.tipWindowDays - 1, to: now) ?? now, calendar: calendar)
        opens = opens.compactMapValues { days in
            let kept = days.filter { $0.key >= oldest }
            return kept.isEmpty ? nil : kept
        }
        countedOpens = countedOpens.filter { ids.contains($0.key) }
    }

    /// Sortable as text: `2026-11-03`.
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
