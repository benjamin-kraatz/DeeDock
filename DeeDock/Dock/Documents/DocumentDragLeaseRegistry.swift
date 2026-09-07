import AppKit

/// Shares existing in-process source grants with a destination before AppKit ends the drag.
/// In particular, a nested file may depend on its parent folder's security scope.
@MainActor
enum DocumentDragLeaseRegistry {
    static let pasteboardType = NSPasteboard.PasteboardType("de.benjaminkraatz.DeeDock.document-lease")
    private static var leases: [String: DocumentResourceAccess] = [:]

    static func register(_ access: DocumentResourceAccess, on item: NSPasteboardItem) -> String {
        let token = UUID().uuidString
        leases[token] = access
        item.setString(token, forType: pasteboardType)
        return token
    }

    static func access(for pasteboard: NSPasteboard, urls: [URL]) -> DocumentResourceAccess {
        if let token = pasteboard.string(forType: pasteboardType), let access = leases[token],
           access.urls == urls {
            return access
        }
        return DocumentResourceAccess(urls)
    }

    static func release(_ token: String?) {
        if let token { leases[token] = nil }
    }
}
