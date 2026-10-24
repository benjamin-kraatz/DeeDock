import SwiftUI

/// A note card in the uninstall sheet: a symbol, a bold first sentence, the rest in secondary text, and
/// optional buttons.
///
/// Information (the password, a running app) is neutral. Orange is kept for things that need the user
/// (Full Disk Access, an extension the Trash can't remove); red for a stopped removal.
struct HubUninstallNote<Actions: View>: View {
    enum Tone { case info, warning, error }

    let tone: Tone
    let symbol: String
    let title: Text
    let detail: Text
    @ViewBuilder var actions: Actions

    init(tone: Tone, symbol: String, title: Text, detail: Text, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.tone = tone
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(accent ?? .secondary)
                .frame(width: 16)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 9) {
                Text("\(title.fontWeight(.semibold).foregroundStyle(.primary)) \(detail)")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) { actions }
                    .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12.5))
        .lineSpacing(1.5)
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(accent.map { $0.opacity(0.1) } ?? Color.primary.opacity(0.045))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(accent.map { $0.opacity(0.38) } ?? Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .padding(.bottom, 8)
        // Combined text reads as one sentence; notes with buttons keep them reachable.
        .accessibilityElement(children: Actions.self == EmptyView.self ? .combine : .contain)
    }

    private var accent: Color? {
        switch tone {
        case .info: nil
        case .warning: .orange
        case .error: .red
        }
    }
}

/// The notes above the sections, by phase: why removal stopped; or that the password will be asked, that
/// the app will be quit, and that an extension needs its own uninstaller.
struct HubUninstallNotices: View {
    let session: AppUninstallSession
    let uninstaller: HubAppsUninstaller

    var body: some View {
        if case .stopped(let reason) = session.phase {
            HubUninstallNote(tone: .error, symbol: "xmark.octagon", title: Text(.hubUninstallStoppedTitle(name: session.appName)),
                             detail: Text(stopDetail(reason)))
                .transition(.opacity.combined(with: .offset(y: -4)))
        }
        if session.isEditable || session.phase == .scanning, let target = session.target {
            if session.needsPassword {
                HubUninstallNote(tone: .info, symbol: "lock",
                                 title: Text(target.ownedByRoot ? target.source.passwordTitle : .hubUninstallPasswordShared),
                                 detail: Text(.hubUninstallPasswordDetail))
            }
            if session.isRunning {
                HubUninstallNote(tone: .info, symbol: "power", title: Text(.hubUninstallRunningTitle(name: session.appName)),
                                 detail: Text(.hubUninstallRunningDetail))
            }
            if target.hasSystemExtensions {
                HubUninstallNote(tone: .warning, symbol: "exclamationmark.triangle",
                                 title: Text(.hubUninstallExtensionTitle(name: session.appName)),
                                 detail: Text(.hubUninstallExtensionDetail)) {
                    if target.vendorUninstaller != nil {
                        Button { uninstaller.openVendorUninstaller() } label: { Text(.hubUninstallOpenUninstaller) }
                            .buttonStyle(.borderedProminent)
                    }
                    Button { uninstaller.openExtensionsSettings() } label: { Text(.hubUninstallExtensionSettings) }
                }
            }
        }
    }

    private func stopDetail(_ reason: AppUninstallSession.Stop) -> LocalizedStringResource {
        switch reason {
        case .passwordCancelled: .hubUninstallStoppedPassword
        case .stillOpen: .hubUninstallStoppedOpen
        case .failed: .hubUninstallStoppedFailed
        }
    }
}
