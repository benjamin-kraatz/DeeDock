import SwiftUI

/// The wall label under a piece: an editable title, the curator's note, catalog facts, and what
/// Vision saw in an image.
struct ClipboardExhibitPlacard: View {
    let exhibit: ClipboardExhibit
    /// True while a redacted exhibit's content is on view.
    let revealed: Bool
    @Binding var isRenaming: Bool
    let rename: (String?) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ClipboardEditableTitle(exhibit: exhibit, isEditing: $isRenaming, rename: rename)
            if let note = exhibit.curatorNote {
                Label { Text(verbatim: note).italic() } icon: { Image(systemName: "sparkles") }
                    .font(.system(.callout, design: .serif))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(.clipboardMuseumCuratorNote) + Text(verbatim: ": " + note))
            }
            HStack(spacing: 6) {
                Text(.clipboardMuseumCatalogNumber(exhibit.catalogNumber)).monospacedDigit()
                Text(verbatim: "·")
                Text(exhibit.medium)
            }
            .font(.caption.weight(.medium))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(.secondary)
            Rectangle().fill(ClipboardMuseumPalette.brass).frame(width: 36, height: 2)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
                ClipboardPlacardFact(label: .clipboardMuseumAcquired) {
                    Text(exhibit.acquiredAt, format: .dateTime.day().month().year().hour().minute())
                }
                ClipboardPlacardFact(label: .clipboardMuseumProvenance) {
                    if let source = exhibit.sourceName { Text(verbatim: source) } else { Text(.clipboardMuseumUnknownSource) }
                }
                if let dimensions = exhibit.dimensionsText {
                    ClipboardPlacardFact(label: .clipboardMuseumDimensions) { dimensions.monospacedDigit() }
                }
                ClipboardPlacardFact(label: .clipboardMuseumCondition) { condition }
                if let secret = exhibit.secret {
                    ClipboardPlacardFact(label: .clipboardMuseumReason) { Text(secret.title) }
                }
                if let labels = exhibit.imageLabels, !labels.isEmpty {
                    ClipboardPlacardFact(label: .clipboardMuseumSeen) {
                        Text(verbatim: labels.map(\.localizedCapitalized).joined(separator: ", "))
                    }
                }
            }
            .font(.callout)
            if let recognized = exhibit.recognizedText {
                DisclosureGroup {
                    Text(verbatim: recognized)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                } label: {
                    Text(.clipboardMuseumTextInImage).font(.callout)
                }
            }
            if exhibit.truncated {
                Text(.clipboardMuseumTruncatedNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: 400, alignment: .leading)
        .background(ClipboardMuseumPalette.placard(colorScheme), in: RoundedRectangle(cornerRadius: 3))
        .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(.separator, lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }

    @ViewBuilder private var condition: some View {
        if exhibit.isRedacted {
            if revealed {
                Text(.clipboardMuseumConditionRevealed).foregroundStyle(.orange)
            } else if !exhibit.isSealed {
                Text(.clipboardMuseumConditionShredded)
            } else if exhibit.redaction == .manual {
                Text(.clipboardMuseumConditionManual)
            } else {
                Text(.clipboardMuseumConditionDetected)
            }
        } else if exhibit.secret != nil {
            Text(.clipboardMuseumConditionSensitive).foregroundStyle(.orange)
        } else {
            Text(.clipboardMuseumConditionIntact)
        }
    }
}

private struct ClipboardPlacardFact<Value: View>: View {
    let label: LocalizedStringResource
    @ViewBuilder var value: Value

    var body: some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            value
        }
    }
}

/// The placard title, renamed in place.
///
/// Double-click the title, click the pencil that appears on hover, press Return on the sidebar
/// row, or use the context menu. Return saves, Escape cancels, clicking away saves, and an empty
/// field goes back to the automatic name, which shows as the field's placeholder.
struct ClipboardEditableTitle: View {
    let exhibit: ClipboardExhibit
    @Binding var isEditing: Bool
    let rename: (String?) -> Void

    @State private var draft = ""
    @State private var hovering = false
    @State private var cancelled = false
    @FocusState private var focused: Bool

    private var titleFont: Font { .system(.title3, design: .serif).weight(.semibold) }

    var body: some View {
        if isEditing {
            TextField(text: $draft, prompt: automaticPrompt) { Text(.clipboardMuseumRenameLabel) }
                .textFieldStyle(.plain)
                .font(titleFont)
                .focused($focused)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1) }
                .padding(.horizontal, -6)
                .onSubmit(commit)
                .onExitCommand {
                    cancelled = true
                    isEditing = false
                }
                .onAppear {
                    draft = exhibit.renameSeed
                    cancelled = false
                    focused = true
                }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused, isEditing, !cancelled { commit() }
                }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                exhibit.titleText
                    .font(titleFont)
                    .lineLimit(2)
                Button { isEditing = true } label: {
                    Image(systemName: "pencil")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
                .accessibilityHidden(true)
                .help(Text(.clipboardMuseumRename))
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { isEditing = true }
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
            .help(Text(.clipboardMuseumRenameHint))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityAction(named: Text(.clipboardMuseumRename)) { isEditing = true }
        }
    }

    /// The name the exhibit would have without a custom title, so clearing the field previews it.
    private var automaticPrompt: Text {
        var copy = exhibit
        copy.customTitle = nil
        return copy.titleText
    }

    private func commit() {
        guard isEditing else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        // Keeping the suggested name unchanged should not pin it as a custom title.
        if trimmed.isEmpty {
            rename(nil)
        } else if trimmed != exhibit.renameSeed || exhibit.customTitle != nil {
            rename(trimmed)
        }
        isEditing = false
    }
}
