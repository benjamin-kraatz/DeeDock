import SwiftUI

/// Shared discovery menu used by initial pairing and by the existing pair's toolbar.
struct AppMeltWindowPickerContents: View {
    let state: AppMeltWindowPickerState
    var disabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.busy {
                ProgressView().controlSize(.small)
            } else {
                Menu {
                    ForEach(state.groups) { group in
                        Menu {
                            ForEach(Array(group.windows.enumerated()), id: \.element.token) { offset, window in
                                Button { state.choose(window) } label: {
                                    let title = window.title.flatMap { $0.isEmpty ? nil : $0 }
                                        ?? String(localized: .meltReplacementUntitled(offset + 1))
                                    if state.unavailable.contains(window.token) {
                                        Text(.meltReplacementAlreadyPaired(title))
                                    } else if window.isMinimized {
                                        Text(.meltReplacementMinimized(title))
                                    } else { Text(verbatim: title) }
                                }
                                .disabled(state.unavailable.contains(window.token))
                            }
                        } label: {
                            if state.blockedApps.contains(group.id) { Text(.meltReplacementAppInUse(group.name)) }
                            else { Text(verbatim: group.name) }
                        }
                        .disabled(state.blockedApps.contains(group.id))
                    }
                } label: { Label(.meltReplacementChoose, systemImage: "macwindow") }
                .disabled(state.groups.isEmpty || disabled)
                if state.groups.isEmpty { Text(.meltNoWindows).font(.caption) }
            }
            if let message = state.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Button(.meltReplacementRefresh) { state.refresh() }.disabled(state.busy || disabled)
        }
        .onAppear { state.refresh() }
        .onDisappear { state.cancel() }
    }
}
