import SwiftUI

/// Explicit permission controls keep Accessibility discovery out of context-click and startup paths.
struct WindowAccessSettingsCard: View {
    let status: WindowAccessStatus
    var requestAccess: () -> Void = {}
    var refresh: () -> Void = {}
    var openSettings: () -> Void = {}

    var body: some View {
        SettingsCard(title: .windowAccessTitle, footnote: .windowAccessExplanation) {
            SettingsStackedRow {
                Label {
                    Text(status.message)
                } icon: {
                    Image(systemName: status == .enabled ? "checkmark.circle.fill" : "circle.dashed")
                }
                .font(.callout)
                .foregroundStyle(status == .enabled ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
                .labelStyle(.titleAndIcon)
            }
            SettingsActionRow { actions }
        }
    }

    @ViewBuilder private var actions: some View {
        Button(.windowAccessCheckAgain, action: refresh)
        Button(.windowAccessOpenSettings, action: openSettings)
        if status != .enabled {
            Button(.windowAccessEnable, action: requestAccess).buttonStyle(.borderedProminent)
        }
    }
}

private extension WindowAccessStatus {
    var message: LocalizedStringResource {
        switch self {
        case .enabled: .windowAccessStatusEnabled
        case .notEnabled: .windowAccessStatusNotEnabled
        case .unavailable: .windowAccessStatusUnavailable
        }
    }
}

#if DEBUG
#Preview("Window access states") {
    VStack(spacing: 20) {
        WindowAccessSettingsCard(status: .enabled)
        WindowAccessSettingsCard(status: .notEnabled)
        WindowAccessSettingsCard(status: .unavailable)
    }
    .padding()
    .frame(width: 530)
}
#endif
