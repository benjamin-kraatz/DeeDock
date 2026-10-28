import SwiftUI

/// The 272 pt preview column for the active pane's selection (or search selection).
///
/// One item: a Quick Look preview in a rounded well, its details, and Open, Quick Look, and
/// Reveal in Finder. Several: a fanned stack with the count and total size. None: the folder.
/// A Lookout hit also gets "Why it matched" under its details, and one selected file Find Similar above the actions,
/// in search results and in the browser alike.
///
/// In a search with a picture the column is compact (the mockup's `.pv.im`): a shorter well, one line of details,
/// and, while nothing is selected, the picture searched with. The well is the one part that gives: it shrinks from
/// its ideal height down to `HubFilesMetrics.previewWellHeights` lower bound before a long name or a two-line
/// sentence could push Open, Quick Look, and Reveal off the bottom of the 640 pt Hub.
struct HubFilesPreviewColumn: View {
    let model: HubFilesModel

    @Environment(\.colorScheme) private var scheme

    private var selection: [HubFileItem] { model.actionableItems }

    var body: some View {
        let selection = selection
        let wellHeights = HubFilesMetrics.previewWellHeights(pictureSearch: model.isPictureSearch,
                                                             searching: model.isSearching)
        VStack(alignment: .leading, spacing: 10) {
            Text(.hubFilesPreviewTitle)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            well(selection)
                .frame(maxWidth: .infinity)
                .frame(minHeight: wellHeights.lowerBound, idealHeight: wellHeights.upperBound,
                       maxHeight: wellHeights.upperBound)
                // Laid out first, with room for the text and cards set aside, so the well gives before they do.
                .layoutPriority(1)
                .background(HubFilesTheme(scheme).well, in: .rect(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(HubFilesTheme(scheme).line, lineWidth: 0.5) }
                .overlay(alignment: .bottomTrailing) {
                    // A Lookout hit on a PDF page says which page, as the mockup's page preview does.
                    if let hit = model.selectedLookoutHit, case .pdf(let page?) = LookoutHitKind(hit) {
                        LookoutPageBadge(page: page)
                            .padding(10)
                            .transition(.opacity)
                    }
                }
                .clipShape(.rect(cornerRadius: 14))
                .id(wellID(selection))
                .transition(wellTransition(selection))
            HubFilesPreviewDetails(model: model, selection: selection)
            if let hit = model.selectedLookoutHit {
                if model.isPictureSearch {
                    if !hit.isFolder {
                        let results = model.pictureResults
                        let queryIsPicture = results.queryIsPicture
                        LookoutPictureWhyCard(why: LookoutPictureWhy(hit: hit, queryIsPicture: queryIsPicture,
                                                                     words: results.words),
                                              picture: model.pictureQuery, queryIsPicture: queryIsPicture, hit: hit)
                            .transition(.opacity)
                    }
                } else {
                    LookoutWhyCard(why: LookoutWhy(hit: hit, isLookup: model.lookoutResults.isLookup))
                        .transition(.opacity)
                }
            }
            if let item = selection.first, selection.count == 1 {
                HubFilesFindSimilar(model: model, item: item)
            }
            if selection.count == 1 {
                HubFilesPreviewActions(model: model)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(width: HubFilesMetrics.previewWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .leading) {
            Rectangle().fill(HubFilesTheme(scheme).line).frame(width: 0.5)
        }
        .animation(HubFilesMotion.animation(.spring(response: 0.35, dampingFraction: 0.85)), value: wellID(selection))
    }

    /// What the well shows, so it cross-fades when that changes: the selection, or the picture searched with.
    private func wellID(_ selection: [HubFileItem]) -> [URL] {
        if selection.isEmpty, let picture = model.pictureQuery {
            return [picture.fileURL ?? URL(filePath: "/pasted/\(picture.id.uuidString)")]
        }
        return selection.map(\.url)
    }

    /// How the well enters and leaves when the selection changes.
    ///
    /// A well that hosts a live Quick Look preview (one file) only fades. Scaling it resizes the
    /// text view inside Quick Look's text preview (Markdown, JSON, source) on every animation
    /// frame. Each resize invalidates SwiftUI's layout in the middle of AppKit's layout pass, and
    /// with a few kilobytes of text the loop never settles: AppKit throws and the app crashes
    /// (DEE-127). The picture searched with also counts when it's a file, because it shows through Quick Look too.
    /// Icons, the fanned stack, the folder, and a pasted picture's own pixels still scale in.
    private func wellTransition(_ selection: [HubFileItem]) -> AnyTransition {
        let hostsQuickLook = selection.count == 1 && selection.first?.isDirectory == false
        let showsPictureFile = selection.isEmpty && model.pictureQuery.map { $0.image == nil && $0.fileURL != nil } == true
        return hostsQuickLook || showsPictureFile ? .opacity : .opacity.combined(with: .scale(scale: 0.97))
    }

    @ViewBuilder
    private func well(_ selection: [HubFileItem]) -> some View {
        if selection.count > 1 {
            HubFilesPreviewStack(items: Array(selection.prefix(3)))
        } else if let item = selection.first {
            if item.isDirectory {
                HubFilesItemIcon(item: item, size: 128, thumbnail: true)
            } else {
                HubFilesQuickLookWell(item: item)
            }
        } else if let picture = model.pictureQuery {
            // Nothing selected in a search with a picture (it's still being read, or nothing stood out): the picture
            // itself, as the mockup's preview shows it.
            LookoutPictureQueryWell(picture: picture)
        } else if let folder = model.isSearching ? nil : model.activePane.folderURL {
            HubFilesFolderIcon(url: folder, size: 128)
        }
    }
}

/// The picture searched with, filling the well: a pasted picture's own pixels, or the file through Quick Look.
private struct LookoutPictureQueryWell: View {
    let picture: LookoutPictureQuery

    var body: some View {
        if let image = picture.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .padding(8)
                .accessibilityLabel(Text(verbatim: picture.name))
        } else if let url = picture.fileURL {
            HubFilesQuickLookWell(item: .lookout(path: url.path, isFolder: false, size: nil, modified: nil))
        }
    }
}

/// Find Similar for the one selected file, a search result or a file in the browser: shown when Lookout can search
/// with it, disabled with why for a kind of file it doesn't read or a document it hasn't read, and absent for folders
/// and until Lookout can search. Whether the index holds a document is asked off the main actor when it's selected.
private struct HubFilesFindSimilar: View {
    let model: HubFilesModel
    let item: HubFileItem

    var body: some View {
        let availability = model.similarAvailability(for: item)
        Group {
            if availability != .hidden {
                LookoutFindSimilarButton(availability: availability) {
                    model.findSimilarForSelection()
                }
                .transition(.opacity)
            }
        }
        .task(id: item.url) { await model.checkSimilarIndexed(item) }
    }
}

/// Fanned icons for a multiple selection, like the mockup's `.multi` stack.
private struct HubFilesPreviewStack: View {
    let items: [HubFileItem]

    var body: some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let step = CGFloat(index - (items.count == 1 ? 0 : 1))
                HubFilesItemIcon(item: item, size: 90, thumbnail: true)
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                    .rotationEffect(.degrees(step * 7))
                    .offset(x: step * 12, y: step * -6)
            }
        }
        .frame(width: 110, height: 110)
    }
}

