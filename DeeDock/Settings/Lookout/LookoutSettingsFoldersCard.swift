import SwiftUI

/// The folders Lookout reads, each with its path and how many of its files are searchable, and a way to remove it;
/// then "Add folder…" and the total (the mockup's folders card). A folder that isn't there right now, or that macOS
/// doesn't let Lookout read, says so, the latter with a way to System Settings.
struct LookoutSettingsFoldersCard: View {
    let model: LookoutSettingsModel

    var body: some View {
        SettingsCard(title: .lookoutSettingsFolders) {
            ForEach(model.folders, id: \.self) { folder in
                LookoutSettingsFolderRow(
                    name: LookoutSetupFolder.displayName(of: folder, home: model.home),
                    path: LookoutSetupFolder.tildePath(folder, home: model.home),
                    state: state(of: folder),
                    remove: { model.removeFolder(folder) },
                    openSettings: { model.openPrivacySettings() })
            }
            if let notice = model.notice {
                LookoutSettingsNoticeRow(notice: notice, home: model.home) { model.openPrivacySettings() }
            }
            HStack {
                Button { Task { await model.addFolder() } } label: { LookoutAddFolderLabel() }
                .buttonStyle(.plain)
                Spacer()
                Text(.lookoutSetupFiles(model.totalCount))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, SettingsMetrics.rowInset)
            .frame(minHeight: SettingsMetrics.rowMinimumHeight)
        }
    }

    private func state(of folder: String) -> LookoutSettingsFolderRow.State {
        if model.isMissing(folder) { return .missing }
        if model.isNotPermitted(folder) { return .notPermitted }
        return .indexed(model.folderCounts[folder])
    }
}

/// One folder of the card.
struct LookoutSettingsFolderRow: View {
    enum State: Equatable {
        /// Searchable files under it; nil before the count arrives.
        case indexed(Int?)
        case missing
        case notPermitted
    }

    let name: String
    let path: String
    let state: State
    let remove: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            LookoutFolderGlyph(size: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                Text(verbatim: path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .layoutPriority(1)
            Spacer(minLength: SettingsMetrics.controlSpacing)
            trailing
            Button(action: remove) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(Text(.lookoutSettingsRemoveFolder))
            .accessibilityLabel(Text(.lookoutSettingsRemoveFolderNamed(name)))
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, SettingsMetrics.rowVerticalInset)
        .frame(minHeight: SettingsMetrics.rowMinimumHeight)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var trailing: some View {
        switch state {
        case .indexed(let count?):
            Text(.lookoutSetupFiles(count))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        case .indexed(nil):
            EmptyView()
        case .missing:
            Text(.lookoutSettingsFolderMissing)
                .font(.callout)
                .foregroundStyle(LookoutTheme.paused)
                .multilineTextAlignment(.trailing)
        case .notPermitted:
            Text(.lookoutSettingsFolderNotAllowed)
                .font(.callout)
                .foregroundStyle(LookoutTheme.paused)
            Button(.lookoutSetupOpenSettings, action: openSettings)
                .controlSize(.small)
        }
    }
}

/// Why the folder the person picked wasn't added, or why deleting failed.
private struct LookoutSettingsNoticeRow: View {
    let notice: LookoutSettingsModel.Notice
    let home: String
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(verbatim: message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if notice == .notAllowed {
                Button(.lookoutSetupOpenSettings, action: openSettings)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, SettingsMetrics.rowVerticalInset + 2)
    }

    private var message: String {
        switch notice {
        case .refused(let refusal): String(localized: refusal.message)
        case .alreadyIncluded(let parent):
            String(localized: .lookoutSetupAlreadyIncluded(LookoutSetupFolder.displayName(of: parent, home: home)))
        case .notAllowed: String(localized: .lookoutSettingsAddNotAllowed)
        case .missing: String(localized: .lookoutSetupFolderMissing)
        case .deleteFailed(let reason): String(localized: .lookoutSettingsDeleteFailed(reason))
        case .deleteWaitedTooLong: String(localized: .lookoutSettingsDeleteIndexBusy)
        }
    }
}
