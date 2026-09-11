import SwiftUI

/// Short-lived confirmation or warning after a deep-link attempt.
enum SystemSettingsCloneToast: Hashable {
    /// The pane URL was accepted; carries the pane for its title and tint.
    case opening(SystemSettingsClonePane)
    case openedRoot
    case failed

    var isWarning: Bool {
        switch self {
        case .opening: false
        case .openedRoot, .failed: true
        }
    }

    /// How long the toast stays before it dismisses itself.
    var lifetime: Duration {
        isWarning ? .seconds(6) : .seconds(1.8)
    }

    var message: Text {
        switch self {
        case let .opening(pane): Text(.systemSettingsCloneOpening(pane: String(localized: pane.title)))
        case .openedRoot: Text(.systemSettingsCloneOpenedRoot)
        case .failed: Text(.systemSettingsCloneOpenFailed)
        }
    }
}

/// Floating glass capsule at the bottom of the window.
struct SystemSettingsCloneToastView: View {
    let toast: SystemSettingsCloneToast
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            switch toast {
            case let .opening(pane):
                SystemSettingsCloneIconTile(symbolName: pane.symbolName, tint: pane.tint, size: 22)
            case .openedRoot:
                Image(systemName: "info.circle.fill").foregroundStyle(.blue)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            toast.message
                .font(.system(size: 12.5, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            if toast.isWarning {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(.actionDismissError))
                .help(Text(.actionDismissError))
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: 460)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#if DEBUG
#Preview("Toasts") {
    VStack(spacing: 16) {
        SystemSettingsCloneToastView(toast: .opening(SystemSettingsDeepLinkCatalog.allPanes[10]), dismiss: {})
        SystemSettingsCloneToastView(toast: .openedRoot, dismiss: {})
        SystemSettingsCloneToastView(toast: .failed, dismiss: {})
    }
    .padding(30)
}
#endif
