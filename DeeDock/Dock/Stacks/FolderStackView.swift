import SwiftUI

struct FolderStackView: View {
    let state: FolderStackState
    let keyboard: Bool
    var forceOpaqueBackground = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if state.searchAvailable {
                FolderStackSearchField(state: state, focused: $searchFocused)
                    .transition(reduceMotion ? .opacity
                                : .asymmetric(insertion: .push(from: .top).combined(with: .opacity),
                                              removal: .opacity))
            }
            Divider()
            if let error = state.error, !state.entries.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text(verbatim: error).font(.callout).lineLimit(2)
                    Spacer(minLength: 4)
                    Button(.folderStackRetry) { state.retry() }
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.quaternary)
                Divider()
            }
            if let error = state.semanticError, state.presentation == .smart {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text(verbatim: error).font(.callout).lineLimit(2)
                    Spacer(minLength: 4)
                    Button(.folderStackRetry) { state.retrySemanticOrganization() }
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.quaternary)
                Divider()
            }
            if state.copying {
                HStack { ProgressView().controlSize(.small); Text(.folderDropCopying) }.padding(8)
            }
            if let preview = state.preview {
                DockFilePreview(item: preview) { state.preview = nil }
            } else {
                content
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: state.searchAvailable)
        // The panel's key handler drives focus for ⌘F, type-ahead, and Escape; the field reports
        // every other focus change back so the handler knows when to stop eating text keys.
        .onChange(of: searchFocused) { _, focused in state.searchFocused = focused }
        .onChange(of: state.searchFocused) { _, focused in
            if searchFocused != focused { searchFocused = focused }
        }
        .overlay(alignment: .bottom) {
            if state.dropTargeted {
                Text(.folderDropCopyHere).font(.callout)
                    .padding(8).background(.regularMaterial, in: .capsule)
                    .padding(12).allowsHitTesting(false)
            }
        }
        .dockPopoverChrome(state.chrome, opaque: reduceTransparency || forceOpaqueBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.folderStackAccessibilityLabel(folderName: state.directoryName)))
        .accessibilityValue(Text(.folderStackItemCount(
            count: state.visibleEntries.count,
            mode: String(localized: modeTitle(state.presentation))
        )))
    }

    private var header: some View {
        HStack(spacing: 12) {
            if !state.history.isEmpty {
                Button(.folderStackBack, systemImage: "chevron.left") { state.back() }
                    .labelStyle(.iconOnly)
                    .disabled(state.copying)
            }
            Image(systemName: "folder.fill").foregroundStyle(.tint).accessibilityHidden(true)
            Text(verbatim: state.directoryName).font(.headline).lineLimit(1)
            Spacer(minLength: 8)
            Menu {
                Picker(.folderSortTitle, selection: Binding(get: { state.sort }, set: { state.chooseSort($0) })) {
                    ForEach(FolderStackSort.allCases, id: \.self) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(.folderSortTitle, systemImage: "arrow.up.arrow.down")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(Text(.folderSortTitle))
            .accessibilityValue(Text(state.sort.title))
            HStack(spacing: 2) {
                modeButton(.grid, symbol: "square.grid.2x2")
                modeButton(.list, symbol: "list.bullet")
                modeButton(.smart, symbol: "sparkles")
            }
            .padding(2)
            .background(.quaternary, in: .rect(cornerRadius: 7))
            .overlay {
                if state.presentationFocused {
                    RoundedRectangle(cornerRadius: 7).strokeBorder(.tint, lineWidth: 2)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(.folderStackPresentationControl))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func modeButton(_ mode: FolderStackPresentation, symbol: String) -> some View {
        Button { state.choose(mode) } label: {
            Image(systemName: symbol).frame(width: 26, height: 22)
                .background(state.presentation == mode ? Color.accentColor.opacity(0.22) : .clear,
                            in: .rect(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(modeTitle(mode)))
        .accessibilityAddTraits(state.presentation == mode ? .isSelected : [])
    }

    /// Rows animate on identity alone; metrics and media arriving later must not restart the motion.
    private var visibleIDs: [String] { state.visibleEntries.map(\.id) }

    @ViewBuilder private var content: some View {
        if state.loading && state.entries.isEmpty {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text(.folderStackLoading))
        } else if let error = state.error, state.entries.isEmpty {
            ContentUnavailableView {
                Label(.folderStackUnavailableTitle, systemImage: "folder.badge.questionmark")
            } description: {
                Text(verbatim: error)
            } actions: {
                Button(.folderStackRetry) { state.retry() }
            }
        } else if state.entries.isEmpty {
            ContentUnavailableView(.folderStackEmpty, systemImage: "folder")
        } else if state.visibleEntries.isEmpty {
            ContentUnavailableView {
                Label(.folderStackSearchEmptyTitle, systemImage: "magnifyingglass")
            } description: {
                Text(.folderStackSearchEmpty(query: state.query))
            } actions: {
                Button(.folderStackSearchClear) {
                    state.clearSearch()
                    searchFocused = true
                }
            }
        } else if state.presentation == .grid {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 12)], spacing: 14) {
                    ForEach(state.visibleEntries) { entry in item(entry, grid: true) }
                }
                .padding(16)
                .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: visibleIDs)
            }
        } else if state.presentation == .list {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(state.visibleEntries) { entry in item(entry, grid: false) }
                }
                .padding(8)
                .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: visibleIDs)
            }
        } else {
            smartContent
        }
    }

    private var smartContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                ForEach(state.sortedSemanticSections) { section in
                    Section {
                        ForEach(section.itemIDs, id: \.self) { id in
                            if let entry = state.entries.first(where: { $0.id == id }) {
                                item(entry, grid: false)
                                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Text(verbatim: section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if section.kind == .organizing {
                                ProgressView().controlSize(.mini)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(.regularMaterial)
                        .accessibilityAddTraits(.isHeader)
                    }
                }
            }
            .padding(8)
            .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: state.semanticSections)
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: visibleIDs)
        }
    }

    private func modeTitle(_ mode: FolderStackPresentation) -> LocalizedStringResource {
        switch mode {
        case .grid: .folderStackGrid
        case .list: .folderStackList
        case .smart: .semanticStackSmart
        }
    }

    private func item(_ entry: FolderStackEntry, grid: Bool) -> some View {
        Button { state.openEntry?(entry.reference) } label: {
            FolderStackItemLabel(entry: entry, grid: grid, sort: state.sort)
            .contentShape(.rect)
            .background(state.selectedID == entry.id ? Color.accentColor.opacity(0.18) : .clear,
                        in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .overlay {
            FolderStackDragSourceView(entry: entry, open: { state.openEntry?(entry.reference) },
                                      completed: { state.dragCompleted?($0) },
                                      lease: { state.dragLease() },
                                      select: { state.selectedID = entry.id; state.presentationFocused = false },
                                      navigate: { state.navigate(to: entry.reference.url) },
                                      receive: { state.receive($0, into: entry.reference.url) },
                                      acceptsDrop: { !state.copying })
        }
        .help(FolderStackItemDetails(reference: entry.reference).help)
        .accessibilityLabel(Text(verbatim: entry.reference.name))
        .accessibilityValue(Text(verbatim: FolderStackItemDetails(reference: entry.reference).summary))
        .accessibilityHint(Text(entry.reference.isFolder ? .folderStackBrowseHint : .folderStackOpenHint))
        .accessibilityAddTraits(state.selectedID == entry.id ? .isSelected : [])
        .contextMenu {
            ShareLink(item: entry.reference.url) {
                Label(.folderItemShare, systemImage: "square.and.arrow.up")
            }
            Button(.filePreviewAction) { state.showPreview(entry.reference) }
            Button(.folderStackShowInFinder) { NSWorkspace.shared.activateFileViewerSelecting([entry.reference.url]) }
        }
        .accessibilityActions {
            Button(.filePreviewAction) { state.showPreview(entry.reference) }
            Button(.actionOpen) {
                state.openEntry?(entry.reference)
            }
        }
    }
}

#if DEBUG
@MainActor private enum FolderStackPreviewData {
    static let icon = NSImage(systemSymbolName: "doc.text.fill", accessibilityDescription: nil)!
    static let folderIcon = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)!
    static let entries = [
        FolderStackEntry(reference: .init(url: URL(fileURLWithPath: "/Preview/item 2.txt"), name: "item 2.txt", isFolder: false, contentType: "public.plain-text",
                                                byteCount: 245_000, createdAt: Date(timeIntervalSince1970: 1_780_000_000),
                                                modifiedAt: Date(timeIntervalSince1970: 1_780_100_000)), icon: icon),
        FolderStackEntry(reference: .init(url: URL(fileURLWithPath: "/Preview/Archives"), name: "Archives", isFolder: true,
                                                byteCount: 96, createdAt: Date(timeIntervalSince1970: 1_779_000_000),
                                                modifiedAt: Date(timeIntervalSince1970: 1_780_200_000),
                                                contents: FolderContentsMetrics(immediateItemCount: 12, recursiveItemCount: 48,
                                                                               totalByteCount: 4_200_000, completeness: .complete)),
                         icon: folderIcon),
        FolderStackEntry(reference: .init(url: URL(fileURLWithPath: "/Preview/Harbor.png"), name: "Harbor.png", isFolder: false, contentType: "public.png",
                                                byteCount: 1_048_576, createdAt: Date(timeIntervalSince1970: 1_780_000_000),
                                                modifiedAt: Date(timeIntervalSince1970: 1_780_200_000),
                                                media: .image(width: 1920, height: 1080)), icon: icon),
        FolderStackEntry(reference: .init(url: URL(fileURLWithPath: "/Preview/Brief.pdf"), name: "Brief.pdf", isFolder: false, contentType: "com.adobe.pdf",
                                                byteCount: 88_000, media: .pdf(pageCount: 12)), icon: icon),
        FolderStackEntry(reference: .init(url: URL(fileURLWithPath: "/Preview/Take.m4a"), name: "Take.m4a", isFolder: false, contentType: "public.mpeg-4-audio",
                                                byteCount: 420_000, media: .audio(duration: 125)), icon: icon),
        FolderStackEntry(reference: .init(url: URL(fileURLWithPath: "/Preview/item 10.txt"), name: "A document with a deliberately long Finder name.txt", isFolder: false), icon: icon)
    ]
    static let folderMetricsEntries = [
        FolderStackEntry(reference: .init(url: URL(fileURLWithPath: "/Preview/Complete"), name: "Complete folder", isFolder: true,
                                                byteCount: 64, contents: FolderContentsMetrics(immediateItemCount: 3, recursiveItemCount: 10,
                                                                                              totalByteCount: 1_500_000, completeness: .complete)),
                         icon: folderIcon),
        FolderStackEntry(reference: .init(url: URL(fileURLWithPath: "/Preview/Calculating"), name: "Still measuring", isFolder: true,
                                                byteCount: 64, contents: .calculating(immediateItemCount: 80)),
                         icon: folderIcon),
        FolderStackEntry(reference: .init(url: URL(fileURLWithPath: "/Preview/Partial"), name: "Partial folder", isFolder: true,
                                                byteCount: 64, contents: FolderContentsMetrics(immediateItemCount: 4, recursiveItemCount: 4,
                                                                                              totalByteCount: 220_000, completeness: .incomplete)),
                         icon: folderIcon),
        FolderStackEntry(reference: .init(url: URL(fileURLWithPath: "/Preview/notes.txt"), name: "notes.txt", isFolder: false,
                                                contentType: "public.plain-text", byteCount: 1_024), icon: icon)
    ]
    /// Enough children to cross the search threshold, with a few obvious shared substrings.
    static let manyEntries: [FolderStackEntry] = (1...14).map { index in
        let names = ["Invoice", "Screenshot", "Notes"]
        let name = "\(names[index % names.count]) \(index).txt"
        return FolderStackEntry(
            reference: .init(url: URL(fileURLWithPath: "/Preview/\(name)"), name: name, isFolder: false,
                             contentType: "public.plain-text", byteCount: Int64(index) * 4_096),
            icon: icon)
    }
    static func state(_ mode: FolderStackPresentation = .grid, name: String = "Projects",
                      entries suppliedEntries: [FolderStackEntry]? = nil,
                      loading: Bool = false, error: String? = nil,
                      sort: FolderStackSort = .alphabetical) -> FolderStackState {
        FolderStackState(folder: FolderReference(url: URL(fileURLWithPath: "/Preview"), name: name,
                                                  bookmarkData: Data(), presentation: mode),
                         entries: suppliedEntries ?? entries, loading: loading, error: error, sort: sort)
    }
}

