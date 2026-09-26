import AppKit

/// App-wide owner for the single transient window preview.
@MainActor
final class WindowPeekCoordinator {
    var actionDisplays: (() -> [DisplaySnapshot])?
    private var windowActionTask: Task<Void, Never>?
    private var actionLayout: [WindowActionDisplay] = []
    private let actionMenu = WindowActionMenu()
    private let fileHandoff: WindowFileHandoffController
    private var fileDocuments: DocumentResourceAccess?
    private var fileDrag = false
    var chooseFiles: ((DockItem, DockPanelController) -> Void)?
    var validatedFileDrop: ((NSDraggingInfo) -> DocumentResourceAccess?)?
    var fileDropAccepted: (() -> Void)?
    var fileDragEnded: (() -> Void)?
    private let history: PeekHistoryStore
    private let watches: WindowWatchController
    private let portals = WindowPortalCoordinator()
    private let menus: ApplicationMenuController
    private let screenCapture: ScreenCaptureAccessController
    private let thumbnails: any WindowThumbnailServicing
    private var controller: WindowPeekPanelController?
    private var enlarge: WindowPeekEnlargeController?
    private let markups: WindowMarkupController
    /// Collisions outside Peek (dock drags, App Fusion gestures) that suspend the enlarged preview.
    var enlargeBlocked: (() -> Bool)?
    /// Stages a file a markup wrote on the Shelf, returning how many did not fit. Set by the dock coordinator.
    var stageOnShelf: ((URL) throws -> Int)? {
        get { markups.stageOnShelf }
        set { markups.stageOnShelf = newValue }
    }
    private weak var sourcePanel: DockPanelController?
    private var sourceItem: DockItem?
    private var allWindows: [ApplicationWindowSummary] = []
    private var discoveryID: UUID?
    private var dwellTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var closeDelay = 0
    private var fallbackDiscoveryTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var pendingThumbnailIDs: Set<ApplicationWindowToken> = []
    private var requestedThumbnailIDs: Set<ApplicationWindowToken> = []
    private var generation = UUID()
    private var sourceHovered = false
    private var panelHovered = false
    var startMelt: ((ApplicationWindowSummary) -> Void)?
    var addToFusion: ((ApplicationWindowSummary, DockPanelController, Bool) -> Void)?
    var prepareSettings: ((String) -> Void)?
    var isOpen: Bool { controller != nil }
    var isFileDragActive: Bool { fileDrag }
    var isKeyboardActive: Bool { controller != nil && sourcePanel?.store.keyboardFocus == true }

    init(menus: ApplicationMenuController, screenCapture: ScreenCaptureAccessController,
         applications: any ApplicationServicing,
         thumbnails: any WindowThumbnailServicing = ScreenCaptureWindowThumbnailService(),
         watchPresets: WindowWatchPresetStore, actions: ActionTilesController, history: PeekHistoryStore) {
        self.history = history
        fileHandoff = WindowFileHandoffController(menus: menus, applications: applications)
        self.menus = menus
        self.screenCapture = screenCapture
        self.thumbnails = thumbnails
        markups = WindowMarkupController(thumbnails: thumbnails)
        watches = WindowWatchController(presets: watchPresets, actions: actions)
    }

