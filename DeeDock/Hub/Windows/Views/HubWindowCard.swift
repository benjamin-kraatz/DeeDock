import SwiftUI

/// Sizes for window cards, shared by the cards and the thumbnail capture budget.
nonisolated enum HubWindowCardMetrics {
    static let thumbnailSize = CGSize(width: 200, height: 124)
    static let thumbnailRadius: CGFloat = 10
    static let titleSpacing: CGFloat = 7
}

/// One window: its thumbnail (or app icon), title, and Minimized/Hidden badge.
///
/// Hovering lifts the thumbnail and rings it in the accent color; keyboard selection shows the
/// same ring. Minimized windows are dimmed. A press settles the card; clicking activates the window.
struct HubWindowCard: View {
    let item: HubWindowItem
    let appName: String
    let icon: NSImage?
    let thumbnail: CGImage?
    let isSelected: Bool
    let reduceMotion: Bool
    var previewControl: WindowPreviewControl? = nil
    var previewUnavailable = false
    let activate: () -> Void

    @State private var isHovered = false

    private var title: String {
        guard let title = item.window.title, !title.isEmpty else { return appName }
        return title
    }

    var body: some View {
        Button(action: activate) {
            VStack(alignment: .leading, spacing: HubWindowCardMetrics.titleSpacing) {
                HubWindowThumbnail(thumbnail: thumbnail, icon: icon, badge: badge, dimmed: item.isMinimized,
                                   ringed: isHovered || isSelected, lifted: isHovered && !reduceMotion,
                                   covered: previewControl?.isRevealed == false, unavailable: previewUnavailable)
                Text(verbatim: title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 1)
            }
            .frame(width: HubWindowCardMetrics.thumbnailSize.width, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.hubPress(scale: 0.97))
        .focusable(false)
        .onHover { isHovered = $0 }
        .animation(HubStyle.hover, value: isHovered)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title == appName ? title : "\(title), \(appName)"))
        .accessibilityValue(badge.map { Text($0) } ?? (previewUnavailable ? Text(.windowPreviewUnavailable) : Text(verbatim: "")))
        .accessibilityHint(Text(.hubWindowsActivateHint))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, activate)
        .overlay(alignment: .top) {
            if let previewControl {
                WindowPreviewControls(control: previewControl)
                    .frame(width: HubWindowCardMetrics.thumbnailSize.width,
                           height: HubWindowCardMetrics.thumbnailSize.height)
                    .scaleEffect(isHovered && !reduceMotion ? 1.02 : 1)
                    .offset(y: isHovered && !reduceMotion ? -3 : 0)
            }
        }
    }

    private var badge: LocalizedStringResource? {
        switch item.window.state {
        case .visible: nil
        case .minimized: .hubWindowsMinimized
        case .hidden: .hubWindowsHidden
        }
    }
}

/// The 200×124 thumbnail well of a window card.
private struct HubWindowThumbnail: View {
    let thumbnail: CGImage?
    let icon: NSImage?
    let badge: LocalizedStringResource?
    let dimmed: Bool
    let ringed: Bool
    let lifted: Bool
    let covered: Bool
    let unavailable: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: HubWindowCardMetrics.thumbnailRadius, style: .continuous)
    }

    var body: some View {
        content
            .frame(width: HubWindowCardMetrics.thumbnailSize.width, height: HubWindowCardMetrics.thumbnailSize.height)
            .opacity(dimmed ? 0.55 : 1)
            .saturation(dimmed ? 0.5 : 1)
            .clipShape(shape)
            .overlay(alignment: .bottomTrailing) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(6)
                }
            }
            .overlay {
                shape.strokeBorder(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.12),
                                   lineWidth: 0.5)
            }
            .overlay {
                if ringed {
                    // Outside the hairline, like the mockup's 2 pt box-shadow ring.
                    RoundedRectangle(cornerRadius: HubWindowCardMetrics.thumbnailRadius + 2, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .padding(-2)
                        .transition(.opacity)
                }
            }
            .shadow(color: .black.opacity(ringed ? 0.3 : 0.22), radius: ringed ? 13 : 9, y: ringed ? 12 : 6)
            .scaleEffect(lifted ? 1.02 : 1)
            .offset(y: lifted ? -3 : 0)
    }

    @ViewBuilder
    private var content: some View {
        if let thumbnail {
            // Fill and crop from the top: the title bar and toolbar identify a window best.
            Image(decorative: thumbnail, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: HubWindowCardMetrics.thumbnailSize.width,
                       height: HubWindowCardMetrics.thumbnailSize.height, alignment: .top)
                .transition(.identity)
        } else {
            WindowPreviewPlaceholder(icon: icon, covered: covered, unavailable: unavailable)
        }
    }
}
