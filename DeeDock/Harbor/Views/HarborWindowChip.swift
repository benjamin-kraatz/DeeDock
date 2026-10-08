import SwiftUI

/// A minimized or hidden window, shown as a chip inside its app's group. Choosing it restores
/// the window: unminimizes it, or unhides its app, then brings it forward.
struct HarborWindowChip: View {
    let title: String
    let state: HarborWindowState
    let icon: NSImage?
    let activate: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    private var stateText: LocalizedStringResource { state == .minimized ? .harborMinimized : .harborHidden }

    var body: some View {
        Button(action: activate) {
            HStack(spacing: 6) {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 18, height: 18)
                }
                Text(verbatim: title).lineLimit(1).truncationMode(.tail)
                Text(verbatim: "· " + String(localized: stateText)).foregroundStyle(.secondary).fixedSize()
            }
            .font(.system(size: 12))
            .padding(.leading, 6)
            .padding(.trailing, 11)
            .frame(height: 28)
            .background(Capsule().fill(colorScheme == .dark ? Color.white.opacity(hovering ? 0.2 : 0.1)
                                                            : Color.black.opacity(hovering ? 0.12 : 0.06)))
            .overlay(Capsule().strokeBorder(colorScheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.09), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(stateText))
    }
}

#if DEBUG
#Preview("Chips") {
    HStack {
        HarborWindowChip(title: "Angebot für Weber", state: .minimized, icon: nil, activate: {})
        HarborWindowChip(title: "Musik", state: .hidden, icon: nil, activate: {})
    }
    .padding(40)
    .background(HarborBackdrop(wallpaper: nil, reduceTransparency: false))
}
#endif
