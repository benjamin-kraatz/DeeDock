import SwiftUI

/// Display-specific controls and connection notices; identity stays in the navigation title.
struct DisplaySettingsHeader: View {
    let context: SettingsOverrideContext

    private var profile: DisplayProfile? { context.profiles.document.profiles[context.id] }
    private var snapshot: DisplaySnapshot? { context.profiles.displays.first { $0.id == context.id } }

    private var status: LocalizedStringResource {
        guard let snapshot else { return .displayDisconnected }
        if snapshot.isPrimary { return .displayPrimaryConnected }
        if !snapshot.isPersistent { return .displaySessionOnly }
        if snapshot.mirrorSource != nil { return .displayMirrored }
        return .displayConnected
    }

    /// At most one caveat is worth a line of its own under the identity.
    private var notice: LocalizedStringResource? {
        if profile?.isPersistent == false { return .displayIdentityWarning }
        if snapshot == nil { return .displayDisconnectedHelp }
        if snapshot?.mirrorSource != nil { return .displayMirrorHelp }
        return nil
    }

    var body: some View {
        if let profile {
            SettingsCard {
                SettingsRow(title: .displayShowDock, subtitle: status) {
                    Toggle(isOn: Binding(get: { profile.enabled },
                                         set: { context.profiles.setEnabled($0, for: context.id) })) {
                        Text(.displayShowDock)
                    }
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel(Text(.displayShowDock))
                }

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
    }
}

#if DEBUG
#Preview("Connected display") {
    let profiles = DisplaySettingsPreview.make()
    ScrollView {
        DisplaySettingsHeader(context: SettingsOverrideContext(profiles: profiles, id: "display.preview2"))
            .padding(24)
    }
    .frame(width: 620, height: 420)
}
#Preview("Disconnected display — dark") {
    let profiles = DisplaySettingsPreview.make()
    ScrollView {
        DisplaySettingsHeader(context: SettingsOverrideContext(profiles: profiles, id: "display.preview3"))
            .padding(24)
    }
    .preferredColorScheme(.dark)
    .frame(width: 620, height: 420)
}
#endif
