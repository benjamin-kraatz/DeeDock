import SwiftUI

/// The sheet's title row: the app's icon and name, then its version, source, and size, or the current
/// step while DOKK scans or removes.
struct HubUninstallHeader: View {
    let session: AppUninstallSession

    var body: some View {
        HStack(spacing: 14) {
            HubUninstallAppIcon(url: session.appURL, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(.hubUninstallTitle(name: session.appName))
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                subline
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 17)
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 18, leading: 22, bottom: 12, trailing: 22))
    }

    @ViewBuilder private var subline: some View {
        switch session.phase {
        case .scanning:
            HubUninstallStatus(text: Text(.hubUninstallChecking))
        case .working(let step):
            HubUninstallStatus(text: status(step))
        default:
            HStack(spacing: 7) {
                if let version = session.target?.version {
                    Text(.hubUninstallVersion(version: version))
                }
                if let source = session.target?.source {
                    Text(source.badge)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(source == .appStore || source == .testFlight ? Color.accentColor : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.07)))
                }
                AppUninstallFormat.size(session.appSize)
                    .monospacedDigit()
            }
        }
    }

    private func status(_ step: AppUninstallSession.Step) -> Text {
        switch step {
        case .quitting: Text(.hubUninstallQuitting(name: session.appName))
        case .waitingForPassword: Text(.hubUninstallWaitingForPassword)
        case .moving: Text(.hubUninstallMoving)
        }
    }
}

/// A small spinner and a status line.
private struct HubUninstallStatus: View {
    let text: Text

    var body: some View {
        HStack(spacing: 7) {
            ProgressView().controlSize(.mini)
            text
        }
        .accessibilityElement(children: .combine)
    }
}
