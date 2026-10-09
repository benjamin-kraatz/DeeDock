import Foundation

/// Display formatting for Files dates and sizes.
nonisolated enum HubFilesFormatting {
    /// "Today, 10:24", "Yesterday, 14:32", or a localized medium date for anything older.
    /// - Parameters:
    ///   - now: The reference date; injected by previews and tests for stable output.
    ///   - calendar: Determines day boundaries.
    static func date(_ date: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let date else { return "—" }
        let time = date.formatted(date: .omitted, time: .shortened)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? Int.max
        switch days {
        case 0: return String(localized: .hubFilesDateToday(time))
        case 1: return String(localized: .hubFilesDateYesterday(time))
        default: return date.formatted(date: .abbreviated, time: .omitted)
        }
    }

    /// A Finder-style size ("1.8 MB"), or an em dash when unknown (folders).
    static func size(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// "N items", the count shown for folders and selections.
    static func itemCount(_ count: Int) -> String {
        String(localized: .hubFilesItemCount(count))
    }
}
