import SwiftUI

/// The Ice Blocks background: one block per dock section, sized from the same magnified
/// geometry as the icons so a block stretches with the items it encloses.
struct DockIceBlocksBackground<Chrome: View>: View {
    let blocks: [DockIceBlock]
    let layout: DockGeometry.Layout
    let sizes: [CGFloat]
    let centers: [CGFloat]
    /// Requested radius; each block caps it to its own bounds.
    let cornerRadius: CGFloat
    let reduceTransparency: Bool
    /// Experiment: live capture of what is behind the dock. Read here, so a new frame redraws
    /// the blocks and nothing else.
    var backdrop: DockIceBackdrop? = nil
    /// Decoration laid over every block, given that block's effective corner radius.
    @ViewBuilder var chrome: (CGFloat) -> Chrome

    var body: some View {
        if blocks.isEmpty {
            block(role: .utility, frame: layout.iceFrame(surface: sizes))
        }
        ForEach(blocks) { item in
            if let frame = layout.iceBlockFrame(item.range, centers: centers, sizes: sizes) {
                block(role: item.role, frame: frame)
            }
        }
    }

    private func block(role: DockIceBlockRole, frame: CGRect) -> some View {
        let radius = min(cornerRadius, min(frame.width, frame.height) / 2)
        return DockIceBlockView(tint: role.tint, cornerRadius: radius, edge: layout.edge,
                                reduceTransparency: reduceTransparency, lightBar: role == .drives,
                                backdrop: backdrop?.frame)
            .overlay { chrome(radius) }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Ice blocks dock") {
    var settings = DockSettings.defaults
    settings.surfaceStyle = .iceBlocks
    return DockPreviewContent(settings: settings, showsLauncher: true)
        .background(.black)
        .preferredColorScheme(.dark)
}

#Preview("Ice blocks dock, reduced transparency, left edge") {
    var settings = DockSettings.defaults
    settings.surfaceStyle = .iceBlocks
    settings.edge = .left
    return DockPreviewContent(reduceMotion: true, reduceTransparency: true, settings: settings, showsLauncher: true)
}
#endif
