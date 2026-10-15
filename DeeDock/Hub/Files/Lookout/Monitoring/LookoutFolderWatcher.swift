// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import CoreServices
import Foundation

/// File-level FSEvents on the chosen folders. Reports which paths changed, a batch at a time; the engine debounces
/// and asks the index service to sync. Costs nothing while nothing changes (no polling), and hidden files
/// (.DS_Store, editors' temp files) are ignored, since browsing a folder in Finder writes those.
///
/// The stream runs on `queue` and is stopped, invalidated and released when the watcher goes away, so the owner ends
/// it by dropping its reference. The callback reaches the watcher through an unretained pointer: the stream never
/// outlives the watcher, because `deinit` invalidates it first.
nonisolated final class LookoutFolderWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let handler: @Sendable ([String]) -> Void

    /// Nil when there's nothing to watch or FSEvents won't start.
    ///
    /// - Parameters:
    ///   - paths: Folders that exist.
    ///   - latency: How long FSEvents gathers changes before reporting them.
    ///   - queue: A serial queue the handler runs on.
    ///   - handler: The changed paths, without hidden ones; never called with none.
    init?(paths: [String], latency: TimeInterval, queue: DispatchQueue,
          handler: @escaping @Sendable ([String]) -> Void) {
        self.handler = handler
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

    fileprivate func received(_ paths: [String]) {
        let relevant = paths.filter { path in
            !path.split(separator: "/").contains { $0.hasPrefix(".") }
        }
        if !relevant.isEmpty { handler(relevant) }
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
    watcher.received(list)
}
