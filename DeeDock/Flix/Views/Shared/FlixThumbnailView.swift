import SwiftUI

/// A row's picture: a Quick Look thumbnail for pictures and documents the read policy allows,
/// otherwise the file's or type's icon. A sensitive item is blurred under a lock.
///
/// The thumbnail loads in a task tied to the view, so a row scrolled away cancels its render.
struct FlixThumbnailView: View {
    let item: FlixItem
    var size: CGFloat = FlixStyle.iconSize
    var policy: FlixReadPolicy
    var sensitive = false

    @State private var thumbnail: NSImage?
    @Environment(\.displayScale) private var scale

    private var wantsThumbnail: Bool {
        switch item.kind {
        case .image, .screenshot, .document: true
        case .folder, .app, .link, .other: false
        }
    }

    var body: some View {
        ZStack {
            if let thumbnail, wantsThumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
            } else {
                Image(nsImage: FlixIconProvider.icon(for: item, policy: policy))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .blur(radius: sensitive ? 4 : 0)
        .overlay {
            if sensitive {
                Image(systemName: "lock.fill")
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
        }
        .accessibilityHidden(true)
        .task(id: item.path) {
            guard wantsThumbnail, let url = item.url, let path = item.path, policy.canRead(path) else { return }
            thumbnail = await HubThumbnailCache.shared.thumbnail(for: url, size: CGSize(width: size, height: size),
                                                                 scale: scale)
        }
    }
}
