import SwiftUI

/// The window's fixed search bar: query field, refresh, scope, and the scope's disclosure text.
///
/// The field owns keyboard navigation because arrow keys must move the selection while the user
/// keeps typing. The parent supplies the focus binding so it can restore focus after other actions.
struct WindowSearchHeaderView: View {
    @Bindable var state: WindowSearchState
    @FocusState.Binding var queryFocused: Bool
    @State private var showsScopeDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                WindowSearchFieldView(state: state, queryFocused: $queryFocused)
                if state.busy {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel(Text(.windowSearchWorking))
                    Button(.windowSearchCancel) { state.cancelWork() }
                        .controlSize(.large)
                } else {
                    Button { state.refresh() } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 16, height: 16)
                    }
                    .controlSize(.large)
                    .help(Text(.windowSearchRefresh))
                    .accessibilityLabel(Text(.windowSearchRefresh))
                }
            }
            HStack(spacing: 8) {
                Picker(selection: $state.scope) {
                    // A segmented control renders text far more reliably than a label, so the
                    // scope symbols stay in the empty states rather than in the picker itself.
                    ForEach(WindowSearchScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                } label: {
                    Text(.windowSearchScope)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel(Text(.windowSearchScope))
                Button { showsScopeDetails.toggle() } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help(Text(.windowSearchScopeDetails))
                .accessibilityLabel(Text(.windowSearchScopeDetails))
                .popover(isPresented: $showsScopeDetails, arrowEdge: .bottom) {
                    Text(state.scope.help)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 320, alignment: .leading)
                        .padding(14)
                }
            }
            Text(state.scope.help)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, WindowSearchStyle.contentPadding)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// A borderless query field in a soft container, the shape macOS uses for search throughout Finder.
private struct WindowSearchFieldView: View {
    @Bindable var state: WindowSearchState
    @FocusState.Binding var queryFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(text: $state.query) { Text(.windowSearchPlaceholder) }
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($queryFocused)
                .onSubmit { state.activateSelection() }
                .onKeyPress(.downArrow) { state.select(by: 1); return .handled }
                .onKeyPress(.upArrow) { state.select(by: -1); return .handled }
            if !state.query.isEmpty {
                Button { state.query = ""; queryFocused = true } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(Text(.windowSearchClearQuery))
                .accessibilityLabel(Text(.windowSearchClearQuery))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(queryFocused ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
                              lineWidth: queryFocused ? 2 : 1)
        }
        .contentShape(.rect)
        .onTapGesture { queryFocused = true }
    }
}
