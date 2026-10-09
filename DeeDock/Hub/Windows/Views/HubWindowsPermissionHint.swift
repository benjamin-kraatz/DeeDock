import SwiftUI

/// A quiet line under the summary when a permission is off, saying what turning it on adds and
/// offering the matching System Settings pane. Never warns people away from the tab.
struct HubWindowsPermissionHint: View {
    let access: HarborAccess
    let openAccessibilitySettings: () -> Void
    let openScreenRecordingSettings: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !access.windows {
                row(symbol: "macwindow", message: .hubWindowsAccessibilityHint, action: openAccessibilitySettings)
            }
            if !access.thumbnails {
                row(symbol: "rectangle.dashed.badge.record", message: .hubWindowsScreenRecordingHint,
                    action: openScreenRecordingSettings)
            }
        }
        .padding(.horizontal, 22)
    }

    private func row(symbol: String, message: LocalizedStringResource, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(action: action) { Text(.hubWindowsOpenSystemSettings) }
                .controlSize(.small)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: HubStyle.rowRadius + 2, style: .continuous)
            .fill(colorScheme == .dark ? Color.white.opacity(0.045) : Color.white.opacity(0.5)))
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Permission hints") {
    HubWindowsPermissionHint(access: HarborAccess(windows: false, thumbnails: false),
                             openAccessibilitySettings: {}, openScreenRecordingSettings: {})
        .frame(width: 900)
        .padding(.vertical)
}
#endif
