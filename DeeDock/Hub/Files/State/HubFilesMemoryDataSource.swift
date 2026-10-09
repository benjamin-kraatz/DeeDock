import Foundation
import UniformTypeIdentifiers

/// An in-memory folder tree for previews and tests. Never touches the file system.
@MainActor
final class HubFilesMemoryDataSource: HubFilesDataSource {
    let homeDirectory: URL
    /// Folder path → children.
    var folders: [String: [HubFileItem]]
    var recentItems: [HubFileItem]
    var available: Int64?
    private(set) var recentsActive = false

    init(home: URL, folders: [String: [HubFileItem]] = [:], recents: [HubFileItem] = [], available: Int64? = nil) {
        homeDirectory = HubFilesPath.normalized(home)
        self.folders = folders
        recentItems = recents
        self.available = available
    }

    func setRecentsActive(_ active: Bool) { recentsActive = active }

    func directoryExists(_ url: URL) -> Bool { folders[FilePathCopy.path(of: url)] != nil }

    func items(in folder: URL) async throws -> [HubFileItem] {
        guard let items = folders[FilePathCopy.path(of: folder)] else { throw CocoaError(.fileNoSuchFile) }
        return items
    }

    func item(at url: URL) async -> HubFileItem? {
        guard let parent = HubFilesPath.parent(of: url) else { return nil }
        return folders[FilePathCopy.path(of: parent)]?.first { HubFilesPath.same($0.url, url) }
    }

    func availableCapacity(for url: URL) async -> Int64? { available }

    func itemCount(in folder: URL) async -> Int? { folders[FilePathCopy.path(of: folder)]?.count }

    func watch(_ folder: URL, onChange: @escaping @MainActor () -> Void) -> HubFilesWatch? { nil }

    /// Adds a folder (and an entry for it in its parent) or a file to the tree.
    @discardableResult
    func add(_ path: String, kind: UTType = .folder, size: Int64? = nil, modified: Date? = nil) -> HubFileItem {
        let url = URL(filePath: path, directoryHint: .notDirectory)
        let isDirectory = kind == .folder
        let item = HubFileItem(url: url, name: url.lastPathComponent, isDirectory: isDirectory, isPackage: false,
                               isHidden: false, contentType: kind, byteSize: isDirectory ? nil : size ?? 0,
                               modified: modified, created: modified, volumeIdentifier: "memory",
                               kindDescription: kind.localizedDescription ?? "")
        if let parent = HubFilesPath.parent(of: url) {
            let key = FilePathCopy.path(of: parent)
            folders[key, default: []].removeAll { $0.url == url }
            folders[key, default: []].append(item)
        }
        if isDirectory, folders[path] == nil { folders[path] = [] }
        return item
    }

    /// Removes a folder and its subtree, as if it was deleted or its volume unmounted.
    func remove(_ path: String) {
        folders = folders.filter { key, _ in key != path && !key.hasPrefix(path + "/") }
        if let parent = HubFilesPath.parent(of: URL(filePath: path)) {
            folders[FilePathCopy.path(of: parent)]?.removeAll { FilePathCopy.path(of: $0.url) == path }
        }
    }
}
