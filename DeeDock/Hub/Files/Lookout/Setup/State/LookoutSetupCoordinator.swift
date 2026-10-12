import AppKit
import Observation

/// Runs Lookout's onboarding: whether it shows, the draft it builds (`LookoutSetupDraft`), the folder reads behind
/// the estimates and the access step, the model download, and setup itself.
///
/// ## Presentation
/// Onboarding is a sheet-like card over the Hub (`LookoutSetupOverlay`), not a window of its own. While it shows,
/// it holds the Hub open (`holdHub`, which takes `HubHoldReason.modal`): an anchored Hub otherwise closes when it
/// loses key status or sees a click elsewhere, and both happen here on purpose. macOS's Files and Folders prompt
/// comes from another process, and the folder picker is an `NSOpenPanel` that takes key status; the Apps tab's file
/// chooser already relies on the same hold. Sleep and display changes still close an anchored Hub (`suspend`), and so
/// do ⌘W and opening Settings; onboarding then ends as if closed, and opens where it left next time.
///
/// ## Lifetime
/// One coordinator exists for the app's lifetime (`HubCoordinator` makes it), so its draft and its downloader outlive
/// the card. Nothing is saved until the first pass starts: then the included folders, the battery choice and "on"
/// go to `LookoutSettings` at once (`commit`), because the first pass needs a running engine to show progress. From
/// there, both buttons and closing the card only end onboarding.
///
/// Main actor. Folder reads run off it (`LookoutFolderInspecting`); each folder has at most one read in flight, and
/// its result lands in the draft whenever it arrives (a read waiting on macOS's prompt can't be cancelled). The
/// activation observer exists only while the card shows.
@MainActor @Observable
final class LookoutSetupCoordinator {
    private(set) var isPresented = false
    private(set) var draft: LookoutSetupDraft
    /// Which way the last step change went, for the slide.
    private(set) var direction: LookoutSetupDirection = .forward

    let engine: LookoutEngine
    let downloader: LookoutModelDownloader

    /// Holds (true) or releases (false) the Hub open while the card shows.
    @ObservationIgnored var holdHub: (Bool) -> Void = { _ in }
    /// Makes the Hub key again after the folder picker or a macOS prompt took key status.
    @ObservationIgnored var refocusHub: () -> Void = {}
    /// "Start searching": puts the caret in the Files search field.
    @ObservationIgnored var focusSearch: () -> Void = {}

    @ObservationIgnored private let inspector: any LookoutFolderInspecting
    @ObservationIgnored private let picker: any LookoutFolderPicking
    @ObservationIgnored private var inspections: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    /// Setup was applied while the card shows (the first pass started).
    @ObservationIgnored private var committed = false
    /// Previews: the first pass's progress and feed instead of the engine's.
    @ObservationIgnored private(set) var previewProgress: LookoutFirstPassProgress?
    @ObservationIgnored private(set) var previewFeed: [LookoutSetupFeedItem] = []

    /// - Parameters:
    ///   - home: The home folder whose Desktop, Documents, Downloads and Pictures are suggested.
    init(engine: LookoutEngine, downloader: LookoutModelDownloader, inspector: any LookoutFolderInspecting,
         picker: any LookoutFolderPicking, home: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.engine = engine
        self.downloader = downloader
        self.inspector = inspector
        self.picker = picker
        draft = LookoutSetupDraft(home: home)
        downloader.onFinished = { [weak engine] in engine?.modelDidArrive() }
    }

    /// The real coordinator: the live inspector, the open panel and the live downloader. Under the test host and in
    /// previews it reads no folder and downloads nothing.
    static func live(engine: LookoutEngine) -> LookoutSetupCoordinator {
        let inert = HostEnvironment.isTestHost || HostEnvironment.isPreview
        let inspector: any LookoutFolderInspecting = inert ? LookoutStubFolderInspector() : LookoutLiveFolderInspector()
        let picker: any LookoutFolderPicking = inert ? LookoutStubFolderPicker() : LookoutOpenPanelPicker()
        return LookoutSetupCoordinator(engine: engine, downloader: .live(), inspector: inspector, picker: picker)
    }

    // MARK: Presenting

    /// Shows onboarding over the Hub, at the step the person left (`LookoutSetupDraft.resumeStep`). Does nothing
    /// once Lookout is set up.
    func present() {
        guard !isPresented, engine.status == .notSetUp else { return }
        draft.step = draft.resumeStep
        direction = .forward
        downloader.refresh()
        isPresented = true
        holdHub(true)
        observeActivation()
        stepDidAppear()
    }

