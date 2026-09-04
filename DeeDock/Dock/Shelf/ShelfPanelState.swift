import AppKit
import SwiftUI
import Observation

/// One staged item as the panel draws it.
struct ShelfPanelEntry: Identifiable {
    let item: ShelfItem
    /// The generic type icon, used until Quick Look supplies the document's own thumbnail.
    let icon: NSImage
    let isAvailable: Bool
    /// Enclosing folder name, shown so two files with the same name stay distinguishable.
    let location: String
    var id: UUID { item.id }
}

/// Presentation state for the open Shelf panel.
///
/// Contents come from `ShelfController`, so there is nothing to load asynchronously and no
/// directory to watch. Removal is always explicit: dragging items out copies their references and
/// leaves them staged.
@MainActor @Observable
final class ShelfPanelState {
    private(set) var entries: [ShelfPanelEntry] = []
    /// Quick Look artwork, keyed by item, replacing the generic icon as it arrives.
    private(set) var thumbnails: [UUID: NSImage] = [:]
    private(set) var sort: ShelfSort = .dateAdded
    private(set) var presentation: ShelfPresentation = .list
    private(set) var semanticSections: [SemanticStackSection] = []
    private(set) var organizing = false
    private(set) var semanticError: String?
    /// Every highlighted row. A drag from a selected row carries all of them.
    var selection: Set<UUID> = []
    /// Where Shift-click extends from, and where the keyboard currently sits.
    var anchorID: UUID?
    /// The rubber band being swept, in the list's coordinate space.
    var band: CGRect?
    /// Item rectangles in that same space, republished as the list scrolls or resizes.
    var rowFrames: [UUID: CGRect] = [:]
    var preview: DockFilePreviewItem?
    var error: String?
    var chrome = DockPopoverChrome(
        edge: .bottom,
        attachment: DockPopoverGeometry.idealSize.width / 2
    )
    @ObservationIgnored var removeItems: ((Set<UUID>) -> Void)?
    @ObservationIgnored var previewItems: (([ShelfItem]) -> Void)?
    @ObservationIgnored var openItems: (([ShelfItem]) -> Void)?
    @ObservationIgnored var revealItems: (([ShelfItem]) -> Void)?
    @ObservationIgnored var copyItems: (([ShelfItem]) -> Void)?
    @ObservationIgnored var clearAll: (() -> Void)?
    @ObservationIgnored var beginDrag: (([ShelfItem], NSView, NSEvent) -> Void)?
    @ObservationIgnored var sortChanged: ((ShelfSort) -> Void)?
    @ObservationIgnored var presentationChanged: ((ShelfPresentation) -> Void)?
    @ObservationIgnored var requestThumbnail: ((ShelfItem, CGSize) -> Void)?
    @ObservationIgnored var reloadSemantic: (() -> Void)?
    @ObservationIgnored private var retryAction: (() -> Void)?
    /// Set on press so the following mouse-up knows whether it still owes a selection change.
    @ObservationIgnored private var pendingCollapse: UUID?
    @ObservationIgnored private var semanticTask: Task<Void, Never>?
    @ObservationIgnored private var semanticGeneration = UUID()
    @ObservationIgnored private let organizer: any SemanticStackOrganizing

    init(entries: [ShelfPanelEntry] = [], error: String? = nil,
         sort: ShelfSort = .dateAdded, presentation: ShelfPresentation = .list,
         organizer: any SemanticStackOrganizing = UnavailableSemanticStackOrganizer()) {
        self.entries = entries
        self.error = error
        self.sort = sort
        self.presentation = presentation
        self.organizer = organizer
        anchorID = entries.first?.id
        selection = anchorID.map { [$0] } ?? []
    }

    var isEmpty: Bool { entries.isEmpty }
    var order: [UUID] {
        guard sort == .smart, !semanticSections.isEmpty else { return entries.map(\.id) }
        return semanticSections.flatMap(\.itemIDs).compactMap(UUID.init(uuidString:))
    }

