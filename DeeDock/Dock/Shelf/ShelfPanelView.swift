import SwiftUI

/// The open Shelf: what is staged, and the two things you can do with it — take it out, or drop it.
struct ShelfPanelView: View {
    let state: ShelfPanelState
    let keyboard: Bool
    var forceOpaqueBackground = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweepBase: Set<UUID> = []

    /// Item rectangles and the rubber band share this space, so both survive scrolling.
    private static let listSpace = "shelf.list"
    private static let thumbnailSize = CGSize(width: 256, height: 256)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = state.error, !state.isEmpty {
                errorBanner(error)
                Divider()
            }
            if let error = state.semanticError, state.sort == .smart {
                semanticErrorBanner(error)
                Divider()
            }
            if let preview = state.preview {
                DockFilePreview(item: preview) { state.preview = nil }
            } else {
                content
            }
        }
        .dockPopoverChrome(state.chrome, opaque: reduceTransparency || forceOpaqueBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.shelfName))
        .accessibilityValue(Text(.shelfItemCount(count: state.entries.count)))
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(verbatim: error).font(.callout).lineLimit(2)
            Spacer(minLength: 4)
            Button(.folderStackRetry) { state.retry() }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.quaternary)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func semanticErrorBanner(_ error: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(verbatim: error).font(.callout).lineLimit(2)
            Spacer(minLength: 4)
            Button(.folderStackRetry) { state.retrySemanticOrganization() }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.quaternary)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: state.isEmpty ? "rectangle.stack" : "rectangle.stack.fill")
                .foregroundStyle(.tint)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            Text(.shelfName).font(.headline).lineLimit(1)
            Text(.shelfItemCount(count: state.entries.count))
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                .contentTransition(.numericText())
                .layoutPriority(-1)
            Spacer(minLength: 8)
            if !state.isEmpty {
                sortMenu
                if state.sort != .smart { presentationControl }
            }
            Button(.shelfClear) { state.clearAll?() }
                .controlSize(.small)
                .disabled(state.isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var sortMenu: some View {
        Menu {
            Picker(selection: Binding(get: { state.sort }, set: { state.choose($0) })) {
                ForEach(ShelfSort.allCases, id: \.self) { value in
                    Label(value.title, systemImage: value.symbol).tag(value)
                }
            } label: { Text(.shelfSort) }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text(.shelfSort))
        .accessibilityLabel(Text(.shelfSort))
        .accessibilityValue(Text(state.sort.title))
    }

    private var presentationControl: some View {
        HStack(spacing: 2) {
            presentationButton(.list, symbol: "list.bullet")
            presentationButton(.grid, symbol: "square.grid.2x2")
        }
        .padding(2)
        .background(.quaternary, in: .rect(cornerRadius: 7))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.shelfPresentationControl))
    }

    private func presentationButton(_ mode: ShelfPresentation, symbol: String) -> some View {
        Button { state.choose(mode) } label: {
            Image(systemName: symbol).frame(width: 24, height: 20)
                .background(state.presentation == mode ? Color.accentColor.opacity(0.22) : .clear,
                            in: .rect(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(mode == .grid ? .shelfPresentationGrid : .shelfPresentationList))
        .accessibilityAddTraits(state.presentation == mode ? .isSelected : [])
    }

    // MARK: - Content

    private var content: some View {
        // The content area owns the panel's remaining height, so an empty or error state centers
        // inside it rather than leaving the header floating.
        contentBody.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var contentBody: some View {
        if let error = state.error, state.isEmpty {
            ContentUnavailableView {
                Label(.shelfName, systemImage: "rectangle.stack.badge.questionmark")
            } description: {
                Text(verbatim: error)
            } actions: {
                Button(.folderStackRetry) { state.retry() }
            }
        } else if state.isEmpty {
            ContentUnavailableView {
                Label(.shelfEmptyTitle, systemImage: "rectangle.stack")
            } description: {
                Text(.shelfEmptyMessage)
            }
            .transition(.opacity)
        } else {
            items
        }
    }

    private var items: some View {
        ScrollView {
            Group {
                if state.sort == .smart {
                    semanticItems
                } else if state.presentation == .grid {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                        ForEach(state.entries) { entry in
                            gridItem(entry).transition(itemTransition)
                        }
                    }
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(state.entries) { entry in
                            row(entry).transition(itemTransition)
                        }
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .coordinateSpace(.named(Self.listSpace))
        .overlay {
            ShelfSelectionOverlayView(
                rowFrames: state.rowFrames,
                began: { additive in sweepBase = additive ? state.selection : [] },
                sweep: { rect, additive in
                    state.sweep(rect, additive: additive, base: sweepBase)
                },
                ended: { state.endSweep() },
                clear: { state.clearSelection() }
            )
        }
        .overlay(alignment: .topLeading) { marquee }
        .onAppear { state.requestThumbnails(size: Self.thumbnailSize) }
        .onChange(of: state.entries.count) { _, _ in
            state.requestThumbnails(size: Self.thumbnailSize)
        }
    }

    private var semanticItems: some View {
        LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
            ForEach(state.semanticSections) { section in
                Section {
                    ForEach(section.itemIDs, id: \.self) { id in
                        if let uuid = UUID(uuidString: id),
                           let entry = state.entries.first(where: { $0.id == uuid }) {
                            row(entry).transition(itemTransition)
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text(verbatim: section.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if section.kind == .organizing { ProgressView().controlSize(.mini) }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(.regularMaterial)
                    .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: state.semanticSections)
    }

    private var itemTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                          removal: .scale(scale: 0.92).combined(with: .opacity))
    }

    @ViewBuilder private var marquee: some View {
        if let band = state.band {
            Rectangle()
                .fill(Color.accentColor.opacity(0.18))
                .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1))
                .frame(width: band.width, height: band.height)
                .offset(x: band.minX, y: band.minY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Item presentation

    /// Finder-supplied folder names and system-formatted dates are shown as provided; only the
    /// unavailable notice is localized.
    private func subtitle(_ entry: ShelfPanelEntry) -> Text {
        guard entry.isAvailable else { return Text(.shelfItemUnavailable) }
        let added = entry.item.addedAt.formatted(.relative(presentation: .named))
        return Text(verbatim: "\(entry.location) · \(added)")
    }

    private func artwork(_ entry: ShelfPanelEntry, size: CGFloat) -> some View {
        Image(nsImage: state.thumbnail(entry.id) ?? entry.icon)
            .resizable().scaledToFit()
            .frame(width: size, height: size)
            .opacity(entry.isAvailable ? 1 : 0.4)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: state.thumbnail(entry.id) != nil)
    }

    private func row(_ entry: ShelfPanelEntry) -> some View {
        let selected = state.selection.contains(entry.id)
        return HStack(spacing: 10) {
            HStack(spacing: 10) {
                artwork(entry, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: entry.item.name).lineLimit(1)
                    subtitle(entry)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .contentShape(.rect)
            .overlay { source(entry) }
            removeButton(entry)
        }
        .padding(.horizontal, 8)
        .frame(height: 46)
        .background(
            selected ? Color.accentColor.opacity(0.18) : .clear,
            in: .rect(cornerRadius: 8)
        )
        .modifier(ShelfItemBehavior(state: state, entry: entry, selected: selected,
                                    space: Self.listSpace, reduceMotion: reduceMotion))
    }

    private func gridItem(_ entry: ShelfPanelEntry) -> some View {
        let selected = state.selection.contains(entry.id)
        return VStack(spacing: 6) {
            artwork(entry, size: 52)
            Text(verbatim: entry.item.name)
                .font(.caption).lineLimit(2).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(6)
        .frame(minHeight: 96)
        .contentShape(.rect)
        .background(
            selected ? Color.accentColor.opacity(0.18) : .clear,
            in: .rect(cornerRadius: 8)
        )
        .overlay { source(entry) }
        // Layered after the drag source so the button, which is frontmost, keeps its own clicks.
        .overlay(alignment: .topTrailing) { removeButton(entry).padding(2) }
        .modifier(ShelfItemBehavior(state: state, entry: entry, selected: selected,
                                    space: Self.listSpace, reduceMotion: reduceMotion))
    }

    private func source(_ entry: ShelfPanelEntry) -> some View {
        // Dragging hands out references; the items deliberately stay staged. In list mode the
        // overlay covers only the leading half, so Remove keeps its own clicks.
        ShelfItemDragSourceView(
            id: entry.id,
            enabled: entry.isAvailable,
            press: { command, shift in state.press(entry.id, command: command, shift: shift) },
            click: { state.click(entry.id) },
            cancelClick: { state.cancelPendingClick() },
            open: { state.openItems?(state.items(for: entry.id)) },
            begin: { view, event in state.beginDrag?(state.items(for: entry.id), view, event) }
        )
    }

    private func removeButton(_ entry: ShelfPanelEntry) -> some View {
        Button {
            state.removeItems?([entry.id])
        } label: {
            Image(systemName: "xmark.circle.fill")
                .imageScale(.large)
                .foregroundStyle(.secondary)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(Text(.shelfRemove))
        .accessibilityHidden(true)
    }
}

/// The context menu, frame reporting, selection animation, and accessibility every staged item
/// carries, whether it is drawn as a row or a grid tile.
private struct ShelfItemBehavior: ViewModifier {
    let state: ShelfPanelState
    let entry: ShelfPanelEntry
    let selected: Bool
    let space: String
    let reduceMotion: Bool

    /// A command acts on the whole selection when this item is part of one.
    private var targets: [ShelfItem] { state.items(for: entry.id) }
    private var count: Int { targets.count }

    func body(content: Content) -> some View {
        content
            .animation(.easeOut(duration: reduceMotion ? 0 : 0.12), value: selected)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(space))
            } action: { frame in
                state.rowFrames[entry.id] = frame
            }
            .contextMenu {
                Button(.filePreviewAction) { state.previewItems?(targets) }
                    .disabled(!entry.isAvailable)
                Button {
                    state.press(entry.id, command: false, shift: false)
                    state.openItems?(targets)
                } label: { Label(.shelfOpenItem(count: count), systemImage: "arrow.up.forward.app") }
                    .disabled(!entry.isAvailable)
                Button {
                    state.revealItems?(targets)
                } label: { Label(.shelfRevealInFinder, systemImage: "folder") }
                    .disabled(!entry.isAvailable)
                Divider()
                Button {
                    state.copyItems?(targets)
                } label: { Label(.shelfCopy(count: count), systemImage: "doc.on.doc") }
                    .disabled(!entry.isAvailable)
                Button {
                    state.selectAll()
                } label: { Label(.shelfSelectAll, systemImage: "checklist") }
                Divider()
                Button(role: .destructive) {
                    state.removeItems?(Set(targets.map(\.id)))
                } label: { Label(.shelfRemoveItem(count: count), systemImage: "xmark.circle") }
                Button(role: .destructive) {
                    state.clearAll?()
                } label: { Label(.shelfClear, systemImage: "rectangle.stack.badge.minus") }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: entry.item.name))
            .accessibilityValue(entry.isAvailable
                                ? Text(verbatim: entry.location)
                                : Text(.shelfItemUnavailable))
            .accessibilityHint(Text(.shelfItemHint))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityActions {
                if entry.isAvailable {
                    Button(.filePreviewAction) { state.previewItems?([entry.item]) }
                    Button(.shelfOpenItem(count: 1)) { state.openItems?([entry.item]) }
                    Button(.shelfRevealInFinder) { state.revealItems?([entry.item]) }
                }
                Button(.shelfRemove) { state.removeItems?([entry.id]) }
            }
    }
}

#if DEBUG
@MainActor private enum ShelfPreviewData {
    static let icon = NSImage(systemSymbolName: "doc.text.fill", accessibilityDescription: nil)!
    static func entry(_ name: String, location: String = "Desktop",
                      available: Bool = true, age: TimeInterval = 0) -> ShelfPanelEntry {
        ShelfPanelEntry(
            item: ShelfItem(url: URL(fileURLWithPath: "/Preview/\(name)"), name: name,
                            bookmarkData: Data(), addedAt: Date(timeIntervalSinceNow: -age)),
            icon: icon, isAvailable: available, location: location
        )
    }
    static func state(_ entries: [ShelfPanelEntry], error: String? = nil, selecting: Int = 1,
                      presentation: ShelfPresentation = .list) -> ShelfPanelState {
        let state = ShelfPanelState(entries: entries, error: error, presentation: presentation)
        state.selection = Set(entries.prefix(selecting).map(\.id))
        return state
    }
    static let sample = [
        entry("Quarterly report.pdf", age: 90),
        entry("A screenshot with a deliberately long Finder name.png", location: "Downloads", age: 7200),
        entry("Moved away.txt", available: false, age: 260_000)
    ]
}

#Preview("List") {
    ShelfPanelView(state: ShelfPreviewData.state(ShelfPreviewData.sample), keyboard: false)
        .frame(width: 420, height: 340).padding()
}
#Preview("Grid") {
    ShelfPanelView(state: ShelfPreviewData.state(ShelfPreviewData.sample, presentation: .grid),
                   keyboard: false).frame(width: 420, height: 340).padding()
}
#Preview("Multiple selection") {
    ShelfPanelView(state: ShelfPreviewData.state(ShelfPreviewData.sample, selecting: 2),
                   keyboard: false).frame(width: 420, height: 340).padding()
}
#Preview("Empty") {
    ShelfPanelView(state: ShelfPreviewData.state([]), keyboard: false)
        .frame(width: 420, height: 340).padding()
}
#Preview("Error, dark") {
    ShelfPanelView(state: ShelfPreviewData.state([ShelfPreviewData.entry("Notes.md")],
                                                 error: "The Shelf could not be saved."),
                   keyboard: true).frame(width: 420, height: 340).padding()
        .preferredColorScheme(.dark)
}
#Preview("Reduced transparency") {
    ShelfPanelView(state: ShelfPreviewData.state([ShelfPreviewData.entry("Notes.md")]),
                   keyboard: false, forceOpaqueBackground: true)
        .frame(width: 420, height: 340).padding()
}
#endif
