import AppKit

/// App-wide popover coordinator for deliberate session checkpoints.
@MainActor
final class SessionCapsuleCoordinator {
    private let capsules: SessionCapsuleController
    private let presenter: DockPopoverPresenter
    private let screenCapture: ScreenCaptureAccessController
    private let contexts: any WindowContextCapturing
    private let composer: any SessionCapsuleComposing
    private let windows: any ApplicationWindowServicing
    private var controller: DockPopoverPanelController<SessionCapsulePanelView>?
    private var state: SessionCapsulePanelState?
    private var task: Task<Void, Never>?
    private var displayID: String?
    private var anchorTarget: DockEntryID = .sessionCapsules
    private weak var sourcePanel: DockPanelController?
    var keyboardDismissed: ((String) -> Void)?
    var isOpen: Bool { controller != nil }

    init(capsules: SessionCapsuleController, presenter: DockPopoverPresenter,
         screenCapture: ScreenCaptureAccessController,
         contexts: any WindowContextCapturing = ScreenCaptureWindowContextService(),
         composer: any SessionCapsuleComposing = FoundationModelsSessionCapsuleComposer(),
         windows: any ApplicationWindowServicing = AccessibilityApplicationWindowService()) {
        self.capsules = capsules
        self.presenter = presenter
        self.screenCapture = screenCapture
        self.contexts = contexts
        self.composer = composer
        self.windows = windows
        presenter.register(.sessionCapsules) { [weak self] in self?.close(returnFocus: false) }
    }

    func toggle(on panel: DockPanelController, anchorTarget: DockEntryID = .sessionCapsules,
                initialCapsuleID: UUID? = nil) {
        if displayID == panel.store.displayID, controller != nil {
            close(returnFocus: true)
            return
        }
        close(returnFocus: false)
        presenter.prepareToOpen(.sessionCapsules)
        guard let anchor = panel.popoverAnchor(for: anchorTarget) else {
            panel.store.errorMessage = .capsulesUnavailable
            return
        }

        let state = SessionCapsulePanelState(capsules: capsules.capsules)
        if let initialCapsuleID,
           let capsule = capsules.capsules.first(where: { $0.id == initialCapsuleID }) {
            state.show(capsule)
        }
        if let failure = capsules.loadFailure { state.error = failure }
        let next = DockPopoverPanelController(anchor: anchor, keyboard: true,
                                              ideal: CGSize(width: 560, height: 500)) { chrome in
            state.chrome = chrome
        } content: {
            SessionCapsulePanelView(state: state)
        }
        self.state = state
        controller = next
        displayID = panel.store.displayID
        self.anchorTarget = anchorTarget
        sourcePanel = panel
        panel.holdPopover(true)
        presenter.didOpen(.sessionCapsules)

        state.discover = { [weak self, weak state] in self?.discover(for: state) }
        state.createDraft = { [weak self, weak state] selected in self?.createDraft(selected, for: state) }
        state.saveDraft = { [weak self, weak state] draft in self?.save(draft, for: state) }
        state.deleteCapsule = { [weak self, weak state] id in self?.delete(id, for: state) }
        state.resumeCapsule = { [weak self] capsule in self?.resume(capsule) }
        state.requestPermission = { [weak self, weak state] in
            guard let self, let state else { return }
            screenCapture.requestAccess()
            if screenCapture.status == .enabled { state.beginNewCapsule() }
            else { screenCapture.openSystemSettings() }
        }
        state.cancelWork = { [weak self] in self?.task?.cancel(); self?.task = nil }
        next.willClose = { [weak self, weak state] in
            self?.task?.cancel(); self?.task = nil; state?.stop()
        }
        next.keyHandler = { [weak self] event in
            guard event.keyCode == 53 else { return false }
            if self?.state?.page != .collection { self?.state?.back() }
            else { self?.close(returnFocus: true) }
            return true
        }
        next.closed = { [weak self, weak panel] returnFocus in
            let sourceID = panel?.store.displayID
            panel?.holdPopover(false)
            self?.presenter.didClose(.sessionCapsules)
            self?.controller = nil; self?.state = nil; self?.displayID = nil; self?.sourcePanel = nil
            self?.anchorTarget = .sessionCapsules
            if returnFocus { panel?.focus() }
            else if let sourceID { self?.keyboardDismissed?(sourceID) }
        }
        next.show()
    }

    func show(_ capsuleID: UUID, on panel: DockPanelController) {
        close(returnFocus: false)
        toggle(on: panel, anchorTarget: .sessionCapsule(capsuleID), initialCapsuleID: capsuleID)
    }

    func resume(_ capsuleID: UUID) {
        guard let capsule = capsules.capsules.first(where: { $0.id == capsuleID }) else { return }
        resume(capsule)
    }

    func delete(_ capsuleID: UUID) {
        delete(capsuleID, for: state)
    }

    func reload() { state?.didSave(capsules.capsules) }

    func reanchor() {
        guard let controller, let sourcePanel,
              let anchor = sourcePanel.popoverAnchor(for: anchorTarget) else {
            close(returnFocus: false)
            return
        }
        controller.update(anchor)
    }