    /// Rebuilds from the shared controller. Called on open and after every edit.
    /// Insertions, removals, and re-sorting animate unless the system asks for reduced motion.
    func apply(_ items: [ShelfItem], sort: ShelfSort = .dateAdded,
               presentation: ShelfPresentation = .list, animated: Bool = true,
               resolve: (ShelfItem) -> ShelfResourceAccess?) {
        var accesses: [ShelfResourceAccess] = []
        let next = items.map { item in 
            let access = resolve(item)
            if let access { accesses.append(access) }
            let resolvedURL = access?.url ?? item.url
            let icon = NSWorkspace.shared.icon(forFile: resolvedURL.path)
            icon.size = NSSize(width: 128, height: 128)
            return ShelfPanelEntry(
                item: item, icon: icon, isAvailable: access?.isAvailable == true,
                location: resolvedURL.deletingLastPathComponent().lastPathComponent
            )
        }
        let changed = next.map(\.id) != entries.map(\.id) || sort != self.sort || presentation != self.presentation
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        self.sort = sort
        self.presentation = presentation
        if animated, changed, !reduceMotion {
            withAnimation(.snappy(duration: 0.24)) { entries = next }
        } else {
            entries = next
        }
        if let preview, !accesses.contains(where: { $0.url == preview.url && $0.isAvailable }) {
            self.preview = nil
        }
        let live = Set(entries.map(\.id))
        selection = selection.intersection(live)
        rowFrames = rowFrames.filter { live.contains($0.key) }
        thumbnails = thumbnails.filter { live.contains($0.key) }
        if anchorID == nil || !live.contains(anchorID!) { anchorID = entries.first?.id }
        if selection.isEmpty, let anchorID { selection = [anchorID] }
        if sort == .smart { refreshSemanticOrganization(accesses: accesses) }
        else { cancelSemanticOrganization(clearError: true) }
    }

    // MARK: - Artwork

    func thumbnail(_ id: UUID) -> NSImage? { thumbnails[id] }

    func setThumbnail(_ image: NSImage, for id: UUID) {
        guard order.contains(id) else { return }
        thumbnails[id] = image
    }

    /// Asks for the artwork of every entry that still shows a generic type icon.
    func requestThumbnails(size: CGSize) {
        for entry in entries where entry.isAvailable && thumbnails[entry.id] == nil {
            requestThumbnail?(entry.item, size)
        }
    }

    // MARK: - View choices

    func choose(_ value: ShelfSort) {
        guard value != sort else { return }
        sort = value
        sortChanged?(value)
        if value != .smart { cancelSemanticOrganization(clearError: true) }
    }

    func choose(_ value: ShelfPresentation) {
        guard value != presentation else { return }
        presentation = value
        presentationChanged?(value)
    }

    // MARK: - Errors

    func report(_ message: String, retry: @escaping () -> Void) {
        error = message
        retryAction = retry
    }

    func retry() {
        let action = retryAction
        error = nil
        retryAction = nil
        action?()
    }

    func retrySemanticOrganization() {
        semanticError = nil
        reloadSemantic?()
    }

    // MARK: - Selection

    /// A press selects immediately unless the item is already part of the selection, where the
    /// decision waits for mouse-up so a drag can still carry the whole group.
    func press(_ id: UUID, command: Bool, shift: Bool) {
        pendingCollapse = nil
        if shift {
            selection = ShelfSelection.extending(from: anchorID, to: id, in: order)
        } else if command {
            selection = ShelfSelection.toggling(selection, id)
            anchorID = id
        } else if selection.contains(id), selection.count > 1 {
            pendingCollapse = id
        } else {
            selection = [id]
            anchorID = id
        }
    }

    /// Completes a click that pressed inside an existing multiple selection without dragging.
    func click(_ id: UUID) {
        guard pendingCollapse == id else { return }
        pendingCollapse = nil
        selection = [id]
        anchorID = id
    }

    func cancelPendingClick() { pendingCollapse = nil }

    func clearSelection() {
        selection = []
        pendingCollapse = nil
    }

    /// Live rubber band. `additive` keeps whatever was selected when the sweep began.
    func sweep(_ rect: CGRect, additive: Bool, base: Set<UUID>) {
        band = rect
        let hit = ShelfSelection.within(rect, frames: rowFrames)
        selection = additive ? base.union(hit) : hit
    }

    func endSweep() { band = nil }

