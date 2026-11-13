// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import CoreServices
import Foundation

/// File-level FSEvents on the chosen folders. Reports which paths changed, a batch at a time; the engine debounces
/// and asks the index service to sync. Costs nothing while nothing changes (no polling). Hidden files (.DS_Store,
/// editors' temp files) are ignored, since browsing a folder in Finder writes those, and so is any change the crawler
/// would pass by (`Rules.canAffectIndex`): a build or an editor's autosave of code doesn't cost a walk of every root.
///
/// The stream runs on `queue` and is stopped, invalidated and released when the watcher goes away, so the owner ends
/// it by dropping its reference. The callback reaches the watcher through an unretained pointer: the stream never
/// outlives the watcher, because `deinit` invalidates it first.
nonisolated final class LookoutFolderWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let handler: @Sendable ([String]) -> Void
    private let scope: Rules.ChangeScope

    /// Nil when there's nothing to watch or FSEvents won't start.
    ///
    /// - Parameters:
    ///   - paths: Folders that exist.
    ///   - latency: How long FSEvents gathers changes before reporting them.
    ///   - queue: A serial queue the handler runs on.
    ///   - scope: What the crawler walks; changes it would pass by are dropped here (`isRelevant`).
    ///   - handler: The changed paths that may change the index; never called with none.
    init?(paths: [String], latency: TimeInterval, queue: DispatchQueue, scope: Rules.ChangeScope,
          handler: @escaping @Sendable ([String]) -> Void) {
        self.handler = handler
        self.scope = scope
        guard !paths.isEmpty else { return nil }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
        guard let stream = FSEventStreamCreate(kCFAllocatorDefault, lookoutFolderWatcherCallback, &context,
                                               paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                               latency, FSEventStreamCreateFlags(flags)) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return nil
        }
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    fileprivate func received(_ paths: [String], flags: [FSEventStreamEventFlags]) {
        let relevant = zip(paths, flags).filter { Self.isRelevant(path: $0.0, flags: $0.1, scope: scope) }.map(\.0)
        if !relevant.isEmpty { handler(relevant) }
    }

    /// Flags that say events were lost or the watched folders themselves changed: a sync must follow, whatever the
    /// path.
    static let alwaysRelevantFlags = FSEventStreamEventFlags(
        kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
            | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged
            | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount)

    /// Whether one FSEvents event should lead to a sync. Runs on the watch queue for every event, so it decides from
    /// the path and flags alone and never touches the file.
    static func isRelevant(path: String, flags: FSEventStreamEventFlags, scope: Rules.ChangeScope) -> Bool {
        if flags & alwaysRelevantFlags != 0 { return true }
        if path.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { return false }
        let isDirectory = flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0
        let itemKinds = FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir | kFSEventStreamEventFlagItemIsFile
            | kFSEventStreamEventFlagItemIsSymlink)
        // An event that names no kind of item can't be judged by its name.
        guard flags & itemKinds != 0 else { return true }
        return Rules.canAffectIndex(path: path, isDirectory: isDirectory, scope: scope)
    }
}

private nonisolated func lookoutFolderWatcherCallback(
    _ stream: ConstFSEventStreamRef, _ info: UnsafeMutableRawPointer?, _ count: Int,
    _ paths: UnsafeMutableRawPointer, _ flags: UnsafePointer<FSEventStreamEventFlags>,
    _ ids: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    let watcher = Unmanaged<LookoutFolderWatcher>.fromOpaque(info).takeUnretainedValue()
    let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
    // One flag word per path. Paths that can't be paired with their flags are all kept, as if FSEvents had asked
    // for a rescan.
    let flagList = list.count == count ? Array(UnsafeBufferPointer(start: flags, count: count))
        : Array(repeating: FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs), count: list.count)
    watcher.received(list, flags: flagList)
}
