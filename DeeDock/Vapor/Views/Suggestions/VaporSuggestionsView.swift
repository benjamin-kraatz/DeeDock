import SwiftUI

/// Finder suggestions beside the orb: up to five bubbles on an arc facing the screen centre and
/// a capsule beyond them. Positions come from ``VaporGeometry/satelliteLayout(orbCenter:count:capsuleSize:visibleFrame:)``,
/// already converted to this window's coordinates.
///
/// Hovering a bubble switches the capsule to that folder's name and tag; clicking adds it.
struct VaporSuggestionsView: View {
    let controller: VaporController
    let layout: VaporSatelliteLayout

    /// The capsule size the geometry reserves room for.
    static let capsuleSize = CGSize(width: 260, height: 34)

    var body: some View {
        let bubbles = controller.bubbleSuggestions
        let all = controller.suggestions
        let hovered = all.first { $0.id == controller.hoveredSuggestionID }
        ZStack(alignment: .topLeading) {
            ForEach(Array(zip(bubbles, layout.bubbleCenters)), id: \.0.id) { suggestion, center in
                VaporSuggestionBubble(suggestion: suggestion, reduceTransparency: controller.reduceTransparency,
                                      hovered: controller.hoveredSuggestionID == suggestion.id) { isHovered in
                    if isHovered {
                        controller.hoveredSuggestionID = suggestion.id
                    } else if controller.hoveredSuggestionID == suggestion.id {
                        controller.hoveredSuggestionID = nil
                    }
                } add: {
                    controller.addSuggestion(suggestion)
                }
                .position(center)
            }
            if !all.isEmpty {
                VaporSuggestionCapsule(
                    text: VaporCopy.suggestionCapsule(count: all.count, folder: controller.finderFolder, hovered: hovered),
                    extra: hovered == nil ? max(all.count - bubbles.count, 0) : 0,
                    reduceTransparency: controller.reduceTransparency,
                    addAll: controller.addAllSuggestions, dismiss: controller.dismissSuggestions)
                    .frame(maxWidth: Self.capsuleSize.width)
                    .position(layout.capsuleCenter)
            }
        }
        .frame(width: layout.windowFrame.width, height: layout.windowFrame.height, alignment: .topLeading)
    }
}

/// One floating folder bubble.
private struct VaporSuggestionBubble: View {
    let suggestion: VaporSuggestion
    let reduceTransparency: Bool
    let hovered: Bool
    let hover: (Bool) -> Void
    let add: () -> Void

    var body: some View {
        Button(action: add) {
            VaporFolderIcon(size: 20)
                .frame(width: VaporGeometry.bubbleDiameter, height: VaporGeometry.bubbleDiameter)
                .vaporGlass(in: Circle(), reduceTransparency: reduceTransparency)
                .scaleEffect(hovered ? 1.08 : 1)
                .animation(.easeOut(duration: 0.12), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover(perform: hover)
        .accessibilityLabel(Text(.vaporAddSuggestion(suggestion.name)))
    }
}

/// "4 caches in dokk-web · 2 more" with Add All and ×.
private struct VaporSuggestionCapsule: View {
    let text: String
    let extra: Int
    let reduceTransparency: Bool
    let addAll: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: text)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            if extra > 0 {
                Text(.vaporMoreSuggestions(extra))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Button(.vaporAddAll, action: addAll)
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(Text(.vaporDismissSuggestions))
            .accessibilityLabel(Text(.vaporDismissSuggestions))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .vaporGlass(in: Capsule(), reduceTransparency: reduceTransparency)
    }
}

#if DEBUG
#Preview("Suggestions") {
    let layout = VaporGeometry.satelliteLayout(orbCenter: CGPoint(x: 1300, y: 300), count: 4,
                                               capsuleSize: VaporSuggestionsView.capsuleSize,
                                               visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950))
    VaporSuggestionsView(controller: VaporPreviewData.controller(suggestions: VaporPreviewData.suggestions, opensLeft: true),
                         layout: layout)
}
#endif
