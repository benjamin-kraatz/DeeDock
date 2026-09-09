import AppKit

/// Stable identity for the built-in Downloads stack, independent of ordinary folder pins.
enum DownloadsDockItem {
    static let id = UUID(uuidString: "5927AC59-94EE-4EE9-92B1-3D6C35F77BE8")!

    static func item(displayID: String) -> FolderDockItem {
        let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        let presentation = UserDefaults.standard.string(forKey: "downloadsPresentation.\(displayID)")
            .flatMap(FolderStackPresentation.init(rawValue:)) ?? .grid
        let reference = FolderReference(id: id, url: url, name: String(localized: .downloadsName),
            bookmarkData: Data(), presentation: presentation)
        return FolderDockItem(reference: reference, icon: NSWorkspace.shared.icon(forFile: url.path),
            isAvailable: FolderResourceAccess(reference).isAvailable)
    }
}

extension FolderDockItem {
    var isDownloads: Bool { reference.id == DownloadsDockItem.id }
}
