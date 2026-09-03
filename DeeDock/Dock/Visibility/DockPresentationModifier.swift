import SwiftUI

/// Uses the same sample as AppKit hit testing, with masks applied before transforms.
struct DockPresentationModifier: ViewModifier {
    let sample: DockAnimationSample
    let size: CGSize
    func body(content: Content) -> some View {
        content
            .mask(alignment: .topLeading) {
                Rectangle().frame(width: max(0, sample.mask.width), height: max(0, sample.mask.height))
                    .offset(x: sample.mask.minX, y: sample.mask.minY)
            }
            .scaleEffect(sample.scale, anchor: UnitPoint(x: sample.anchor.x / max(1, size.width), y: sample.anchor.y / max(1, size.height)))
            .offset(sample.offset)
            .opacity(sample.opacity)
    }
}
