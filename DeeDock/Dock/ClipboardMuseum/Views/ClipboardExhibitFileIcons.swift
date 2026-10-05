import AppKit
import UniformTypeIdentifiers

/// Finder icon and existence for one copied path.
struct ClipboardExhibitFileIcon {
    /// False when the file was moved or deleted after the copy.
    let exists: Bool
    /// Artwork owned by the tile. The workspace's shared image is copied before its size is set.
    let image: NSImage
}

/// Path-keyed file icons for clipboard exhibits.
///
/// `FileManager.fileExists` and `NSWorkspace.icon(forFile:)` can block in the kernel on a
/// network path, so a tile draws a type placeholder first. Lookups run on a private queue.
/// Folder stacks batch 16 icons because that lookup stays on the main actor and a listing can
/// be large. An exhibit shows at most 12 tiles, and each stat can stall, so this batch is smaller.
/// A batch already inside the kernel finishes. The next batch is skipped once the exhibit changes.
///
/// The cache outlives the current exhibit, so a slide the person returns to does not stat again.
/// A file removed while that entry is cached keeps the last icon until newer paths push it out.
@MainActor enum ClipboardExhibitFileIcons {
    /// Paths resolved between publishes.
    static let batchSize = 4
    private static let cacheLimit = 48
    private static let iconSize = NSSize(width: 128, height: 128)
    private static var cache: [String: ClipboardExhibitFileIcon] = [:]
    private static var cacheOrder: [String] = []
    private static var placeholders: [String: NSImage] = [:]

    /// The last lookup for `path`, if it is still in the cache.
    static func cached(_ path: String) -> ClipboardExhibitFileIcon? {
        cache[path]
    }

    /// A UTI icon for the path extension. Does not touch the file.
    static func placeholder(for url: URL) -> NSImage {
        let type = UTType(filenameExtension: url.pathExtension) ?? .item
        if let cached = placeholders[type.identifier] { return cached }
        let icon = (NSWorkspace.shared.icon(for: type).copy() as? NSImage) ?? NSImage(size: iconSize)
        icon.size = iconSize
        placeholders[type.identifier] = icon
        return icon
    }

    /// Publishes cached icons, then fills the rest.
    ///
    /// Returns without publishing once the calling task is cancelled, so a slide change cannot
    /// paint the previous exhibit. `load` exists so tests can suspend a batch. Production reads
    /// through ``ClipboardExhibitFileIconProbe/load(_:)``.
    static func fill(
        _ urls: [URL],
        load: @MainActor ([String]) async -> [ClipboardExhibitFileIconProbe.Loaded],
        publish: (String, ClipboardExhibitFileIcon) -> Void
    ) async {
        guard !Task.isCancelled else { return }
        var seen = Set<String>()
        var pending: [String] = []
        pending.reserveCapacity(urls.count)
        for url in urls {
            let path = url.path
            guard seen.insert(path).inserted else { continue }
            if let icon = cache[path] {
                publish(path, icon)
            } else {
                pending.append(path)
            }
        }
        var offset = 0
        while offset < pending.count {
            guard !Task.isCancelled else { return }
            let end = min(offset + batchSize, pending.count)
            let loaded = await load(Array(pending[offset..<end]))
            guard !Task.isCancelled else { return }
            for item in loaded {
                let icon = ClipboardExhibitFileIcon(exists: item.exists, image: item.image)
                remember(item.path, icon)
                publish(item.path, icon)
            }
            offset = end
        }
    }

    /// Production fill. The probe reads existence and icons off the main actor.
    static func fill(_ urls: [URL], publish: (String, ClipboardExhibitFileIcon) -> Void) async {
        await fill(urls, load: { await ClipboardExhibitFileIconProbe.load($0) }, publish: publish)
    }

    private static func remember(_ path: String, _ icon: ClipboardExhibitFileIcon) {
        guard cache[path] == nil else { return }
        cache[path] = icon
        cacheOrder.append(path)
        guard cacheOrder.count > cacheLimit else { return }
        cache.removeValue(forKey: cacheOrder.removeFirst())
    }
}

/// Blocking existence checks and Finder icons for clipboard file tiles.
///
/// A wedged network path blocks in the kernel. A private serial queue stalls only this read.
/// The cooperative pool would hold one of the few threads every task in the app shares, which
/// is the same reason `VolumeReads` exists.
///
/// `NSImage` is not `Sendable`. Each image is created on the queue and handed to the main actor
/// once, never shared back. Drop the unchecked conformance if `NSImage` becomes `Sendable`.
nonisolated enum ClipboardExhibitFileIconProbe {
    struct Loaded: @unchecked Sendable {
        let path: String
        let exists: Bool
        let image: NSImage
    }

    private static let queue = DispatchQueue(label: "DeeDock.ClipboardExhibitFileIcons", qos: .userInitiated)
    private static let iconSize = NSSize(width: 128, height: 128)

    /// Reads `paths` in order.
    ///
    /// Cancelling the caller does not interrupt a stat already inside the kernel. Paths still
    /// waiting in this batch are skipped.
    static func load(_ paths: [String]) async -> [Loaded] {
        let cancelled = CancelFlag()
        return await withTaskCancellationHandler {
            await run {
                var loaded: [Loaded] = []
                loaded.reserveCapacity(paths.count)
                for path in paths {
                    if cancelled.isCancelled { break }
                    let exists = FileManager.default.fileExists(atPath: path)
                    let icon = (NSWorkspace.shared.icon(forFile: path).copy() as? NSImage) ?? NSImage(size: iconSize)
                    icon.size = iconSize
                    loaded.append(Loaded(path: path, exists: exists, image: icon))
                }
                return loaded
            }
        } onCancel: {
            cancelled.cancel()
        }
    }

    private static func run<Value: Sendable>(_ read: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: read()) }
        }
    }
}

/// Set from the cancelled task and read on the icon queue.
///
/// Default actor isolation would put this on the main actor. The queue calls `isCancelled`
/// between stats, so the flag has to be usable from that queue.
private nonisolated final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}
