import SwiftUI

/// Quiet outlines connect an app, its disclosure, and its windows using the same animated
/// geometry as their buttons. No independent layout or pointer region is introduced.
struct DockWindowGroupBackgrounds: View {
    let slots: [DockRenderSlot]
    let layout: DockGeometry.Layout
    let sizes: [CGFloat]
    let opacity: Double

    private var groups: [(id: String, frame: CGRect)] {
        let centers = layout.centers(sizes: sizes)
        return slots.indices.compactMap { index in
            guard let app = slots[index].item, index + 1 < slots.count,
                  slots[index + 1].windowGroup?.app.id == app.id, index < sizes.count else { return nil }
            var frame = layout.iconFrame(centerAlong: centers[index], size: sizes[index])
            for child in (index + 1)..<slots.count {
                guard slots[child].windowOwner?.id == app.id, child < sizes.count else { break }
                frame = frame.union(layout.iconFrame(centerAlong: centers[child], size: sizes[child]))
            }
            return (app.id, frame.insetBy(dx: -2, dy: -2))
        }
    }

    var body: some View {
        ForEach(groups, id: \.id) { group in
            RoundedRectangle(cornerRadius: 12)
                .fill(.primary.opacity(0.035))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5) }
                .opacity(opacity)
                .frame(width: group.frame.width, height: group.frame.height)
                .position(x: group.frame.midX, y: group.frame.midY)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
