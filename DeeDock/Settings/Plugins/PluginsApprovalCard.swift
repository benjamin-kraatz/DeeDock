import SwiftUI

/// "N plugins are waiting for approval" with Manage Plugins…, or, when none wait, a quiet note
/// that macOS keeps the list. The waiting state is tinted with the accent colour so it is noticed.
///
/// macOS counts waiting plugins but never names them, so the card cannot list them.
struct PluginsApprovalCard: View {
    let waitingCount: Int
    let manage: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var waiting: Bool { waitingCount > 0 }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: waiting ? "rays" : "checkmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.16), in: .rect(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(waiting ? .pluginsWaitingTitle(waitingCount) : .pluginsAllApprovedTitle)
                Text(waiting ? .pluginsWaitingDetail : .pluginsAllApprovedDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer(minLength: SettingsMetrics.controlSpacing)
            manageButton
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, SettingsMetrics.rowVerticalInset)
        .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowMinimumHeight, alignment: .leading)
        .background(waiting ? AnyShapeStyle(Color.accentColor.opacity(0.07)) : AnyShapeStyle(.background.secondary), in: shape)
        .overlay(shape.strokeBorder(waiting ? AnyShapeStyle(Color.accentColor.opacity(0.45))
                                    : AnyShapeStyle(.separator.opacity(colorScheme == .dark ? 0.6 : 0.4)),
                                    lineWidth: 0.5))
        .accessibilityElement(children: .contain)
    }

    /// Prominent while plugins wait, since approving them is the next step.
    @ViewBuilder private var manageButton: some View {
        if waiting {
            Button(action: manage) { Text(.pluginsManage) }.buttonStyle(.borderedProminent)
        } else {
            Button(action: manage) { Text(.pluginsManage) }.buttonStyle(.bordered)
        }
    }
}

#if DEBUG
#Preview("Waiting and approved") {
    VStack(spacing: 22) {
        PluginsApprovalCard(waitingCount: 1) {}
        PluginsApprovalCard(waitingCount: 3) {}
        PluginsApprovalCard(waitingCount: 0) {}
    }
    .padding(24)
    .frame(width: 640)
}
#endif
