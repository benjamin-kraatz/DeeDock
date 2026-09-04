import SwiftUI

/// Persistent bar under the panes: failure feedback plus the one destructive action.
struct SettingsFooterBar: View {
    let errorMessage: LocalizedStringResource?
    var resetTitle: LocalizedStringResource = .settingsRestoreDefaults
    var resetDisabled = false
    let restoreDefaults: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            if let errorMessage {
                SettingsErrorBanner(message: errorMessage)
                    .transition(reduceMotion ? .opacity
                                : .move(edge: .bottom).combined(with: .opacity))
            }
            HStack {
                Spacer()
                Button(action: restoreDefaults) {
                    Label {
                        Text(resetTitle)
                    } icon: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                }
                .controlSize(.regular)
                .disabled(resetDisabled)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 11)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: errorMessage)
    }
}
