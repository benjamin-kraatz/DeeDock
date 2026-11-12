import SwiftUI

/// Finder suggestions beside the orb: up to five bubbles on an arc facing the screen centre and
/// a capsule just beyond them. The view works out its own layout
/// (``VaporGeometry/satelliteLayout(orbCenter:count:capsuleSize:visibleFrame:)``) from the
/// bubbles it is showing, so positions always match the count; the window it sits in depends
/// only on where the orb is.
///
/// Bubbles spring out of the orb one after another and bob gently. Hovering one switches the
/// capsule to that folder's name and tag; clicking flies it into the orb, and the folder is
/// added as it lands, so the orb's own drop-in and squash continue the motion. Add All does the
/// same for every bubble in turn. When a bubble comes or goes, the others and the capsule glide
/// to their new places. Under Reduce Motion the bubbles fade in and out in place, nothing
/// glides, and folders are added at once.
struct VaporSuggestionsView: View {
    let controller: VaporController
    /// The orb's centre and its display's visible frame, in AppKit global coordinates.
    let orbCenter: CGPoint
    let visibleFrame: CGRect
    /// False renders bubbles already in place, for snapshots.
    var animatesEntrance = true

    /// The most room the capsule takes. A shorter capsule sits flush with the side facing the orb.
    static let capsuleSize = CGSize(width: 320, height: 34)

    /// The layout for `count` bubbles around an orb at `orbCenter`.
    static func layout(orbCenter: CGPoint, count: Int, visibleFrame: CGRect) -> VaporSatelliteLayout {
        VaporGeometry.satelliteLayout(orbCenter: orbCenter, count: count, capsuleSize: capsuleSize, visibleFrame: visibleFrame)
    }

    @State private var eaten: Set<String> = []
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let bubbles = controller.bubbleSuggestions
        let all = controller.suggestions
        let hovered = all.first { $0.id == controller.hoveredSuggestionID }
        let palette = VaporOrbPalette(colorScheme: colorScheme, reduceTransparency: controller.reduceTransparency)
        let reduceMotion = controller.reduceMotion
        let layout = Self.layout(orbCenter: orbCenter, count: bubbles.count, visibleFrame: visibleFrame)
        let text = VaporCopy.suggestionCapsule(count: all.count, folder: controller.finderFolder, hovered: hovered)
        ZStack(alignment: .topLeading) {
            ForEach(Array(zip(bubbles, layout.bubbleCenters).enumerated()), id: \.element.0.id) { index, pair in
                let (suggestion, center) = pair
                VaporSuggestionBubble(suggestion: suggestion, index: index, target: center, orb: layout.orbCenter,
                                      lighting: controller.lighting, palette: palette,
                                      isEaten: eaten.contains(suggestion.id), animatesEntrance: animatesEntrance,
                                      reduceMotion: reduceMotion) { isHovered in
                    hover(suggestion, isHovered)
                } add: {
                    eat([suggestion]) { controller.addSuggestion(suggestion) }
                }
                .transition(.asymmetric(insertion: .identity, removal: .opacity))
            }
            if !bubbles.isEmpty {
                VaporSuggestionCapsule(
                    text: text, extra: hovered == nil ? max(all.count - bubbles.count, 0) : 0,
                    reduceTransparency: controller.reduceTransparency, reduceMotion: reduceMotion,
                    animatesEntrance: animatesEntrance,
                    addAll: {
                        let shown = all
                        eat(bubbles) { controller.addAllSuggestions(shown) }
                    },
                    dismiss: controller.dismissSuggestions)
                    // Flush with the side of the reserved room that faces the orb: `dx` -1 puts
                    // all the slack on the left.
                    .alignmentGuide(.vaporCapsuleSide) { size in
                        -(Self.capsuleSize.width - size.width) * (1 - layout.capsuleLean.dx) / 2
                    }
                    .frame(width: Self.capsuleSize.width, height: Self.capsuleSize.height,
                           alignment: Alignment(horizontal: .vaporCapsuleSide, vertical: .center))
                    .position(layout.capsuleCenter)
                    .animation(reduceMotion ? nil : VaporMotion.bubbleGlide, value: layout.capsuleCenter)
                    .animation(.easeOut(duration: 0.18), value: text)
            }
        }
        .frame(width: layout.windowFrame.width, height: layout.windowFrame.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.2), value: bubbles.map(\.id))
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

private extension HorizontalAlignment {
    /// Places the capsule inside its reserved room. A guide of its own, not `.leading`: an
    /// explicit `.leading` would travel up to the bubbles' stack and shift them.
    static let vaporCapsuleSide = HorizontalAlignment(VaporCapsuleSide.self)

    private enum VaporCapsuleSide: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[.leading] }
    }
}

#if DEBUG
#Preview("Suggestions, dark") {
    VaporSuggestionsView(controller: VaporPreviewData.controller(suggestions: VaporPreviewData.suggestions, opensLeft: true),
                         orbCenter: VaporPreviewData.Lamp.upperLeft.orbCenter, visibleFrame: VaporPreviewData.visibleFrame)
        .background(VaporPreviewBackdrop())
        .preferredColorScheme(.dark)
}

#Preview("Suggestions, light, Reduce Motion") {
    VaporSuggestionsView(controller: VaporPreviewData.controller(suggestions: Array(VaporPreviewData.suggestions.prefix(3)),
                                                                 reduceMotion: true, lamp: .upperRight),
                         orbCenter: VaporPreviewData.Lamp.upperRight.orbCenter, visibleFrame: VaporPreviewData.visibleFrame)
        .background(VaporPreviewBackdrop())
        .preferredColorScheme(.light)
}
#endif
