import SwiftUI

/// A miniature dock with one sample app and its name, placed by the dock's tooltip geometry.
///
/// The label uses the production renderer at full size so it stays readable; only the dock strip
/// is scaled down. The sample icon's slot depends on the preset's placement so a before, after, or
/// dock-centred label has room to show where it goes. `DockTooltipGeometry` still decides the
/// final frame, including its fallback to the inward position when a narrow card has no room.
struct DockTooltipPresetThumbnail: View {
    let preset: DockTooltipPreset
    let phase: DockTooltipPresetPlayback.Phase
    let edge: DockEdge
    let reduceMotion: Bool
    let reduceTransparency: Bool
    @State private var measured = CGSize(width: 96, height: 26)

    var body: some View {
        GeometryReader { proxy in
            let scene = DockTooltipThumbnailScene(size: proxy.size, edge: edge, placement: preset.placement)
            let frame = DockTooltipGeometry.frame(size: measured, icon: scene.sample, dock: scene.dock,
                                                  region: scene.region, edge: edge, placement: preset.placement)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(.secondary.opacity(0.12))
                    .frame(width: scene.dock.width, height: scene.dock.height)
                    .position(x: scene.dock.midX, y: scene.dock.midY)
                ForEach(scene.placeholders.indices, id: \.self) { index in
                    let slot = scene.placeholders[index]
                    RoundedRectangle(cornerRadius: 5).fill(.secondary.opacity(0.22))
                        .frame(width: slot.width, height: slot.height)
                        .position(x: slot.midX, y: slot.midY)
                }
                RoundedRectangle(cornerRadius: 5).fill(.indigo.gradient)
                    .overlay(Image(systemName: "paperplane.fill").font(.system(size: 10)).foregroundStyle(.white))
                    .frame(width: scene.sample.width, height: scene.sample.height)
                    .position(x: scene.sample.midX, y: scene.sample.midY)
                // Mirrors `DockTooltipsOverlay`: the label is absent during the delay and inserted with
                // the preset's transition inside the animation the playback model reveals it with.
                if phase != .waiting {
                    DockTooltipArtwork(name: String(localized: .tooltipSampleApp),
                        icon: NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: nil),
                        preset: preset, edge: edge, maximumWidth: max(1, scene.region.width - 16),
                        reduceTransparency: reduceTransparency)
                        .onGeometryChange(for: CGSize.self) { $0.size } action: {
                            if measured != $0 { measured = $0 }
                        }
                        .frame(width: frame.width, height: frame.height).clipped()
                        .position(x: frame.midX, y: frame.midY)
                        .transition(preset.transition(edge: edge, reduceMotion: reduceMotion))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

/// Thumbnail geometry in top-left coordinates, laid out canonically for a bottom dock and then
/// mapped to `edge` with `DockEdge.rect`, like the dock and the Settings live preview.
private struct DockTooltipThumbnailScene {
    let dock: CGRect
    let sample: CGRect
    let placeholders: [CGRect]
    /// The inward band the label may occupy, matching the dock's callout region.
    let region: CGRect

    init(size: CGSize, edge: DockEdge, placement: DockTooltipPreset.Placement) {
        let length = edge.length(of: size), depth = edge.depth(of: size)
        let icon: CGFloat = 20, spacing: CGFloat = 5, inset: CGFloat = 5, margin: CGFloat = 3
        let count = max(3, min(5, Int((length - 2 * inset + spacing) / (icon + spacing))))
        let stripLength = CGFloat(count) * icon + CGFloat(count - 1) * spacing + 2 * inset
        let stripDepth = icon + 2 * inset
        let strip = CGRect(x: (length - stripLength) / 2, y: depth - margin - stripDepth,
                           width: stripLength, height: stripDepth)
        // Before needs room ahead of the icon, after needs room behind it, and a dock-centred label
        // only reads as centred when the pointed-at icon is not in the middle.
        let sampleIndex = switch placement {
        case .inward: count / 2
        case .before, .dockCenter: count - 1
        case .after: 0
        }
        let slots = (0..<count).map { index in
            edge.rect(CGRect(x: strip.minX + inset + CGFloat(index) * (icon + spacing), y: strip.minY + inset,
                             width: icon, height: icon), depth: depth)
        }
        dock = edge.rect(strip, depth: depth)
        sample = slots[sampleIndex]
        placeholders = slots.enumerated().filter { $0.offset != sampleIndex }.map(\.element)
        region = edge.rect(CGRect(x: 0, y: 0, width: length, height: max(1, strip.minY - margin)), depth: depth)
    }
}

#if DEBUG
/// Every placement on every edge, at rest and while waiting for the hover delay.
#Preview("Thumbnail placements, every edge") {
    Grid(horizontalSpacing: 12, verticalSpacing: 12) {
        ForEach(DockEdge.allCases, id: \.self) { edge in
            GridRow {
                ForEach([DockTooltipPreset.speechBubble, .leadingTag, .trailingPill, .dockCaption], id: \.self) { preset in
                    DockTooltipPresetThumbnail(preset: preset, phase: .idle, edge: edge,
                                               reduceMotion: false, reduceTransparency: false)
                        .frame(width: 170, height: 86)
                        .background(.background.secondary, in: .rect(cornerRadius: 8))
                }
                DockTooltipPresetThumbnail(preset: .speechBubble, phase: .waiting, edge: edge,
                                           reduceMotion: false, reduceTransparency: false)
                    .frame(width: 170, height: 86)
                    .background(.background.secondary, in: .rect(cornerRadius: 8))
            }
        }
    }
    .padding(16)
}
#endif
