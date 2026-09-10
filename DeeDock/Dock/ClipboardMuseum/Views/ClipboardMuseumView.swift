import SwiftUI

/// Everything the museum views can ask for. The controller supplies live closures; previews
/// supply ``preview``.
struct ClipboardMuseumActions {
    var imageURL: (ClipboardExhibit) -> URL?
    var restore: (ClipboardExhibit, ClipboardVeiledPayload?) -> Bool
    var redact: (UUID) -> Void
    /// Authenticates the owner, then returns the decrypted content, or nil on cancel or failure.
    var reveal: (UUID) async -> ClipboardVeiledPayload?
    /// Authenticates the owner, then permanently un-redacts. False on cancel or failure.
    var unredact: (UUID) async -> Bool
    var shred: (UUID) -> Void
    /// Nil or blank returns the exhibit to its automatic title.
    var rename: (UUID, String?) -> Void
    var remove: (UUID) -> Void
    var clear: () -> Void
    /// The last argument reports a failed write; it is not called on cancel.
    var save: (ClipboardExhibit, ClipboardExportFormat, ClipboardVeiledPayload?, @escaping @MainActor (Bool) -> Void) -> Void
    /// Plays the given exhibits full screen, starting at the second argument.
    var slideshow: ([UUID], UUID?) -> Void
    var enableCapture: () -> Void

    #if DEBUG
    static let preview = ClipboardMuseumActions(
        imageURL: { _ in nil }, restore: { _, _ in true }, redact: { _ in },
        reveal: { _ in ClipboardVeiledPayload(text: "ghp_previewToken") }, unredact: { _ in true },
        shred: { _ in }, rename: { _, _ in }, remove: { _ in }, clear: {}, save: { _, _, _, _ in },
        slideshow: { _, _ in }, enableCapture: {})
    #endif
}

/// Live museum content for the window. Reads the observable store so captures, redactions, and
/// removals show immediately.
struct ClipboardMuseumView: View {
    let store: ClipboardMuseumStore
    let actions: ClipboardMuseumActions

    var body: some View {
        ClipboardMuseumGallery(exhibits: store.exhibits, captureEnabled: store.captureEnabled,
                               requiresReset: store.requiresReset, actions: actions)
    }
}

/// Sidebar galleries grouped by day, a framed piece in the detail, and collection-wide actions.
/// Driven by plain values so previews can show every state without storage.
struct ClipboardMuseumGallery: View {
    let exhibits: [ClipboardExhibit]
    let captureEnabled: Bool
    let requiresReset: Bool
    let actions: ClipboardMuseumActions

    @State private var selection: ClipboardExhibit.ID?
    /// The exhibit whose title is being edited; shared so the sidebar can start a rename in the detail.
    @State private var renaming: ClipboardExhibit.ID?
    @State private var query = ""
    @State private var wing = ClipboardMuseumWing.all
    @State private var confirmsClear = false

    private var visible: [ClipboardExhibit] {
        exhibits.filter { wing.contains($0) && $0.matches(query) }
    }

    private var selected: ClipboardExhibit? {
        selection.flatMap { id in exhibits.first { $0.id == id } }
    }

    private var slideshowIDs: [UUID] {
        visible.filter { !$0.isRedacted }.map(\.id)
    }

