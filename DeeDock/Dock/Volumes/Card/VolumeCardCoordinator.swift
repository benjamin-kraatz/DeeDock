import AppKit

/// Presents the single volume card: hover dwell, pointer-travel grace, anchoring, and the
/// farewell after an eject. What the card's buttons do belongs to `VolumeDockCoordinator`.
@MainActor
final class VolumeCardCoordinator {
    private let volumes: VolumeController
    private var controller: VolumeCardPanelController?
    private weak var sourcePanel: DockPanelController?
    private var volumeID: String?
    private var dwellTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var farewellTask: Task<Void, Never>?
    private var sourceHovered = false
    private var panelHovered = false
    /// Invalidates dwell, usage, and farewell work that belongs to an earlier presentation.
    private var generation = UUID()

    /// Receives a card button press with the volume and the dock the card belongs to.
    var perform: ((VolumeCardAction, VolumeDockItem, DockPanelController) -> Void)?
    /// Reports the volume whose card just closed.
    var closed: ((String) -> Void)?

    var isOpen: Bool { controller != nil }
    /// True while the open card is the plain hover card rather than a question or a result.
    var isShowingInfo: Bool { controller?.state.phase == .info }
    /// The open card's state when it shows `volumeID`.
    func state(for volumeID: String) -> VolumeCardState? {
        self.volumeID == volumeID ? controller?.state : nil
    }

    init(volumes: VolumeController) {
        self.volumes = volumes
    }

    /// Opens the card after the Window Peek hover delay. Leaving the tile cancels an unfinished
    /// dwell; an open info card then closes after a short grace so the pointer can reach it.
    func hover(_ volume: VolumeDockItem?, on panel: DockPanelController) {
        guard let volume else {
            guard sourcePanel === panel || controller == nil else { return }
            sourceHovered = false
            dwellTask?.cancel(); dwellTask = nil
            scheduleClose()
            return
        }
        sourceHovered = true
        cancelClose()
        if sourcePanel === panel, volumeID == volume.volumeID, controller != nil || dwellTask != nil { return }
        // A sticky card (a question, an eject, a refusal) stays until it is answered or dismissed.
        if let phase = controller?.state.phase, phase.isSticky { return }
        close()
        sourceHovered = true
        sourcePanel = panel
        volumeID = volume.volumeID
        let delay = panel.currentSettings?.windowPeekHoverDelay ?? DockSettings.defaults.windowPeekHoverDelay
        let token = generation
        dwellTask = Task { [weak self, weak panel] in
            try? await Task.sleep(for: .milliseconds(Int64((delay * 1_000).rounded())))
            guard let self, let panel, !Task.isCancelled, generation == token else { return }
            dwellTask = nil
            guard sourceHovered, let current = volumes.item(volume.volumeID) else { return }
            present(current, on: panel, phase: .info, keyboard: false)
        }
    }

    /// Shows the card now, in `phase`, replacing whatever card is open. Returns nil when the
    /// volume's tile is not visible on that dock.
    @discardableResult
    func present(_ volume: VolumeDockItem, on panel: DockPanelController, phase: VolumeCardPhase,
                 keyboard: Bool, anchor: DockPopoverAnchor? = nil) -> VolumeCardState? {
        if let state = state(for: volume.volumeID), sourcePanel === panel {
            state.volume = volume
            state.phase = phase
            if phase == .ejected { scheduleFarewellClose() }
            return state
        }
        guard let anchor = anchor ?? panel.popoverAnchor(for: .volume(volume.volumeID)) else { return nil }
        close()
        let state = VolumeCardState(volume: volume, phase: phase,
                                    chrome: DockPopoverChrome(edge: anchor.edge, attachment: 0))
        let next = VolumeCardPanelController(state: state, anchor: anchor, keyboard: keyboard)
        state.perform = { [weak self, weak panel, weak state] action in
            guard let self, let panel, let state else { return }
            perform?(action, state.volume, panel)
        }
        state.hovered = { [weak self] inside in
            self?.panelHovered = inside
            self?.updatePointer()
        }
        next.outsideClick = { [weak self, weak next] in
            // A click on the card's own tile reopens nothing; the tile's click opens the stack,
            // which closes the card through the popover presenter.
            guard let self, let next, controller === next else { return }
            if next.contains(NSEvent.mouseLocation) { return }
            close()
        }
        next.escape = { [weak self] in self?.close() }
        controller = next
        sourcePanel = panel
        volumeID = volume.volumeID
        panel.holdVolumeCard(true)
        next.show()
        if phase == .info { loadDetails(for: volume, state: state) }
        if phase == .ejected { scheduleFarewellClose() }
        return state
    }

