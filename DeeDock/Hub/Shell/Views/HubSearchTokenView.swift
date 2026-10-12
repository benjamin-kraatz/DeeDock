import SwiftUI

/// The token before the search field's text (the mockup's `.tok`): an 18 pt thumbnail, the name, and ✕. It pops in
/// with a short spring (`tokin`: from 0.6 scale), or fades under Reduce Motion.
///
/// VoiceOver reads it as one element named by `token.accessibilityLabel`, with a Remove action; ✕ is its own button.
struct HubSearchTokenView: View {
    let token: HubSearchToken
    let reduceMotion: Bool
    let remove: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var shown = false

    var body: some View {
        let accent = LookoutTheme(scheme).accent
        HStack(spacing: 6) {
            HubSearchTokenThumbnail(token: token)
            Text(verbatim: token.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .contentShape(.circle)
            }
            .buttonStyle(HubSearchTokenRemoveStyle())
            .help(Text(.lookoutPictureRemove))
            .accessibilityLabel(Text(.lookoutPictureRemove))
        }
        .padding(.leading, 2)
        .padding(.trailing, 4)
        .frame(height: 22)
        .frame(maxWidth: 190, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .background(LookoutTheme(scheme).accentSoft, in: .rect(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(accent.opacity(0.55), lineWidth: 0.5)
        }
        .scaleEffect(shown || reduceMotion ? 1 : 0.6)
        .opacity(shown ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.34, dampingFraction: 0.62)) {
                shown = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: token.accessibilityLabel))
        .accessibilityAction(named: Text(.lookoutPictureRemove), remove)
    }
}

/// The token's 18 pt picture: a pasted picture's pixels, else the file's Quick Look thumbnail, its icon meanwhile.
private struct HubSearchTokenThumbnail: View {
    let token: HubSearchToken

    @Environment(\.displayScale) private var scale
    @State private var thumbnail: NSImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        Group {
            if let image = token.image ?? thumbnail {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else if let url = token.fileURL {
                Image(nsImage: HubThumbnailCache.shared.icon(for: url)).resizable()
            } else {
                Image(systemName: "photo").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5) }
        .task(id: token.fileURL) {
            thumbnail = nil
            guard token.image == nil, let url = token.fileURL, !HostEnvironment.isPreview else { return }
            let image = await HubThumbnailCache.shared.thumbnail(for: url, size: CGSize(width: 18, height: 18),
                                                                 scale: scale)
            guard !Task.isCancelled else { return }
            thumbnail = image
        }
        .accessibilityHidden(true)
    }
}

/// ✕ inside the token: a quiet circle that fills on hover.
private struct HubSearchTokenRemoveStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hovered ? .primary : .secondary)
            .background(Color.primary.opacity(hovered || configuration.isPressed ? 0.12 : 0), in: .circle)
            .onHover { hovered = $0 }
    }
}

#Preview("Token") {
    VStack(alignment: .leading, spacing: 10) {
        HubSearchTokenView(token: HubSearchToken(id: UUID(), title: "IMG_5012.HEIC", fileURL: nil, image: nil,
                                                 accessibilityLabel: "Picture: IMG_5012.HEIC"),
                           reduceMotion: false) {}
        HubSearchTokenView(token: HubSearchToken(id: UUID(), title: "Screenshot 2026-10-11 at 18.40.02.png",
                                                 fileURL: nil, image: nil,
                                                 accessibilityLabel: "Picture: Screenshot"),
                           reduceMotion: true) {}
    }
    .padding(20)
    .background(.regularMaterial)
}
