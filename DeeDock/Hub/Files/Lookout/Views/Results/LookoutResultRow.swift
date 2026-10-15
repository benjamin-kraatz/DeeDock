import SwiftUI

/// One Lookout result (the mockup's `.row.big`): a 58 pt thumbnail, or a fanned stack for a folder; the name, where
/// it is ("Desktop › Holiday Sylt 2026"), up to two lines of the matching text with the words highlighted, the kind
/// and match chips; and the date at the trailing edge.
///
/// Clicks, double clicks, dragging out, folder drops and the context menu go through the shared AppKit region
/// (`HubFilesInteractions.lookoutResult`); VoiceOver gets the name, a value with kind, match, place, date and text,
/// and Open and Quick Look actions.
struct LookoutResultRow: View {
    let model: HubFilesModel
    let hit: LookoutHit
    /// The query's content words, to highlight in an excerpt that carries no markers.
    let terms: [String]
    /// The match chip's text in place of meaning/words: "Looks alike" or "Same subject" in a search with a picture.
    var matchTitle: String?

    @State private var hovered = false

    private var item: HubFileItem { hit.fileItem }
    private var kind: LookoutHitKind { LookoutHitKind(hit) }
    private var isSelected: Bool { model.lookoutSelection == hit.path }
    private var location: String { model.lookoutLocation(of: hit) }
    private var date: String? { hit.modifiedDate.map { HubFilesFormatting.date($0) } }

    var body: some View {
        let item = item
        let snippet = LookoutSnippet(hit: hit, terms: terms)
        HStack(alignment: .top, spacing: 11) {
            Group {
                if hit.isFolder {
                    LookoutFolderStack(files: hit.topFileItems)
                } else {
                    LookoutThumbnail(item: item, kind: kind)
                }
            }
            .hubFilesQuickLookSource(item.url, quickLook: model.quickLook)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: item.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: location)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .padding(.top, 1)
                if let snippet {
                    LookoutSnippetText(snippet: snippet)
                        .padding(.top, 4)
                }
                LookoutChips(kind: kind, match: hit.match, matchTitle: matchTitle)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: date ?? "")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: 92, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .contentShape(.rect)
        .modifier(HubFilesItemBackground(
            shape: .rect(cornerRadius: 10), isSelected: isSelected, isActivePane: true, isHovered: hovered,
            isDropTarget: hit.isFolder && model.dropHighlight == .item(item.url), isFresh: false))
        .overlay {
            HubFilesInteractionRegion(interaction: HubFilesInteractions.lookoutResult(hit, model: model) { hovered = $0 },
                                      model: model)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: item.name))
        .accessibilityValue(Text(verbatim: accessibilityValue(snippet: snippet)))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.openLookoutResult(hit) }
        .accessibilityAction(named: Text(.hubFilesMenuOpen)) { model.openLookoutResult(hit) }
        .accessibilityAction(named: Text(.hubFilesMenuQuickLook)) {
            if !isSelected { model.clickLookoutResult(hit) }
            model.toggleQuickLook()
        }
        .accessibilityAction(named: Text(.lookoutSimilarButton)) {
            if model.similarAvailability(for: item).isAvailable { model.findSimilar(item, segmentID: hit.segmentID) }
        }
    }

    private func accessibilityValue(snippet: LookoutSnippet?) -> String {
        [kind.title, matchTitle ?? hit.match.title, location, date, snippet?.text].compactMap { $0 }
            .joined(separator: ", ")
    }
}

#Preview("Rows") {
    let model = LookoutPreviewData.model(status: .ready, phase: .done, results: LookoutPreviewData.beachResults) { model in
        model.lookoutSelection = LookoutPreviewData.beach.path
    }
    VStack(spacing: 0) {
        ForEach(LookoutPreviewData.beachResults.all) { hit in
            LookoutResultRow(model: model, hit: hit, terms: ["dog", "beach"])
        }
    }
    .padding(10)
    .frame(width: 640)
    .background(.regularMaterial)
    .environment(\.hubFilesIconSource, .typeOnly)
}
