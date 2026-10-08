import SwiftUI

/// One window's card: its thumbnail, or its app's icon when there is none, plus the hover ring
/// and Close button.
///
/// The tile is drawn at whatever size ``HarborView`` gives it, from the window's own desktop size
/// down to grid size, so the corner radius scales with it. The hover area extends past the
/// thumbnail by ``hoverMargin`` so the Close button, which straddles the corner, stays reachable.
struct HarborWindowTile: View {
    /// Half the gap between windows, so neighbouring hover areas meet without overlapping.
    static let hoverMargin: CGFloat = 9

    let title: String
    let appName: String
    let icon: NSImage?
    let thumbnail: CGImage?
    let size: CGSize
    let cornerRadius: CGFloat
    let highlighted: Bool
    let lifted: Bool
    let canClose: Bool
    let reduceMotion: Bool
    let hover: (Bool) -> Void
    let activate: () -> Void
    let close: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var pointerInside = false

    var body: some View {
        thumbnailView
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                // A hairline keeps light window edges from dissolving into a light backdrop.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.black.opacity(0.35), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.34), radius: 24, y: 12)
            .overlay {
                if highlighted {
                    RoundedRectangle(cornerRadius: cornerRadius + 5, style: .continuous)
                        .strokeBorder(colorScheme == .dark ? Color.white : Color.accentColor, lineWidth: 3)
                        .padding(-5)
                        .transition(.opacity)
                }
            }
            .contentShape(.rect)
            .onTapGesture(perform: activate)
            .overlay(alignment: .topLeading) {
                if canClose && pointerInside {
                    HarborCloseButton(action: close)
                        .offset(x: -9, y: -9)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .scaleEffect(lifted && !reduceMotion ? HarborStyle.hoverLift : 1)
            .animation(HarborStyle.hover, value: lifted)
            .animation(.easeOut(duration: 0.15), value: highlighted)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: pointerInside)
            .padding(Self.hoverMargin)
            .contentShape(.rect)
            .onHover { inside in
                pointerInside = inside
                hover(inside)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: title == appName ? title : "\(title), \(appName)"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, activate)
            .accessibilityActions {
                if canClose {
                    Button(action: close) { Text(.harborCloseWindow) }
                }
            }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(decorative: thumbnail, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
        } else {
            HarborWindowPlaceholder(title: title, icon: icon, size: size)
        }
    }
}

/// The caption under a thumbnail: the window title, or the app name for an untitled window, and
/// when the thumbnails are tall enough, a second line saying where the document lives.
struct HarborCaption: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: title)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(height: 17)
            if let subtitle {
                Text(verbatim: subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(height: 15)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityHidden(true)
    }
}

/// Stands in for a window Harbor cannot capture: Screen Recording is off, the content is
/// protected, or the thumbnail has not arrived yet.
struct HarborWindowPlaceholder: View {
    let title: String
    let icon: NSImage?
    let size: CGSize
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let iconSide = min(64, size.height * 0.42, size.width * 0.42)
        ZStack {
            (colorScheme == .dark ? Color(red: 0.16, green: 0.17, blue: 0.20) : Color(red: 0.95, green: 0.95, blue: 0.96))
            VStack(spacing: iconSide * 0.16) {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: iconSide, height: iconSide)
                }
                if size.height > 90 {
                    Text(verbatim: title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                }
            }
        }
    }
}

/// The round Close button on a hovered window. It turns red under the pointer.
struct HarborCloseButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(hovering ? Color(red: 1, green: 0.27, blue: 0.23) : Color(white: 0.16).opacity(0.92)))
                .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(Text(.harborCloseWindow))
        .accessibilityLabel(Text(.harborCloseWindow))
    }
}

#if DEBUG
#Preview("Window tiles") {
    HStack(alignment: .top, spacing: 30) {
        HarborWindowTile(title: "Getting Started – DOKK", appName: "Safari", icon: nil, thumbnail: nil,
                         size: CGSize(width: 240, height: 158), cornerRadius: 8, highlighted: true, lifted: true,
                         canClose: true, reduceMotion: false, hover: { _ in }, activate: {}, close: {})
        HarborWindowTile(title: "Dokumente", appName: "Finder", icon: nil, thumbnail: nil,
                         size: CGSize(width: 200, height: 125), cornerRadius: 7, highlighted: false, lifted: false,
                         canClose: false, reduceMotion: false, hover: { _ in }, activate: {}, close: {})
    }
    .padding(40)
    .background(HarborBackdrop(wallpaper: nil, reduceTransparency: false))
}

#Preview("Captions") {
    VStack(spacing: 16) {
        HarborCaption(title: "Getting Started – DOKK", subtitle: "docs.example/dokk").frame(width: 220)
        HarborCaption(title: "Hausentwurf.pdf", subtitle: "~/Documents/Architecture").frame(width: 160)
        HarborCaption(title: "Ein sehr langer Fenstertitel, der nicht in die Breite passt").frame(width: 160)
    }
    .padding(40)
    .background(HarborBackdrop(wallpaper: nil, reduceTransparency: false))
}
#endif
