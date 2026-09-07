import SwiftUI

/// Device names come from macOS; lifecycle/status copy stays in the string catalog.
struct DisplayProfileRow: View {
    let profile: DisplayProfile
    let snapshot: DisplaySnapshot?

    private var status: LocalizedStringResource {
        guard let snapshot else { return .displayDisconnected }
        if snapshot.isPrimary { return .displayPrimaryConnected }
        if !snapshot.isPersistent { return .displaySessionOnly }
        if snapshot.mirrorSource != nil { return .displayMirrored }
        return .displayConnected
    }

    /// A disabled dock reads as switched off, so its tile loses the section color too.
    private var tileColors: [Color] {
        profile.enabled ? SettingsSection.dock.tileColors : [Color(red: 0.62, green: 0.65, blue: 0.70),
                                                             Color(red: 0.40, green: 0.43, blue: 0.48)]
    }

    var body: some View {
        HStack(spacing: 8) {
            // Matched to the section tiles above so both groups share one leading edge.
            SettingsIconTile(glyph: .symbol("display"), colors: tileColors)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: profile.name).lineLimit(1)
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if !profile.enabled {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(.displayDockDisabled))
            }
        }
        .padding(.vertical, 1)
    }
}
