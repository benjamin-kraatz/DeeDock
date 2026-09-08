import SwiftUI

/// The launcher's search field and its adjacent search, capture, clear, and close actions.
struct LauncherSearchBar: View {
    @Bindable var state: LauncherState
    var searchFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 14) {
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

            TextField(text: $state.query, prompt: Text(.unifiedSearchPrompt)) {
                Text(.launcherSearch)
            }
            .textFieldStyle(.plain)
            .font(.title2)
            .focused(searchFocused)
            .onSubmit { state.openSelection() }
            .autocorrectionDisabled()

            Button {
                state.search.explicitSearch?()
            } label: {
                Image(systemName: "camera.viewfinder")
            }
            .buttonStyle(.borderless)
            .help(.unifiedCaptureRoute)
            .accessibilityLabel(Text(.unifiedCaptureRoute))

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
