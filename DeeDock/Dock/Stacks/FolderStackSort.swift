import Foundation

/// Fixed sort directions for folder contents, with stable name and path tie breakers.
///
/// Size uses file metadata and finished folder contents totals. Folders still being
/// measured sort last, then by name, so rows do not jump while a walk runs.
nonisolated enum FolderStackSort: String, CaseIterable {
    case recency, alphabetical, size

    var title: LocalizedStringResource {
        switch self {
        case .recency: .folderSortRecency
        case .alphabetical: .folderSortAlphabetical
        case .size: .folderSortSize
        }
    }

    func precedes(_ lhs: FolderStackEntryReference, _ rhs: FolderStackEntryReference) -> Bool {
        switch self {
        case .recency:
            let left = lhs.modifiedAt ?? lhs.createdAt ?? .distantPast
            let right = rhs.modifiedAt ?? rhs.createdAt ?? .distantPast
            if left != right { return left > right }
        case .size:
            let left = lhs.sizeSortByteCount
            let right = rhs.sizeSortByteCount
            if left != right { return left > right }
        case .alphabetical: break
        }
        let comparison = lhs.name.localizedStandardCompare(rhs.name)
        return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
    }
}
