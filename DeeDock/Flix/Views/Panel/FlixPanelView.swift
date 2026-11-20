import SwiftUI
import UniformTypeIdentifiers

/// The Flix Files panel: sidebar and activity list on one sheet of glass, with sheets and dialogs
/// over the list.
///
/// The open pose springs from the tile or the pointer (``FlixPanelState/growthAnchor``): scaled to
/// 90 %, blurred and transparent, to rest. Reduce Motion crossfades instead; Reduce Transparency
/// draws a solid background. A file or web address dragged in from another app is kept as an item.
struct FlixPanelView: View {
    let state: FlixPanelState

    private var anchor: UnitPoint { UnitPoint(x: state.growthAnchor.x, y: state.growthAnchor.y) }
    private var resting: Bool { state.phase == .shown }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FlixStyle.cornerRadius, style: .continuous)
        HStack(spacing: 0) {
            FlixSidebarView(state: state)
                .frame(width: FlixStyle.sidebarWidth)
            Divider().opacity(0.6)
            FlixMainColumn(state: state)
        }
        .overlay {
            if state.isDropTargeted {
                shape.strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(Color.accentColor.opacity(0.08), in: shape)
                    .allowsHitTesting(false)
            }
        }
        .overlay { FlixConfirmationLayer(state: state) }
        .background(FlixPanelBackground(reduceTransparency: state.reduceTransparency))
        .clipShape(shape)
        .padding(FlixPanelGeometry.shadowMargin)
        .scaleEffect(state.reduceMotion ? 1 : (resting ? 1 : (state.phase == .leaving ? 0.96 : 0.9)), anchor: anchor)
        .blur(radius: state.reduceMotion || resting || state.phase == .leaving ? 0 : 6)
        .opacity(resting ? 1 : 0)
        .onDrop(of: [.fileURL, .url], delegate: FlixKeepDropDelegate(state: state))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.flixName))
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
#Preview("Flix Files, plain") {
    FlixPanelView(state: FlixPreviewData.panelState())
        .frame(width: 760, height: 608)
}

#Preview("Flix Files, with intelligence") {
    FlixPanelView(state: FlixPreviewData.panelState(withIntelligence: true))
        .frame(width: 760, height: 608)
}

#Preview("Flix Files, light, German") {
    FlixPanelView(state: FlixPreviewData.panelState(withIntelligence: true))
        .frame(width: 760, height: 608)
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.light)
}

#Preview("Flix Files, solid background") {
    let state = FlixPreviewData.panelState()
    state.reduceTransparency = true
    return FlixPanelView(state: state).frame(width: 760, height: 608)
}
#endif
