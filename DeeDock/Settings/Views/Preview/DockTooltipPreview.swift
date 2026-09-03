import SwiftUI

/// Inert sample of placement and entrance timing. Playback owns and cancels its scheduled dismissal.
struct DockTooltipPreview: View {
    let preset: DockTooltipPreset
    let edge: DockEdge
    let reduceMotion: Bool
    let reduceTransparency: Bool
    @State private var controller = DockTooltipController()
    @State private var playing = false
    @State private var dismissal: DockScheduledAction?
    @State private var measured = CGSize(width: 130, height: 30)
    private let sampleID = DockEntryID.app("tooltip-preview")

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { proxy in
                let bounds = CGRect(origin: .zero, size: proxy.size)
                let center = edge.point(CGPoint(x: edge.length(of: proxy.size) / 2, y: edge.depth(of: proxy.size) - 34), depth: edge.depth(of: proxy.size))
                let icon = CGRect(x: center.x - 22, y: center.y - 22, width: 44, height: 44)
                let dock = edge.rect(CGRect(x: edge.length(of: proxy.size) / 2 - 70,
                    y: edge.depth(of: proxy.size) - 62, width: 140, height: 56), depth: edge.depth(of: proxy.size))
                let region = edge.rect(CGRect(x: 0, y: 0, width: edge.length(of: proxy.size), height: max(1, edge.depth(of: proxy.size) - 72)), depth: edge.depth(of: proxy.size))
                let frame = DockTooltipGeometry.frame(size: measured, icon: icon, dock: dock, region: region, edge: edge, placement: preset.placement)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12).fill(.secondary.opacity(0.12))
                        .frame(width: dock.width, height: dock.height).position(x: dock.midX, y: dock.midY)
                    RoundedRectangle(cornerRadius: 9).fill(.indigo.gradient)
                        .overlay(Image(systemName: "paperplane.fill").foregroundStyle(.white).font(.title2))
                        .frame(width: 44, height: 44).position(center)
                    if !playing || controller.visible != nil {
                        DockTooltipArtwork(name: String(localized: .tooltipSampleApp),
                            icon: NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: nil),
                            preset: preset, edge: edge, maximumWidth: max(1, region.width - 16), reduceTransparency: reduceTransparency)
                            .onGeometryChange(for: CGSize.self) { $0.size } action: { measured = $0 }
                            .position(x: frame.midX, y: frame.midY)
                            .transition(preset.transition(edge: edge, reduceMotion: reduceMotion))
                    }
                }.frame(width: bounds.width, height: bounds.height).clipped()
            }.frame(height: 180)
            Text(preset.subtitle).font(.caption).foregroundStyle(.secondary)
            Button(.tooltipPlayPreview, systemImage: "play.fill") { play() }.disabled(preset == .off)
        }
        .padding(14)
        .background {
            SettingsWindowLifecycle(closed: cancel, activityChanged: { active in if !active { cancel() } })
        }
        .onChange(of: preset) { _, _ in cancel() }
        .onChange(of: edge) { _, _ in cancel() }
        .onChange(of: reduceMotion) { _, _ in cancel() }
        .onChange(of: reduceTransparency) { _, _ in cancel() }
        .onDisappear { cancel() }
    }

    private func play() {
        cancel(); playing = true
        controller.update(.init(target: sampleID, preset: preset, reduceMotion: reduceMotion))
        dismissal = DockVisibilityScheduler().schedule(after: preset.delay + 1.5) {
            controller.clear(); playing = false; dismissal = nil
        }
    }
    private func cancel() { dismissal?.cancel(); dismissal = nil; controller.clear(); playing = false }
}

#if DEBUG
#Preview("Tooltip placements on every edge") {
    VStack {
        ForEach(DockEdge.allCases, id: \.self) { edge in
            DockTooltipPreview(preset: .leadingTag, edge: edge, reduceMotion: true, reduceTransparency: true)
        }
    }.frame(width: 560)
}
#endif
