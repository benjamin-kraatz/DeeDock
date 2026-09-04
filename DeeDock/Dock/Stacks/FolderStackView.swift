import SwiftUI

struct FolderStackView: View {
    let state: FolderStackState
    let keyboard: Bool
    var forceOpaqueBackground = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
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
            content
        }
        .dockPopoverChrome(state.chrome, opaque: reduceTransparency || forceOpaqueBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.folderStackAccessibilityLabel(folderName: state.folder.name)))
        .accessibilityValue(Text(.folderStackItemCount(
            count: state.entries.count,
            mode: String(localized: modeTitle(state.presentation))
        )))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill").foregroundStyle(.tint).accessibilityHidden(true)
            Text(verbatim: state.folder.name).font(.headline).lineLimit(1)
            Spacer(minLength: 8)
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
        } else if state.presentation == .grid {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 12)], spacing: 14) {
                    ForEach(state.entries) { entry in item(entry, grid: true) }
                }
                .padding(16)
            }
        } else if state.presentation == .list {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(state.entries) { entry in item(entry, grid: false) }
                }
                .padding(8)
            }
        } else {
            smartContent
        }
    }

    private var smartContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                ForEach(state.semanticSections) { section in
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
            Group {
                if grid {
                    VStack(spacing: 6) {
                        Image(nsImage: entry.icon).resizable().scaledToFit().frame(width: 48, height: 48)
                        Text(verbatim: entry.reference.name).font(.caption).lineLimit(2)
                            .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    }.frame(minHeight: 78)
                } else {
                    HStack(spacing: 9) {
                        Image(nsImage: entry.icon).resizable().scaledToFit().frame(width: 24, height: 24)
                        Text(verbatim: entry.reference.name).lineLimit(1)
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 8).frame(height: 34)
                }
            }
            .contentShape(.rect)
            .background(state.selectedID == entry.id ? Color.accentColor.opacity(0.18) : .clear,
                        in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .overlay {
            FolderStackDragSourceView(entry: entry, open: { state.openEntry?(entry.reference) },
                                      completed: { state.dragCompleted?($0) })
        }
        .accessibilityLabel(Text(verbatim: entry.reference.name))
        .accessibilityHint(Text(entry.reference.isFolder ? .folderStackRevealHint : .folderStackOpenHint))
        .accessibilityAddTraits(state.selectedID == entry.id ? .isSelected : [])
        .accessibilityActions {
            Button(entry.reference.isFolder ? .folderStackShowInFinder : .actionOpen) {
                state.openEntry?(entry.reference)
            }
        }
    }
}

#if DEBUG
@MainActor private enum FolderStackPreviewData {
    static let icon = NSImage(systemSymbolName: "doc.text.fill", accessibilityDescription: nil)!
    static let entries = [
        FolderStackEntry(reference: .init(url: URL(fileURLWithPath: "/Preview/item 2.txt"), name: "item 2.txt", isFolder: false), icon: icon),
        FolderStackEntry(reference: .init(url: URL(fileURLWithPath: "/Preview/item 10.txt"), name: "A document with a deliberately long Finder name.txt", isFolder: false), icon: icon)
    ]
    static func state(_ mode: FolderStackPresentation = .grid, name: String = "Projects",
                      entries suppliedEntries: [FolderStackEntry]? = nil,
                      loading: Bool = false, error: String? = nil) -> FolderStackState {
        FolderStackState(folder: FolderReference(url: URL(fileURLWithPath: "/Preview"), name: name,
                                                  bookmarkData: Data(), presentation: mode),
                         entries: suppliedEntries ?? entries, loading: loading, error: error)
    }
}

#Preview("Grid populated") {
    FolderStackView(state: FolderStackPreviewData.state(), keyboard: false).frame(width: 560, height: 420).padding()
}
#Preview("List, long name, dark") {
    FolderStackView(state: FolderStackPreviewData.state(.list, name: "A very long folder name that must remain on one line"), keyboard: true)
        .frame(width: 560, height: 420).padding().preferredColorScheme(.dark)
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
#endif
