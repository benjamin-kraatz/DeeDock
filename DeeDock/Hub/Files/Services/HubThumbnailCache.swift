import AppKit
import QuickLookThumbnailing

/// Thumbnails and icons for Files rows and grid cells.
///
/// `icon(for:)` is synchronous and cheap after the first call per URL, so a row can draw at once.
/// `thumbnail(for:size:scale:)` asks Quick Look to render the document, which is what Finder
/// shows for pictures, PDFs, and videos; it falls back to the workspace icon when Quick Look has
/// nothing. Both caches are `NSCache`s, so memory pressure evicts them. Keys include the
/// requested pixel size so a grid at a larger zoom never shows a blurry list thumbnail.
@MainActor
final class HubThumbnailCache {
    /// The app-wide cache.
    static let shared = HubThumbnailCache()

    private let icons = NSCache<NSURL, NSImage>()
    private let thumbnails = NSCache<NSString, NSImage>()
    /// Requests in flight per cache key, so many cells asking for the same image share one render.
    private var inFlight: [NSString: Task<NSImage?, Never>] = [:]

    init() {
        icons.countLimit = 2000
        thumbnails.countLimit = 600
    }

    /// The workspace icon for `url`. Cached per URL.
    func icon(for url: URL) -> NSImage {
        if let image = icons.object(forKey: url as NSURL) { return image }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        icons.setObject(image, forKey: url as NSURL)
        return image
    }

    /// A Quick Look thumbnail of `url` at `size` points and `scale`, or the workspace icon when
    /// Quick Look cannot render one. Returns nil only when the calling task was cancelled.
    func thumbnail(for url: URL, size: CGSize, scale: CGFloat) async -> NSImage? {
        let key = "\(url.path)|\(Int(size.width * scale))x\(Int(size.height * scale))" as NSString
        if let image = thumbnails.object(forKey: key) { return image }
        let task: Task<NSImage?, Never>
        if let existing = inFlight[key] {
            task = existing
        } else {
            task = Task { await Self.render(url, size: size, scale: scale) }
            inFlight[key] = task
        }
        let image = await task.value
        inFlight[key] = nil
        guard !Task.isCancelled else { return nil }
        let result = image ?? icon(for: url)
        thumbnails.setObject(result, forKey: key)
        return result
    }

    /// Drops cached artwork for `url`, for example after the file changed.
    func invalidate(_ url: URL) {
        icons.removeObject(forKey: url as NSURL)
        // NSCache cannot enumerate keys; stale sized thumbnails age out by count limit.
    }

    nonisolated private static func render(_ url: URL, size: CGSize, scale: CGFloat) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale,
                                                   representationTypes: .thumbnail)
        do {
            return try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        } catch {
            return nil
        }
    }
}
