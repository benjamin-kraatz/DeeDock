import AppKit
import QuickLookThumbnailing

/// Produces the artwork Finder shows for a staged file.
///
/// `NSWorkspace.icon(forFile:)` only knows the file's type, which is why a screenshot arrives as a
/// generic picture icon. Quick Look renders the document itself and falls back to that same type
/// icon when it cannot, so the panel asks it for every item and keeps whatever comes back.
///
/// Requests are made while the item's security scope is held, cancelled when the panel closes, and
/// cached by item identity so scrolling and re-sorting never regenerate the same image.
@MainActor
final class ShelfThumbnailLoader {
    private let generator = QLThumbnailGenerator.shared
    private var cache: [UUID: NSImage] = [:]
    private var inFlight: Set<UUID> = []
    private var generation = UUID()

    func cached(_ id: UUID) -> NSImage? { cache[id] }

    /// Requests one thumbnail. `completion` runs on the main actor, once, only if still current.
    func load(_ item: ShelfItem, size: CGSize, scale: CGFloat,
              access: @escaping () -> ShelfResourceAccess?,
              completion: @escaping (NSImage) -> Void) {
        if let image = cache[item.id] {
            completion(image)
            return
        }
        guard !inFlight.contains(item.id) else { return }
        guard let resource = access() else { return }
        inFlight.insert(item.id)
        let token = generation
        let request = QLThumbnailGenerator.Request(
            fileAt: resource.url, size: size, scale: scale,
            representationTypes: .thumbnail
        )
        generator.generateBestRepresentation(for: request) { [weak self] representation, _ in
            let image = representation?.nsImage
            Task { @MainActor [weak self] in
                // The access object lives until the generator is finished with the URL.
                withExtendedLifetime(resource) {}
                guard let self, generation == token else { return }
                inFlight.remove(item.id)
                guard let image else { return }
                cache[item.id] = image
                completion(image)
            }
        }
    }

    /// Drops artwork for items that are no longer staged.
    func retain(_ ids: Set<UUID>) {
        cache = cache.filter { ids.contains($0.key) }
        inFlight = inFlight.intersection(ids)
    }

    /// Invalidates every pending request. Callbacks that arrive afterwards are ignored.
    func stop() {
        generation = UUID()
        inFlight.removeAll()
        cache.removeAll()
    }
}
