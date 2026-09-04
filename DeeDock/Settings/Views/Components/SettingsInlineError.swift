import SwiftUI

/// Inline failure notice; saved settings stay in use until an edit succeeds.
///
/// Shared by the footer bar and the General cards so a failure reads the same wherever it lands.
struct SettingsInlineError: View {
    let message: LocalizedStringResource
    /// Omit where the notice clears itself, such as the next successful save.
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let dismiss {
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(.actionDismissError))
                    .help(Text(.actionDismissError))
            }
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 11)
        .background(.orange.opacity(0.1))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// The same notice as a standalone banner, for surfaces that are not cards.
struct SettingsErrorBanner: View {
    let message: LocalizedStringResource
    var dismiss: (() -> Void)?

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous) }

    var body: some View {
        SettingsInlineError(message: message, dismiss: dismiss)
            .background(.orange.opacity(0.06), in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.orange.opacity(0.3), lineWidth: 0.5))
    }
}
