import SwiftUI

/// Shown when Accessibility is off: Harbor can still show windows, but it can only bring their
/// apps forward. Explains what turning it on adds, without warning anyone away.
struct HarborAccessNotice: View {
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(.harborAccessibilityNotice)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: openSettings) { Text(.harborOpenSettings) }
                .controlSize(.small)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: 760)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
    }
}

#if DEBUG
#Preview("Accessibility notice") {
    HarborAccessNotice(openSettings: {})
        .padding(40)
        .background(HarborBackdrop(wallpaper: nil, reduceTransparency: false))
}
#endif
