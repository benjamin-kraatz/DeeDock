import AppKit
import UniformTypeIdentifiers

/// Icons that never read the file: the type's icon from Launch Services, or an app's icon by its
/// bundle identifier. Used wherever the read policy does not allow touching the file, and as the
/// placeholder while a thumbnail loads.
@MainActor
enum FlixIconProvider {
    private static let cache = NSCache<NSString, NSImage>()

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

    /// The file's own icon when `policy` allows reading it, otherwise the type icon. The icon is
    /// read at the path the policy just resolved, never through a link.
    static func icon(for item: FlixItem, policy: FlixReadPolicy) -> NSImage {
        guard item.kind != .app, let path = item.path, let url = policy.readableURL(path) else {
            return typeIcon(for: item)
        }
        return HubThumbnailCache.shared.icon(for: url)
    }

    private static func cached(_ key: String, make: () -> NSImage) -> NSImage {
        if let image = cache.object(forKey: key as NSString) { return image }
        let image = make()
        cache.setObject(image, forKey: key as NSString)
        return image
    }
}
