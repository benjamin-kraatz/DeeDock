import AppKit
import SwiftUI

/// The header search field, bound to the visible tab's query and prompt.
///
/// Focus is driven from AppKit through request counters on ``HubShellState`` (⌘F, opening on a
/// tab, a tab's `focusSearchField()`), and the field reports its own focus back so the key monitor
/// can tell tabs whether an event was typed into it.
struct HubSearchField: View {
    @Binding var query: String
    let prompt: LocalizedStringResource
    let state: HubShellState

    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            TextField(text: $query, prompt: Text(prompt)) {
                Text(prompt)
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13.5))
            .focused($focused)
            if !query.isEmpty {
                Button {
                    query = ""
                    state.requestSearchFocus()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(Text(.hubSearchClear))
                .accessibilityLabel(Text(.hubSearchClear))
                .transition(.opacity)
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, 8)
        .frame(width: HubStyle.searchFieldWidth, height: 34)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.05), in: shape)
        .overlay { shape.strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.075), lineWidth: 0.5) }
        // The mockup's focus ring: a soft 3 pt accent halo outside the field.
        .overlay {
            shape
                .inset(by: -2)
                .strokeBorder(Color.accentColor.opacity(focused ? 0.4 : 0), lineWidth: 3)
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.2), value: focused)
        .animation(.easeOut(duration: 0.15), value: query.isEmpty)
        .contentShape(shape)
        .onTapGesture { focused = true }
        .onChange(of: state.searchFocusRequest) {
            focused = true
            guard state.searchFocusPlacesCaretAtEnd else { return }
            // AppKit selects a text field's contents when it becomes first responder. Collapse the
            // selection on the next turn, once the field editor exists, so type-to-search appends.
            DispatchQueue.main.async {
                guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
                editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
            }
        }
        .onChange(of: state.contentFocusRequest) { focused = false }
        .onChange(of: focused) { _, value in state.searchFieldFocused = value }
    }
}

#Preview("Search field") {
    @Previewable @State var query = ""
    @Previewable @State var filled = "Downloads"
    VStack(spacing: 16) {
        HubSearchField(query: $query, prompt: .hubTabFiles, state: HubShellState(tab: .files))
        HubSearchField(query: $filled, prompt: .hubTabFiles, state: HubShellState(tab: .files))
    }
    .padding(24)
}
