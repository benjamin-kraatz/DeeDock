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
            FlixSheetNote(text: Text(.flixTidyNothing), symbol: "checkmark.circle.fill", tint: .green)
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
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 230)
            .fixedSize(horizontal: false, vertical: true)
            let chosen = suggestions.filter { !unchecked.contains($0.itemID) }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button { state.sheet = nil } label: { Text(.flixCancel) }
                    .buttonStyle(FlixCardButtonStyle())
                Button { state.applyTidy(chosen) } label: {
                    Text(.flixTidyApply(chosen.count))
                        .contentTransition(state.reduceMotion ? .identity : .numericText(value: Double(chosen.count)))
                }
                .buttonStyle(FlixCardButtonStyle(primary: true))
                .disabled(chosen.isEmpty)
                .keyboardShortcut(.defaultAction)
                .animation(state.reduceMotion ? nil : FlixMotion.row, value: chosen.count)
            }
        }
    }
}

/// One Tidy suggestion: "Rename to **…** · Move to **Documents › Finance**". The whole row
/// toggles its checkbox; an unchecked row dims.
private struct FlixTidyRow: View {
    let item: FlixItem
    let suggestion: FlixTidySuggestion
    let policy: FlixReadPolicy
    @Binding var checked: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $checked) { Text(verbatim: item.name) }
                .toggleStyle(.checkbox)
                .labelsHidden()
            Group {
                FlixThumbnailView(item: item, size: 24, policy: policy)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: item.name).lineLimit(1).truncationMode(.middle)
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            .opacity(checked ? 1 : 0.5)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(hovered ? FlixStyle.hover : FlixStyle.pane, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(.rect)
        .onTapGesture { checked.toggle() }
        .onHover { hovered = $0 }
        .animation(FlixMotion.hover, value: hovered)
        .animation(FlixMotion.hover, value: checked)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    private var detail: AttributedString {
        var parts: [String] = []
        if let rename = suggestion.rename { parts.append(String(localized: .flixTidyRenameTo(rename))) }
        if let folder = suggestion.moveTo { parts.append(String(localized: .flixTidyMoveTo(FlixFolderNames.displayName(of: folder)))) }
        var text = (try? AttributedString(markdown: parts.joined(separator: " · "))) ?? AttributedString(parts.joined(separator: " · "))
        // The suggested name and folder stand out in the intelligence violet, as in the mockup.
        for run in text.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            text[run.range].foregroundColor = FlixStyle.aiViolet
        }
        return text
    }
}

#if DEBUG
#Preview("Tidy sheet") {
    FlixPanelView(state: FlixPreviewData.panelState(.tidySheet)).frame(width: 760, height: 608)
}

#Preview("Tidy, nothing to do, German") {
    let state = FlixPreviewData.panelState(.search)
    state.searchActive = false
    state.sheet = .tidy
    return FlixPanelView(state: state).frame(width: 760, height: 608)
        .environment(\.locale, Locale(identifier: "de"))
}
#endif
