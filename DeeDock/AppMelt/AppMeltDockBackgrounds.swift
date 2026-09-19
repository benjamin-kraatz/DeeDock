import SwiftUI

/// One continuous enclosure behind the two independently positioned app icons.
/// Uses the dock's magnified geometry on every edge, without adding a third hit target.
struct AppMeltDockBackgrounds: View {
    let slots: [DockRenderSlot]
    let layout: DockGeometry.Layout
    let sizes: [CGFloat]
    let opacity: Double
    let reduceTransparency: Bool

    private struct GroupFrame: Identifiable {
        let id: UUID
        var frame: CGRect
    }

    private var groups: [GroupFrame] {
        let centers = layout.centers(sizes: sizes)
        var result: [GroupFrame] = []
        for (index, slot) in slots.enumerated() {
            guard let pair = slot.melt, index < sizes.count, index < centers.count else { continue }
            let frame = layout.iconFrame(centerAlong: centers[index], size: sizes[index])
            if let existing = result.firstIndex(where: { $0.id == pair.id }) {
                result[existing].frame = result[existing].frame.union(frame)
            } else {
                result.append(GroupFrame(id: pair.id, frame: frame))
            }
        }
        return result
    }

    var body: some View {
        ForEach(groups) { group in
            RoundedRectangle(cornerRadius: layout.iconSize * 0.25)
                .fill(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : Color.primary.opacity(0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: layout.iconSize * 0.25)
                        .strokeBorder(.primary.opacity(0.2), lineWidth: 1)
                }
                .frame(width: group.frame.width + 8, height: group.frame.height + 8)
                .position(x: group.frame.midX, y: group.frame.midY)
                .opacity(opacity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
