import SwiftUI

/// Finder suggestions beside the orb: up to five bubbles on an arc facing the screen centre and
/// a capsule beyond them. Positions come from ``VaporGeometry/satelliteLayout(orbCenter:count:capsuleSize:visibleFrame:)``,
/// already converted to this window's coordinates.
///
/// Bubbles spring out of the orb one after another and bob gently. Hovering one switches the
/// capsule to that folder's name and tag; clicking flies it into the orb, and the folder is
/// added as it lands. Add All does the same for every bubble in turn. Under Reduce Motion the
/// bubbles fade in and out in place and folders are added at once.
///
/// The window is rebuilt with a new layout when the bubbles change; the root view's identity
/// stays the same, so bubbles keep their state.
struct VaporSuggestionsView: View {
    let controller: VaporController
    let layout: VaporSatelliteLayout
    /// False renders bubbles already in place, for snapshots.
    var animatesEntrance = true

    /// The capsule size the geometry reserves room for.
    static let capsuleSize = CGSize(width: 260, height: 34)

    @State private var eaten: Set<String> = []
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let bubbles = controller.bubbleSuggestions
        let all = controller.suggestions
        let hovered = all.first { $0.id == controller.hoveredSuggestionID }
        let palette = VaporOrbPalette(colorScheme: colorScheme, reduceTransparency: controller.reduceTransparency)
        ZStack(alignment: .topLeading) {
            ForEach(Array(zip(bubbles, layout.bubbleCenters).enumerated()), id: \.element.0.id) { index, pair in
                let (suggestion, center) = pair
                VaporSuggestionBubble(suggestion: suggestion, index: index, target: center, orb: layout.orbCenter,
                                      lighting: controller.lighting, palette: palette,
                                      isEaten: eaten.contains(suggestion.id), animatesEntrance: animatesEntrance,
                                      reduceMotion: controller.reduceMotion) { isHovered in
                    hover(suggestion, isHovered)
                } add: {
                    eat([suggestion]) { controller.addSuggestion(suggestion) }
                }
            }
            if !all.isEmpty {
                VaporSuggestionCapsule(
                    text: VaporCopy.suggestionCapsule(count: all.count, folder: controller.finderFolder, hovered: hovered),
                    extra: hovered == nil ? max(all.count - bubbles.count, 0) : 0,
                    reduceTransparency: controller.reduceTransparency, reduceMotion: controller.reduceMotion,
                    animatesEntrance: animatesEntrance,
                    addAll: { eat(bubbles, then: controller.addAllSuggestions) },
                    dismiss: controller.dismissSuggestions)
                    .frame(maxWidth: Self.capsuleSize.width)
                    .position(layout.capsuleCenter)
            }
        }
        .frame(width: layout.windowFrame.width, height: layout.windowFrame.height, alignment: .topLeading)
        .onChange(of: bubbles.map(\.id)) { _, ids in
            eaten.formIntersection(ids)
        }
    }

    private func hover(_ suggestion: VaporSuggestion, _ isHovered: Bool) {
        if isHovered {
            controller.hoveredSuggestionID = suggestion.id
        } else if controller.hoveredSuggestionID == suggestion.id {
            controller.hoveredSuggestionID = nil
        }
    }

    /// Flies the bubbles into the orb, one every ``VaporMotion/addAllStagger`` seconds, then adds.
    private func eat(_ suggestions: [VaporSuggestion], then add: @escaping () -> Void) {
        let fresh = suggestions.filter { !eaten.contains($0.id) }
        guard !controller.reduceMotion, !fresh.isEmpty else {
            add()
            return
        }
        for (order, suggestion) in fresh.enumerated() {
            withAnimation(VaporMotion.bubbleEat.delay(Double(order) * VaporMotion.addAllStagger)) {
                _ = eaten.insert(suggestion.id)
            }
        }
        if controller.hoveredSuggestionID.map({ id in fresh.contains { $0.id == id } }) == true {
            controller.hoveredSuggestionID = nil
        }
        let landing = VaporMotion.bubbleEatDelay + Double(fresh.count - 1) * VaporMotion.addAllStagger
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(landing))
            add()
        }
    }
}

#if DEBUG
#Preview("Suggestions, dark") {
    let layout = VaporGeometry.satelliteLayout(orbCenter: VaporPreviewData.Lamp.upperLeft.orbCenter, count: 4,
                                               capsuleSize: VaporSuggestionsView.capsuleSize,
                                               visibleFrame: VaporPreviewData.visibleFrame)
    VaporSuggestionsView(controller: VaporPreviewData.controller(suggestions: VaporPreviewData.suggestions, opensLeft: true),
                         layout: layout)
        .background(VaporPreviewBackdrop())
        .preferredColorScheme(.dark)
}

#Preview("Suggestions, light, Reduce Motion") {
    let layout = VaporGeometry.satelliteLayout(orbCenter: VaporPreviewData.Lamp.upperRight.orbCenter, count: 3,
                                               capsuleSize: VaporSuggestionsView.capsuleSize,
                                               visibleFrame: VaporPreviewData.visibleFrame)
    VaporSuggestionsView(controller: VaporPreviewData.controller(suggestions: Array(VaporPreviewData.suggestions.prefix(3)),
                                                                 reduceMotion: true, lamp: .upperRight),
                         layout: layout)
        .background(VaporPreviewBackdrop())
        .preferredColorScheme(.light)
}
#endif