#Preview("Grid populated") {
    FolderStackView(state: FolderStackPreviewData.state(), keyboard: false).frame(width: 560, height: 420).padding()
}
#Preview("List, long name, dark") {
    FolderStackView(state: FolderStackPreviewData.state(.list, name: "A very long folder name that must remain on one line"), keyboard: true)
        .frame(width: 560, height: 420).padding().preferredColorScheme(.dark)
}
#Preview("List with media details") {
    FolderStackView(state: FolderStackPreviewData.state(.list), keyboard: false)
        .frame(width: 560, height: 420).padding()
}
#Preview("Loading") {
    FolderStackView(state: FolderStackPreviewData.state(entries: [], loading: true), keyboard: false)
        .frame(width: 560, height: 420).padding()
}
#Preview("Empty") {
    FolderStackView(state: FolderStackPreviewData.state(entries: []), keyboard: false)
        .frame(width: 560, height: 420).padding()
}
#Preview("Unavailable") {
    FolderStackView(state: FolderStackPreviewData.state(entries: [], error: "This folder is unavailable."), keyboard: false)
        .frame(width: 560, height: 420).padding()
}
#Preview("Recoverable error") {
    FolderStackView(state: FolderStackPreviewData.state(entries: [], error: "The folder could not be read."), keyboard: false)
        .frame(width: 560, height: 420).padding()
}
#Preview("Reduced motion and transparency") {
    FolderStackView(state: FolderStackPreviewData.state(), keyboard: false, forceOpaqueBackground: true)
        .frame(width: 560, height: 420).padding()
}
#Preview("Folder contents, list") {
    FolderStackView(state: FolderStackPreviewData.state(.list, entries: FolderStackPreviewData.folderMetricsEntries),
                    keyboard: false)
        .frame(width: 560, height: 420).padding()
}
#Preview("Search available") {
    FolderStackView(state: FolderStackPreviewData.state(.list, name: "Downloads",
                                                        entries: FolderStackPreviewData.manyEntries),
                    keyboard: true)
        .frame(width: 560, height: 420).padding()
}
#Preview("Search filtering") {
    let state = FolderStackPreviewData.state(.list, name: "Downloads", entries: FolderStackPreviewData.manyEntries)
    state.query = "invoice"
    return FolderStackView(state: state, keyboard: true)
        .frame(width: 560, height: 420).padding().preferredColorScheme(.dark)
}
#Preview("Search without matches") {
    let state = FolderStackPreviewData.state(.grid, name: "Downloads", entries: FolderStackPreviewData.manyEntries)
    state.query = "keynote"
    return FolderStackView(state: state, keyboard: true)
        .frame(width: 560, height: 420).padding()
}
#Preview("Folder contents, size sort") {
    FolderStackView(state: FolderStackPreviewData.state(.grid, entries: FolderStackPreviewData.folderMetricsEntries, sort: .size),
                    keyboard: false)
        .frame(width: 560, height: 420).padding()
}
#endif
