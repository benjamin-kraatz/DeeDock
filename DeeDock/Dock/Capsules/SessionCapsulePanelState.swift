import CoreGraphics
import Foundation
import Observation

@MainActor @Observable
final class SessionCapsulePanelState {
    enum Page: Equatable { case collection, selection, draft, detail(UUID) }

    private(set) var capsules: [SessionCapsule]
    private(set) var candidates: [WindowContextCandidate] = []
    var selectedWindowIDs: Set<CGWindowID> = []
    var draft: SessionCapsuleDraft?
    var page: Page = .collection
    private(set) var busy = false
    private(set) var permissionRequired = false
    var error: String?
    var chrome = DockPopoverChrome(edge: .bottom, attachment: DockPopoverGeometry.idealSize.width / 2)

    @ObservationIgnored var discover: (() -> Void)?
    @ObservationIgnored var createDraft: (([WindowContextCandidate]) -> Void)?
    @ObservationIgnored var saveDraft: ((SessionCapsuleDraft) -> Void)?
    @ObservationIgnored var deleteCapsule: ((UUID) -> Void)?
    @ObservationIgnored var resumeCapsule: ((SessionCapsule) -> Void)?
    @ObservationIgnored var requestPermission: (() -> Void)?
    @ObservationIgnored var cancelWork: (() -> Void)?

    init(capsules: [SessionCapsule]) { self.capsules = capsules }

    var selectedCandidates: [WindowContextCandidate] {
        candidates.filter { selectedWindowIDs.contains($0.id) }
    }

    var detail: SessionCapsule? {
        guard case .detail(let id) = page else { return nil }
        return capsules.first { $0.id == id }
    }

    func beginNewCapsule() {
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
        case .failure: error = String(localized: .capsulesCaptureUnavailable)
        }
    }

    func save() {
        guard let draft, draft.canSave else { return }
        saveDraft?(draft)
    }

    func didSave(_ capsules: [SessionCapsule]) {
        self.capsules = capsules
        draft = nil
        page = .collection
        error = nil
    }

    func didDelete(_ capsules: [SessionCapsule]) {
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
        draft = nil
        error = nil
    }

    func stop() {
        discover = nil; createDraft = nil; saveDraft = nil; deleteCapsule = nil
        resumeCapsule = nil; requestPermission = nil
        cancelWork = nil
    }
}
