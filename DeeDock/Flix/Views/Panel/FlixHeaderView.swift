import SwiftUI

/// Title and count, ✦ Tidy, search (a button that becomes the field), and the pin.
///
/// Every control is an icon, so the header stays quiet: Tidy is used now and then, and it steps
/// away while search is open. The title keeps its width first and the search field gives way, so
/// a long German title or count never pushes the buttons out: the field shrinks from 220 points
/// down to 120.
struct FlixHeaderView: View {
    let state: FlixPanelState
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: state.title)
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 220, alignment: .leading)
                .fixedSize(horizontal: !state.searchActive, vertical: false)
                .layoutPriority(2)
                .accessibilityAddTraits(.isHeader)
                .help(Text(verbatim: state.title))
            Text(.flixItemCount(count))
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(FlixStyle.faint)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(3)
                .contentTransition(state.reduceMotion ? .identity : .numericText(value: Double(count)))
                .animation(state.reduceMotion ? nil : state.motion(FlixMotion.row), value: count)
            Spacer(minLength: 4)
            if state.intelligence.canTidy, !state.searchActive {
                FlixHeaderButton(help: .flixTidyHelp, action: state.openTidy) {
                    Image(systemName: "wand.and.sparkles")
                }
                .layoutPriority(3)
                .transition(.opacity)
            }
            FlixSearchField(state: state)
                .layoutPriority(1)
            FlixHeaderButton(help: state.isPinned ? .flixUnpinHelp : .flixPinHelp, active: state.isPinned,
                             action: state.togglePin) {
                Image(systemName: state.isPinned ? "pin.fill" : "pin")
                    .contentTransition(state.reduceMotion ? .identity : .symbolEffect(.replace))
            }
            .layoutPriority(3)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: FlixStyle.headerHeight)
        // Tidy steps away in the same motion as the field opens.
        .animation(state.reduceMotion ? nil : FlixMotion.field, value: state.searchActive)
    }
}

/// A small borderless header button, tinted while its mode is on. Hover and press only highlight.
struct FlixHeaderButton<Label: View>: View {
    let help: LocalizedStringResource
    var active = false
    let action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(FlixHeaderButtonStyle(active: active))
            .help(Text(help))
            .accessibilityLabel(Text(help))
            .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// The header button's look: quiet until hovered, accent-tinted while on, dimmed while pressed.
private struct FlixHeaderButtonStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: FlixStyle.controlRadius, style: .continuous)
        FlixHover { hovered in
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .frame(minWidth: 28, minHeight: 26)
                .foregroundStyle(active ? Color.accentColor : hovered ? Color.primary : Color.secondary)
                .background(active ? FlixStyle.accentSoft : hovered ? FlixStyle.hover : .clear, in: shape)
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(.rect)
                .contentShape(.focusEffect, shape)
                .animation(FlixMotion.hover, value: active)
        }
    }
}

#if DEBUG
#Preview("Header") {
    VStack(spacing: 0) {
        FlixHeaderView(state: FlixPreviewData.panelState(withIntelligence: true), count: 12)
        FlixHairline()
        FlixHeaderView(state: FlixPreviewData.panelState(.tokens), count: 3)
    }
    .frame(width: 516)
}

#Preview("Header, German, searching") {
    FlixHeaderView(state: FlixPreviewData.panelState(.tokens), count: 128)
        .frame(width: 516)
        .environment(\.locale, Locale(identifier: "de"))
}
#endif
