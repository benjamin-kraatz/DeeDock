import SwiftUI

/// The dock's native material, with an opaque alternative for Reduce Transparency.
struct DockBackgroundView: View {
    let reduceTransparency: Bool

    var body: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 22).fill(
                Color(nsColor: .windowBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22).strokeBorder(
                    .primary.opacity(0.14),
                    lineWidth: 0.5
                )
            )
        } else {
            RoundedRectangle(cornerRadius: 22).fill(.clear)
                .glassEffect(.clear, in: .rect(cornerRadius: 22))
        }
    }
}

#if DEBUG
    #Preview("Glass and opaque material") {
        VStack(spacing: 20) {
            DockBackgroundView(reduceTransparency: false)
            DockBackgroundView(reduceTransparency: true)
        }
        .frame(width: 300, height: 180)
        .padding(20)
    }
#endif
