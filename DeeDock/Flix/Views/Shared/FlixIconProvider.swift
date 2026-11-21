import AppKit
import UniformTypeIdentifiers

/// Icons that never read the file on the main actor: the type's icon from Launch Services, an
/// app's icon by its bundle identifier, or a file's own icon once ``loadIcon(forPath:policy:)``
/// read it in the background. Used wherever the read policy does not allow touching the file, and
/// as the placeholder while a thumbnail loads.
@MainActor
enum FlixIconProvider {
    private static let cache = NSCache<NSString, NSImage>()
    /// Files' own icons by standardized path, filled off the main actor. `nonisolated(unsafe)`:
    /// `NSCache` is documented as thread-safe, and the images are only drawn, never mutated.
    nonisolated(unsafe) private static let fileIcons: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 2_000
        return cache
    }()

    static func typeIcon(for item: FlixItem) -> NSImage {
        if item.kind == .app, let id = item.bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return cached("app:" + id) { NSWorkspace.shared.icon(forFile: url.path) }
        }
        if item.kind == .folder { return cached("type:folder") { NSWorkspace.shared.icon(for: .folder) } }
        if item.kind == .link { return cached("type:link") { NSWorkspace.shared.icon(for: .internetLocation) } }
        let type = item.contentType
            ?? item.path.flatMap { UTType(filenameExtension: ($0 as NSString).pathExtension) }
            ?? .data
        return cached("type:" + type.identifier) { NSWorkspace.shared.icon(for: type) }
    }

    /// The file's own icon when ``loadIcon(forPath:policy:)`` already read it, otherwise the type
    /// icon. Never touches the disk, so rows and drag images can call it while drawing.
    static func icon(for item: FlixItem, policy: FlixReadPolicy) -> NSImage {
        guard item.kind != .app, let path = item.path,
              let icon = fileIcons.object(forKey: FlixPaths.standardized(path) as NSString) else { return typeIcon(for: item) }
        return icon
    }

    /// The file's own icon (an app's, a folder's custom icon), read off the main actor when
    /// `policy` allows reading the path, at the place the policy just resolved, never through a
    /// link. Cached by path; nil when the policy refuses.
    nonisolated static func loadIcon(forPath path: String, policy: FlixReadPolicy) async -> NSImage? {
        let key = FlixPaths.standardized(path) as NSString
        if let icon = fileIcons.object(forKey: key) { return icon }
        guard let icon = await readIcon(path, policy: policy) else { return nil }
        fileIcons.setObject(icon, forKey: key)
        return icon
    }

    @concurrent nonisolated private static func readIcon(_ path: String, policy: FlixReadPolicy) async -> NSImage? {
        guard let url = policy.readableURL(path) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private static func cached(_ key: String, make: () -> NSImage) -> NSImage {
        if let image = cache.object(forKey: key as NSString) { return image }
        let image = make()
        cache.setObject(image, forKey: key as NSString)
        return image
    }
}
