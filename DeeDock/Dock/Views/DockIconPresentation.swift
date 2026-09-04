import SwiftUI

/// Upright artwork with a running-state decoration and an independent keyboard-selection outline.
///
/// Most tiles draw an `NSImage`, but Session Capsules draw a vector mark, so the artwork is generic
/// and the `icon:` initializer is the convenience for the common case.
struct DockIconPresentation<Artwork: View>: View {
    let artwork: Artwork
    let size: CGFloat
    let edge: DockEdge
    let available: Bool
    let running: Bool
    let launching: Bool
    let keyboardSelected: Bool
    var runningIndicatorStyle: DockSettings.RunningIndicatorStyle = .dot
    /// Per-application shader variation; the drawn indicator styles ignore it.
    var indicatorVariant: DockIndicatorVariant = .neutral
    /// Whether the shader indicators may animate right now.
    var indicatorAnimated = false

    /// Applied only to artwork, preserving focus/launch feedback and the button hit region.
    var artworkOpacity: Double = 1
    var artworkAnimation: Animation? = nil

    init(size: CGFloat, edge: DockEdge, available: Bool, running: Bool, launching: Bool,
         keyboardSelected: Bool, runningIndicatorStyle: DockSettings.RunningIndicatorStyle = .dot,
         indicatorVariant: DockIndicatorVariant = .neutral, indicatorAnimated: Bool = false,
         artworkOpacity: Double = 1, artworkAnimation: Animation? = nil,
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
    }

    var body: some View {
        let depth = size + DockGeometry.indicatorAreaDepth
        let bounds = edge.size(length: size, depth: depth)
        let iconCenter = edge.point(CGPoint(x: size / 2, y: size / 2), depth: depth)
        let marker = edge.point(CGPoint(x: size / 2,
            y: size + DockGeometry.indicatorSpacing + DockGeometry.indicatorSize / 2), depth: depth)
        ZStack(alignment: .topLeading) {
            artwork
                .frame(width: size, height: size)
                .opacity(available ? 1 : 0.4)
                .modifier(DockIconIndicator(style: runningIndicatorStyle, running: running, size: size,
                                            variant: indicatorVariant, animated: indicatorAnimated))
                .animation(artworkAnimation) { $0.opacity(artworkOpacity) }
                .overlay {
                    if keyboardSelected {
                        RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                    if launching {
                        Circle().fill(.black.opacity(0.14))
                        ProgressView().controlSize(.small).padding(8).glassEffect(.clear)
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
         artworkOpacity: Double = 1, artworkAnimation: Animation? = nil) {
        self.init(size: size, edge: edge, available: available, running: running, launching: launching,
                  keyboardSelected: keyboardSelected, runningIndicatorStyle: runningIndicatorStyle,
                  indicatorVariant: indicatorVariant, indicatorAnimated: indicatorAnimated,
                  artworkOpacity: artworkOpacity, artworkAnimation: artworkAnimation) {
            Image(nsImage: icon).resizable().interpolation(.high)
        }
    }
}
