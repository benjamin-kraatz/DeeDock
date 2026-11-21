import SwiftUI

/// The ✦ tip card offering a Smart Filter learned from what you open.
struct FlixFilterTipCard: View {
    let tip: FlixFilterTip
    let make: () -> Void
    let dismiss: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                FlixSparkle(size: 11)
                Text(verbatim: tip.message)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Wraps when both buttons do not fit side by side (German).
            FlixFlow(spacing: 6, lineSpacing: 6) {
                FlixCardButton(title: String(localized: .flixTipMake), primary: true, intelligent: true, compact: true,
                               action: make)
                FlixCardButton(title: String(localized: .flixTipNotNow), compact: true, action: dismiss)
            }
        }
        .font(.system(size: 11.5))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FlixStyle.aiSoft, in: shape)
        .overlay(shape.strokeBorder(FlixStyle.aiStroke, lineWidth: 0.5))
        .padding(.top, 12)
        .padding(.horizontal, 2)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Filter tip") {
    FlixFilterTipCard(tip: FlixFilterTip(id: "oak", message: "You open Oak & Ash files most mornings. Make a Smart Filter for them?",
                                         proposal: FlixPreviewData.proposal.filter), make: {}, dismiss: {})
        .padding(8)
        .frame(width: FlixStyle.sidebarWidth)
}
#endif