    /// "Not now", Escape, or the close of the first pass: ends onboarding. Before setup that's abandoning it (the
    /// draft stays for next time, a download keeps going); during the first pass it's finishing in the background.
    func close() {
        end()
    }

    /// The Hub closed under the card.
    func hubDidClose() {
        end()
    }

    /// "Start searching" (true) or "Finish in the background" (false) on the first pass.
    func finish(startSearching: Bool) {
        end()
        if startSearching { focusSearch() }
    }

    private func end() {
        guard isPresented else { return }
        isPresented = false
        holdHub(false)
        stopObservingActivation()
        if committed {
            committed = false
            draft = LookoutSetupDraft(home: draft.home)
        } else {
            Analytics.track(.lookoutSetupAbandoned(lastStep: draft.step.analytics))
        }
    }

    /// Forgets the draft and stops a download ("Delete index and model" in Settings), so onboarding starts over.
    func reset() async {
        if isPresented { end() }
        await downloader.stop()
        inspections.values.forEach { $0.cancel() }
        inspections = [:]
        draft = LookoutSetupDraft(home: draft.home)
    }

    // MARK: Steps

    /// The first pass so far, from the index service's status.
    var firstPassProgress: LookoutFirstPassProgress {
        previewProgress ?? LookoutFirstPassProgress(status: engine.indexStatus)
    }

    /// Whether the primary button is enabled.
    var canContinue: Bool { draft.canContinue(modelsReady: downloader.isReady) }

    /// The primary button: Continue, or "Start searching" on the first pass. Starting the first pass applies setup.
    func continueStep() {
        guard draft.step != .firstPass else { return finish(startSearching: true) }
        guard canContinue, let next = draft.nextStep else { return }
        if next == .firstPass { commit() }
        move(to: next, .forward)
    }

    func goBack() {
        guard let previous = draft.previousStep else { return }
        move(to: previous, .back)
    }

    private func move(to step: LookoutSetupStep, _ direction: LookoutSetupDirection) {
        self.direction = direction
        draft.step = step
        stepDidAppear()
    }

    /// Each step's own work when it comes on screen.
    private func stepDidAppear() {
        Analytics.track(.lookoutSetupStepViewed(draft.step.analytics))
        switch draft.step {
        case .folders:
            // Folders that read without a prompt (and ones the person picked) are checked and estimated now.
            for folder in draft.folders where folder.access == .unknown && (!folder.needsPrompt || folder.suggestion == nil) {
                inspect(folder.path, prompted: false)
            }
        case .access:
            for folder in draft.chosen where folder.access == .unknown && !folder.needsPrompt {
                inspect(folder.path, prompted: false)
            }
        case .download:
            downloader.start()
        case .welcome, .firstPass:
            break
        }
    }

    // MARK: Folders

    func setChosen(_ path: String, _ isChosen: Bool) {
        draft.setChosen(path, isChosen)
    }

    /// "Add folder…": the open panel, then the folder joins the list and is read at once. Picking it is consent, so
    /// a macOS prompt that follows comes right after the person's own choice.
    func addFolder() {
        Task {
            let url = await picker.pickFolder()
            refocusHub()
            guard let url else { return }
            if case .add(let path, _) = draft.add(url.path) { inspect(path, prompted: false) }
        }
    }

    /// "Allow…": reads the folder, which makes macOS ask if it hasn't been asked.
    func requestAccess(_ path: String) {
        inspect(path, prompted: true)
    }

    /// "Open Settings" beside a folder macOS declined.
    func openPrivacySettings() {
        LookoutPrivacySettings.openFilesAndFolders()
    }

    func setIndexOnBattery(_ value: Bool) {
        draft.indexOnBattery = value
    }

    /// Reads a folder's access, then estimates it when allowed and not estimated yet.
    ///
    /// - Parameter prompted: The person pressed "Allow…": the answer is reported (`lookout_access_result`) and the
    ///   Hub becomes key again, since macOS's prompt may have taken key status.
    private func inspect(_ path: String, prompted: Bool) {
        guard inspections[path] == nil else { return }
        draft.setAccess(path, .checking)
        let inspector = inspector
        inspections[path] = Task { [weak self] in
            let access = await inspector.access(path)
            guard let self, !Task.isCancelled else { return }
            draft.setAccess(path, access)
            if prompted {
                if access == .allowed || access == .denied {
                    Analytics.track(.lookoutAccessResult(access == .allowed ? .allowed : .denied, context: .onboarding))
                }
                refocusHub()
            }
            if access == .allowed, draft.folder(path)?.estimate.estimate == nil {
                draft.setEstimate(path, .estimating)
                let estimate = await inspector.estimate(path)
                guard !Task.isCancelled else { return }
                draft.setEstimate(path, estimate.map { .ready($0) } ?? .unavailable)
            }
            inspections[path] = nil
        }
    }

