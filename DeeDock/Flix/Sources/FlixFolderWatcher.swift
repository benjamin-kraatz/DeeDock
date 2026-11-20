import CoreServices
import Foundation
import UniformTypeIdentifiers

/// New, saved, and downloaded files in the watched folders, from FSEvents with file-level events.
///
/// Only folders the read policy allows are watched, so the stream and the follow-up reads never make
/// macOS ask. Events coalesce per path for ``settleDelay`` so a download being written, or a save in
/// several steps, records once. Each settled path is classified off the main actor:
/// - a file born in the last few minutes is **downloaded** when it carries `kMDItemWhereFroms` or
///   sits in Downloads, a **screenshot** when `kMDItemIsScreenCapture` is set, otherwise **new**;
/// - an older file that changed is **saved**.
/// Partial downloads, hidden files, package internals, and noise are skipped here; the finished file
/// arrives as its own event.
///
/// The stream runs on a private queue and is invalidated by ``stop()``; nothing polls.
nonisolated final class FlixFolderWatcher: @unchecked Sendable {
    static let settleDelay: TimeInterval = 1.2
    /// A file younger than this counts as new rather than saved.
    static let newWindow: TimeInterval = 5 * 60

    private let queue = DispatchQueue(label: "dokk.flix.folders", qos: .utility)
    /// Queue-confined state.
    private var stream: FSEventStreamRef?
    private var pending: [String: FSEventStreamEventFlags] = [:]
    private var flushScheduled = false
    private var roots: [String] = []
    private var downloads = FlixPaths.downloads()
    private var deliver: (@Sendable ([FlixActivityEvent]) -> Void)?

    init() {}

    /// Watches `folders` (standardized, readable) and reports settled events through `deliver`, on
    /// the main actor. Replaces any earlier stream; an empty list just stops.
    func start(folders: [String], deliver: @escaping @MainActor @Sendable ([FlixActivityEvent]) -> Void) {
        queue.async { [self] in
            stopOnQueue()
            roots = folders
            guard !folders.isEmpty else { return }
            self.deliver = { events in
                DispatchQueue.main.async { MainActor.assumeIsolated { deliver(events) } }
            }
            var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                               retain: nil, release: nil, copyDescription: nil)
            let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
                guard let info else { return }
                let watcher = Unmanaged<FlixFolderWatcher>.fromOpaque(info).takeUnretainedValue()
                let array = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
                for index in 0..<min(count, array.count) { watcher.received(array[index], flags: flags[index]) }
            }
            let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
                                | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagIgnoreSelf)
            guard let created = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, folders as CFArray,
                                                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, flags)
            else { return }
            FSEventStreamSetDispatchQueue(created, queue)
            FSEventStreamStart(created)
            stream = created
        }
    }

    /// Stops and releases the stream. Pending events are dropped.
    func stop() {
        queue.sync { stopOnQueue() }
    }

    private func stopOnQueue() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        pending.removeAll()
        deliver = nil
    }

    /// FSEvents callback, on `queue`.
    private func received(_ path: String, flags: FSEventStreamEventFlags) {
        let interesting = UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRenamed
                                 | kFSEventStreamEventFlagItemModified)
        guard flags & interesting != 0, !Self.isIgnored(path) else { return }
        pending[path, default: 0] |= flags
        guard !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in self?.flush() }
    }

    private func flush() {
        flushScheduled = false
        let batch = pending
        pending.removeAll()
        let now = Date.now
        let events = batch.compactMap { path, flags in classify(path, flags: flags, now: now) }
        guard !events.isEmpty else { return }
        deliver?(events)
    }

    /// Reads one settled path. Nil when it is gone, hidden, or not worth a row.
    private func classify(_ path: String, flags: FSEventStreamEventFlags, now: Date) -> FlixActivityEvent? {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isHiddenKey, .creationDateKey,
                                         .contentModificationDateKey, .contentTypeKey, .fileSizeKey,
                                         .localizedNameKey]
        guard let values = try? url.resourceValues(forKeys: keys), values.isHidden != true else { return nil }
        let isDirectory = values.isDirectory == true
        let isPackage = values.isPackage == true
        // A folder's own modification only means its contents changed; those report themselves.
        if isDirectory, !isPackage, flags & UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRenamed) == 0 {
            return nil
        }
        let created = values.creationDate ?? .distantPast
        let isNew = now.timeIntervalSince(created) < Self.newWindow
        let whereFroms = Self.stringArrayAttribute("com.apple.metadata:kMDItemWhereFroms", at: path)
        let isScreenshot = Self.boolAttribute("com.apple.metadata:kMDItemIsScreenCapture", at: path)
        let inDownloads = path.hasPrefix(downloads + "/")
        let activity: FlixActivity = if isNew {
            !whereFroms.isEmpty || inDownloads ? .downloaded : .created
        } else {
            .saved
        }
        let date = isNew ? max(created, values.contentModificationDate ?? created) : (values.contentModificationDate ?? now)
        let type = values.contentType
        return FlixActivityEvent(path: path, name: values.localizedName ?? url.lastPathComponent,
                                 kind: FlixItemKind.classify(contentType: type, isDirectory: isDirectory,
                                                             isPackage: isPackage, isScreenshot: isScreenshot),
                                 activity: activity, date: min(date, now),
                                 sourcePage: FlixPaths.sourcePage(fromWhereFroms: whereFroms),
                                 contentTypeIdentifier: type?.identifier,
                                 byteSize: values.fileSize.map(Int64.init))
    }

    /// Hidden components, package internals, partial downloads, and noise never become events.
    static func isIgnored(_ path: String) -> Bool {
        let components = (path as NSString).pathComponents
        if components.contains(where: { $0.hasPrefix(".") && $0 != "." }) { return true }
        let packages: Set<String> = ["app", "photoslibrary", "bundle", "xcodeproj", "xcworkspace", "framework",
                                     "rtfd", "pages", "numbers", "key", "musiclibrary", "tvlibrary", "fcpbundle"]
        if components.dropLast().contains(where: { packages.contains(($0 as NSString).pathExtension.lowercased()) }) {
            return true
        }
        return FlixNoiseRules.isNoise(path: path)
    }

    /// A binary-plist extended attribute holding a string array, such as `kMDItemWhereFroms`.
    private static func stringArrayAttribute(_ name: String, at path: String) -> [String] {
        guard let data = attribute(name, at: path),
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return [] }
        return value as? [String] ?? []
    }

    private static func boolAttribute(_ name: String, at path: String) -> Bool {
        guard let data = attribute(name, at: path),
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return false }
        return (value as? Bool) ?? ((value as? NSNumber)?.boolValue ?? false)
    }

    private static func attribute(_ name: String, at path: String) -> Data? {
        let length = getxattr(path, name, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var data = Data(count: length)
        let read = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, length, 0, 0) }
        return read == length ? data : nil
    }
}
