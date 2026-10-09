import SwiftUI
import UniformTypeIdentifiers

/// Where item icons come from. Previews use type icons so they never read the file system.
enum HubFilesIconSource {
    /// Workspace icons and Quick Look thumbnails from `HubThumbnailCache`.
    case live
    /// Generic icons for the item's content type.
    case typeOnly
}

extension EnvironmentValues {
    @Entry var hubFilesIconSource: HubFilesIconSource = .live
}

/// A file's icon, upgraded to a Quick Look thumbnail when `thumbnail` is set.
///
/// The icon comes from a cache synchronously; the thumbnail renders off the main actor and the
/// task is cancelled when the view disappears or shows another item.
struct HubFilesItemIcon: View {
    let item: HubFileItem
    let size: CGFloat
    var thumbnail = false

    @Environment(\.hubFilesIconSource) private var source
    @Environment(\.displayScale) private var scale
    @State private var rendered: NSImage?

    var body: some View {
        Image(nsImage: rendered ?? baseIcon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .task(id: thumbnailKey) { await loadThumbnail() }
            .accessibilityHidden(true)
    }

    private var baseIcon: NSImage {
        switch source {
        case .live: HubThumbnailCache.shared.icon(for: item.url)
        case .typeOnly: NSWorkspace.shared.icon(for: item.isDirectory ? .folder : item.contentType ?? .data)
        }
    }

    private var thumbnailKey: String? {
        guard thumbnail, source == .live, !item.isDirectory, !item.isPackage else { return nil }
        return "\(item.url.path)|\(item.modified?.timeIntervalSince1970 ?? 0)|\(size)"
    }

    private func loadThumbnail() async {
        guard thumbnailKey != nil else { rendered = nil; return }
        let image = await HubThumbnailCache.shared.thumbnail(for: item.url, size: CGSize(width: size, height: size), scale: scale)
        guard !Task.isCancelled else { return }
        rendered = image
    }
}

/// Reports an item icon's frame to the Files tab's Quick Look controller while the icon is on
/// screen, so the Quick Look panel zooms out of the icon and back into it.
///
/// Frames are read in SwiftUI's global space and written to plain storage on the controller, so
/// scrolling a long listing costs a dictionary write per visible icon and no view update.
private struct HubFilesQuickLookSource: ViewModifier {
    let url: URL
    let quickLook: HubFilesQuickLook

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                quickLook.setSourceFrame(frame, for: url)
            }
            .onDisappear { quickLook.setSourceFrame(nil, for: url) }
    }
}

extension View {
    /// Marks this view as the on-screen icon of `url` for the Quick Look zoom.
    func hubFilesQuickLookSource(_ url: URL, quickLook: HubFilesQuickLook) -> some View {
        modifier(HubFilesQuickLookSource(url: url, quickLook: quickLook))
    }
}

/// A folder icon for a URL that may not have been listed (tabs, breadcrumbs, the sidebar).
struct HubFilesFolderIcon: View {
    let url: URL?
    let size: CGFloat

    @Environment(\.hubFilesIconSource) private var source

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var icon: NSImage {
        guard let url, source == .live else { return NSWorkspace.shared.icon(for: .folder) }
        return HubThumbnailCache.shared.icon(for: url)
    }
}
