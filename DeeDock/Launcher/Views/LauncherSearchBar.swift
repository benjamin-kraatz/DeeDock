import SwiftUI

/// The launcher's search field, overflow menu, and query-gated clear and Robi actions.
struct LauncherSearchBar: View {
    @Bindable var state: LauncherState
    var searchFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Button {
                searchFocused.wrappedValue = true
                state.keyboardNavigationActive = false
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: .command)
            .accessibilityLabel(Text(.launcherSearch))

            TextField(text: $state.query, prompt: Text(state.usesFileActions ? .launcherFileSearchPrompt : .unifiedSearchPrompt)) {
                Text(.launcherSearch)
            }
            .textFieldStyle(.plain)
            .font(.title2)
            .focused(searchFocused)
            .onSubmit { state.openSelection() }
            .autocorrectionDisabled()
            .layoutPriority(1)

            LauncherSearchBarOverflowMenu(state: state)

            if !state.query.isEmpty {
                Button {
                    state.query = ""
                    searchFocused.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text(.launcherClearSearch))
            }

            if !state.usesFileActions {
                LauncherRobiButton(state: state)
            }

            Button {
                state.close?()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .help(.launcherClose)
            .accessibilityLabel(Text(.launcherClose))
        }
        .padding(16)
        .background(.primary.opacity(0.045), in: .rect(cornerRadius: 18))
    }
}
