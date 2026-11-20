import SwiftUI

/// The folders watched for new, saved, and downloaded files, each with its switch and whether
/// DOKK may read it. **Allow…** is the explicit request that lets macOS ask; **Add Folder…** asks
/// right after you choose one.
struct FlixWatchedFoldersCard: View {
    let store: FlixSettingsStore
    let requestingAccess: String?
    let requestAccess: (String) -> Void
    let addFolder: (URL) -> Void

    private let policy = FlixReadPolicy(allowedRoots: [])

    var body: some View {
        SettingsCard(title: .flixSettingsWatchedFolders, footnote: .flixSettingsWatchedFoldersHelp, dividerInset: 44) {
            ForEach(store.settings.watchedFolders) { folder in
                FlixWatchedFolderRow(folder: folder, needsPermission: policy.isProtected(folder.path),
                                     requesting: requestingAccess == folder.path,
                                     isOn: Binding(get: { folder.isEnabled }, set: { value in
                                         guard let index = store.settings.watchedFolders.firstIndex(where: { $0.id == folder.id })
                                         else { return }
                                         store.settings.watchedFolders[index].isEnabled = value
                                     }),
                                     allow: { requestAccess(folder.path) },
                                     remove: { store.removeWatchedFolder(folder.path) })
            }
            SettingsListFooter {
                Button(action: chooseFolder) {
                    Label { Text(.flixSettingsAddFolder) } icon: { Image(systemName: "plus") }
                }
            }
        }
        .disabled(!store.settings.tracksWatchedFolders)
    }

    /// An open panel is the explicit choice; what it returns may be read at once.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: .flixSettingsAddFolderPrompt)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addFolder(url)
    }
}

/// One watched folder: its name and place, access, switch, and a menu to remove it.
private struct FlixWatchedFolderRow: View {
    let folder: FlixWatchedFolder
    let needsPermission: Bool
    let requesting: Bool
    @Binding var isOn: Bool
    let allow: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            LookoutFolderGlyph(size: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: FileManager.default.displayName(atPath: folder.path)).lineLimit(1)
                Text(status).font(.caption).foregroundStyle(statusColor).lineLimit(1)
            }
            Spacer(minLength: 8)
            if requesting {
                ProgressView().controlSize(.small)
            } else if needsPermission, folder.access != .allowed, folder.access != .missing {
                Button(action: allow) { Text(.flixSettingsAllow) }.controlSize(.small)
            }
            Toggle(isOn: $isOn) { Text(verbatim: folder.path) }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            SettingsMoreMenu {
                Button(role: .destructive, action: remove) { Text(.flixSettingsRemoveFolder) }
            }
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, SettingsMetrics.rowVerticalInset)
        .frame(minHeight: SettingsMetrics.rowMinimumHeight)
        .accessibilityElement(children: .contain)
    }

    private var status: LocalizedStringResource {
        switch folder.access {
        case .missing: .flixAccessMissing
        case .denied: .flixAccessDenied
        case .allowed: .flixAccessAllowed
        case .unknown: needsPermission ? .flixAccessAsk : .flixAccessAllowed
        }
    }

    private var statusColor: Color {
        switch folder.access {
        case .denied, .missing: .orange
        default: .secondary
        }
    }
}