    var body: some View {
        NavigationSplitView {
            ClipboardMuseumSidebar(halls: ClipboardMuseumHall.group(visible), count: exhibits.count,
                                   captureEnabled: captureEnabled, selection: $selection, renaming: $renaming,
                                   wing: $wing, actions: actions)
                .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 380)
        } detail: {
            if let selected {
                ClipboardExhibitDetail(exhibit: selected, renaming: $renaming, actions: actions)
            } else if exhibits.isEmpty {
                ClipboardMuseumEmptyState(captureEnabled: captureEnabled, requiresReset: requiresReset,
                                          enableCapture: actions.enableCapture)
            } else {
                ContentUnavailableView {
                    Label { Text(visible.isEmpty ? .clipboardMuseumNoMatches : .clipboardMuseumNoSelection) }
                        icon: { Image(systemName: "building.columns") }
                }
            }
        }
        .searchable(text: $query, placement: .sidebar, prompt: Text(.clipboardMuseumSearchPrompt))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { actions.slideshow(slideshowIDs, selection) } label: {
                    Label { Text(.clipboardMuseumSlideshow) } icon: { Image(systemName: "play.rectangle.fill") }
                }
                .help(Text(.clipboardMuseumSlideshow))
                .keyboardShortcut("f", modifiers: [.command, .control])
                .disabled(slideshowIDs.isEmpty)
                Button(role: .destructive) { confirmsClear = true } label: {
                    Label { Text(.clipboardMuseumClear) } icon: { Image(systemName: "trash") }
                }
                .help(Text(.clipboardMuseumClear))
                .disabled(exhibits.isEmpty || requiresReset)
            }
        }
        .confirmationDialog(Text(.clipboardMuseumClearConfirm), isPresented: $confirmsClear) {
            Button(role: .destructive, action: actions.clear) { Text(.clipboardMuseumClearConfirm) }
        } message: {
            Text(.clipboardMuseumClearHelp)
        }
        .onAppear { if selection == nil { selection = visible.first?.id } }
        // A new copy, a removal, or a filter change can leave the selection pointing at nothing.
        .onChange(of: visible.map(\.id)) { _, ids in
            if let selection, ids.contains(selection) { return }
            selection = ids.first
        }
        .onChange(of: selection) { _, id in
            if renaming != id { renaming = nil }
        }
    }
}

/// One day of exhibits, drawn as a titled section like a gallery room.
struct ClipboardMuseumHall: Identifiable {
    let day: Date
    var exhibits: [ClipboardExhibit]
    var id: Date { day }

    /// Groups newest-first exhibits by local calendar day, keeping order.
    static func group(_ exhibits: [ClipboardExhibit], calendar: Calendar = .current) -> [ClipboardMuseumHall] {
        var halls: [ClipboardMuseumHall] = []
        for exhibit in exhibits {
            let day = calendar.startOfDay(for: exhibit.acquiredAt)
            if halls.last?.day == day {
                halls[halls.count - 1].exhibits.append(exhibit)
            } else {
                halls.append(ClipboardMuseumHall(day: day, exhibits: [exhibit]))
            }
        }
        return halls
    }
}

/// Filters the collection by medium, or to the vault of redacted and sensitive pieces.
enum ClipboardMuseumWing: String, CaseIterable, Identifiable {
    case all, text, links, images, files, vault

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .all: .clipboardMuseumWingAll
        case .text: .clipboardMuseumWingText
        case .links: .clipboardMuseumWingLinks
        case .images: .clipboardMuseumWingImages
        case .files: .clipboardMuseumWingFiles
        case .vault: .clipboardMuseumWingVault
        }
    }

    func contains(_ exhibit: ClipboardExhibit) -> Bool {
        switch self {
        case .all: true
        case .text: exhibit.kind == .text
        case .links: exhibit.kind == .link
        case .images: exhibit.kind == .image
        case .files: exhibit.kind == .files
        case .vault: exhibit.isRedacted || exhibit.secret != nil
        }
    }
}

#if DEBUG
#Preview("Collection") {
    ClipboardMuseumGallery(exhibits: ClipboardExhibit.previewCollection, captureEnabled: true, requiresReset: false,
                           actions: .preview)
        .frame(width: 980, height: 700)
}

#Preview("Collection, dark") {
    ClipboardMuseumGallery(exhibits: ClipboardExhibit.previewCollection, captureEnabled: true, requiresReset: false,
                           actions: .preview)
        .frame(width: 980, height: 700)
        .preferredColorScheme(.dark)
}

#Preview("Empty, collecting off") {
    ClipboardMuseumGallery(exhibits: [], captureEnabled: false, requiresReset: false, actions: .preview)
        .frame(width: 980, height: 700)
}
#endif
