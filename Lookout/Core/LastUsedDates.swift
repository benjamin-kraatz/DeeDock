import CoreServices
import Foundation

/// When files were last opened, from Spotlight (`kMDItemLastUsedDate`), so the first pass can index what people use
/// first.
///
/// One scoped query per folder, not one `MDItemCreateWithURL` per file: on an M4 (2026-10-12) the per-file lookup
/// cost 330–880 µs a file (a 20,000-file folder: 7–17 s, on every sync), while a query for the files that have a
/// last-used date cost 20–170 ms a folder whatever its size, because only files someone opened have one (46 of 978
/// in the measured folder). Synchronous queries work off the main thread (measured on a utility queue).
///
/// Folders Spotlight doesn't index (an excluded folder, a volume without an index, `/tmp`) just have no dates, and
/// their files are ordered by modification date.
nonisolated enum LastUsedDates {
    /// Paths → seconds since 1970, for the files under `folders` that have a last-used date. Paths are as Spotlight
    /// records them (real paths).
    static func query(_ folders: [String]) -> [String: Double] {
        guard !folders.isEmpty,
              let query = MDQueryCreate(kCFAllocatorDefault, "kMDItemLastUsedDate = *" as CFString, nil, nil)
        else { return [:] }
        MDQuerySetSearchScope(query, folders as CFArray, 0)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [:] }
        var dates: [String: Double] = [:]
        for index in 0..<MDQueryGetResultCount(query) {
            autoreleasepool {
                guard let raw = MDQueryGetResultAtIndex(query, index) else { return }
                let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
                guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String,
                      let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date else { return }
                dates[path] = date.timeIntervalSince1970
            }
        }
        return dates
    }
}
