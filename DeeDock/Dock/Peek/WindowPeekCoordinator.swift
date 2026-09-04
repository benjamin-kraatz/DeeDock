import AppKit

/// App-wide owner for the single transient window preview.
@MainActor
final class WindowPeekCoordinator {
    private let menus: ApplicationMenuController
    private let screenCapture: ScreenCaptureAccessController
    private let thumbnails: any WindowThumbnailServicing
    private var controller: WindowPeekPanelController?
    private weak var sourcePanel: DockPanelController?
    private var sourceItem: DockItem?
    private var allWindows: [ApplicationWindowSummary] = []
    private var discoveryID: UUID?
    private var dwellTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var fallbackDiscoveryTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var pendingThumbnailIDs: Set<ApplicationWindowToken> = []
    private var requestedThumbnailIDs: Set<ApplicationWindowToken> = []
    private var generation = UUID()
    private var sourceHovered = false
    private var panelHovered = false
    var prepareSettings: ((String) -> Void)?
    var isOpen: Bool { controller != nil }
    var isKeyboardActive: Bool { controller != nil && sourcePanel?.store.keyboardFocus == true }

    init(menus: ApplicationMenuController, screenCapture: ScreenCaptureAccessController,
         thumbnails: any WindowThumbnailServicing = ScreenCaptureWindowThumbnailService()) {
        self.menus = menus
        self.screenCapture = screenCapture
        self.thumbnails = thumbnails
    }

