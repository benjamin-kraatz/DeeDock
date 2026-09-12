import SwiftUI

/// Quiet numeric feedback with a directly available, confirmation-free kill switch.
/// Static system text and controls need no animation or transparency override.
struct FocusDebtStatusView: View {
    let count: Int
    let turnOff: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.focusDebtTitle).font(.headline)
            Text(.focusDebtCount(count)).monospacedDigit()
            Text(count == 0 ? .focusDebtEmpty : .focusDebtFeedback)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(.focusDebtDisable, action: turnOff)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview("Focus debt, fresh start") {
    FocusDebtStatusView(count: 0, turnOff: {}).padding().frame(width: 350)
}
#Preview("Focus debt, German feedback") {
    FocusDebtStatusView(count: 3, turnOff: {}).padding().frame(width: 350)
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark)
}
#endif
