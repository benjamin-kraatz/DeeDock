import SwiftUI

/// The search field, which grows out of the search button while search is on.
///
/// Its placeholder invites a sentence when a provider understands them ("✦ Ask in your own words")
/// and a name otherwise. Focus mirrors into the state so typed keys reach the field, not the list.
/// The field is up to 220 points wide and gives way down to 120 when the header is crowded. With
/// Reduce Motion it appears at once.
struct FlixSearchField: View {
    @Bindable var state: FlixPanelState
    @FocusState private var focused: Bool

    private var plainWords: Bool { state.intelligence.searchesInPlainWords }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FlixStyle.controlRadius, style: .continuous)
        HStack(spacing: 6) {
            if plainWords { FlixSparkle(size: 11) } else {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            TextField(text: $state.searchText) {
                Text(plainWords ? .flixSearchPlaceholderWords : .flixSearchPlaceholder)
            }
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .focused($focused)
            .accessibilityLabel(Text(.flixSearchHelp))
        }
        .padding(.horizontal, 8)
        .frame(minWidth: state.searchActive ? 120 : 0, maxWidth: state.searchActive ? 220 : 0)
        .frame(height: 26)
        .background(FlixStyle.field, in: shape)
        .overlay(shape.strokeBorder(focused ? Color.accentColor.opacity(0.7) : FlixStyle.outline, lineWidth: focused ? 1 : 0.5))
        .opacity(state.searchActive ? 1 : 0)
        .clipped()
        .animation(state.reduceMotion ? nil : FlixMotion.field, value: state.searchActive)
        .animation(state.reduceMotion ? nil : FlixMotion.hover, value: focused)
        .accessibilityHidden(!state.searchActive)
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
}