    func hover(_ item: DockItem?, on panel: DockPanelController, documents: DocumentResourceAccess? = nil) {
        guard let item else {
            if sourcePanel === panel {
                leaveSource()
                // A portal card press still has to record that the pointer left the tile.
                // Blocking that exit kept Peek open after mouse-up off the icon and panel.
                if controller?.state.portalDragging != true { scheduleClose() }
            }
            return
        }
        guard controller?.state.portalDragging != true else { return }
        guard item.isRunning, item.isAvailable,
              let context = panel.windowPeekContext(for: item.id), context.settings.windowPeekEnabled else {
            close(returnFocus: false)
            return
        }
        sourceHovered = true
        cancelClose()
        if sourcePanel === panel, sourceItem?.id == item.id, fileDrag == (documents != nil),
           controller != nil || dwellTask != nil { return }
        close(returnFocus: false)
        fileDocuments = documents
        fileDrag = documents != nil
        sourceHovered = true
        sourcePanel = panel
        sourceItem = item
        let delay = context.settings.windowPeekHoverDelay
        let currentGeneration = generation
        dwellTask = Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(for: .milliseconds(Int64((delay * 1_000).rounded())))
            guard let self, let panel, !Task.isCancelled, generation == currentGeneration else { return }
            dwellTask = nil
            guard sourceHovered, sourcePanel === panel else { return }
            present(item, on: panel, keyboard: false)
        }
    }

    func showKeyboard(_ item: DockItem, on panel: DockPanelController, documents: DocumentResourceAccess? = nil) {
        guard item.isRunning, item.isAvailable,
              panel.windowPeekContext(for: item.id)?.settings.windowPeekEnabled == true else {
            if documents != nil { panel.store.errorMessage = .fileRouteDestinationUnavailable }
            return
        }
        close(returnFocus: false)
        fileDocuments = documents
        sourcePanel = panel
        sourceItem = item
        present(item, on: panel, keyboard: true)
    }

    /// The drag coordinator owns payload validation and calls this even across panel boundaries.
    func hoverFiles(_ item: DockItem?, on panel: DockPanelController?, documents: DocumentResourceAccess?) {
        if let item, let panel, let documents,
           documents.urls.count <= WindowFileHandoffController.maximumFiles {
            hover(item, on: panel, documents: documents)
        } else if fileDrag {
            leaveSource()
            updatePointer()
            if !panelHovered { scheduleClose() }
        }
    }

    /// Every exit invalidates an unfinished dwell. Re-entry must satisfy the full delay,
    /// while an already-visible panel retains its separate pointer-travel grace period.
    private func leaveSource() {
        sourceHovered = false
        dwellTask?.cancel()
        dwellTask = nil
    }

    func endFileDrag() { if fileDrag { close(returnFocus: false) } }
    func dismissFileHandoff() { fileHandoff.stop() }

    func updatePointer() {
        if fileDocuments != nil, !fileDrag { return }

        let pointer = NSEvent.mouseLocation
        enlarge?.pointerMoved(pointer)
        // A pointer resting on the enlarged picture counts as being on the panel.
        panelHovered = controller?.contains(pointer) == true || enlarge?.retainsPeek == true
        if WindowPeekLifecycle.retainsPresentation(sourceHovered: sourceHovered, panelHovered: panelHovered) {
            cancelClose()
        } else if controller != nil { scheduleClose() }
    }

    func refresh() {
        if controller?.state.actionBusy == true, actionDisplaySnapshot() != actionLayout {
            close(returnFocus: false)
            return
        }
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
        windowActionTask?.cancel()
        windowActionTask = nil
        actionMenu.cancel()
        generation = UUID()
        dwellTask?.cancel()
        cancelClose()
        fallbackDiscoveryTask?.cancel()
        captureTask?.cancel()
        dwellTask = nil
        closeTask = nil
        fallbackDiscoveryTask = nil
        captureTask = nil
        if let discoveryID { menus.cancelDiscovery(discoveryID) }
        discoveryID = nil
        enlarge?.stop()
        enlarge = nil
        Task { await thumbnails.stop() }
        let panel = sourcePanel
        let activeController = controller
        controller = nil
        activeController?.closed = nil
        activeController?.close(returnFocus: false)
        sourcePanel = nil
        sourceItem = nil
        fileDocuments = nil
        fileDrag = false
        allWindows = []
        pendingThumbnailIDs = []
        requestedThumbnailIDs = []
        sourceHovered = false
        panelHovered = false
        panel?.holdWindowPeek(false)
        if returnFocus { panel?.focus() }
    }

    func focusNextPortal() { portals.focusNext() }

    func stop() {
        history.stop()
        fileHandoff.stop()
        portals.stop()
        markups.stop()
        close(returnFocus: false)
        watches.stop()
        prepareSettings = nil
        enlargeBlocked = nil
        addToFusion = nil
        startMelt = nil
    }

    private func present(_ item: DockItem, on panel: DockPanelController, keyboard: Bool) {
        guard !QuarantineStampController.shared.armed,
              !QuarantineStore.shared.contains(item.id, url: item.resolvedURL ?? item.reference.url),
              !QuarantineStore.shared.unreadable else { return }
        guard let context = panel.windowPeekContext(for: item.id), context.settings.windowPeekEnabled else { return }
        let next = WindowPeekPanelController(item: item, anchor: context.anchor,
                                             settings: context.settings, keyboard: keyboard)
        controller = next
        panel.holdWindowPeek(true)
        next.closed = { [weak self] returnFocus in self?.close(returnFocus: returnFocus) }
        next.state.routingFiles = fileDocuments != nil
        next.state.receivingFileDrag = fileDrag
        next.state.chooseFiles = { [weak self, weak panel] in
            guard let self, let panel else { return }
            chooseFiles?(item, panel)
        }
        next.state.fileDragUpdated = { [weak self, weak next] info, token in
            guard let self, fileDrag, validatedFileDrop?(info) != nil else { return false }
            panelHovered = true
            cancelClose()
            next?.state.selectedID = token
            return true
        }
        next.state.fileDrop = { [weak self] info, token in
            guard let self, fileDrag, let documents = validatedFileDrop?(info) else { return false }
            fileDocuments = documents
            guard routeFiles(to: token) else { return false }
            fileDropAccepted?()
            return true
        }
        next.state.fileDragExited = { [weak self] in self?.updatePointer() }
        next.state.fileDragEnded = { [weak self] in self?.fileDragEnded?() }
        next.state.hovered = { [weak self] hovered in
            self?.panelHovered = hovered
            if hovered { self?.cancelClose() } else { self?.scheduleClose() }
        }
        next.state.watch = { [weak self, weak panel] token in
            guard let self, let panel,
                  let summary = allWindows.first(where: { $0.token == token }),
                  let currentContext = panel.windowPeekContext(for: item.id) else { return }
            close(returnFocus: false)
            watches.show(summary, visibleFrame: currentContext.anchor.visibleFrame)
        }
        next.state.markup = { [weak self] token in self?.openMarkup(token) }
        next.state.startMelt = { [weak self] window in
            guard let self else { return }
            let action = startMelt
            close(returnFocus: false)
            action?(window)
        }
        next.state.addToFusion = { [weak self, weak panel] window in
            guard let self, let panel else { return }
            let action = addToFusion
            close(returnFocus: false)
            action?(window, panel, keyboard)
        }
        next.state.pinPortal = { [weak self, weak panel] window in
            guard let self else { return }
            guard portals.pin(window, appName: item.reference.name, keyboard: keyboard) else {
                panel?.store.errorMessage = .portalLimit
                return
            }
            close(returnFocus: false)
        }
        next.state.portalTracking = { [weak self, weak next] tracking in
            next?.state.portalDragging = tracking
            if tracking { self?.enlarge?.dismiss() }
            if tracking { self?.cancelClose() } else { self?.updatePointer() }
        }
        next.state.dropPortal = { [weak self, weak panel] window, point, frozen in
            guard let self else { return }
            guard portals.pin(window, appName: item.reference.name, keyboard: false,
                              dropPoint: point, frozen: frozen) else {
                panel?.store.errorMessage = .portalLimit
                return
            }
            close(returnFocus: false)
        }
        next.state.pinFrozen = { [weak self, weak panel] window in
            guard let self else { return }
            guard portals.pin(window, appName: item.reference.name, keyboard: keyboard, frozen: true) else {
                panel?.store.errorMessage = .portalLimit
                return
            }
            close(returnFocus: false)
        }
        next.state.manage = { [weak self] token in self?.manage(token) }
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
        if fileDocuments == nil, context.settings.windowPeekEnlargeEnabled {
            let enlarge = WindowPeekEnlargeController(peek: next, thumbnails: thumbnails) { [weak self] in
                self?.enlargeBlocked?() ?? false
            }
            self.enlarge = enlarge
            enlarge.markup = { [weak self] token in self?.openMarkup(token) }
            // Deferred: the hold changes inside a pointer update, and the re-evaluation must see
            // the stage's final state rather than re-enter it.
            enlarge.heldChanged = { [weak self] in Task { @MainActor [weak self] in self?.updatePointer() } }
            next.state.cardHovered = { [weak enlarge] token, inside in enlarge?.hover(token, inside: inside) }
        }
        if fileDocuments != nil {
            next.state.watch = nil
            next.state.markup = nil
            next.state.pinPortal = nil
            next.state.pinFrozen = nil
            next.state.dropPortal = nil
            next.state.portalTracking = nil
            next.state.addToFusion = nil
            next.state.startMelt = nil
        }
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
            guard let settings = controller?.state.settings else { return }
            let size = settings.windowPeekSize.thumbnailSize
            let historyEpoch = history.collectionEpoch
            // OCR reuses this capture at a larger logical size. Capture multiplies by the window's
            // display scale, so a 2× screen stores at most 1600 × 1000 pixels.
            let captureSize = historyEpoch == nil ? size : CGSize(width: 800, height: 500)
            let images = await thumbnails.capture(windows, size: captureSize)
            guard !Task.isCancelled,
                  WindowPeekLifecycle.acceptsResult(expected: currentGeneration, current: generation),
                  let controller else { return }
            controller.state.cards = controller.state.cards.map { card in
                guard let captured = windows.first(where: { $0.token == card.id }),
                      captured == card.window else { return card }
                var updated = card
                updated.thumbnail = images[card.id]
                return updated
            }
            let historyCards = controller.state.cards.filter { card in
                images[card.id] != nil && windows.contains { $0 == card.window }
            }
            history.record(historyCards, appName: controller.state.appName, epoch: historyEpoch)
            WindowPeekDiagnostics.shared.record(
                settings: settings, placement: controller.placementFrame, panel: controller.frame,
                screen: controller.screen,
                captures: windows.map { window in
                    let image = images[window.token]
                    return WindowPeekDiagnostics.Capture(
                        frame: window.frame ?? .zero,
                        pixels: image.map { CGSize(width: $0.width, height: $0.height) })
                })
            captureTask = nil
            scheduleCapture()
        }
    }

    @discardableResult
    private func routeFiles(to token: ApplicationWindowToken?) -> Bool {
        guard let documents = fileDocuments, let item = sourceItem, let panel = sourcePanel,
              let context = panel.windowPeekContext(for: item.id) else {
            sourcePanel?.store.errorMessage = .fileRouteDestinationUnavailable
            return false
        }
        let window = token.flatMap { id in allWindows.first { $0.token == id } }
        let exact = window != nil && controller?.state.usesApplicationSelection != true
        let transferredDiscovery = discoveryID
        discoveryID = nil // The handoff now owns the AX handles until activation or dismissal.
        close(returnFocus: false)
        fileHandoff.show(documents: documents, item: item, window: window, exactWindow: exact,
                         discoveryID: transferredDiscovery, visibleFrame: context.anchor.visibleFrame)
        return true
    }

    private func actionDisplaySnapshot() -> [WindowActionDisplay] {
        let displays = actionDisplays?() ?? []
        guard let primary = displays.first(where: \.isPrimary) else { return [] }
        // NSScreen uses upward y; AX uses downward y relative to the primary screen's top.
        func quartz(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        return displays.filter(\.hostsDock).map {
            WindowActionDisplay(id: $0.id, runtimeID: $0.runtimeID, name: $0.name, frame: quartz($0.frame), usable: quartz($0.visibleFrame))
        }
    }

    private func manage(_ token: ApplicationWindowToken) {
        guard let controller, !controller.state.actionBusy, !controller.state.routingFiles else { return }
        enlarge?.dismiss()
        guard !controller.state.usesApplicationSelection else {
            controller.state.actionMessage = .peekActionCaptureOnly
            return
        }
        actionLayout = actionDisplaySnapshot()
        controller.state.actionBusy = true
        controller.state.actionMessage = nil
        cancelClose()
        let currentGeneration = generation
        let point = isKeyboardActive ? controller.actionMenuPoint : NSEvent.mouseLocation
        windowActionTask = Task { [weak self, weak controller] in
            guard let self, let controller else { return }
            defer {
                if generation == currentGeneration {
                    controller.state.actionBusy = false
                    windowActionTask = nil
                }
            }
            var closingWindow = false
            do {
                let capabilities = try await menus.windowCapabilities(token)
                guard !Task.isCancelled, generation == currentGeneration else { return }
                guard capabilities.canMinimize || capabilities.canClose || capabilities.canMove else {
                    controller.state.actionMessage = capabilities.restricted ? .peekActionRestricted : .peekActionUnsupported
                    return
                }
                controller.state.actionMenuTracking = true
                let selection = actionMenu.show(capabilities: capabilities, displays: actionDisplaySnapshot(), at: point)
                controller.state.actionMenuTracking = false
                guard let action = selection else { return }
                guard !Task.isCancelled, generation == currentGeneration else { return }
                closingWindow = action == .close
                let result = try await menus.performWindowAction(action, token: token, displays: actionDisplaySnapshot())
                guard !Task.isCancelled, generation == currentGeneration else { return }
                if action == .close {
                    // Dismiss without focus restoration so a native document prompt stays in charge.
                    close(returnFocus: false)
                    return
                }
                if let result { refreshActionCard(result) }
                controller.state.actionMessage = .peekActionCompleted
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled, generation == currentGeneration else { return }
                if closingWindow {
                    sourcePanel?.store.errorMessage = .peekActionFailed
                    close(returnFocus: false)
                    return
                }
                if let summary = try? await menus.windowActionSummary(token),
                   !Task.isCancelled, generation == currentGeneration {
                    refreshActionCard(summary)
                }
                guard !Task.isCancelled, generation == currentGeneration else { return }
                switch error {
                case WindowActionError.permission, ApplicationWindowServiceError.permissionRequired:
                    controller.state.actionMessage = .peekActionPermission
                case WindowActionError.constrained:
                    controller.state.actionMessage = .peekActionConstrained
                case WindowActionError.unsupported:
                    controller.state.actionMessage = .peekActionUnsupported
                default: controller.state.actionMessage = .peekActionFailed
                }
            }
        }
    }

    /// Keep sibling thumbnails and filtering intact when a single command changes its source.
    private func refreshActionCard(_ summary: ApplicationWindowSummary) {
        guard let controller, let index = allWindows.firstIndex(where: { $0.token == summary.token }) else { return }
        allWindows[index] = summary
        if let cardIndex = controller.state.cards.firstIndex(where: { $0.id == summary.token }) {
            controller.state.cards[cardIndex] = WindowPeekCard(window: summary, thumbnail: nil)
        }
        controller.state.selectedID = summary.token
        requestedThumbnailIDs.remove(summary.token)
        requestThumbnail(summary.token)
    }

    private func choose(_ token: ApplicationWindowToken) {
        if fileDocuments != nil { routeFiles(to: token); return }
        guard let item = sourceItem, let panel = sourcePanel else { return }
        guard controller?.state.usesApplicationSelection != true else {
            // App activation may front a different window, so the image must not claim this one.
            enlarge?.dismiss()
            showApp()
            return
        }
        // The staged image flies onto the window this selection brings forward, then fades to reveal it.
        enlarge?.land(token, windowFrame: allWindows.first { $0.token == token }?.frame)
        menus.perform(.selectWindow(token), for: item) { [weak self, weak panel] error in
            if let error { panel?.store.errorMessage = error }
            else { panel?.store.applicationOpened?() }
            self?.close(returnFocus: false)
        }
    }

    /// Closes Peek and opens the markup editor for `token`'s window.
    ///
    /// The Peek thumbnail, or the enlarged preview's sharper capture, is the editor's first picture;
    /// the editor requests its own full-resolution capture. When the card is staged on the enlarge
    /// stage, its on-screen frame travels along so the picture appears to move into the editor.
    private func openMarkup(_ token: ApplicationWindowToken) {
        guard fileDocuments == nil, let item = sourceItem, let panel = sourcePanel, let controller,
              let card = controller.state.cards.first(where: { $0.id == token }),
              let context = panel.windowPeekContext(for: item.id) else { return }
        let staged = enlarge?.stagedExhibit(for: token)
        let request = WindowMarkupRequest(
            window: card.window, appName: item.reference.name, appIcon: item.icon,
            preview: staged?.image ?? card.thumbnail, origin: staged?.frame,
            visibleFrame: context.anchor.visibleFrame,
            backingScale: controller.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2,
            settings: context.settings, shelfAvailable: context.settings.showShelf)
        close(returnFocus: false)
        markups.show(request)
    }

    private func showApp() {
        if fileDocuments != nil { routeFiles(to: nil); return }
        guard let item = sourceItem else { return }
        sourcePanel?.store.open(item)
        close(returnFocus: false)
    }

    private func scheduleClose() {
        if controller?.state.actionBusy == true || controller?.state.portalDragging == true { return }
        if fileDocuments != nil, !fileDrag { return }
        let delay = fileDrag ? 650 : 180
        // Pointer updates call this on every move outside the peek. Keep the pending deadline so
        // continuous movement neither churns tasks nor postpones the close indefinitely.
        if closeTask != nil, closeDelay == delay { return }
        cancelClose()
        closeDelay = delay
        closeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard let self, !Task.isCancelled else { return }
            closeTask = nil
            guard !WindowPeekLifecycle.retainsPresentation(sourceHovered: sourceHovered, panelHovered: panelHovered)
            else { return }
            close(returnFocus: false)
        }
    }

    private func cancelClose() {
        closeTask?.cancel()
        closeTask = nil
    }
}
