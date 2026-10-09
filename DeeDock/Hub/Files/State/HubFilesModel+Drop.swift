import AppKit

/// Drop handling shared by panes, folder items, sidebar entries, tabs, and columns.
extension HubFilesModel {
    /// The operation a drop of `sources` onto `destination` performs, or `[]` when invalid.
    ///
    /// Same-volume drops move and cross-volume drops copy (`HubFileTransferQueue.defaultKind`);
    /// Option forces a copy. The source's operation mask can veto a move (another app offering
    /// only copy). Results are cached per target and modifier state, because AppKit asks on every
    /// pointer move and the default kind reads volume identifiers from disk.
    func dropOperation(sources: [URL], destination: URL, optionHeld: Bool, sourceMask: NSDragOperation) -> NSDragOperation {
        guard !sources.isEmpty else { return [] }
        let key = "\(FilePathCopy.path(of: destination))|\(optionHeld)|\(sourceMask.rawValue)|\(sources.count)|"
            + sources.map(\.path).joined(separator: "\u{1F}")
        if let cache = dropOperationCache, cache.key == key { return cache.operation }
        let operation: NSDragOperation
        if !HubFileTransferQueue.isValidDrop(sources: sources, destination: destination) {
            operation = []
        } else {
            let kind = HubFileTransferQueue.defaultKind(sources: sources, destination: destination, optionHeld: optionHeld)
            if kind == .move, sourceMask.contains(.move) {
                operation = .move
            } else {
                operation = sourceMask.contains(.copy) || sourceMask.contains(.generic) ? .copy : []
            }
        }
        dropOperationCache = (key, operation)
        return operation
    }

    /// Queues the copy or move for a completed drop.
    /// - Returns: False when the drop is invalid.
    @discardableResult
    func performDrop(sources: [URL], destination: URL, optionHeld: Bool, sourceMask: NSDragOperation) -> Bool {
        let operation = dropOperation(sources: sources, destination: destination, optionHeld: optionHeld,
                                      sourceMask: sourceMask)
        dropOperationCache = nil
        dropHighlight = nil
        guard !operation.isEmpty else { return false }
        transfers.enqueue(operation == .move ? .move : .copy, sources: sources, to: destination)
        return true
    }

    /// The folder a browser tab accepts drops into: its active pane's folder (none for Recents).
    func dropFolder(for tab: HubFilesBrowserTab) -> URL? {
        tab.activePane.folderURL
    }

    /// Ends a drag hover without a drop.
    func clearDropHighlight(_ highlight: HubFilesDropHighlight) {
        if dropHighlight == highlight { dropHighlight = nil }
    }
}
