import SwiftUI

/// Static, click-through chatter. The owning dock cancels it when interaction begins.
struct DockRumourBubble: View {
    let speaker: String
    let listener: String
    let message: String
    let maximumWidth: CGFloat
    let reduceTransparency: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(.simsRumourSpeakers(speaker, listener))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(verbatim: message)
                .font(.caption)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: maximumWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(reduceTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.regularMaterial))
        }
        .accessibilityElement(children: .combine)
        .allowsHitTesting(false)
    }
}

#if DEBUG
#Preview("Generated dialogue layout") {
    DockRumourBubble(speaker: "Safari", listener: "Notes", message: String(localized: .simsRumourPreviewLine),
                     maximumWidth: 250, reduceTransparency: false)
        .padding()
}

#Preview("Long names, opaque") {
    DockRumourBubble(speaker: "Eine Anwendung mit langem Namen", listener: "Notizen",
                     message: String(localized: .simsRumourPreviewLine), maximumWidth: 220, reduceTransparency: true)
        .padding()
        .preferredColorScheme(.dark)
}
#endif
