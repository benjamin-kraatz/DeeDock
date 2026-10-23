import SwiftUI

/// Shared native artwork for the dock and Settings. App names are always verbatim OS-provided text.
struct DockTooltipArtwork: View {
    let name: String
    var icon: NSImage? = nil
    let preset: DockTooltipPreset
    var edge: DockEdge = .bottom
    var maximumWidth: CGFloat = 240
    var reduceTransparency = false
    /// A Line dock's badge detail: a count beside the name and the latest banner under it.
    var badge: DockTooltipBadge? = nil
    /// A state line under the name, such as "Running in Background", like the system Dock's
    /// two-line tooltip. It takes the place of a badge banner; the badge count stays beside the name.
    var status: String? = nil
    @Environment(\.colorScheme) private var colorScheme

    private var capsule: Bool { [.glassPill, .accent, .trailingPill, .dockCaption].contains(preset) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: capsule ? 100 : 7) }
    private var opaque: Bool { reduceTransparency || [.bold, .outline, .leadingOutline, .dockTitle, .spectrum].contains(preset) }
    private var fontSize: CGFloat { preset == .compact ? 11 : ([.bold, .dockTitle].contains(preset) ? 14 : 12) }
    /// The system Dock centers both lines of its tooltip. Name Card keeps a leading column
    /// beside its icon, where a centered second line would float.
    private var lineAlignment: HorizontalAlignment { preset == .nameCard ? .leading : .center }
    private var accentText: Color {
        let color = NSColor.controlAccentColor.usingColorSpace(.deviceRGB) ?? .systemBlue
        // Choose the larger WCAG contrast ratio against the actual system accent.
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
        return luminance > 0.179 ? .black : .white
    }

    var body: some View {
        if preset != .off {
            HStack(spacing: 6) {
                if preset == .nameCard, let icon { Image(nsImage: icon).resizable().frame(width: 24, height: 24) }
                if preset == .leadingTag { Capsule().fill(.tint).frame(width: 3, height: 16) }
                VStack(alignment: lineAlignment, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(verbatim: name)
                            .font(.system(size: fontSize, weight: fontSize == 14 ? .semibold : .medium))
                            .lineLimit(preset == .nameCard ? 2 : 1)
                            .foregroundStyle(preset == .accent ? accentText : .primary)
                        if let summary = badge?.summary {
                            Text(verbatim: "· \(summary)")
                                .font(.system(size: fontSize, weight: .medium))
                                .lineLimit(1)
                                .foregroundStyle(summaryStyle)
                                .layoutPriority(1)
                        }
                    }
                    if let status {
                        // Two points under the name, like the system tooltip's 13/11 pairing.
                        Text(verbatim: status)
                            .font(.system(size: max(9, fontSize - 2)))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(preset == .accent ? accentText.opacity(0.8) : .secondary)
                    } else if let banner = badge?.banner {
                        Text(verbatim: banner)
                            .font(.system(size: max(10, fontSize - 1)))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(preset == .accent ? accentText.opacity(0.8) : .secondary)
                    }
                }
                .shadow(color: preset == .plain ? (colorScheme == .dark ? Color.black : Color.white) : .clear, radius: 2)
                if preset == .trailingTag { Capsule().fill(.tint).frame(width: 3, height: 16) }
            }
            .padding(.horizontal, [.compact, .leadingOutline].contains(preset) ? 6 : 10)
            .padding(.vertical, [.compact, .leadingOutline].contains(preset) ? 4 : 6)
            .frame(maxWidth: max(1, min(240, maximumWidth)))
            .fixedSize(horizontal: true, vertical: true)
            .background { background }
            .overlay { border }
            .overlay(alignment: tailAlignment) {
                if preset == .speechBubble {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 9)).rotationEffect(tailRotation)
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                        .offset(tailOffset)
                }
            }
            .padding(preset == .speechBubble ? 5 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Red while the badge is news, like the ring; quiet once seen. The accent fill keeps its own contrast.
    private var summaryStyle: Color {
        if preset == .accent { return accentText }
        return badge?.isNew == true ? Color(nsColor: .systemRed) : .secondary
    }

    @ViewBuilder private var background: some View {
        if preset == .accent { shape.fill(Color.accentColor) }
        else if preset != .plain {
            if opaque { shape.fill(Color(nsColor: .windowBackgroundColor)) }
            else { shape.fill(.regularMaterial) }
            if preset == .trailingPill { shape.fill(Color.accentColor.opacity(reduceTransparency ? 0 : 0.15)) }
        }
    }
    @ViewBuilder private var border: some View {
        switch preset {
        case .glassPill: shape.strokeBorder(.primary.opacity(0.2), lineWidth: 0.5)
        case .outline, .leadingOutline: shape.strokeBorder(.primary, lineWidth: 1)
        case .pop, .trailingPill: shape.strokeBorder(.tint, lineWidth: 1)
        case .spectrum: shape.strokeBorder(LinearGradient(colors: [.pink, .purple, .blue, .mint], startPoint: .leading, endPoint: .trailing), lineWidth: 2)
        default: EmptyView()
        }
    }
    private var tailAlignment: Alignment {
        switch edge { case .bottom: .bottom; case .top: .top; case .left: .leading; case .right: .trailing }
    }
    private var tailRotation: Angle {
        .degrees(edge == .bottom ? 180 : edge == .left ? -90 : edge == .right ? 90 : 0)
    }
    private var tailOffset: CGSize {
        switch edge { case .bottom: CGSize(width: 0, height: 5); case .top: CGSize(width: 0, height: -5)
        case .left: CGSize(width: -5, height: 0); case .right: CGSize(width: 5, height: 0) }
    }
}

