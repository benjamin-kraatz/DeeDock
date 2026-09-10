import SwiftUI

/// The folder panel's filter field, shown only once a listing is long enough to be worth filtering.
///
/// The panel owns keyboard focus: its key handler moves the selection with the arrow keys while the
/// user keeps typing, so the field never claims those keys itself.
struct FolderStackSearchField: View {
    @Bindable var state: FolderStackState
    @FocusState.Binding var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var matchCount: Int { state.visibleEntries.count }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(focused ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
            TextField(text: $state.query, prompt: Text(.folderStackSearchPrompt)) {
                Text(.folderStackSearch)
            }
            .textFieldStyle(.plain)
            .labelsHidden()
            .focused($focused)
            .autocorrectionDisabled()
            if state.searching {
                Text(.folderStackSearchMatches(matchCount))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(matchCount == 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .contentTransition(.numericText())
                    .accessibilityHidden(true)
                Button {
                    state.clearSearch()
                    focused = true
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(Text(.folderStackSearchClear))
                .accessibilityLabel(Text(.folderStackSearchClear))
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(.quaternary.opacity(focused ? 0.6 : 0.35), in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(focused ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
                              lineWidth: focused ? 2 : 1)
        }
        .contentShape(.rect)
        .onTapGesture { focused = true }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: focused)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: state.searching)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: matchCount)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.folderStackSearch))
        .accessibilityValue(Text(.folderStackSearchMatches(matchCount)))
    }
}