/// Name, kind and size, and modification date under the well.
private struct HubFilesPreviewDetails: View {
    let model: HubFilesModel
    let selection: [HubFileItem]

    @State private var childCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(lines, id: \.self) { line in
                Text(verbatim: line)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
        .task(id: countedFolder) {
            childCount = nil
            guard let folder = countedFolder else { return }
            childCount = await model.dataSource.itemCount(in: folder)
        }
    }

    /// The folder whose items are counted: a single selected folder, or the shown folder.
    private var countedFolder: URL? {
        if selection.count == 1, let item = selection.first { return item.isDirectory ? item.url : nil }
        return selection.isEmpty && !model.isSearching ? model.activePane.folderURL : nil
    }

    private var title: String {
        if selection.count > 1 { return HubFilesFormatting.itemCount(selection.count) }
        if let item = selection.first { return item.name }
        // The picture searched with, while nothing is selected.
        if let picture = model.pictureQuery { return picture.name }
        return model.isSearching ? "" : model.displayName(for: model.activePane.location)
    }

    private var lines: [String] {
        if selection.count > 1 {
            let total = selection.compactMap(\.byteSize).reduce(0, +)
            return [HubFilesFormatting.size(total)]
        }
        let count = childCount.map(HubFilesFormatting.itemCount)
        guard let item = selection.first else {
            return count.map { [$0] } ?? []
        }
        let kind = item.isDirectory ? String(localized: .hubFilesKindFolder) : item.kindDescription
        let amount = item.isDirectory ? count : HubFilesFormatting.size(item.byteSize)
        // A search with a picture keeps to the mockup's one line, "Desktop › Holiday Sylt 2026 · 3.1 MB", so the
        // comparison card and Find Similar fit under the well; the row already shows the date.
        if let hit = model.selectedLookoutHit, model.isPictureSearch {
            return [[model.lookoutLocation(of: hit), amount].compactMap { $0 }.joined(separator: " · ")]
        }
        var lines = [[kind, amount].compactMap { $0 }.joined(separator: " · ")]
        // A Lookout hit's place, as its row shows it; name results show theirs in the row's Where column.
        if let hit = model.selectedLookoutHit { lines.insert(model.lookoutLocation(of: hit), at: 0) }
        if !item.isDirectory || item.modified != nil {
            lines.append(String(localized: .hubFilesPreviewModified(HubFilesFormatting.date(item.modified))))
        }
        return lines
    }
}

/// Open (primary), Quick Look, and Reveal in Finder for a single selection.
private struct HubFilesPreviewActions: View {
    let model: HubFilesModel

    var body: some View {
        HStack(spacing: 6) {
            HubFilesPreviewButton(title: .hubFilesMenuOpen, isPrimary: true) { model.openSelection() }
            HubFilesPreviewButton(title: .hubFilesMenuQuickLook, isPrimary: false) { model.toggleQuickLook() }
            HubFilesPreviewButton(title: .hubFilesPreviewReveal, isPrimary: false) { model.revealSelectionInFinder() }
        }
    }
}

/// A compact rounded button in the preview column.
private struct HubFilesPreviewButton: View {
    let title: LocalizedStringResource
    let isPrimary: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false

    var body: some View {
        let theme = HubFilesTheme(scheme)
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(isPrimary ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isPrimary ? Color.accentColor : (hovered ? theme.chipHighlight : theme.chip),
                            in: .rect(cornerRadius: 8))
                .overlay {
                    if !isPrimary { RoundedRectangle(cornerRadius: 8).strokeBorder(theme.line, lineWidth: 0.5) }
                }
                .brightness(isPrimary && hovered ? 0.06 : 0)
                .contentShape(.rect)
        }
        .buttonStyle(.hubPress(scale: 0.96))
        .onHover { hovered = $0 }
    }
}
