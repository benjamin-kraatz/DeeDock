import Foundation

/// Everything onboarding has gathered, and the rules for moving between its steps. A plain value, so every rule is
/// testable without a view or a service.
///
/// Nothing here is saved. Onboarding keeps one draft in memory while the app runs, so closing it partway and opening
/// it again resumes where the person left (`resumeStep`), and `LookoutSettings` stays untouched until the first pass
/// starts (`settings(from:)`). Quitting forgets the draft; only a download in progress survives (its partial file).
nonisolated struct LookoutSetupDraft: Equatable, Sendable {
    var step: LookoutSetupStep = .welcome
    /// The suggested folders first, then the ones the person added, in that order.
    private(set) var folders: [LookoutSetupFolder]
    /// "Read files on battery too", on by default.
    var indexOnBattery = true
    /// Why the last folder the person picked wasn't added, for a line under "Add folder…".
    private(set) var addNotice: LookoutFolderChoice.Outcome?

    let home: String

    init(home: String) {
        self.home = LookoutFolderChoice.normalized(home)
        folders = LookoutFolderChoice.suggestions(home: home)
    }

    // MARK: Folders

    var chosen: [LookoutSetupFolder] { folders.filter(\.isChosen) }
    /// Chosen and allowed: what setup saves.
    var included: [LookoutSetupFolder] { folders.filter(\.isIncluded) }
    /// Chosen but not allowed, so left out.
    var skipped: [LookoutSetupFolder] { folders.filter(\.isSkipped) }

    func folder(_ path: String) -> LookoutSetupFolder? { folders.first { $0.path == path } }

    /// Checks or unchecks a row.
    mutating func setChosen(_ path: String, _ isChosen: Bool) {
        update(path) { $0.isChosen = isChosen }
        addNotice = nil
    }

    /// Adds a folder the person picked (`LookoutFolderChoice.choose`). A listed but unchecked folder is checked
    /// instead; chosen folders inside the new one are removed (added ones) or unchecked (suggested ones).
    ///
    /// - Returns: What happened; `.add` means a row was added or checked.
    @discardableResult
    mutating func add(_ path: String) -> LookoutFolderChoice.Outcome {
        let outcome = LookoutFolderChoice.choose(path, chosen: chosen.map(\.path), home: home)
        guard case .add(let path, let replacing) = outcome else {
            addNotice = outcome
            return outcome
        }
        addNotice = nil
        for inner in replacing {
            if folder(inner)?.suggestion != nil {
                update(inner) { $0.isChosen = false }
            } else {
                folders.removeAll { $0.path == inner }
            }
        }
        if folder(path) != nil {
            update(path) { $0.isChosen = true }
        } else {
            folders.append(LookoutSetupFolder(path: path, needsPrompt: LookoutFolderChoice.needsPrompt(path, home: home),
                                              isChosen: true))
        }
        return outcome
    }

    mutating func setAccess(_ path: String, _ access: LookoutFolderAccess) {
        update(path) {
            $0.access = access
            switch access {
            case .denied, .missing: $0.estimate = .unavailable
            case .allowed where $0.estimate == .afterAccess || $0.estimate == .unavailable: $0.estimate = .estimating
            default: break
            }
        }
    }

    mutating func setEstimate(_ path: String, _ estimate: LookoutFolderEstimateState) {
        update(path) { $0.estimate = estimate }
    }

    private mutating func update(_ path: String, _ change: (inout LookoutSetupFolder) -> Void) {
        guard let index = folders.firstIndex(where: { $0.path == path }) else { return }
        change(&folders[index])
    }

    // MARK: Totals

    /// The chosen folders' known estimates added up, and how many chosen folders have none yet.
    var total: (estimate: LookoutFolderEstimate, pending: Int) {
        chosen.reduce((LookoutFolderEstimate.zero, 0)) { sum, folder in
            if let estimate = folder.estimate.estimate { return (sum.0 + estimate, sum.1) }
            return folder.estimate == .unavailable ? sum : (sum.0, sum.1 + 1)
        }
    }

    /// The included folders' known file counts added up, for `lookout_setup_completed`.
    var estimatedFiles: Int {
        included.reduce(0) { $0 + ($1.estimate.estimate?.files ?? 0) }
    }

    // MARK: Steps

    /// Whether the primary button may move on from the current step.
    ///
    /// - Folders: at least one chosen.
    /// - Access: every chosen folder has an answer, and at least one is allowed (with none, there'd be nothing to
    ///   read; the person can go back, add another folder, or allow one in System Settings).
    /// - Download: both model files in place.
    func canContinue(modelsReady: Bool) -> Bool {
        switch step {
        case .welcome, .firstPass: true
        case .folders: !chosen.isEmpty
        case .access: !chosen.isEmpty && chosen.allSatisfy(\.access.isSettled) && !included.isEmpty
        case .download: modelsReady && !included.isEmpty
        }
    }

    /// Whether the access step has anything to ask: false when every chosen folder is allowed already (folders that
    /// read without a prompt were checked while the person chose them), so Continue goes straight to the download.
    var needsAccessStep: Bool {
        chosen.contains { $0.access != .allowed }
    }

    /// Where Continue goes from the current step.
    var nextStep: LookoutSetupStep? {
        switch step {
        case .welcome: .folders
        case .folders: needsAccessStep ? .access : .download
        case .access: .download
        case .download: .firstPass
        case .firstPass: nil
        }
    }

    /// Where Back goes from the current step. The first pass has no way back: setup is complete there.
    var previousStep: LookoutSetupStep? {
        switch step {
        case .welcome, .firstPass: nil
        case .folders: .welcome
        case .access: .folders
        case .download: needsAccessStep ? .access : .folders
        }
    }

    /// The step to show when onboarding opens again: where the person left, unless an earlier step no longer holds
    /// (no folder chosen, or none allowed any more).
    var resumeStep: LookoutSetupStep {
        switch step {
        case .welcome, .folders: step
        case .access: chosen.isEmpty ? .folders : .access
        case .download, .firstPass: chosen.isEmpty ? .folders : included.isEmpty ? .access : .download
        }
    }

    // MARK: Committing

    /// `base` with setup complete: the included folders, the battery choice, and Lookout on. What onboarding applies
    /// when the first pass starts.
    func settings(from base: LookoutSettings) -> LookoutSettings {
        var settings = base
        settings.folders = included.map(\.path)
        settings.excludedFolders = []
        settings.indexOnBattery = indexOnBattery
        settings.enabled = true
        settings.setupCompleted = true
        return settings
    }
}
