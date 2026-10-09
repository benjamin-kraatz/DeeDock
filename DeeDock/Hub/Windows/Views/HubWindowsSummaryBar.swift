import SwiftUI

/// The line above the window groups: "N windows in M apps" and the Open Radar button.
struct HubWindowsSummaryBar: View {
    let windowCount: Int
    let appCount: Int
    let openRadar: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(.hubWindowsSummary(String(localized: .hubWindowsWindowCount(windowCount)),
                                    String(localized: .hubWindowsAppCount(appCount))))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.snappy, value: windowCount)
            Spacer(minLength: 0)
            HubWindowsBarButton(symbol: "scope", title: .hubWindowsOpenRadar, action: openRadar)
        }
        .padding(.horizontal, 22)
        .frame(height: 44)
    }
}

/// The mockup's `.btn2`: a small chip button with a symbol and title that brightens on hover.
struct HubWindowsBarButton: View {
    let symbol: String
    let title: LocalizedStringResource
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Label { Text(title) } icon: { Image(systemName: symbol).font(.system(size: 12, weight: .medium)) }
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12.5))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.075),
                                  lineWidth: 0.5))
                .contentShape(.rect)
        }
        .buttonStyle(.hubPress(scale: 0.96))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var fill: Color {
        switch (colorScheme == .dark, isHovered) {
        case (true, false): .white.opacity(0.08)
        case (true, true): .white.opacity(0.15)
        case (false, false): .black.opacity(0.05)
        case (false, true): .black.opacity(0.09)
        }
    }
}

#if DEBUG
#Preview("Summary bar") {
    HubWindowsSummaryBar(windowCount: 9, appCount: 5, openRadar: {})
        .frame(width: 900)
}
#endif
