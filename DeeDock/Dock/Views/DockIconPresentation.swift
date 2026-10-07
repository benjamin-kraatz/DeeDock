import SwiftUI

/// Upright artwork with a running-state decoration and an independent keyboard-selection outline.
///
/// Most tiles draw an `NSImage`, but Session Capsules draw a vector mark, so the artwork is generic
/// and the `icon:` initializer is the convenience for the common case.
///
/// A non-nil `lineIcon` replaces the artwork with a white glyph that glows while the tile is hovered
/// or keyboard-selected. Tiles pass one only when their dock uses ``DockIconStyle/line``.
///
/// A line tile with a badge source (a non-nil `badgeAttention`) draws ``DockBadgeRing`` instead of
/// the corner badge: the ring shows while the badge is news, and the glyph plays its motion as
/// the news arrives.
struct DockIconPresentation<Artwork: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dockTileHovered) private var hovered
    @Environment(\.pinWeatherSample) private var pinWeatherSample
    let artwork: Artwork
    let size: CGFloat
    let edge: DockEdge
    let available: Bool
    let running: Bool
    let launching: Bool
    let keyboardSelected: Bool
    var runningIndicatorStyle: DockSettings.RunningIndicatorStyle = .dot
    /// Per-application variation; only Stardust reads it.
    var indicatorVariant: DockIndicatorVariant = .neutral
    /// Whether Stardust may twinkle right now.
    var indicatorAnimated = false

    /// Applied only to artwork, preserving focus/launch feedback and the button hit region.
    var artworkOpacity: Double = 1
    var artworkAnimation: Animation? = nil
    var badgeLabel: String? = nil
    var badgeStyle: DockAppBadge.Style = .dot
    /// Whether the badge is news; nil for a tile without a badge source. Read only by line tiles.
    var badgeAttention: Bool? = nil
    var launchAnimation = DockSettings.defaults.launchAnimation
    var launchRequest: Date? = nil
    var launchMotionEnabled = true
    var lineIcon: DockLineIcon? = nil

    init(size: CGFloat, edge: DockEdge, available: Bool, running: Bool, launching: Bool,
         keyboardSelected: Bool, runningIndicatorStyle: DockSettings.RunningIndicatorStyle = .dot,
         indicatorVariant: DockIndicatorVariant = .neutral, indicatorAnimated: Bool = false,
         artworkOpacity: Double = 1, artworkAnimation: Animation? = nil, badgeLabel: String? = nil,
         badgeStyle: DockAppBadge.Style = .dot, badgeAttention: Bool? = nil,
         launchAnimation: DockLaunchAnimation = DockSettings.defaults.launchAnimation,
         launchRequest: Date? = nil, launchMotionEnabled: Bool = true, lineIcon: DockLineIcon? = nil,
         @ViewBuilder artwork: () -> Artwork) {
        self.artwork = artwork()
        self.size = size
        self.edge = edge
        self.available = available
        self.running = running
        self.launching = launching
        self.keyboardSelected = keyboardSelected
        self.runningIndicatorStyle = runningIndicatorStyle
        self.indicatorVariant = indicatorVariant
        self.indicatorAnimated = indicatorAnimated
        self.artworkOpacity = artworkOpacity
        self.artworkAnimation = artworkAnimation
        self.badgeLabel = badgeLabel
        self.badgeStyle = badgeStyle
        self.badgeAttention = badgeAttention
        self.launchAnimation = launchAnimation
        self.launchRequest = launchRequest
        self.launchMotionEnabled = launchMotionEnabled
        self.lineIcon = lineIcon
    }

    /// Line tiles announce badges with a ring rather than the corner mark.
    private var showsBadgeRing: Bool { lineIcon != nil && badgeAttention != nil }

    @ViewBuilder private var styledArtwork: some View {
        if let lineIcon {
            DockLineIconArtwork(icon: lineIcon, size: size, hovered: hovered || keyboardSelected,
                                reduceMotion: reduceMotion, reduceTransparency: reduceTransparency,
                                attention: badgeAttention == true ? badgeLabel ?? "" : nil)
        } else {
            artwork
        }
    }

    var body: some View {
        let depth = size + DockGeometry.indicatorAreaDepth
        let bounds = edge.size(length: size, depth: depth)
        let iconCenter = edge.point(CGPoint(x: size / 2, y: size / 2), depth: depth)
        let marker = edge.point(CGPoint(x: size / 2,
            y: size + DockGeometry.indicatorSpacing + DockGeometry.indicatorSize / 2), depth: depth)
        ZStack(alignment: .topLeading) {
            styledArtwork
                .frame(width: size, height: size)
                .opacity(available ? 1 : 0.4)
                .modifier(PinWeatherChrome(sample: pinWeatherSample))
                .modifier(DockIconIndicator(style: runningIndicatorStyle, running: running, size: size,
                                            variant: indicatorVariant, animated: indicatorAnimated))
                .overlay {
                    // Inside the launch motion and idle fade, so the ring moves and fades with its glyph.
                    if showsBadgeRing {
                        DockBadgeRing(active: badgeAttention == true, size: size,
                                      highlighted: hovered || keyboardSelected,
                                      reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
                    }
                }
                .animation(artworkAnimation) { $0.opacity(artworkOpacity) }
                .modifier(DockLaunchMotion(style: launchAnimation, request: launchRequest, busy: launching,
                                           enabled: launchMotionEnabled, edge: edge, size: size))
                .overlay {
                    if keyboardSelected {
                        RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                    if launching && (launchRequest == nil || launchAnimation == .none || reduceMotion) {
                        Circle().fill(.black.opacity(0.14))
                        ProgressView().controlSize(.small).padding(8).glassEffect(.clear)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if launching && launchRequest != nil && launchAnimation != .none && !reduceMotion {
                        ProgressView().controlSize(.mini).padding(3).glassEffect(.clear)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let badgeLabel, !showsBadgeRing {
                        DockAppBadge(label: badgeLabel, iconSize: size, style: badgeStyle)
                            .animation(artworkAnimation) { $0.opacity(artworkOpacity) }
                    }
                }
                .position(iconCenter)
            if running {
                DockRunningIndicator(style: runningIndicatorStyle, edge: edge)
                    .animation(artworkAnimation) { $0.opacity(artworkOpacity) }
                    .position(marker)
            }
        }
        .frame(width: bounds.width, height: bounds.height)
    }
}

extension DockIconPresentation where Artwork == Image {
    init(icon: NSImage, size: CGFloat, edge: DockEdge, available: Bool, running: Bool, launching: Bool,
         keyboardSelected: Bool, runningIndicatorStyle: DockSettings.RunningIndicatorStyle = .dot,
         indicatorVariant: DockIndicatorVariant = .neutral, indicatorAnimated: Bool = false,
         artworkOpacity: Double = 1, artworkAnimation: Animation? = nil, badgeLabel: String? = nil,
         badgeStyle: DockAppBadge.Style = .dot, badgeAttention: Bool? = nil,
         launchAnimation: DockLaunchAnimation = DockSettings.defaults.launchAnimation,
         launchRequest: Date? = nil, launchMotionEnabled: Bool = true, lineIcon: DockLineIcon? = nil) {
        self.init(size: size, edge: edge, available: available, running: running, launching: launching,
                  keyboardSelected: keyboardSelected, runningIndicatorStyle: runningIndicatorStyle,
                  indicatorVariant: indicatorVariant, indicatorAnimated: indicatorAnimated,
                  artworkOpacity: artworkOpacity, artworkAnimation: artworkAnimation, badgeLabel: badgeLabel,
                  badgeStyle: badgeStyle, badgeAttention: badgeAttention,
                  launchAnimation: launchAnimation, launchRequest: launchRequest, launchMotionEnabled: launchMotionEnabled,
                  lineIcon: lineIcon) {
            Image(nsImage: icon).resizable().interpolation(.high)
        }
    }
}
