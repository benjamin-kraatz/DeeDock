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

    var body: some View {
        HStack(spacing: 8) {
            // Matched to the category tiles above so both groups share one leading edge.
            Image(systemName: "display")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
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
        .padding(.vertical, 3)
    }
}
