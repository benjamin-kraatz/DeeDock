import SwiftUI

/// Search: a magnifier button that becomes the search field.
///
/// One view in both states, so the button itself widens into the field: its trailing edge stays
/// put, the field grows to the left, and the glyph slides from the button's middle to the field's
/// leading edge. A close button inside the field turns it back into the button; Escape does too.
///
/// The placeholder invites a sentence when a provider understands them ("✦ Ask in your own words"),
/// with a sparkle in place of the magnifier, and a name otherwise. Focus mirrors into the state so
/// typed keys reach the field, not the list. The field is up to 220 points wide and gives way down
/// to 120 when the header is crowded. With Reduce Motion it changes at once.
struct FlixSearchField: View {
    @Bindable var state: FlixPanelState
    @FocusState private var focused: Bool

    private var plainWords: Bool { state.intelligence.searchesInPlainWords }
    private var active: Bool { state.searchActive }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FlixStyle.controlRadius, style: .continuous)
        FlixHover { hovered in
            HStack(spacing: 6) {
                glyph(hovered: hovered)
                TextField(text: $state.searchText) {
                    Text(plainWords ? .flixSearchPlaceholderWords : .flixSearchPlaceholder)
                }
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($focused)
                .opacity(active ? 1 : 0)
                .allowsHitTesting(active)
                .accessibilityLabel(Text(.flixSearchHelp))
                .accessibilityHidden(!active)
                if active { closeButton.transition(.opacity) }
            }
            .padding(.horizontal, 6)
            .frame(minWidth: active ? 120 : 28, maxWidth: active ? 220 : 28, alignment: .leading)
            .frame(height: 26)
            .background(active ? FlixStyle.field : hovered ? FlixStyle.hover : .clear, in: shape)
            .overlay(shape.strokeBorder(active ? (focused ? Color.accentColor.opacity(0.7) : FlixStyle.outline) : .clear,
                                        lineWidth: focused ? 1 : 0.5))
            .clipShape(shape)
            .overlay { if !active { openButton(shape) } }
        }
        .animation(state.reduceMotion ? nil : FlixMotion.field, value: active)
        .animation(state.reduceMotion ? nil : FlixMotion.hover, value: focused)
        .onChange(of: state.searchFocusRequest) { _, _ in focused = true }
        .onChange(of: focused) { _, value in
            state.searchFieldFocused = value
            // Focusing selects the field's text; type-to-search already put the first character
            // there, so the caret goes after it or the next key would replace it.
            guard value else { return }
            DispatchQueue.main.async {
                (NSApp.keyWindow?.firstResponder as? NSTextView)?.moveToEndOfDocument(nil)
            }
        }
        .onChange(of: state.searchActive) { _, active in if !active { focused = false } }
    }

    /// The magnifier, or the sparkle once the field is open and understands sentences. Centered in
    /// the closed button (6 + 16 + 6 points), at the field's leading edge when open.
    @ViewBuilder private func glyph(hovered: Bool) -> some View {
        Group {
            if active, plainWords { FlixSparkle(size: 11) } else { Image(systemName: "magnifyingglass") }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(!active && hovered ? Color.primary : Color.secondary)
        .frame(width: 16)
        .accessibilityHidden(true)
    }

    /// Covers the closed button: a real button for clicks, keyboard focus, and VoiceOver.
    private func openButton(_ shape: RoundedRectangle) -> some View {
        Button { state.setSearchActive(true) } label: { Color.clear.contentShape(shape) }
            .buttonStyle(.plain)
            .help(Text(.flixSearchHelp))
            .accessibilityLabel(Text(.flixSearchHelp))
    }

    private var closeButton: some View {
        Button { state.setSearchActive(false) } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11.5))
                .foregroundStyle(FlixStyle.faint)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(Text(.flixSearchClose))
        .accessibilityLabel(Text(.flixSearchClose))
    }
}
