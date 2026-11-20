import SwiftUI

/// Title and count, ✦ Tidy, the search field that grows from its button, and the pin.
struct FlixHeaderView: View {
    let state: FlixPanelState
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: state.title)
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
                .frame(maxWidth: 220, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Text(.flixItemCount(count))
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            FlixSearchField(state: state)
            if state.intelligence.canTidy {
                FlixHeaderButton(help: .flixTidyHelp, action: state.openTidy) {
                    HStack(spacing: 4) {
                        FlixSparkle(size: 11)
                        Text(.flixTidy)
                    }
                }
            }
            FlixHeaderButton(help: .flixSearchHelp, active: state.searchActive,
                             action: { state.setSearchActive(!state.searchActive) }) {
                Image(systemName: "magnifyingglass")
            }
            FlixHeaderButton(help: state.isPinned ? .flixUnpinHelp : .flixPinHelp, active: state.isPinned,
                             action: state.togglePin) {
                Image(systemName: state.isPinned ? "pin.fill" : "pin")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: FlixStyle.headerHeight)
    }
}

/// A small borderless header button, tinted while its mode is on.
struct FlixHeaderButton<Label: View>: View {
    let help: LocalizedStringResource
    var active = false
    let action: () -> Void
    @ViewBuilder var label: Label
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 12))
                .padding(.horizontal, 6)
                .frame(minWidth: 28, minHeight: 26)
                .foregroundStyle(active ? Color.accentColor : hovered ? .primary : .secondary)
                .background(active ? Color.accentColor.opacity(0.2) : hovered ? FlixStyle.hover : .clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(Text(help))
        .accessibilityLabel(Text(help))
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
