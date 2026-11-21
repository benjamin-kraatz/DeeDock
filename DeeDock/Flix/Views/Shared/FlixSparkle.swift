import SwiftUI

/// The ✦ mark of everything intelligence adds, in the intelligence gradient. The same character
/// appears inside localized strings and menu titles ("✦ by meaning"), so the mark is one glyph
/// everywhere. White on a selected row, where the gradient would not read. Decorative; VoiceOver
/// skips it.
struct FlixSparkle: View {
    var size: CGFloat = 12
    var selected = false

    var body: some View {
        Text(verbatim: "✦")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(FlixStyle.aiGradient))
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Sparkle") {
    HStack(spacing: 12) {
        FlixSparkle(size: 10)
        FlixSparkle()
        FlixSparkle(size: 16)
        FlixSparkle(selected: true).padding(6).background(Color.accentColor, in: .rect(cornerRadius: 6))
    }
    .padding()
}
#endif
