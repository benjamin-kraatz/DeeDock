import SwiftUI

/// The sheet after the app went to the Trash: the icon sinking in with a trash badge, what moved, what
/// stayed and why, and the way to the Trash.
struct HubUninstallDoneView: View {
    let session: AppUninstallSession
    let summary: AppUninstallSession.Summary
    let uninstaller: HubAppsUninstaller

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    HubUninstallAppIcon(url: session.appURL, size: 72)
                        .scaleEffect(appeared || reduceMotion ? 1 : 1.15)
                        .opacity(appeared ? 1 : 0)
                    Image(systemName: "trash.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(.regularMaterial))
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                        .offset(x: 8, y: 6)
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.3)
                        .opacity(appeared ? 1 : 0)
                        .accessibilityHidden(true)
                }
                .padding(.bottom, 10)
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
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)
            }
            .padding(EdgeInsets(top: 28, leading: 30, bottom: 16, trailing: 30))
            .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                Spacer()
                if summary.hasSystemExtensions {
                    Button { uninstaller.openExtensionsSettings() } label: { Text(.hubUninstallExtensionSettings) }
                }
                Button { uninstaller.showTrash() } label: { Text(.hubUninstallShowInTrash) }
                Button { uninstaller.end() } label: { Text(.hubUninstallDone) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(EdgeInsets(top: 12, leading: 22, bottom: 14, trailing: 18))
            .overlay(alignment: .top) {
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5).accessibilityHidden(true)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.72)) {
                appeared = true
            }
        }
    }
}
