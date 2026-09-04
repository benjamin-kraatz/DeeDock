import SwiftUI

/// Explicit permission controls keep Accessibility discovery out of context-click and startup paths.
struct WindowAccessSettingsCard: View {
    let status: WindowAccessStatus
    var requestAccess: () -> Void = {}
    var refresh: () -> Void = {}
    var openSettings: () -> Void = {}

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(.windowAccessTitle)
                } icon: {
                    Image(systemName: status == .enabled ? "macwindow.badge.checkmark" : "macwindow")
                        .accessibilityHidden(true)
                }
                .font(.headline)

                Text(.windowAccessExplanation)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Label(status.message, systemImage: status == .enabled ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(status == .enabled ? .green : .secondary)

                ViewThatFits(in: .horizontal) {
                    HStack { actions }
                    VStack(alignment: .leading) { actions }
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder private var actions: some View {
        if status != .enabled {
            Button(.windowAccessEnable, action: requestAccess)
        }
        Button(.windowAccessCheckAgain, action: refresh)
        Button(.windowAccessOpenSettings, action: openSettings)
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