    func hover(_ item: DockItem?, on panel: DockPanelController) {
        guard let item else {
            if sourcePanel === panel { sourceHovered = false; scheduleClose() }
            return
        }
        guard item.isRunning, item.isAvailable,
              let context = panel.windowPeekContext(for: item.id), context.settings.windowPeekEnabled else {
            close(returnFocus: false)
            return
        }
        sourceHovered = true
        closeTask?.cancel()
        if sourcePanel === panel, sourceItem?.id == item.id { return }
        close(returnFocus: false)
        sourceHovered = true
        sourcePanel = panel
        sourceItem = item
        let delay = context.settings.windowPeekHoverDelay
        let currentGeneration = generation
        dwellTask = Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(for: .milliseconds(Int64((delay * 1_000).rounded())))
            guard let self, let panel, !Task.isCancelled, generation == currentGeneration,
                  sourceHovered, sourcePanel === panel else { return }
            present(item, on: panel, keyboard: false)
        }
    }

    func showKeyboard(_ item: DockItem, on panel: DockPanelController) {
        guard item.isRunning, item.isAvailable,
              panel.windowPeekContext(for: item.id)?.settings.windowPeekEnabled == true else { return }
        close(returnFocus: false)
        sourcePanel = panel
        sourceItem = item
        present(item, on: panel, keyboard: true)
    }

    func updatePointer() {
        panelHovered = controller?.contains(NSEvent.mouseLocation) == true
        if WindowPeekLifecycle.retainsPresentation(sourceHovered: sourceHovered, panelHovered: panelHovered) {
            closeTask?.cancel()
        } else if controller != nil { scheduleClose() }
    }

    func refresh() {
        guard let sourcePanel, let sourceItem,
              let context = sourcePanel.windowPeekContext(for: sourceItem.id),
              context.settings.windowPeekEnabled else {
            close(returnFocus: false)
            return
        }
        guard controller?.state.settings == context.settings else {
            close(returnFocus: false)
            return
        }
        controller?.update(anchor: context.anchor, settings: context.settings,
                           count: max(1, controller?.state.cards.count ?? 0))
    }

    func close(returnFocus: Bool) {
        generation = UUID()
        dwellTask?.cancel()
        closeTask?.cancel()
        fallbackDiscoveryTask?.cancel()
        captureTask?.cancel()
        dwellTask = nil
        closeTask = nil
        fallbackDiscoveryTask = nil
        captureTask = nil
        if let discoveryID { menus.cancelDiscovery(discoveryID) }
        discoveryID = nil
        Task { await thumbnails.stop() }
        let panel = sourcePanel
        let activeController = controller
        controller = nil
        activeController?.closed = nil
        activeController?.close(returnFocus: false)
        sourcePanel = nil
        sourceItem = nil
        allWindows = []
        pendingThumbnailIDs = []
        requestedThumbnailIDs = []
        sourceHovered = false
        panelHovered = false
        panel?.holdWindowPeek(false)
        if returnFocus { panel?.focus() }
    }

    func stop() {
        close(returnFocus: false)
        prepareSettings = nil
    }

    private func present(_ item: DockItem, on panel: DockPanelController, keyboard: Bool) {
        guard let context = panel.windowPeekContext(for: item.id), context.settings.windowPeekEnabled else { return }
        let next = WindowPeekPanelController(item: item, anchor: context.anchor,
                                             settings: context.settings, keyboard: keyboard)
        controller = next
        panel.holdWindowPeek(true)
        next.closed = { [weak self] returnFocus in self?.close(returnFocus: returnFocus) }
        next.state.hovered = { [weak self] hovered in
            self?.panelHovered = hovered
            if hovered { self?.closeTask?.cancel() } else { self?.scheduleClose() }
        }
        next.state.choose = { [weak self] token in self?.choose(token) }
        next.state.showApp = { [weak self] in self?.showApp() }
        next.state.settingsSelected = { [weak self, weak panel] in
            guard let panel else { return }
            self?.prepareSettings?(panel.store.displayID)
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.close(returnFocus: false)
            }
        }
        next.state.showAll = { [weak self] in self?.displayWindows(applyFilters: false) }
        next.state.thumbnailNeeded = { [weak self] token in self?.requestThumbnail(token) }
        next.show()
        discover(item)
    }

    private func discover(_ item: DockItem) {
        let snapshot = menus.snapshot(for: item)
        guard !snapshot.processes.isEmpty else {
            controller?.state.phase = .appFallback
            if let controller, let sourcePanel,
               let context = sourcePanel.windowPeekContext(for: item.id) {
                controller.update(anchor: context.anchor, settings: context.settings, count: 1)
            }
            return
        }
        guard snapshot.windowState == .loading else {
            discoverWithScreenCapture(processes: snapshot.processes, originalFailure: .permissionRequired)
            return
        }
        discoveryID = menus.beginDiscovery(for: item, snapshot: snapshot) { [weak self] state in
            guard let self else { return }
            switch state {
            case .loaded(let windows):
                controller?.state.usesApplicationSelection = false
                allWindows = windows
                displayWindows(applyFilters: true)
            case .unavailable(let failure):
                discoverWithScreenCapture(processes: snapshot.processes, originalFailure: failure)
            case .hidden:
                controller?.state.phase = .appFallback
                if let controller, let sourcePanel, let sourceItem,
                   let context = sourcePanel.windowPeekContext(for: sourceItem.id) {
                    controller.update(anchor: context.anchor, settings: context.settings, count: 1)
                }
            case .loading: break
            }
        }
    }

    /// ScreenCaptureKit keeps Peek useful when sandboxed Accessibility cannot enumerate windows.
    /// These summaries deliberately activate the app on selection because they have no AX handle.
    private func discoverWithScreenCapture(processes: [ApplicationProcessSnapshot],
                                           originalFailure: ApplicationWindowDiscoveryFailure) {
        screenCapture.refresh()
        guard screenCapture.status == .enabled else {
            showDiscoveryFailure(originalFailure)
            return
        }
        let currentGeneration = generation
        let sessionID = UUID()
        fallbackDiscoveryTask?.cancel()
        fallbackDiscoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let windows = try await thumbnails.discover(processes: processes, sessionID: sessionID)
                guard !Task.isCancelled,
                      WindowPeekLifecycle.acceptsResult(expected: currentGeneration, current: generation)
                else { return }
                fallbackDiscoveryTask = nil
                controller?.state.usesApplicationSelection = true
                allWindows = windows
                displayWindows(applyFilters: true)
            } catch is CancellationError {
                return
            } catch {
                guard WindowPeekLifecycle.acceptsResult(expected: currentGeneration, current: generation) else { return }
                fallbackDiscoveryTask = nil
                showDiscoveryFailure(originalFailure)
            }
        }
    }

    private func showDiscoveryFailure(_ failure: ApplicationWindowDiscoveryFailure) {
        controller?.state.phase = failure == .permissionRequired ? .appFallback : .discoveryFailed(failure)
        if let controller, let sourcePanel, let sourceItem,
           let context = sourcePanel.windowPeekContext(for: sourceItem.id) {
            controller.update(anchor: context.anchor, settings: context.settings, count: 1)
        }
    }

    private func displayWindows(applyFilters: Bool) {
        guard let controller, let sourcePanel,
              let sourceItem, let context = sourcePanel.windowPeekContext(for: sourceItem.id) else { return }
        let filtered = applyFilters ? allWindows.filter { window in
            (context.settings.windowPeekIncludeMinimized || !window.isMinimized)
                && (context.settings.windowPeekIncludeUntitled || window.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        } : allWindows
        guard !filtered.isEmpty else {
            controller.state.cards = []
            controller.state.phase = allWindows.isEmpty ? .noWindows : .noMatch
            controller.update(anchor: context.anchor, settings: context.settings, count: 1)
            return
        }
        let ordered = filtered.enumerated().sorted { lhs, rhs in
            if lhs.element.isMain != rhs.element.isMain { return lhs.element.isMain }
            return lhs.offset < rhs.offset
        }.map(\.element)
        controller.state.cards = ordered.map { WindowPeekCard(window: $0, thumbnail: nil) }
        controller.state.selectedID = ordered.first?.token
        controller.state.phase = .windows
        controller.update(anchor: context.anchor, settings: context.settings, count: ordered.count)
    }

    private func requestThumbnail(_ token: ApplicationWindowToken) {
        guard !requestedThumbnailIDs.contains(token), allWindows.contains(where: { $0.token == token }) else { return }
        screenCapture.refresh()
        guard screenCapture.status == .enabled else { return }
        pendingThumbnailIDs.insert(token)
        scheduleCapture()
    }

    /// SwiftUI requests only cards that enter a lazy container's rendered region.
    private func scheduleCapture() {
        guard captureTask == nil, !pendingThumbnailIDs.isEmpty, controller != nil else { return }
        let currentGeneration = generation
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()
            guard !Task.isCancelled,
                  WindowPeekLifecycle.acceptsResult(expected: currentGeneration, current: generation)
            else { return }
            let ids = pendingThumbnailIDs
            pendingThumbnailIDs.subtract(ids)
            requestedThumbnailIDs.formUnion(ids)
            let windows = allWindows.filter { ids.contains($0.token) }
            guard let size = controller?.state.settings.windowPeekSize.thumbnailSize else { return }
            let images = await thumbnails.capture(windows, size: size)
            guard !Task.isCancelled,
                  WindowPeekLifecycle.acceptsResult(expected: currentGeneration, current: generation),
                  let controller else { return }
            controller.state.cards = controller.state.cards.map { card in
                var updated = card
                updated.thumbnail = images[card.id]
                return updated
            }
            captureTask = nil
            scheduleCapture()
        }
    }

    private func choose(_ token: ApplicationWindowToken) {
        guard let item = sourceItem, let panel = sourcePanel else { return }
        guard controller?.state.usesApplicationSelection != true else {
            showApp()
            return
        }
        menus.perform(.selectWindow(token), for: item) { [weak self, weak panel] error in
            if let error { panel?.store.errorMessage = error }
            else { panel?.store.applicationOpened?() }
            self?.close(returnFocus: false)
        }
    }

    private func showApp() {
        guard let item = sourceItem else { return }
        sourcePanel?.store.open(item)
        close(returnFocus: false)
    }

    private func scheduleClose() {
        closeTask?.cancel()
        closeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !Task.isCancelled,
                  !WindowPeekLifecycle.retainsPresentation(sourceHovered: sourceHovered, panelHovered: panelHovered)
            else { return }
            close(returnFocus: false)
        }
    }
}
