import CoreGraphics
import Foundation
import Observation

@MainActor @Observable
final class SessionCapsulePanelState {
    enum Page: Equatable { case collection, selection, draft, detail(UUID) }

    private(set) var capsules: [SessionCapsule]
    private(set) var candidates: [WindowContextCandidate] = []
    var selectedWindowIDs: Set<CGWindowID> = []
    var isBreadcrumb = false
    var draft: SessionCapsuleDraft?
    var page: Page = .collection
    private(set) var busy = false
    private(set) var permissionRequired = false
    var error: String?
    var chrome = DockPopoverChrome(edge: .bottom, attachment: DockPopoverGeometry.idealSize.width / 2)

    @ObservationIgnored private var captureReferenceIDs: [CGWindowID: UUID] = [:]
    @ObservationIgnored var discover: (() -> Void)?
    @ObservationIgnored var createDraft: (([WindowContextCandidate]) -> Void)?
    @ObservationIgnored var captureBreadcrumb: (([WindowContextCandidate]) -> Void)?
    @ObservationIgnored var saveDraft: ((SessionCapsuleDraft) -> Void)?
    @ObservationIgnored var deleteCapsule: ((UUID) -> Void)?
    @ObservationIgnored var resumeCapsule: ((SessionCapsule) -> Void)?
    @ObservationIgnored var requestPermission: (() -> Void)?
    @ObservationIgnored var cancelWork: (() -> Void)?

    init(capsules: [SessionCapsule]) { self.capsules = capsules }

    var selectedCandidates: [WindowContextCandidate] {
        candidates.filter { selectedWindowIDs.contains($0.id) }
    }

    var captureCandidates: [WindowContextCandidate] {
        let included = Set(draft?.windows.map(\.id) ?? [])
        return selectedCandidates.filter { candidate in
            captureReferenceIDs[candidate.id].map(included.contains) == true
        }
    }

    func referenceID(for candidateID: CGWindowID) -> UUID? { captureReferenceIDs[candidateID] }

    var detail: SessionCapsule? {
        guard case .detail(let id) = page else { return nil }
        return capsules.first { $0.id == id }
    }

    func beginNewCapsule(breadcrumb: Bool = false) {
        cancelWork?()
        draft = nil
        isBreadcrumb = breadcrumb
        page = .selection
        candidates = []
        selectedWindowIDs = []
        permissionRequired = false
        error = nil
        busy = true
        discover?()
    }

    func applyDiscovery(_ result: Result<[WindowContextCandidate], Error>) {
        busy = false
        switch result {
        case .success(let windows):
            candidates = windows
            selectedWindowIDs = Set(windows.prefix(3).map(\.id))
        case .failure(let failure as WindowContextCaptureError) where failure == .permissionRequired:
            permissionRequired = true
        case .failure(let failure as WindowContextCaptureError) where failure == .noWindows:
            error = String(localized: .capsulesNoWindows)
        case .failure(_ as WindowContextCaptureError):
            error = String(localized: .capsulesCaptureUnavailable)
        case .failure(let failure):
            error = failure.localizedDescription
        }
    }

    /// Manual editing uses selected metadata only, and remains available without any permission.
    func writeBreadcrumb() {
        cancelWork?()
        busy = false
        isBreadcrumb = true
        captureReferenceIDs = [:]
        let references = selectedCandidates.prefix(SessionCapsuleDocument.maximumWindowsPerCapsule).map {
            var reference = SessionCapsuleWindowReference(applicationName: $0.applicationName,
                bundleIdentifier: $0.bundleIdentifier, windowTitle: $0.title)
            reference.observedAt = Date()
            captureReferenceIDs[$0.id] = reference.id
            return reference
        }
        draft = SessionCapsuleDraft(title: String(localized: .breadcrumbDefaultTitle), summary: "",
            unfinishedTasks: [], windows: references, note: "", breadcrumb: SessionCapsuleBreadcrumb())
        error = nil
        page = .draft
    }

    func generateBreadcrumb() {
        guard !busy, draft?.breadcrumb != nil, !captureCandidates.isEmpty else { return }
        busy = true
        error = nil
        captureBreadcrumb?(captureCandidates)
    }

    func finishBreadcrumbCapture(references: [SessionCapsuleWindowReference], generated: SessionCapsuleDraft?) {
        busy = false
        guard var draft, draft.breadcrumb != nil else { return }
        // Preserve user-entered notes, next steps, links, and bookmarks across capture and failure.
        draft.windows = draft.windows.map { original in
            guard let captured = references.first(where: { $0.id == original.id }) else { return original }
            var merged = original
            merged.capturedAt = captured.capturedAt
            merged.textPreview = captured.textPreview
            return merged
        }
        if let generated {
            draft.summary = String(generated.summary.prefix(8_000))
            draft.unfinishedTasks = Array(generated.unfinishedTasks.prefix(6)).map { String($0.prefix(2_000)) }
            draft.breadcrumb?.generatedAt = Date()
        } else {
            error = String(localized: .breadcrumbManualFallback)
        }
        self.draft = draft
    }

    func cancelCapture() {
        cancelWork?()
        busy = false
    }

    func captureFailed() {
        busy = false
        error = String(localized: .breadcrumbManualFallback)
    }

    func edit(_ capsule: SessionCapsule) {
        cancelWork?()
        selectedWindowIDs = []
        candidates = []
        busy = false
        isBreadcrumb = capsule.breadcrumb != nil
        draft = SessionCapsuleDraft(title: capsule.title, summary: capsule.summary,
            unfinishedTasks: capsule.unfinishedTasks, windows: capsule.windows, note: capsule.note,
            breadcrumb: capsule.breadcrumb, editingID: capsule.id, originalCreatedAt: capsule.createdAt)
        page = .draft
        error = nil
    }

    func compose() {
        let selected = selectedCandidates
        guard !selected.isEmpty else { return }
        busy = true
        page = .draft
        error = nil
        createDraft?(selected)
    }

    func applyDraft(_ result: Result<SessionCapsuleDraft, Error>) {
        busy = false
        switch result {
        case .success(let draft): self.draft = draft; page = .draft
        case .failure:
            page = .selection
            error = String(localized: .capsulesCaptureUnavailable)
        }
    }

    func save() {
        guard let draft, draft.canSave else { return }
        saveDraft?(draft)
    }

    func didSave(_ capsules: [SessionCapsule]) {
        self.capsules = capsules
        draft = nil
        candidates = []
        selectedWindowIDs = []
        captureReferenceIDs = [:]
        page = .collection
        error = nil
    }

    func didDelete(_ capsules: [SessionCapsule]) {
        cancelWork?()
        draft = nil
        candidates = []
        selectedWindowIDs = []
        captureReferenceIDs = [:]
        busy = false
        self.capsules = capsules
        page = .collection
        error = nil
    }

    func show(_ capsule: SessionCapsule) { page = .detail(capsule.id); error = nil }

    func back() {
        if page == .collection { return }
        cancelWork?()
        page = .collection
        busy = false
        permissionRequired = false
        candidates = []
        selectedWindowIDs = []
        captureReferenceIDs = [:]
        draft = nil
        error = nil
    }

    func stop() {
        discover = nil; createDraft = nil; captureBreadcrumb = nil; saveDraft = nil; deleteCapsule = nil
        resumeCapsule = nil; requestPermission = nil
        cancelWork = nil
    }
}
