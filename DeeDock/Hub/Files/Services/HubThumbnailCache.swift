import AppKit
import QuickLookThumbnailing

/// Thumbnails and icons for Files rows and grid cells.
///
/// `icon(for:)` is synchronous and cheap after the first call per URL, so a row can draw at once.
/// `thumbnail(for:size:scale:modified:)` asks Quick Look to render the document, which is what Finder
/// shows for pictures, PDFs, and videos; it falls back to the workspace icon when Quick Look has
/// nothing. Both caches are `NSCache`s, so memory pressure evicts them. Keys include the
/// requested pixel size so a grid at a larger zoom never shows a blurry list thumbnail, and the
/// file's modification date so an edited file renders again.
///
/// One render serves every cell asking for the same key. The render stores its own result, so a
/// thumbnail finished while its cell scrolled away is still there on scroll-back; when the last
/// cell waiting for it goes away first, the render is cancelled, so a fast scroll doesn't queue
/// Quick Look work ahead of the visible cells.
@MainActor
final class HubThumbnailCache {
    /// Renders one thumbnail of a file at a size in points and a scale, or nil when there is none.
    /// Must stop early when its task is cancelled.
    typealias Renderer = @Sendable (URL, CGSize, CGFloat) async -> NSImage?

    /// The app-wide cache.
    static let shared = HubThumbnailCache()

    /// A render in flight and how many callers wait for it. `id` tells it apart from a later render
    /// of the same key, because the waiters' cancellation arrives on the main actor later.
    private struct Render {
        let id: UUID
        let task: Task<NSImage?, Never>
        var waiters: Int
    }

    private let icons = NSCache<NSURL, NSImage>()
    private let thumbnails = NSCache<NSString, NSImage>()
    /// Requests in flight per cache key, so many cells asking for the same image share one render.
    private var inFlight: [String: Render] = [:]
    private let render: Renderer

    /// - Parameter render: Draws the thumbnails; tests pass their own. Defaults to Quick Look.
    init(render: @escaping Renderer = { url, size, scale in await HubThumbnailCache.quickLook(url, size: size, scale: scale) }) {
        self.render = render
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
    ///
    /// - Parameter modified: The file's modification date, when known: part of the cache key, so a
    ///   changed file isn't answered with its old thumbnail.
    func thumbnail(for url: URL, size: CGSize, scale: CGFloat, modified: Date? = nil) async -> NSImage? {
        let pixels = "\(Int(size.width * scale))x\(Int(size.height * scale))"
        let key = "\(url.path)|\(modified?.timeIntervalSince1970 ?? 0)|\(pixels)"
        if let image = thumbnails.object(forKey: key as NSString) { return image }
        guard !Task.isCancelled else { return nil }
        let entry: Render
        if var existing = inFlight[key] {
            existing.waiters += 1
            inFlight[key] = existing
            entry = existing
        } else {
            entry = start(key: key, url: url, size: size, scale: scale)
            inFlight[key] = entry
        }
        // The handler runs on whichever thread cancels this caller, so it only hops to the main
        // actor; `leave` decides there whether anyone still waits. Either way this caller waits for
        // the render to end, which is prompt once the render is cancelled.
        let id = entry.id
        let image = await withTaskCancellationHandler {
            await entry.task.value
        } onCancel: {
            Task { @MainActor [weak self] in self?.leave(key, id: id) }
        }
        guard !Task.isCancelled else { return nil }
        return image
    }

    /// Drops cached artwork for `url`, for example after the file changed.
    func invalidate(_ url: URL) {
        icons.removeObject(forKey: url as NSURL)
        // NSCache cannot enumerate keys; stale sized thumbnails age out by count limit.
    }

    /// Starts the one render for `key`. It caches its own result and ends its in-flight entry on
    /// the main actor, whether or not anyone still waits; a cancelled render caches nothing, so the
    /// next request renders again.
    private func start(key: String, url: URL, size: CGSize, scale: CGFloat) -> Render {
        let id = UUID()
        let render = render
        let task = Task { [weak self] () -> NSImage? in
            let image = await render(url, size, scale)
            guard let self else { return image }
            if inFlight[key]?.id == id { inFlight[key] = nil }
            guard !Task.isCancelled else { return nil }
            let result = image ?? icon(for: url)
            thumbnails.setObject(result, forKey: key as NSString)
            return result
        }
        return Render(id: id, task: task, waiters: 1)
    }

    /// One caller of `key`'s render `id` was cancelled. The last one to go cancels the render, which
    /// cancels its Quick Look request.
    private func leave(_ key: String, id: UUID) {
        guard var entry = inFlight[key], entry.id == id else { return }
        entry.waiters -= 1
        if entry.waiters > 0 {
            inFlight[key] = entry
        } else {
            inFlight[key] = nil
            entry.task.cancel()
        }
    }

    /// The live renderer: asks Quick Look for the thumbnail, off the main actor. Cancelling the task
    /// cancels the generator's request, so a render nobody waits for stops taking Quick Look's time.
    @concurrent nonisolated static func quickLook(_ url: URL, size: CGSize, scale: CGFloat) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale,
                                                   representationTypes: .thumbnail)
        do {
            return try await withTaskCancellationHandler {
                try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
            } onCancel: {
                QLThumbnailGenerator.shared.cancel(request)
            }
        } catch {
            return nil
        }
    }
}
