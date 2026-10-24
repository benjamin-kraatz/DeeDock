import SwiftUI

/// A section heading in the sheet: an optional leading control, the title, and a trailing value.
struct HubUninstallSectionHeader<Leading: View>: View {
    let title: LocalizedStringResource
    var trailing: Text?
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 9) {
            leading.frame(width: 18)
            Text(title).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing.fontWeight(.medium).monospacedDigit()
        }
        .hubUninstallSectionHeading()
    }
}

/// The app bundle and, when the app is pinned, the Unpin checkbox.
struct HubUninstallAppSection: View {
    @Bindable var session: AppUninstallSession

    var body: some View {
        HubUninstallSectionHeader(title: .hubUninstallSectionApp) { EmptyView() }
        HubUninstallAppRow(session: session)
        if session.pinnedDisplayCount > 0 {
            Toggle(isOn: $session.unpin) {
                Text(.hubUninstallUnpin(session.pinnedDisplayCount)).font(.system(size: 12.5))
            }
            .toggleStyle(.checkbox)
            .disabled(!session.isEditable)
            .padding(EdgeInsets(top: 8, leading: 8, bottom: 2, trailing: 8))
        }
    }
}

/// The app's own data: a select-all checkbox, the Full Disk Access card when macOS hides some of it, and
/// one row per item.
struct HubUninstallDataSection: View {
    let session: AppUninstallSession

    var body: some View {
        let selectable = session.dataItems.filter { !$0.isProtected }
        HubUninstallSectionHeader(title: .hubUninstallSectionData, trailing: total) {
            if !selectable.isEmpty {
                Toggle(sources: selectable.map(binding), isOn: \.self) { EmptyView() }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(!session.isEditable)
                    .accessibilityLabel(Text(.hubUninstallSelectAllData))
            }
        }
        if session.phase == .scanning {
            // The header already shows the spinner; a second one here would compete with it.
            Text(.hubUninstallChecking)
                .font(.system(size: 12.5))
                .foregroundStyle(.tertiary)
                .padding(EdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8))
        } else if session.dataItems.isEmpty {
            Text(.hubUninstallNoData)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        } else {
            if session.protectedCount > 0, session.isEditable {
                HubUninstallAccessCard(session: session)
                    .transition(.opacity)
            }
            ForEach(session.dataItems) { item in
                HubUninstallItemRow(session: session, item: item)
            }
        }
    }

    private var total: Text? {
        let bytes = session.selectedItems.filter { $0.match != .similarName }.reduce(Int64(0)) { sum, item in
            if case .size(let size) = session.measures[item.id] { sum + size } else { sum }
        }
        return bytes > 0 ? Text(verbatim: AppUninstallFormat.bytes(bytes)) : nil
    }

    private func binding(_ item: AppLeftover) -> Binding<Bool> {
        Binding(get: { session.isSelected(item) }, set: { session.setSelected($0, item) })
    }
}

/// Name-only matches, collapsed by default and never selected by DOKK.
struct HubUninstallRelatedSection: View {
    @Bindable var session: AppUninstallSession

    var body: some View {
        DisclosureGroup(isExpanded: $session.relatedExpanded) {
            Text(.hubUninstallRelatedHint)
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(EdgeInsets(top: 0, leading: 8, bottom: 4, trailing: 8))
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(session.relatedItems) { item in
                HubUninstallItemRow(session: session, item: item)
            }
        } label: {
            HStack(spacing: 9) {
                Text(.hubUninstallSectionRelated).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                // The size shows even while collapsed, so a large unselected folder isn't missed.
                Text(verbatim: relatedSummary).fontWeight(.medium).monospacedDigit()
            }
        }
        .disclosureGroupStyle(.hubUninstall)
    }

    private var relatedSummary: String {
        let bytes = session.relatedItems.reduce(Int64(0)) { sum, item in
            if case .size(let size) = session.measures[item.id] { sum + size } else { sum }
        }
        let count = "\(session.relatedItems.count)"
        return bytes > 0 ? "\(count) · \(AppUninstallFormat.bytes(bytes))" : count
    }
}

/// Why some of the app's data stays, and the way to change it: Full Disk Access, then a relaunch, after
/// which the sheet reopens for the same app.
///
/// DOKK can't tell whether the user allowed it until it relaunches, so after System Settings opens the
/// card asks for the relaunch instead of claiming access was granted.
struct HubUninstallAccessCard: View {
    let session: AppUninstallSession

    var body: some View {
        switch session.accessStage {
        case .idle:
            HubUninstallNote(tone: .warning, symbol: "lock",
                             title: Text(.hubUninstallAccessTitle(session.protectedCount)),
                             detail: Text(.hubUninstallAccessDetail(name: session.appName))) {
                Button { session.openAccessSettings() } label: { Text(.folderStackOpenFullDiskAccess) }
            }
            .padding(.top, 2)
        case .openedSettings:
            HubUninstallNote(tone: .info, symbol: "arrow.clockwise",
                             title: Text(.hubUninstallAccessRelaunchTitle),
                             detail: Text(.hubUninstallAccessRelaunchDetail)) {
                Button { session.relaunch() } label: { Text(.hubUninstallRelaunch) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 2)
            .transition(.opacity.combined(with: .offset(y: -4)))
        }
    }
}
