import SwiftUI

/// Persistent bar under the panes: failure feedback plus the one destructive action.
struct SettingsFooterBar: View {
    let errorMessage: LocalizedStringResource?
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
                        Text(.settingsRestoreDefaults)
                    } icon: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: errorMessage)
    }
}

/// Inline failure notice; saved settings stay in use until an edit succeeds.
private struct SettingsErrorBanner: View {
    let message: LocalizedStringResource

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(.orange.opacity(0.35), lineWidth: 0.5))
        .accessibilityAddTraits(.updatesFrequently)
    }
}
