import SwiftUI

extension HubTab {
    /// The switcher label.
    var title: LocalizedStringResource {
        switch self {
        case .apps: .hubTabApps
        case .windows: .hubTabWindows
        case .files: .hubTabFiles
        }
    }

    /// The switcher glyph, matching the mockup's app grid, window, and folder drawings.
    var symbol: String {
        switch self {
        case .apps: "square.grid.2x2"
        case .windows: "macwindow"
        case .files: "folder"
        }
    }

    /// ⌘1, ⌘2, ⌘3 in switcher order.
    var shortcutDigit: Character {
        switch self {
        case .apps: "1"
        case .windows: "2"
        case .files: "3"
        }
    }
}

/// The segmented Apps / Windows / Files switcher with a sliding pill.
///
/// The pill moves with ``HubStyle/motion`` through a matched geometry effect, so it slides
/// between segments instead of cross-fading. Reduce Motion moves it without animation.
struct HubTabSwitcher: View {
    let selection: HubTab
    let reduceMotion: Bool
    let select: (HubTab) -> Void

    @Namespace private var pill
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HubTab.allCases) { tab in
                segment(tab)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.05),
                    in: .rect(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.075), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.hubTabSwitcherLabel))
    }

    private func segment(_ tab: HubTab) -> some View {
        let selected = tab == selection
        return Button {
            withAnimation(reduceMotion ? nil : HubStyle.motion) { select(tab) }
        } label: {
            Label {
                Text(tab.title)
            } icon: {
                Image(systemName: tab.symbol)
                    .font(.system(size: 14, weight: .medium))
            }
            .labelStyle(.titleAndIcon)
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(selected ? .primary : .secondary)
            .frame(width: HubStyle.tabSwitcherItemWidth, height: 32)
            .background {
                if selected {
                    HubTabPill()
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(Text(tab.title))
    }
}

/// The raised pill under the selected segment: white in light mode, a brighter chip in dark mode.
private struct HubTabPill: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        shape
            .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.white)
            .overlay { shape.strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.12), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
    }
}

#Preview("Tab switcher") {
    @Previewable @State var tab: HubTab = .windows
    HubTabSwitcher(selection: tab, reduceMotion: false) { tab = $0 }
        .padding(24)
}