#if DEBUG
/// Every preset with the plain name, the status line, the status beside a badge count, and the
/// longer German status at the narrowest width a small dock offers, so truncation shows.
private struct DockTooltipStatusGallery: View {
    let scheme: ColorScheme
    var reduceTransparency = false
    private let english = String(localized: .appTooltipRunningInBackground)
    private let german = "Im Hintergrund ausgeführt"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(DockTooltipPreset.allCases.filter { $0 != .off }, id: \.self) { preset in
                    HStack(spacing: 16) {
                        DockTooltipArtwork(name: "Cursor", preset: preset, reduceTransparency: reduceTransparency)
                        DockTooltipArtwork(name: "Cursor", icon: NSImage(systemSymbolName: "cursorarrow.rays",
                                                                         accessibilityDescription: nil),
                                           preset: preset, reduceTransparency: reduceTransparency, status: english)
                        DockTooltipArtwork(name: "Cursor", preset: preset, reduceTransparency: reduceTransparency,
                                           badge: DockTooltipBadge(summary: "2", isNew: false, banner: "Build finished"),
                                           status: english)
                        DockTooltipArtwork(name: "Cursor", preset: preset, maximumWidth: 120,
                                           reduceTransparency: reduceTransparency, status: german)
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 760, height: 720)
        .background(LinearGradient(colors: [.blue.opacity(0.6), .indigo.opacity(0.4)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .preferredColorScheme(scheme)
    }
}

#Preview("Running in Background line, dark") { DockTooltipStatusGallery(scheme: .dark) }
#Preview("Running in Background line, light") { DockTooltipStatusGallery(scheme: .light) }
#Preview("Running in Background line, Reduce Transparency") {
    DockTooltipStatusGallery(scheme: .dark, reduceTransparency: true)
}

/// Each edge's speech-bubble tail stays on the icon side under a two-line label.
#Preview("Two lines, every edge") {
    HStack(spacing: 24) {
        ForEach([DockEdge.bottom, .top, .left, .right], id: \.self) { edge in
            DockTooltipArtwork(name: "Cursor", preset: .speechBubble, edge: edge,
                               status: String(localized: .appTooltipRunningInBackground))
        }
    }
    .padding(24)
}
#endif
