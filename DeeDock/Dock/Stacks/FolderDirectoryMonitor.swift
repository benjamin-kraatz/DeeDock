import Darwin
import Dispatch
import Foundation

/// Watches one open folder without keeping any idle polling alive.
///
/// `open` can block in the kernel on a wedged volume. Callers create the monitor on
/// `VolumeReads` and keep it only when the stack is still opening. The source is resumed
/// before the instance is published; `stop` is the only later mutation.
nonisolated final class FolderDirectoryMonitor: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?

    init?(url: URL, changed: @escaping @Sendable () -> Void) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete], queue: .global(qos: .utility))
        source.setEventHandler(handler: changed)
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    func stop() { source?.cancel(); source = nil }
    deinit { stop() }
}
