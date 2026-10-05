import AppKit

/// File-only copy or move destination. Private pin drags never become filesystem operations.
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

    /// The operation a drop performs: copy, or move while Shift is held where moving is offered.
    ///
    /// Shift is DOKK's own convention for these targets, read from the live modifier state because
    /// the drag source does not translate it into an operation the way it does Option or Command.
    static func operation(_ info: NSDraggingInfo, allowsMove: Bool) -> NSDragOperation {
        guard urls(info) != nil else { return [] }
        return operation(mask: info.draggingSourceOperationMask, allowsMove: allowsMove)
    }

    /// The same decision from the source's operation mask alone. AppKit narrows the mask for the
    /// modifiers it owns (⌘ leaves only move, ⌥ only copy), so the hint and the drop agree with it:
    /// a move-only drag is refused, and ⌥ keeps a copy even with Shift held.
    static func operation(mask: NSDragOperation, allowsMove: Bool) -> NSDragOperation {
        guard mask.contains(.copy) else { return [] }
        return allowsMove && NSEvent.modifierFlags.contains(.shift) && mask.contains(.move) ? .move : .copy
    }

    /// Captures source grants before the native drop callback returns. Work continues if the
    /// popover closes; completion reports partial success and never retries a batch silently.
    ///
    /// - Parameter move: Moves instead of copying. Across volumes FileManager copies and then
    ///   removes the source, so a failure part-way leaves the source in place.
    static func copy(_ urls: [URL], to destination: URL, lease: FolderResourceAccess, move: Bool = false,
                     completion: @escaping (String?) -> Void) {
        let sources = DocumentResourceAccess(urls)
        Task {
            let error = await Task.detached {
                defer { withExtendedLifetime((sources, lease)) {} }
                let manager = FileManager.default
                let target = destination.resolvingSymlinksInPath().standardizedFileURL
                var completed = 0
                do {
                    var reserved: [String] = []
                    // Validate every destination before copying. FileManager still refuses a
                    // collision that races this check, so existing content is never replaced.
                    // Reserved names use the destination volume's case rule, the same one
                    // containment reads from `volumeSupportsCaseSensitiveNames`. On a
                    // case-insensitive volume, Notes.txt and notes.txt are one file, and the
                    // batch has to fail before the first move removes a source.
                    let caseSensitive = target.volumeReportsCaseSensitiveNames
                    for source in sources.urls {
                        let canonical = source.resolvingSymlinksInPath().standardizedFileURL
                        let name = source.lastPathComponent
                        let output = target.appendingPathComponent(name)
                        let claimed = reserved.contains { existing in
                            caseSensitive ? existing == name : existing.caseInsensitiveCompare(name) == .orderedSame
                        }
                        guard !target.isSameOrDescendant(of: canonical),
                              !claimed,
                              !manager.fileExists(atPath: output.path) else {
                            throw CocoaError(.fileWriteFileExists)
                        }
                        reserved.append(name)
                    }
                    for source in sources.urls {
                        let output = target.appendingPathComponent(source.lastPathComponent)
                        if move { try manager.moveItem(at: source, to: output) }
                        else { try manager.copyItem(at: source, to: output) }
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