    /// The items a gesture on this entry acts on: the whole selection when it belongs to one.
    func items(for id: UUID) -> [ShelfItem] {
        let ids = ShelfSelection.dragging(id, selection: selection)
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.item) })
        return order.filter { ids.contains($0) }.compactMap { byID[$0] }
    }

    var selectedItems: [ShelfItem] {
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.item) })
        return order.filter { selection.contains($0) }.compactMap { byID[$0] }
    }

    func select(by distance: Int) {
        let navigable = order
        guard !navigable.isEmpty else { return }
        let current = anchorID.flatMap { navigable.firstIndex(of: $0) } ?? 0
        let next = navigable[(current + distance + navigable.count) % navigable.count]
        anchorID = next
        selection = [next]
    }

    func selectAll() { selection = Set(order) }

    // MARK: - Commands

    func removeSelection() {
        guard !selection.isEmpty else { return }
        removeItems?(selection)
    }

    func openSelection() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        openItems?(items)
    }

    func revealSelection() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        revealItems?(items)
    }

    func stop() {
        cancelSemanticOrganization(clearError: true)
        retryAction = nil
        band = nil
        thumbnails.removeAll()
        removeItems = nil
        preview = nil
        previewItems = nil
        openItems = nil
        revealItems = nil
        copyItems = nil
        clearAll = nil
        beginDrag = nil
        sortChanged = nil
        presentationChanged = nil
        requestThumbnail = nil
        reloadSemantic = nil
    }

    // MARK: - Semantic organization

    private func refreshSemanticOrganization(accesses suppliedAccesses: [ShelfResourceAccess]) {
        guard sort == .smart else { return }
        semanticTask?.cancel()
        semanticGeneration = UUID()
        let token = semanticGeneration
        semanticError = nil

        let availableEntries = entries.filter(\.isAvailable)
        let unavailableEntries = entries.filter { !$0.isAvailable }.sorted {
            $0.item.name.localizedStandardCompare($1.item.name) == .orderedAscending
        }
        let unavailableSection = unavailableEntries.isEmpty ? nil : SemanticStackSection(
            id: "unavailable",
            title: String(localized: .semanticStackUnavailable),
            itemIDs: unavailableEntries.map { $0.id.uuidString },
            kind: .unavailable
        )
        let availableIDs = availableEntries.map { $0.id.uuidString }
        semanticSections = (availableIDs.isEmpty ? [] : [SemanticStackSection(
            id: "organizing",
            title: String(localized: .semanticStackOrganizing),
            itemIDs: availableIDs,
            kind: .organizing
        )]) + (unavailableSection.map { [$0] } ?? [])

        let accessByID = Dictionary(uniqueKeysWithValues: suppliedAccesses.map { ($0.id, $0) })
        let inputs = ShelfSemanticRequestBuilder.inputs(
            for: availableEntries.map(\.item),
            accessByID: accessByID
        )
        organizing = inputs.count >= 4

        semanticTask = Task { [weak self] in
            guard let self else { return }
            let candidates = await SemanticStackMetadataLoader.candidates(from: inputs)
            withExtendedLifetime(suppliedAccesses) {}
            guard !Task.isCancelled, semanticGeneration == token else { return }

            guard candidates.count >= 4 else {
                semanticSections = SemanticStackNormalizer.fallback(
                    candidates: candidates,
                    title: String(localized: .semanticStackItems)
                ).sections + (unavailableSection.map { [$0] } ?? [])
                organizing = false
                return
            }

            let availability = await organizer.availability()
            guard !Task.isCancelled, semanticGeneration == token else { return }
            guard availability == .available else {
                applySemanticFailure(Self.message(for: availability), candidates: candidates,
                                     unavailableSection: unavailableSection, token: token)
                return
            }

            let request = ShelfSemanticRequestBuilder.request(candidates: candidates)
            let stream = await organizer.snapshots(for: request)
            do {
                for try await snapshot in stream {
                    guard !Task.isCancelled, semanticGeneration == token else { return }
                    semanticSections = snapshot.sections + (unavailableSection.map { [$0] } ?? [])
                    organizing = !snapshot.isFinal
                    selection = ShelfSelection.retained(selection, in: order)
                    if snapshot.isFinal { announce(String(localized: .semanticStackFinished)) }
                }
            } catch is CancellationError {
                return
            } catch {
                guard semanticGeneration == token else { return }
                applySemanticFailure(String(localized: .semanticStackFailed), candidates: candidates,
                                     unavailableSection: unavailableSection, token: token)
            }
        }
    }

    private func applySemanticFailure(_ message: String, candidates: [SemanticStackCandidate],
                                      unavailableSection: SemanticStackSection?, token: UUID) {
        guard semanticGeneration == token else { return }
        semanticError = message
        organizing = false
        semanticSections = SemanticStackNormalizer.fallback(
            candidates: candidates,
            title: String(localized: .semanticStackItems)
        ).sections + (unavailableSection.map { [$0] } ?? [])
        announce(message)
    }

    private func cancelSemanticOrganization(clearError: Bool) {
        semanticGeneration = UUID()
        semanticTask?.cancel()
        semanticTask = nil
        semanticSections = []
        organizing = false
        if clearError { semanticError = nil }
    }

    private static func message(for availability: SemanticStackAvailability) -> String {
        switch availability {
        case .available: String(localized: .semanticStackFailed)
        case .deviceNotEligible: String(localized: .semanticStackDeviceNotEligible)
        case .appleIntelligenceNotEnabled: String(localized: .semanticStackAppleIntelligenceDisabled)
        case .modelNotReady: String(localized: .semanticStackModelNotReady)
        }
    }

    private func announce(_ message: String) {
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
    }
}
