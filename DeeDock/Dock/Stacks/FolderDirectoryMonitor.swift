import Darwin
import Dispatch
import Foundation

/// Watches one open folder without keeping any idle polling alive.
final class FolderDirectoryMonitor {
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
