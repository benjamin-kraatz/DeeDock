import SwiftUI
import UniformTypeIdentifiers

/// A Lookout hit's square thumbnail (the mockup's `.thumb`): the file's icon at once, then its Quick Look thumbnail
/// from `HubThumbnailCache` once rendered. Pictures and screenshots fill the rounded square; pages and documents fit
/// inside it on a quiet backdrop so a portrait page isn't cropped. When Quick Look has nothing, the icon stays, drawn
/// without a frame.
///
/// The render runs off the main actor and is cancelled when the row goes away or shows another file. Previews
/// (`.typeOnly` icon source) never read the file.
struct LookoutThumbnail: View {
    let item: HubFileItem
    let kind: LookoutHitKind
    var size: CGFloat = 58
    /// The corner radius; a row's 9 pt at 58 pt, scaled, unless given.
    var cornerRadius: CGFloat?

    @Environment(\.hubFilesIconSource) private var source
    @Environment(\.displayScale) private var scale
    @Environment(\.colorScheme) private var scheme
    @State private var thumbnail: NSImage?

    private var radius: CGFloat { cornerRadius ?? size * 9 / 58 }

    var body: some View {
        ZStack {
            if let thumbnail {
                framed(thumbnail)
                    .transition(.opacity)
            } else {
                HubFilesItemIcon(item: item, size: size)
            }
        }
        .frame(width: size, height: size)
        .animation(HubFilesMotion.quick, value: thumbnail != nil)
        .task(id: key) { await load() }
        .accessibilityHidden(true)
    }

    private func framed(_ image: NSImage) -> some View {
        let fills: Bool = switch kind {
        case .picture, .screenshot: true
        default: false
        }
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: fills ? .fill : .fit)
            .padding(fills ? 0 : size * 0.08)
            .frame(width: size, height: size)
            .background(HubFilesTheme(scheme).chip)
            .clipShape(shape)
            .overlay { shape.strokeBorder(LookoutTheme(scheme).strongLine, lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }

    private var key: String? {
        guard source == .live, !item.isDirectory else { return nil }
        return "\(item.url.path)|\(item.modified?.timeIntervalSince1970 ?? 0)|\(size)"
    }

    private func load() async {
        guard key != nil else { thumbnail = nil; return }
        let cache = HubThumbnailCache.shared
        let image = await cache.thumbnail(for: item.url, size: CGSize(width: size, height: size), scale: scale)
        guard !Task.isCancelled else { return }
        // The cache answers with the workspace icon itself when Quick Look can't render: keep the plain icon then.
        thumbnail = image === cache.icon(for: item.url) ? nil : image
    }
}

/// A folder hit's fanned stack of three of its best files (the mockup's `.stack`), each a small `LookoutThumbnail`.
struct LookoutFolderStack: View {
    /// Up to three of the folder's best files, best first.
    let files: [HubFileItem]
    var size: CGFloat = 58

    /// Each card's (x, y) offset and rotation, from the mockup: left one tilted back, right one forward.
    private static let placements: [(x: CGFloat, y: CGFloat, degrees: Double)] = [(0, 10, -8), (8, 6, 2), (14, 2, 9)]

    var body: some View {
        let card = size * 44 / 58
        let scale = size / 58
        ZStack(alignment: .topLeading) {
            if files.isEmpty {
                HubFilesFolderIcon(url: nil, size: size)
            }
            ForEach(Array(files.prefix(3).enumerated()), id: \.element.id) { index, file in
                let placement = Self.placements[index]
                LookoutThumbnail(item: file, kind: LookoutHitKind(fileNamed: file.name), size: card)
                    .rotationEffect(.degrees(placement.degrees))
                    .offset(x: placement.x * scale, y: placement.y * scale)
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

extension LookoutHitKind {
    /// A rough kind from a file name alone, for the folder stack's thumbnails (it only decides fill or fit).
    init(fileNamed name: String) {
        let type = UTType(filenameExtension: (name as NSString).pathExtension)
        if type?.conforms(to: .image) == true {
            self = .picture
        } else if type?.conforms(to: .pdf) == true {
            self = .pdf(page: nil)
        } else {
            self = .document
        }
    }
}

#Preview("Thumbnails") {
    HStack(spacing: 18) {
        LookoutThumbnail(item: LookoutPreviewData.beach.fileItem, kind: .picture)
        LookoutThumbnail(item: LookoutPreviewData.lease.fileItem, kind: .pdf(page: 7))
        LookoutFolderStack(files: LookoutPreviewData.sylt.topFileItems)
    }
    .padding(24)
    .background(.regularMaterial)
    .environment(\.hubFilesIconSource, .typeOnly)
}
