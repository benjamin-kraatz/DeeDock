import SwiftUI

/// The search field, which grows out of the search button while search is on.
///
/// Its placeholder invites a sentence when a provider understands them ("✦ Ask in your own words")
/// and a name otherwise. Focus mirrors into the state so typed keys reach the field, not the list.
struct FlixSearchField: View {
    @Bindable var state: FlixPanelState
    @FocusState private var focused: Bool

    private var plainWords: Bool { state.intelligence.searchesInPlainWords }

    var body: some View {
        HStack(spacing: 6) {
            if plainWords { FlixSparkle(size: 11) } else {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
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
        .frame(width: state.searchActive ? 220 : 0, height: 26)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
        .opacity(state.searchActive ? 1 : 0)
        .clipped()
        .animation(state.reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: state.searchActive)
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