    /// Back from System Settings: folders macOS declined are read again quietly. A declined folder never prompts
    /// again; one the person allowed meanwhile now reads.
    private func observeActivation() {
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheckDeclined() }
        }
    }

    private func stopObservingActivation() {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
    }

    private func recheckDeclined() {
        guard isPresented, draft.step == .access else { return }
        for folder in draft.chosen where folder.access == .denied || folder.access == .missing {
            inspect(folder.path, prompted: false)
        }
    }

    // MARK: Setup

    /// Applies setup as the first pass starts: the engine starts reading at once, and the query encoder warms so its
    /// first launch (Metal shader compilation, about 5 s) happens during the first pass.
    private func commit() {
        engine.apply(draft.settings(from: engine.settings))
        engine.warmQueryEncoder()
        committed = true
        Analytics.track(.lookoutSetupCompleted(folderCount: draft.chosen.count, allowedCount: draft.included.count,
                                               skippedCount: draft.skipped.count,
                                               estimatedFiles: draft.estimatedFiles,
                                               indexOnBattery: draft.indexOnBattery))
    }

    // MARK: Keyboard

    /// Keys while the card shows: Return is the primary button, Escape closes, and the Hub's tab and search shortcuts
    /// wait until it closes. Everything else goes on (Tab and Space for keyboard navigation of the card's controls).
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 53, modifiers.isEmpty {
            close()
            return true
        }
        if modifiers.isEmpty, event.specialKey == .carriageReturn || event.specialKey == .enter {
            continueStep()
            return true
        }
        if modifiers == .command, let key = event.charactersIgnoringModifiers?.lowercased(),
           ["1", "2", "3", "f"].contains(key) {
            return true
        }
        return false
    }

    isolated deinit {
        inspections.values.forEach { $0.cancel() }
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }
}

// MARK: - Previews

extension LookoutSetupCoordinator {
    /// A coordinator at `step` with sample folders, estimates and access answers, over an inert engine and a
    /// downloader in `download`. It reads no folder, downloads nothing and opens no panel.
    static func preview(step: LookoutSetupStep, download: LookoutModelDownloader.FileState = .waiting,
                        configure: (inout LookoutSetupDraft) -> Void = { _ in }) -> LookoutSetupCoordinator {
        let home = "/Users/preview"
        let coordinator = LookoutSetupCoordinator(
            engine: .inert(), downloader: .inert(state: download), inspector: LookoutStubFolderInspector(),
            picker: LookoutStubFolderPicker(), home: home)
        var draft = LookoutSetupDraft(home: home)
        let samples: [(String, LookoutFolderEstimate)] = [
            ("Desktop", LookoutFolderEstimate(files: 412, seconds: 110, bytes: 14_000_000)),
            ("Documents", LookoutFolderEstimate(files: 2_860, seconds: 830, bytes: 96_000_000)),
            ("Downloads", LookoutFolderEstimate(files: 1_930, seconds: 650, bytes: 70_000_000)),
            ("Pictures", LookoutFolderEstimate(files: 8_240, seconds: 2_270, bytes: 180_000_000)),
        ]
        for (name, estimate) in samples where name == "Pictures" || step > .access {
            draft.setAccess(home + "/" + name, .allowed)
            draft.setEstimate(home + "/" + name, .ready(estimate))
        }
        draft.step = step
        configure(&draft)
        coordinator.draft = draft
        coordinator.isPresented = true
        coordinator.previewProgress = LookoutFirstPassProgress(done: 2_184, total: 5_202)
        coordinator.previewFeed = [
            .init(file: .init(kind: .image, name: "IMG_4821.HEIC")),
            .init(file: .init(kind: .screenshot, name: "Screenshot 2026-10-02 at 14.12.33.png")),
            .init(file: .init(kind: .pdf, name: "Mietvertrag_Wohnung_Kreuzberg.pdf")),
            .init(file: .init(kind: .doc, name: "Stripe dispute notes.md")),
        ]
        return coordinator
    }
}
