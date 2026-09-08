import Foundation
import ImageIO
import UniformTypeIdentifiers
import Darwin

/// Validates and saves clipboard images off the main actor. Successful files outlive Shelf references.
actor ShelfClipboardArtifacts {
    private let directory: URL?
    static let maximumPixels = 40_000_000

    /// An injected destination lets tests avoid the user's Application Support directory.
    init(directory: URL? = nil) { self.directory = directory }

    func write(_ data: Data) throws -> URL {
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= ShelfClipboardSnapshot.maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source),
              [UTType.png.identifier, UTType.tiff.identifier].contains(type as String),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= Self.maximumPixels / height,
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { throw ShelfClipboardFailure.image }
        try Task.checkCancellation()

        // Encoding a single PNG gives downstream consumers one validated, full-resolution image.
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil)
        else { throw ShelfClipboardFailure.image }
        // Preserve display orientation as well as the decoded pixels and transparency.
        let outputProperties = properties[kCGImagePropertyOrientation].map {
            [kCGImagePropertyOrientation: $0] as CFDictionary
        }
        CGImageDestinationAddImage(destination, image, outputProperties)
        guard CGImageDestinationFinalize(destination), encoded.length <= ShelfClipboardSnapshot.maximumBytes
        else { throw ShelfClipboardFailure.image }
        try Task.checkCancellation()

        let folder: URL
        if let directory { folder = directory }
        else {
            folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)
                .appendingPathComponent(Bundle.main.bundleIdentifier ?? "DeeDock", isDirectory: true)
                .appendingPathComponent("Clipboard", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Clipboard-\(UUID().uuidString).png")
        // Exclusive creation must never replace an existing artifact. The Shelf only sees the URL
        // after the complete write. No cancellation check after writing: the caller now owns rollback.
        try writeExclusively(encoded as Data, to: url)
        return url
    }

    /// Exclusive creation establishes ownership before writing. A failed write removes only the
    /// file opened here; EEXIST never enters cleanup and cannot delete someone else's file.
    private func writeExclusively(_ data: Data, to url: URL) throws {
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR) } ?? -1
        }
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            do { try FileManager.default.removeItem(at: url) }
            catch { throw ShelfClipboardFailure.retainedFile(url) }
            throw error
        }
    }

    /// Call only for a file returned by this import's write, never for a supplied source URL.
    func discard(_ url: URL) throws { try FileManager.default.removeItem(at: url) }

    func isReadable(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) && FileManager.default.isReadableFile(atPath: url.path)
    }
}