    func close(for displayID: String? = nil, returnFocus: Bool = false) {
        guard displayID == nil || self.displayID == displayID else { return }
        controller?.close(returnFocus: returnFocus)
    }

    func stop() {
        close(returnFocus: false)
        task?.cancel(); task = nil
        Task { await windows.stop() }
        keyboardDismissed = nil
    }

    private func discover(for state: SessionCapsulePanelState?) {
        task?.cancel()
        task = Task { [weak self, weak state] in
            guard let self, let state else { return }
            do {
                let candidates = try await contexts.discover()
                guard !Task.isCancelled else { return }
                state.applyDiscovery(.success(candidates))
            } catch is CancellationError {
                return
            } catch {
                state.applyDiscovery(.failure(error))
            }
            task = nil
        }
    }

    private func createDraft(_ selected: [WindowContextCandidate], for state: SessionCapsulePanelState?) {
        task?.cancel()
        task = Task { [weak self, weak state] in
            guard let self, let state else { return }
            do {
                let snapshots = try await contexts.capture(selected)
                try Task.checkCancellation()
                let draft: SessionCapsuleDraft
                if await composer.availability() == .available {
                    do { draft = try await composer.compose(from: snapshots) }
                    catch is CancellationError { return }
                    catch { draft = SessionCapsuleDraftFallback.make(from: snapshots) }
                } else {
                    draft = SessionCapsuleDraftFallback.make(from: snapshots)
                }
                try Task.checkCancellation()
                // `draft` has no pixels or OCR. Let snapshots and every captured image die here.
                state.applyDraft(.success(draft))
            } catch is CancellationError {
                return
            } catch {
                state.applyDraft(.failure(error))
            }
            task = nil
        }
    }

    private func save(_ draft: SessionCapsuleDraft, for state: SessionCapsulePanelState?) {
        do {
            try capsules.save(draft.capsule())
            state?.didSave(capsules.capsules)
        } catch {
            state?.error = String(localized: .capsulesSaveFailed(details: error.localizedDescription))
        }
    }

    private func delete(_ id: UUID, for state: SessionCapsulePanelState?) {
        guard confirmDelete() else { return }
        do {
            anchorTarget = .sessionCapsules
            try capsules.delete(id)
            state?.didDelete(capsules.capsules)
        } catch {
            state?.error = String(localized: .capsulesDeleteFailed(details: error.localizedDescription))
        }
    }

    /// Reopens missing applications, then raises the first currently matchable saved window.
    /// Geometry is intentionally untouched: a capsule restores context, not a workspace layout.
    private func resume(_ capsule: SessionCapsule) {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            let workspace = NSWorkspace.shared
            let identifiers = Set(capsule.windows.compactMap(\.bundleIdentifier))
            let runningPairs: [(String, NSRunningApplication)] = workspace.runningApplications.compactMap {
                guard let id = $0.bundleIdentifier, identifiers.contains(id) else { return nil }
                return (id, $0)
            }
            let runningBefore = Dictionary(uniqueKeysWithValues: runningPairs)
            for identifier in identifiers where runningBefore[identifier] == nil {
                guard let url = workspace.urlForApplication(withBundleIdentifier: identifier) else { continue }
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                configuration.createsNewApplicationInstance = false
                _ = try? await workspace.openApplication(at: url, configuration: configuration)
            }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            let running = workspace.runningApplications.filter {
                $0.bundleIdentifier.map(identifiers.contains) == true && !$0.isTerminated
            }
            guard !running.isEmpty else {
                state?.error = String(localized: .capsulesResumeUnavailable)
                return
            }
            let processes = running.map {
                ApplicationProcessSnapshot(processIdentifier: $0.processIdentifier,
                                           isHidden: $0.isHidden, isActive: $0.isActive)
            }
            let sessionID = UUID()
            if let summaries = try? await windows.discover(processes: processes, sessionID: sessionID),
               let match = capsule.windows.compactMap({ reference -> ApplicationWindowSummary? in
                   guard let title = reference.windowTitle,
                         let application = running.first(where: { $0.bundleIdentifier == reference.bundleIdentifier }) else { return nil }
                   return summaries.first { $0.processIdentifier == application.processIdentifier && $0.title == title }
               }).first,
               (try? await windows.selectWindow(match.token)) != nil {
                close(returnFocus: false)
                return
            }
            await windows.discard(sessionID: sessionID)
            guard let application = running.first else {
                state?.error = String(localized: .capsulesResumeUnavailable)
                return
            }
            let unhidden = !application.isHidden || application.unhide()
            guard unhidden && application.activate(options: .activateAllWindows) else {
                state?.error = String(localized: .capsulesResumeUnavailable)
                return
            }
            close(returnFocus: false)
        }
    }

    private func confirmDelete() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: .capsulesDeleteConfirmationTitle)
        alert.informativeText = String(localized: .capsulesDeleteConfirmationMessage)
        let delete = alert.addButton(withTitle: String(localized: .capsulesDelete))
        delete.hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: .capsulesCancel))
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
