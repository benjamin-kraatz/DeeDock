import SwiftUI

/// "✦ Tidy up": suggested renames and moves for Downloads, each with a checkbox, applied together
/// with one Undo.
struct FlixTidySheet: View {
    let state: FlixPanelState
    @State private var unchecked: Set<FlixItem.ID> = []

    private var suggestions: [FlixTidySuggestion] {
        state.intelligence.tidy.filter { state.history.item($0.itemID) != nil }
    }

    var body: some View {
        let suggestions = suggestions
        FlixSheetTitle(title: Text(.flixTidyTitle), intelligent: true,
                       trailing: suggestions.isEmpty ? nil : Text(.flixTidySuggestionCount(suggestions.count))) {
            state.sheet = nil
        }
        if suggestions.isEmpty {
            Text(.flixTidyNothing)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(suggestions) { suggestion in
                        if let item = state.history.item(suggestion.itemID) {
                            FlixTidyRow(item: item, suggestion: suggestion, policy: state.readPolicy,
                                        checked: Binding(get: { !unchecked.contains(item.id) },
                                                         set: { if $0 { unchecked.remove(item.id) } else { unchecked.insert(item.id) } }))
                        }
                    }
                }
            }
            .frame(maxHeight: 230)
            let chosen = suggestions.filter { !unchecked.contains($0.itemID) }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button { state.sheet = nil } label: { Text(.flixCancel) }
                Button { state.applyTidy(chosen) } label: { Text(.flixTidyApply(chosen.count)) }
                    .buttonStyle(.borderedProminent)
                    .disabled(chosen.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
    }
}

/// One Tidy suggestion: "Rename to **…** · Move to **Documents › Finance**".
private struct FlixTidyRow: View {
    let item: FlixItem
    let suggestion: FlixTidySuggestion
    let policy: FlixReadPolicy
    @Binding var checked: Bool

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $checked) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
            FlixThumbnailView(item: item, size: 24, policy: policy)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: item.name).lineLimit(1)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(FlixStyle.pane, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var detail: AttributedString {
        var parts: [String] = []
        if let rename = suggestion.rename { parts.append(String(localized: .flixTidyRenameTo(rename))) }
        if let folder = suggestion.moveTo { parts.append(String(localized: .flixTidyMoveTo(FileManager.default.displayName(atPath: folder)))) }
        return (try? AttributedString(markdown: parts.joined(separator: " · "))) ?? AttributedString(parts.joined(separator: " · "))
    }
}
