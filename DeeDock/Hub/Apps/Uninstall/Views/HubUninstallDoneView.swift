import SwiftUI

/// The sheet after the app went to the Trash: the icon sinking in with a trash badge, what moved, what
/// stayed and why, and the way to the Trash.
///
/// The icon settles from 115 % (mockup `sink`: 0.5 s, `cubic-bezier(.2,1.1,.35,1)`); the badge pops in
/// 0.15 s later with a bounce (mockup `pop`). Reduce Motion fades both in place.
struct HubUninstallDoneView: View {
    let session: AppUninstallSession
    let summary: AppUninstallSession.Summary
    let uninstaller: HubAppsUninstaller

    @State private var iconShown = false
    @State private var badgeShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    static let sink = Animation.timingCurve(0.2, 1.1, 0.35, 1, duration: 0.5)
    static let badgePop = Animation.spring(response: 0.42, dampingFraction: 0.55).delay(0.15)

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                icon.padding(.bottom, 14)
                Text(.hubUninstallDoneTitle(name: session.appName))
                    .font(.system(size: 17, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Group {
                    Text(summary.movedItems == 0 ? .hubUninstallDoneAppOnly : .hubUninstallDoneItems(summary.movedItems))
                        .foregroundStyle(.secondary)
                    Text(.hubUninstallDoneTotal(size: AppUninstallFormat.bytes(summary.bytes)))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                    if summary.protectedItems > 0 {
                        Text(.hubUninstallDoneProtected(summary.protectedItems)).foregroundStyle(.orange)
                    }
                    if summary.failedItems > 0 {
                        Text(.hubUninstallDoneFailed(summary.failedItems)).foregroundStyle(.orange)
                    }
                    if summary.hasSystemExtensions {
                        Text(.hubUninstallDoneExtension).foregroundStyle(.orange)
                    }
                    if summary.helpersKeepRunning {
                        Text(.hubUninstallDoneHelpers).foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)
            }
            .padding(EdgeInsets(top: 28, leading: 30, bottom: 16, trailing: 30))
            .frame(maxWidth: .infinity)
            HubUninstallFooterBar {
                Spacer()
                if summary.hasSystemExtensions {
                    Button { uninstaller.openExtensionsSettings() } label: { Text(.hubUninstallExtensionSettings) }
                }
                Button { uninstaller.showTrash() } label: { Text(.hubUninstallShowInTrash) }
                Button { uninstaller.end() } label: { Text(.hubUninstallDone) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Self.sink) { iconShown = true }
            withAnimation(reduceMotion ? .easeOut(duration: 0.2).delay(0.1) : Self.badgePop) { badgeShown = true }
        }
    }

    /// The app's icon with the trash badge (mockup `.done-v .ic`, `.tb`). The badge wears the sheet's own
    /// surface so it looks cut into the icon's corner.
    private var icon: some View {
        ZStack(alignment: .bottomTrailing) {
            HubUninstallAppIcon(url: session.appURL, size: 72)
                .scaleEffect(iconShown || reduceMotion ? 1 : 1.15)
                .opacity(iconShown ? 1 : 0)
            Image(systemName: "trash.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background { HubUninstallSurface(shape: Circle(), opaque: reduceTransparency) }
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                .offset(x: 8, y: 6)
                .scaleEffect(badgeShown || reduceMotion ? 1 : 0.3)
                .opacity(badgeShown ? 1 : 0)
                .accessibilityHidden(true)
        }
    }
}
