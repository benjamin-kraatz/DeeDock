import SwiftUI

/// Settings for the notification feed: the opt-in switch, Accessibility access, what the reader
/// is doing, how DOKK handles notification text, and Clear.
///
/// Turning the switch on never prompts. macOS asks for Accessibility only after the explicit
/// Enable click, the same flow App Badges use.
struct NotificationFeedSettingsCard: View {
    @Binding var isOn: Bool
    let windowAccess: WindowAccessController
    /// Nil when Settings has no running dock, such as in previews of the whole page.
    let feed: NotificationFeedController?
    let locked: Bool

    var body: some View {
        NotificationFeedSettingsCardContent(
            isOn: $isOn,
            accessGranted: windowAccess.status == .enabled,
            status: feed?.state ?? .off,
            entryCount: feed?.store.entries.count ?? 0,
            locked: locked,
            requestAccess: windowAccess.requestAccess,
            checkAgain: {
                windowAccess.refresh()
                feed?.refreshAccess()
            },
            openSystemSettings: windowAccess.openSystemSettings,
            clear: { feed?.store.clear() })
        .onAppear { windowAccess.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            windowAccess.refresh()
        }
    }
}

/// The card's rendering, driven by plain values so each state is previewable.
struct NotificationFeedSettingsCardContent: View {
    @Binding var isOn: Bool
    let accessGranted: Bool
    let status: NotificationFeedController.State
    let entryCount: Int
    let locked: Bool
    let requestAccess: () -> Void
    let checkAgain: () -> Void
    let openSystemSettings: () -> Void
    let clear: () -> Void

    var body: some View {
        SettingsCard(title: .notificationFeedName, footnote: .notificationFeedSettingsHelp) {
            SettingsToggleRow(title: .notificationFeedToggle, subtitle: .notificationFeedToggleHelp, isOn: $isOn)
                .disabled(locked)
            if isOn && !accessGranted {
                SettingsStatusRow(symbol: "exclamationmark.triangle.fill", tint: .orange,
                                  message: Text(.notificationFeedPermission)) {
                    Button(.windowAccessEnable, action: requestAccess)
                        .buttonStyle(.borderedProminent)
                    SettingsMoreMenu {
                        Button(.windowAccessCheckAgain, action: checkAgain)
                        Button(.windowAccessOpenSettings, action: openSystemSettings)
                    }
                }
            } else if isOn, let message = statusMessage {
                SettingsStatusRow(symbol: status == .listening ? "checkmark.circle.fill" : "hourglass",
                                  tint: status == .listening ? .green : .secondary,
                                  message: Text(message)) {
                    EmptyView()
                }
            }
            SettingsStackedRow {
                Label { Text(.notificationFeedPrivacyNote) } icon: {
                    Image(systemName: "lock.shield").foregroundStyle(.secondary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            if isOn {
                SettingsActionRow {
                    Button(role: .destructive, action: clear) { Text(.notificationFeedClear) }
                        .disabled(entryCount == 0)
                }
            }
        }
    }

    private var statusMessage: LocalizedStringResource? {
        switch status {
        case .listening: .notificationFeedListening
        case .waiting: .notificationFeedWaitingTitle
        case .needsAccess, .off: nil
        }
    }
}

#if DEBUG
private func notificationFeedCard(isOn: Bool, access: Bool, status: NotificationFeedController.State,
                                  entries: Int = 0) -> some View {
    NotificationFeedSettingsCardContent(isOn: .constant(isOn), accessGranted: access, status: status,
                                        entryCount: entries, locked: false, requestAccess: {},
                                        checkAgain: {}, openSystemSettings: {}, clear: {})
        .padding(24)
        .frame(width: SettingsMetrics.columnWidth)
}

#Preview("Off") {
    notificationFeedCard(isOn: false, access: false, status: .off)
}

#Preview("On, needs access") {
    notificationFeedCard(isOn: true, access: false, status: .needsAccess)
}

#Preview("Collecting, dark") {
    notificationFeedCard(isOn: true, access: true, status: .listening, entries: 7)
        .preferredColorScheme(.dark)
}

#Preview("Waiting, German") {
    notificationFeedCard(isOn: true, access: true, status: .waiting)
        .environment(\.locale, Locale(identifier: "de"))
}
#endif
