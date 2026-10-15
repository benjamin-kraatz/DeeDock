import Foundation

/// A folder's metadata-only estimate for the first pass (`Estimator`): files to read, seconds, and the index's size
/// once everything is read.
nonisolated struct LookoutFolderEstimate: Equatable, Sendable {
    var files: Int
    /// The first pass, in seconds.
    var seconds: Double
    /// Index bytes on disk.
    var bytes: Double

    static let zero = LookoutFolderEstimate(files: 0, seconds: 0, bytes: 0)

    static func + (lhs: Self, rhs: Self) -> Self {
        LookoutFolderEstimate(files: lhs.files + rhs.files, seconds: lhs.seconds + rhs.seconds,
                              bytes: lhs.bytes + rhs.bytes)
    }

    /// Whole minutes for "about 2 min", at least one.
    var minutes: Int { max(1, Int((seconds / 60).rounded(.up))) }
}

/// Whether Lookout may read a folder, as far as onboarding knows.
nonisolated enum LookoutFolderAccess: Equatable, Sendable {
    /// Not asked yet.
    case unknown
    /// Reading it now (macOS may be showing its prompt).
    case checking
    case allowed
    /// macOS said no (Files and Folders), or the folder can't be read.
    case denied
    /// The folder isn't there.
    case missing

    /// Asked, with an answer.
    var isSettled: Bool {
        switch self {
        case .allowed, .denied, .missing: true
        case .unknown, .checking: false
        }
    }
}

/// Where a folder's estimate is.
nonisolated enum LookoutFolderEstimateState: Equatable, Sendable {
    /// A protected folder: estimating would read it, which makes macOS ask before the person reached the access step.
    case afterAccess
    case estimating
    case ready(LookoutFolderEstimate)
    /// It can't be read, so there's nothing to estimate.
    case unavailable

    var estimate: LookoutFolderEstimate? {
        if case .ready(let estimate) = self { estimate } else { nil }
    }
}

/// One row of onboarding's folder list.
nonisolated struct LookoutSetupFolder: Identifiable, Equatable, Sendable {
    /// The four folders onboarding suggests, from `LookoutFolderChoice.suggestions`.
    enum Suggestion: String, Sendable {
        case desktop, documents, downloads, pictures
    }

    /// Absolute and standardized (`LookoutFolderChoice.normalized`).
    let path: String
    /// Set for the four suggested folders; nil for one the person added.
    let suggestion: Suggestion?
    /// Reading it may make macOS ask (`LookoutFolderChoice.needsPrompt`).
    let needsPrompt: Bool
    var isChosen: Bool
    var access: LookoutFolderAccess = .unknown
    var estimate: LookoutFolderEstimateState

    var id: String { path }

    init(path: String, suggestion: Suggestion? = nil, needsPrompt: Bool, isChosen: Bool) {
        self.path = path
        self.suggestion = suggestion
        self.needsPrompt = needsPrompt
        self.isChosen = isChosen
        estimate = needsPrompt && suggestion != nil ? .afterAccess : .estimating
    }

    /// Chosen and allowed: what setup saves.
    var isIncluded: Bool { isChosen && access == .allowed }
    /// Chosen, but macOS said no or it's gone: left out ("Not allowed · Skipped").
    var isSkipped: Bool { isChosen && (access == .denied || access == .missing) }
}
