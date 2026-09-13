import SwiftUI

/// The launcher's search field, overflow menu, and query-gated clear and Robi actions.
///
/// While Robi is active a Robi chip replaces the magnifier. Clicking it, or pressing Esc,
/// returns to app search with the query kept.
struct LauncherSearchBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var state: LauncherState
    var searchFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            leading
                .fixedSize()
                .padding(.trailing, 4)

            TextField(text: $state.query, prompt: Text(state.usesFileActions ? .launcherFileSearchPrompt : .unifiedSearchPrompt)) {
                Text(.launcherSearch)
            }
            .textFieldStyle(.plain)
            .font(.title2)
            .focused(searchFocused)
            .onSubmit { state.openSelection() }
            .autocorrectionDisabled()
            .layoutPriority(1)

            HStack(spacing: 2) {
                if hasQuery {
                    Button {
                        state.query = ""
                        searchFocused.wrappedValue = true
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(LauncherSearchAccessoryButtonStyle())
                    .accessibilityLabel(Text(.launcherClearSearch))
                    .transition(.opacity)
                }

                LauncherSearchBarOverflowMenu(state: state)
            }

            if !state.usesFileActions, !state.robiActive || state.robiBusy {
                LauncherRobiButton(state: state)
                    .fixedSize()
            }

            Button {
                state.close?()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(LauncherSearchAccessoryButtonStyle())
            .help(.launcherClose)
            .accessibilityLabel(Text(.launcherClose))
        }
        .padding(.vertical, 12)
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .background(.primary.opacity(hasQuery ? 0.07 : 0.045), in: .rect(cornerRadius: 18, style: .continuous))
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: hasQuery)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: state.robiActive)
    }

    private var hasQuery: Bool { !state.query.isEmpty }

    @ViewBuilder private var leading: some View {
        if state.robiActive, !state.robiBusy {
            LauncherRobiScopeChip { state.cancelRobi(); searchFocused.wrappedValue = true }
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
        } else {
            Button {
                searchFocused.wrappedValue = true
                state.keyboardNavigationActive = false
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(hasQuery ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: .command)
            .accessibilityLabel(Text(.launcherSearch))
        }
    }
}

/// Marks Robi's answer as the field's scope. The whole chip is the way back to app search.
private struct LauncherRobiScopeChip: View {
    @Environment(\.colorScheme) private var colorScheme
    var dismiss: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: dismiss) {
            HStack(spacing: 5) {
                Image(systemName: hovering ? "xmark" : "sparkles")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 14)
                Text(.launcherRobiScope)
            }
            .font(.body.weight(.medium))
            .foregroundStyle(LauncherRobiTint.label(colorScheme))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(LauncherRobiTint.fill(hovering: hovering), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.15), value: hovering)
        .help(Text(.launcherRobiScopeHelp))
        .accessibilityLabel(Text(.launcherTextSearch))
    }
}

/// Round, hover-lit chrome for the search field's small trailing icons.
struct LauncherSearchAccessoryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LauncherSearchAccessory(isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

/// Shared hover and press treatment for accessory buttons and the overflow menu label.
struct LauncherSearchAccessory<Label: View>: View {
    @State private var hovering = false
    var isPressed = false
    @ViewBuilder var label: Label

    var body: some View {
        label
            .font(.body.weight(.medium))
            .imageScale(.medium)
            .foregroundStyle(hovering ? .primary : .secondary)
            .frame(width: 28, height: 28)
            .background(.primary.opacity(isPressed ? 0.12 : hovering ? 0.07 : 0), in: .circle)
            .contentShape(.circle)
            .onHover { hovering = $0 }
            .animation(.snappy(duration: 0.15), value: hovering)
    }
}