    /// Leaves a question or refusal for the plain card, loading capacity and usage if this
    /// presentation started in another phase and never read them.
    func returnToInfo(_ volumeID: String) {
        guard let state = state(for: volumeID) else { return }
        state.phase = .info
        if state.usage == .checking, loadTask == nil { loadDetails(for: state.volume, state: state) }
        updatePointer()
    }

    /// Called from the shared pointer monitor. Only the info card follows hover.
    func updatePointer() {
        guard let controller else { return }
        panelHovered = controller.contains(NSEvent.mouseLocation)
        if sourceHovered || panelHovered || controller.state.phase.isSticky { cancelClose() }
        else { scheduleClose() }
    }

    /// Re-anchors after any dock refresh and swaps in the latest volume snapshot. A card whose
    /// tile disappeared closes, except the farewell, which outlives its tile on purpose.
    func refresh() {
        guard let controller, let volumeID else { return }
        if controller.state.phase == .ejected { return }
        // A successful eject removes the tile before its result arrives; the card stays where it
        // is and turns into the farewell instead of closing and reopening.
        if controller.state.phase == .ejecting, volumes.item(volumeID) == nil { return }
        guard let sourcePanel, let volume = volumes.item(volumeID),
              let anchor = sourcePanel.popoverAnchor(for: .volume(volumeID)) else {
            close()
            return
        }
        controller.state.volume = volume
        controller.update(anchor)
    }

    func close(for displayID: String) {
        if sourcePanel?.store.displayID == displayID { close() }
    }

    func close() {
        generation = UUID()
        dwellTask?.cancel(); dwellTask = nil
        loadTask?.cancel(); loadTask = nil
        farewellTask?.cancel(); farewellTask = nil
        cancelClose()
        let panel = sourcePanel
        let closedID = controller == nil ? nil : volumeID
        controller?.close()
        controller = nil
        sourcePanel = nil
        volumeID = nil
        sourceHovered = false
        panelHovered = false
        panel?.holdVolumeCard(false)
        if let closedID { closed?(closedID) }
    }

    func stop() {
        close()
        perform = nil
        closed = nil
    }

    /// Reads fresh capacity and what holds files open. Both are disk work, done off the main
    /// actor and only while this presentation lasts.
    private func loadDetails(for volume: VolumeDockItem, state: VolumeCardState) {
        let token = generation
        let url = volume.url
        loadTask = Task { [weak self, weak state] in
            if let fresh = await self?.volumes.refreshCapacity(volume.volumeID), let state, !Task.isCancelled {
                state.volume = fresh
            }
            let processes = await Task.detached(priority: .userInitiated) {
                VolumeBlockerScanner.processes(onVolumeAt: url)
            }.value
            guard let self, let state, !Task.isCancelled, generation == token else { return }
            let blockers = VolumeBlockerResolver.blockers(from: processes)
            state.usage = blockers.isEmpty ? .idle : .inUse(blockers)
            loadTask = nil
        }
    }

    private func scheduleFarewellClose() {
        farewellTask?.cancel()
        let token = generation
        farewellTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2_200))
            guard let self, !Task.isCancelled, generation == token else { return }
            farewellTask = nil
            close()
        }
    }

    /// Continuous pointer movement keeps one pending deadline rather than restarting it.
    private func scheduleClose() {
        guard controller != nil, closeTask == nil, controller?.state.phase.isSticky != true else { return }
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !Task.isCancelled else { return }
            closeTask = nil
            guard !sourceHovered, !panelHovered, controller?.state.phase.isSticky != true else { return }
            close()
        }
    }

    private func cancelClose() {
        closeTask?.cancel()
        closeTask = nil
    }
}
