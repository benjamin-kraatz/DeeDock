import SwiftUI

/// The picture searched with, as the results bar and "Why it matched" draw it: a pasted picture's own pixels, or the
/// file's Quick Look thumbnail (`LookoutThumbnail`), filling a rounded square. A document searched with (Find Similar
/// on a PDF) shows its page fitted inside.
struct LookoutPictureThumbnail: View {
    let picture: LookoutPictureQuery
    var size: CGFloat = 46

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 8 / 46, style: .continuous)
        Group {
            if let image = picture.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(LookoutTheme(scheme).strongLine, lineWidth: 0.5) }
            } else if let url = picture.fileURL {
                let item = HubFileItem.lookout(path: url.path, isFolder: false, size: nil, modified: nil)
                LookoutThumbnail(item: item, kind: LookoutHitKind(fileNamed: item.name), size: size)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
                    .background(HubFilesTheme(scheme).chip, in: shape)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
