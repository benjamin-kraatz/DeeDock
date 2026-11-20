import SwiftUI

/// The ✦ tip card offering a Smart Filter learned from what you open.
struct FlixFilterTipCard: View {
    let tip: FlixFilterTip
    let make: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                FlixSparkle(size: 11)
                Text(verbatim: tip.message).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                FlixCardButton(title: String(localized: .flixTipMake), primary: true, intelligent: true, action: make)
                FlixCardButton(title: String(localized: .flixTipNotNow), action: dismiss)
            }
        }
        .font(.system(size: 11.5))
        .padding(10)
        .background(FlixStyle.aiSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(FlixStyle.aiStroke, lineWidth: 0.5))
        .padding(.top, 12)
        .padding(.horizontal, 2)
    }
}
