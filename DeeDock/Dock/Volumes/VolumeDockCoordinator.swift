import AppKit

/// Connects volume tiles to their stack, card, and eject flows on every dock.
///
/// Every eject path (card button, context menu, VoiceOver action, dragging the tile off the dock)
/// goes through `requestEject`, so confirmation, refusal, and the farewell look the same
/// whichever gesture started them.
@MainActor
final class VolumeDockCoordinator {
    private let volumes: VolumeController
    private let folderStacks: FolderStackCoordinator
    let cards: VolumeCardCoordinator
    /// An eject waiting for the applications the user quit from the card to exit.
    private struct PendingRetry {
        weak var panel: DockPanelController?
        var quitting: Set<pid_t>
    }
    private var retryAfterQuit: [String: PendingRetry] = [:]
    private var terminationObserver: NSObjectProtocol?
    private var ejectTasks: [String: Task<Void, Never>] = [:]

    init(volumes: VolumeController, folderStacks: FolderStackCoordinator) {
        self.volumes = volumes
        self.folderStacks = folderStacks
        cards = VolumeCardCoordinator(volumes: volumes)
    }

    /// Installs the shared callbacks. Call before `VolumeController.start()`, so the first
    /// unmount already releases DOKK's own stack.
    func start() {
        guard terminationObserver == nil else { return }
        cards.perform = { [weak self] action, volume, panel in self?.perform(action, volume: volume, on: panel) }
        // A dismissed card abandons its pending retry; the user can eject again from the tile.
        cards.closed = { [weak self] volumeID in self?.retryAfterQuit[volumeID] = nil }
        volumes.volumeWillUnmount = { [weak folderStacks] url in folderStacks?.close(within: url) }
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let pid else { return }
                self?.applicationTerminated(pid)
            }
        }
    }

    /// Installs this dock's volume actions. `isDragging` suppresses hover cards during drags.
    func connect(_ panel: DockPanelController, isDragging: @escaping () -> Bool) {
        panel.store.openVolume = { [weak self, weak panel] volume, keyboard in
            guard let self, let panel else { return }
            openStack(volume, on: panel, keyboard: keyboard)
        }
        panel.interaction.openVolume = { [weak self, weak panel] volume in
            guard let self, let panel else { return }
            openStack(volume, on: panel, keyboard: false)
        }
        panel.interaction.revealVolume = { [weak self] volume in self?.openInFinder(volume) }
        panel.interaction.ejectVolume = { [weak self, weak panel] volume in
            guard let self, let panel else { return }
            requestEject(volume, on: panel, keyboard: panel.store.keyboardFocus)
        }
        panel.interaction.hideVolume = { [weak self] volume in self?.hide(volume) }
        panel.interaction.volumeHoverChanged = { [weak self, weak panel] volume in
            guard let self, let panel else { return }
            if volume != nil, isDragging() { return }
            cards.hover(volume, on: panel)
        }
    }

    /// Asks first when the volume is a fixed disk and Settings says so; otherwise ejects at once.
    func requestEject(_ volume: VolumeDockItem, on panel: DockPanelController, keyboard: Bool) {
        guard !volume.isEjecting, ejectTasks[volume.volumeID] == nil else { return }
        let confirms = panel.currentSettings?.confirmBeforeEjectingDisks ?? DockSettings.defaults.confirmBeforeEjectingDisks
        if volume.kind == .externalDisk, confirms {
            if cards.present(volume, on: panel, phase: .confirmDisk, keyboard: keyboard) != nil { return }
            // The tile is scrolled out of view, so the card has nowhere to attach. Ask anyway.
            guard VolumeEjectAlert.confirmDisk(named: volume.name) else { return }
        }
        startEject(volume, on: panel, force: false, keyboard: keyboard)
    }

    func stop() {
        ejectTasks.values.forEach { $0.cancel() }
        ejectTasks = [:]
        retryAfterQuit = [:]
        if let terminationObserver { NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver) }
        terminationObserver = nil
        cards.stop()
    }

    private func openStack(_ volume: VolumeDockItem, on panel: DockPanelController, keyboard: Bool) {
        guard !volume.isEjecting else { return }
        cards.dismiss()
        folderStacks.show(volume.stackItem(displayID: panel.store.displayID), on: panel, keyboard: keyboard,
                          anchoredTo: .volume(volume.volumeID), volumeRoot: true)
    }

    /// Spring-opens the volume's stack while files hover its tile, so they can be dropped deeper.
    func springOpen(_ volume: VolumeDockItem, on panel: DockPanelController) {
        guard !volume.isEjecting else { return }
        cards.dismiss()
        folderStacks.show(volume.stackItem(displayID: panel.store.displayID), on: panel, keyboard: false, spring: true,
                          anchoredTo: .volume(volume.volumeID), volumeRoot: true)
    }

    /// Copies, or with Shift moves, files dropped on the tile into the volume's root. The stack
    /// opens to show progress and any failure, as it does for a pinned folder.
    func receive(_ info: NSDraggingInfo, volume: VolumeDockItem, on panel: DockPanelController) -> Bool {
        guard !volume.isEjecting else { return false }
        cards.dismiss()
        return folderStacks.receive(info, folder: volume.stackItem(displayID: panel.store.displayID), on: panel,
                                    anchoredTo: .volume(volume.volumeID), volumeRoot: true)
    }

    /// Hides the drive from every dock. Its card and stack close first, since the tile they hang
    /// from is about to leave. An eject already running carries on.
    private func hide(_ volume: VolumeDockItem) {
        cards.close()
        folderStacks.close(within: volume.url)
        volumes.arrangement.setHidden(volume.volumeID, true)
    }

    private func openInFinder(_ volume: VolumeDockItem) {
        cards.dismiss()
        NSWorkspace.shared.open(volume.url)
    }

    private func perform(_ action: VolumeCardAction, volume: VolumeDockItem, on panel: DockPanelController) {
        let state = cards.state(for: volume.volumeID)
        switch action {
        case .openInFinder: openInFinder(volume)
        case .eject: requestEject(volume, on: panel, keyboard: false)
        case .confirmEject, .retry: startEject(volume, on: panel, force: false, keyboard: false)
        case .forceEject:
            if case .blocked(let blockers) = state?.phase { state?.phase = .confirmForce(blockers) }
            else { state?.phase = .confirmForce([]) }
        case .confirmForceEject: startEject(volume, on: panel, force: true, keyboard: false)
        case .cancel:
            if case .confirmForce(let blockers) = state?.phase, !blockers.isEmpty {
                state?.phase = .blocked(blockers)
            } else {
                cards.returnToInfo(volume.volumeID)
            }
        case .showApplication(let pid):
            NSRunningApplication(processIdentifier: pid)?.activate()
        case .quitApplication(let pid):
            // A polite quit; the app may ask to save first. The eject retries once it exits. An app
            // that refuses (Finder, or one already gone) never joins the wait.
            guard let application = NSRunningApplication(processIdentifier: pid), application.terminate() else { return }
            var pending = retryAfterQuit[volume.volumeID] ?? PendingRetry(panel: panel, quitting: [])
            pending.quitting.insert(pid)
            retryAfterQuit[volume.volumeID] = pending
            state?.quitting.insert(pid)
        case .revealExecutable(let path):
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        case .dismiss: cards.close()
        }
    }

    /// Runs one eject. The tile dims at once, and the outcome is reported in the card, opening it
    /// on the tile when the eject started from the context menu or a drag.
    private func startEject(_ volume: VolumeDockItem, on panel: DockPanelController, force: Bool, keyboard: Bool) {
        let volumeID = volume.volumeID
        guard ejectTasks[volumeID] == nil else { return }
        retryAfterQuit[volumeID] = nil
        // The farewell outlives the tile, so remember where the tile was before it leaves.
        let anchor = panel.popoverAnchor(for: .volume(volumeID))
        if let state = cards.state(for: volumeID) {
            state.quitting = []
            state.phase = .ejecting
        }
        ejectTasks[volumeID] = Task { [weak self, weak panel] in
            guard let self else { return }
            let result = await volumes.eject(volumeID, force: force)
            ejectTasks[volumeID] = nil
            guard !Task.isCancelled, let panel else { return }
            switch result {
            case .ejected:
                cards.present(volume, on: panel, phase: .ejected, keyboard: false, anchor: anchor)
            case .blocked(let blockers):
                let current = volumes.item(volumeID) ?? volume
                if cards.present(current, on: panel, phase: .blocked(blockers), keyboard: keyboard) == nil {
                    panel.store.errorMessage = .volumeEjectFailed(name: volume.name,
                        details: String(localized: blockers.isEmpty ? .volumeBlockedUnknown : .volumeBlockedMany))
                }
            case .failed(let details):
                let current = volumes.item(volumeID) ?? volume
                if cards.present(current, on: panel, phase: .failed(details), keyboard: keyboard) == nil {
                    panel.store.errorMessage = .volumeEjectFailed(name: volume.name, details: details)
                }
            }
        }
    }

    /// Retries an eject once every application the user quit from the card has exited.
    private func applicationTerminated(_ pid: pid_t) {
        for (volumeID, pending) in retryAfterQuit where pending.quitting.contains(pid) {
            var remaining = pending
            remaining.quitting.remove(pid)
            cards.state(for: volumeID)?.quitting.remove(pid)
            if remaining.quitting.isEmpty {
                retryAfterQuit[volumeID] = nil
                guard let volume = volumes.item(volumeID), let panel = remaining.panel,
                      case .blocked = cards.state(for: volumeID)?.phase else { continue }
                startEject(volume, on: panel, force: false, keyboard: false)
            } else {
                retryAfterQuit[volumeID] = remaining
            }
        }
    }
}
