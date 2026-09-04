import SwiftUI

/// Per-display visibility and status; remembered displays remain editable when disconnected.
///
/// The device identity, its connection state, and the one switch that turns its dock off belong
/// together, so they share a single card the way a device page does elsewhere in macOS.
struct DisplaySettingsHeader: View {
    let context: SettingsOverrideContext
    @Binding var category: SettingsCategory

    private var profile: DisplayProfile? { context.profiles.document.profiles[context.id] }
    private var snapshot: DisplaySnapshot? { context.profiles.displays.first { $0.id == context.id } }

    private var status: LocalizedStringResource {
        guard let snapshot else { return .displayDisconnected }
        if snapshot.isPrimary { return .displayPrimaryConnected }
        if !snapshot.isPersistent { return .displaySessionOnly }
        if snapshot.mirrorSource != nil { return .displayMirrored }
        return .displayConnected
    }

    /// At most one caveat is worth a line of its own under the identity row.
    private var notice: LocalizedStringResource? {
        if profile?.isPersistent == false { return .displayIdentityWarning }
        if snapshot == nil { return .displayDisconnectedHelp }
        if snapshot?.mirrorSource != nil { return .displayMirrorHelp }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let profile {
                SettingsCard {
                    identityRow(profile)
                    if let notice {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: profile.isPersistent ? "info.circle" : "exclamationmark.triangle.fill")
                                .foregroundStyle(profile.isPersistent ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                                .accessibilityHidden(true)
                            Text(notice)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, SettingsMetrics.rowInset)
                        .padding(.vertical, 10)
                    }
                }
            }
            Picker(selection: $category) {
                ForEach(SettingsCategory.allCases) { category in Text(category.title).tag(category) }
            } label: { Text(.settingsGroupDock) }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel(Text(.settingsGroupDock))
        }
    }

    private func identityRow(_ profile: DisplayProfile) -> some View {
        HStack(spacing: 12) {
            SettingsIconTile(glyph: .dock, colors: SettingsCategory.position.tileColors, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: profile.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Toggle(isOn: Binding(get: { profile.enabled },
                                 set: { context.profiles.setEnabled($0, for: context.id) })) {
                Text(.displayShowDock)
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel(Text(.displayShowDock))
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
