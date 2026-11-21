import SwiftUI
import UniformTypeIdentifiers

/// The Flix Files panel: sidebar and activity list on one sheet of glass, with sheets and dialogs
/// over the list.
///
/// The open pose springs from the tile or the pointer (``FlixPanelState/growthAnchor``): scaled to
/// 90 %, blurred and transparent, to rest. While a drag is outside the panel it steps aside: the
/// window fades (see `FlixPanelController.stepAside`) and the content eases to 97 % toward where it grew from. Reduce Motion
/// keeps only the fades; Reduce Transparency draws a solid background. A file or web address
/// dragged in from another app is kept as an item.
struct FlixPanelView: View {
    let state: FlixPanelState

    private var anchor: UnitPoint { UnitPoint(x: state.growthAnchor.x, y: state.growthAnchor.y) }
    private var resting: Bool { state.phase == .shown }
    private var steppedAside: Bool { state.drag?.isOutside == true }

    private var scale: CGFloat {
        if state.reduceMotion { return 1 }
        switch state.phase {
        case .entering: return 0.9
        case .leaving: return 0.96
        case .shown: return steppedAside ? 0.97 : 1
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            FlixSidebarView(state: state)
                .frame(width: FlixStyle.sidebarWidth)
            FlixHairline(axis: .vertical)
            FlixMainColumn(state: state)
        }
        .overlay { FlixDropTargetRing(targeted: state.isDropTargeted, reduceMotion: state.reduceMotion) }
        .overlay { FlixConfirmationLayer(state: state) }
        .modifier(FlixPanelGlass(reduceTransparency: state.reduceTransparency, increaseContrast: state.increaseContrast))
        .padding(FlixPanelGeometry.shadowMargin)
        .scaleEffect(scale, anchor: anchor)
        .blur(radius: state.reduceMotion || state.phase != .entering ? 0 : 6)
        .opacity(resting ? 1 : 0)
        // The same curve and time as the window's fade in `stepAside`.
        .animation(state.reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.3, 1, duration: 0.2), value: steppedAside)
        .onDrop(of: [.fileURL, .url], delegate: FlixKeepDropDelegate(state: state))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.flixName))
    }
}

/// The accent ring and wash while a file or page from another app is over the panel.
private struct FlixDropTargetRing: View {
    let targeted: Bool
    let reduceMotion: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FlixStyle.cornerRadius, style: .continuous)
        shape.strokeBorder(Color.accentColor, lineWidth: 2)
            .background(Color.accentColor.opacity(0.08), in: shape)
            .opacity(targeted ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: targeted)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Keeps files and pages dropped on the panel from other apps. Flix's own drags are refused, so
/// dragging a row back over the panel never duplicates it.
private struct FlixKeepDropDelegate: DropDelegate {
    let state: FlixPanelState

    func validateDrop(info: DropInfo) -> Bool {
        state.drag == nil && info.hasItemsConforming(to: [.fileURL, .url])
    }

    func dropEntered(info: DropInfo) { state.isDropTargeted = validateDrop(info: info) }
    func dropExited(info: DropInfo) { state.isDropTargeted = false }

    func performDrop(info: DropInfo) -> Bool {
        state.isDropTargeted = false
        guard validateDrop(info: info) else { return false }
        let providers = info.itemProviders(for: [.fileURL, .url])
        Task { @MainActor in
            var files: [URL] = []
            var links: [URL] = []
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    if let url = await Self.url(from: provider, type: .fileURL) { files.append(url) }
                } else if let url = await Self.url(from: provider, type: .url) {
                    links.append(url)
                }
            }
            state.keep(files: files, links: links)
        }
        return true
    }

    /// A URL pasteboard item's bytes are the address itself, for files and pages alike.
    private static func url(from provider: NSItemProvider, type: UTType) async -> URL? {
        let data: Data? = await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
        return data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
    }
}

#if DEBUG
#Preview("Stream") {
    FlixPanelView(state: FlixPreviewData.panelState())
        .frame(width: 760, height: 608)
}

#Preview("Stream with intelligence, dark") {
    FlixPanelView(state: FlixPreviewData.panelState(withIntelligence: true))
        .frame(width: 760, height: 608)
        .preferredColorScheme(.dark)
}

#Preview("Fits loading and morning card") {
    FlixPanelView(state: FlixPreviewData.panelState(.fitsLoading))
        .frame(width: 760, height: 608)
}

#Preview("Thread card") {
    FlixPanelView(state: FlixPreviewData.panelState(.thread))
        .frame(width: 760, height: 608)
}

#Preview("Search suggestions") {
    FlixPanelView(state: FlixPreviewData.panelState(.search))
        .frame(width: 760, height: 608)
}

#Preview("Search, understanding") {
    FlixPanelView(state: FlixPreviewData.panelState(.understanding))
        .frame(width: 760, height: 608)
}

#Preview("Search tokens") {
    FlixPanelView(state: FlixPreviewData.panelState(.tokens))
        .frame(width: 760, height: 608)
}

#Preview("More like this, German") {
    FlixPanelView(state: FlixPreviewData.panelState(.moreLikeThis))
        .frame(width: 760, height: 608)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Empty history") {
    FlixPanelView(state: FlixPreviewData.panelState(.empty))
        .frame(width: 760, height: 608)
}

#Preview("Nothing flagged, light") {
    FlixPanelView(state: FlixPreviewData.panelState(.nothingMatches))
        .frame(width: 760, height: 608)
        .preferredColorScheme(.light)
}

#Preview("Light, German, long names") {
    FlixPanelView(state: FlixPreviewData.panelState(.longNames))
        .frame(width: 760, height: 608)
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.light)
}

#Preview("Tidy sheet") {
    FlixPanelView(state: FlixPreviewData.panelState(.tidySheet))
        .frame(width: 760, height: 608)
}

#Preview("New Smart Filter sheet, German") {
    FlixPanelView(state: FlixPreviewData.panelState(.smartFilterSheet))
        .frame(width: 760, height: 608)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Rename sheet") {
    FlixPanelView(state: FlixPreviewData.panelState(.renameSheet))
        .frame(width: 760, height: 608)
}

#Preview("Sensitive question") {
    FlixPanelView(state: FlixPreviewData.panelState(.sensitiveQuestion))
        .frame(width: 760, height: 608)
}

#Preview("Newer version question, toast") {
    FlixPanelView(state: FlixPreviewData.panelState(.newerVersionQuestion))
        .frame(width: 760, height: 608)
}

#Preview("Solid background, small panel") {
    let state = FlixPreviewData.panelState(withIntelligence: true)
    state.reduceTransparency = true
    state.reduceMotion = true
    return FlixPanelView(state: state)
        .frame(width: 580, height: 420)
}
#endif
