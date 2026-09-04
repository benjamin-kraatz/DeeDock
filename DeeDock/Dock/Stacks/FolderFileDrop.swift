import AppKit

/// File-only copy destination. Private pin drags never become filesystem operations.
@MainActor
enum FolderFileDrop {
    static func urls(_ info: NSDraggingInfo) -> [URL]? {
        guard info.draggingSourceOperationMask.contains(.copy),
              info.draggingPasteboard.string(forType: DockDragCoordinator.pasteboardType) == nil,
              let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty,
              urls.count == info.draggingPasteboard.pasteboardItems?.count else { return nil }
        return urls
    }

    /// Captures source grants before the native drop callback returns. Work continues if the
    /// popover closes; completion reports partial success and never retries a batch silently.
    static func copy(_ urls: [URL], to destination: URL, lease: FolderResourceAccess,
                     completion: @escaping (String?) -> Void) {
        let sources = DocumentResourceAccess(urls)
        Task {
            let error = await Task.detached {
                defer { withExtendedLifetime((sources, lease)) {} }
                let manager = FileManager.default
                let target = destination.resolvingSymlinksInPath().standardizedFileURL
                var completed = 0
                do {
                    var names = Set<String>()
                    // Validate every destination before copying. FileManager still refuses a
                    // collision that races this check, so existing content is never replaced.
                    for source in sources.urls {
                        let canonical = source.resolvingSymlinksInPath().standardizedFileURL
                        let output = target.appendingPathComponent(source.lastPathComponent)
                        guard target != canonical,
                              !target.path.hasPrefix(canonical.path + "/"),
                              names.insert(source.lastPathComponent).inserted,
                              !manager.fileExists(atPath: output.path) else {
                            throw CocoaError(.fileWriteFileExists)
                        }
                    }
                    for source in sources.urls {
                        try manager.copyItem(at: source, to: target.appendingPathComponent(source.lastPathComponent))
                        completed += 1
                    }
                    return nil as String?
                } catch {
                    return String(localized: .folderDropFailed(completed, error.localizedDescription))
                }
            }.value
            completion(error)
        }
    }
}
