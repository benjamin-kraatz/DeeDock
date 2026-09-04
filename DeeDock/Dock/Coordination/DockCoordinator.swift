import AppKit
import Observation

/// Application lifetime owner for display reconciliation, global pointer events, and exclusive keyboard focus.
@MainActor @Observable
final class DockCoordinator {
    let actionTiles = ActionTilesController()
    let settings: DockSettingsStore
    let profiles: DisplayProfilesStore
    let zonePreview = DockZonePreviewController()
    let displayIndicator = DisplaySelectionIndicatorController()
    /// One-shot navigation consumed by Settings, including when its window is first created.
    var settingsDisplayRequest: String?
    /// One-shot route used by Window Peek's permission fallback.
    var settingsFeaturesRequest = false
    /// One-shot route opened from the menu-bar mode submenu.
    var settingsModesRequest = false
    @ObservationIgnored private var suspensionObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var accessibilityObserver: NSObjectProtocol?
    private(set) var enabledDisplays: [DisplaySnapshot] = []
    var canFocus: Bool { !enabledDisplays.isEmpty }
    var canSwitchModes: Bool {
        profiles.modes.canEdit && !dragging.isDragging && !filePicker.isActive
            && !panels.values.contains(where: \.isMenuTracking)
    }
    @ObservationIgnored private let dragging = DockDragCoordinator()
    @ObservationIgnored private let popovers = DockPopoverPresenter()
    @ObservationIgnored private let folderStacks: FolderStackCoordinator
    @ObservationIgnored private let shelves: ShelfCoordinator
    @ObservationIgnored private let sessionCapsules: SessionCapsuleCoordinator
    @ObservationIgnored private let shelfSemanticWarmup: ShelfSemanticWarmupController
    @ObservationIgnored private let filePicker = DockFilePickerController(makePicker: { DockNativeFilePicker() })
    @ObservationIgnored private let catalog: ApplicationCatalog
    @ObservationIgnored private let trash = TrashController()
    @ObservationIgnored private let shelf = ShelfController()
    @ObservationIgnored private let capsules = SessionCapsuleController()
    @ObservationIgnored private let applicationMenus: ApplicationMenuController
    @ObservationIgnored private let windowPeeks: WindowPeekCoordinator
    @ObservationIgnored private let modePicker = DockModePickerCoordinator()
    @ObservationIgnored private let displayService = DisplayService()
    @ObservationIgnored private var panels: [String: DockPanelController] = [:]
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var focusedID: String?
    @ObservationIgnored private var previousApplication: NSRunningApplication?
    @ObservationIgnored private var lastExternalApplication: NSRunningApplication?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var reconciling = false

    init(windowAccess: WindowAccessController, screenCapture: ScreenCaptureAccessController) {
        let settings = DockSettingsStore(repository: DockSettingsRepository())
        self.settings = settings
        profiles = DisplayProfilesStore(defaults: settings, repository: DisplayProfilesRepository(),
                                         modesRepository: DockModesRepository())
        let applicationService = ApplicationService()
        catalog = ApplicationCatalog(service: applicationService)
        let menus = ApplicationMenuController(
            access: windowAccess,
            applications: ApplicationMenuService(applications: applicationService),
            windows: AccessibilityApplicationWindowService()
        )
        applicationMenus = menus
        windowPeeks = WindowPeekCoordinator(menus: menus, screenCapture: screenCapture)
        let semanticStacks = CoalescingSemanticStackOrganizer(
            base: FoundationModelsSemanticStackOrganizer()
        )
        folderStacks = FolderStackCoordinator(presenter: popovers, organizer: semanticStacks)
        shelves = ShelfCoordinator(shelf: shelf, presenter: popovers, organizer: semanticStacks)
        sessionCapsules = SessionCapsuleCoordinator(capsules: capsules, presenter: popovers,
                                                    screenCapture: screenCapture)
        let shelf = self.shelf
        shelfSemanticWarmup = ShelfSemanticWarmupController(organizer: semanticStacks) {
            let items = shelf.ordered
            let accesses = shelf.resolveAll()
            let accessByID = Dictionary(uniqueKeysWithValues: accesses.map { ($0.id, $0) })
            let inputs = ShelfSemanticRequestBuilder.inputs(for: items, accessByID: accessByID)
            guard inputs.count >= 4 else { return nil }
            let candidates = await SemanticStackMetadataLoader.candidates(from: inputs)
            withExtendedLifetime(accesses) {}
            guard !Task.isCancelled, candidates.count >= 4 else { return nil }
            return ShelfSemanticRequestBuilder.request(candidates: candidates)
        }
    }

    func start() {
        guard !started else { return }
        started = true
        actionTiles.changed = { [weak self] in self?.refreshPanels() }
        actionTiles.start()
        rememberExternal(NSWorkspace.shared.frontmostApplication)
        dragging.openSpringFolder = { [weak self] folder, panel in
            self?.folderStacks.show(folder, on: panel, keyboard: false, spring: true)
        }
        dragging.dropInFolder = { [weak self] info, folder, panel in
            self?.folderStacks.receive(info, folder: folder, on: panel) ?? false
        }
        dragging.springDragEnded = { [weak self] in self?.folderStacks.dragEnded() }
        folderStacks.keyboardDismissed = { [weak self] displayID in
            guard let self, focusedID == displayID else { return }
            endFocus(restore: false)
        }
        shelves.keyboardDismissed = { [weak self] displayID in
            guard let self, focusedID == displayID else { return }
            endFocus(restore: false)
        }
        sessionCapsules.keyboardDismissed = { [weak self] displayID in
            guard let self, focusedID == displayID else { return }
            endFocus(restore: false)
        }
        popovers.openChanged = { [weak self] open in
            if open {
                self?.windowPeeks.close(returnFocus: false)
                self?.modePicker.close(returnFocus: false)
            }
            self?.panels.values.forEach { $0.holdPopover(open) }
        }
        windowPeeks.prepareSettings = { [weak self] _ in
            self?.settingsFeaturesRequest = true
        }
        catalog.didChange = { [weak self] in self?.refreshPanels() }
        trash.didChange = { [weak self] in self?.refreshPanels() }
        // One shared Shelf: an edit on any display re-renders every dock and the open panel.
        shelf.didChange = { [weak self] in
            self?.scheduleShelfSemanticWarmup()
            self?.shelves.reload()
            self?.refreshPanels()
        }
        capsules.didChange = { [weak self] in
            self?.sessionCapsules.reload()
            self?.refreshPanels()
        }
        catalog.activated = { [weak self] app in
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            if app.bundleIdentifier == "com.apple.finder" { self?.trash.refreshAfterFinderActivity() }
            self?.rememberExternal(app)
            self?.windowPeeks.close(returnFocus: false)
            self?.endFocus(restore: false)
        }
        profiles.didChange = { [weak self] in
            guard let self else { return }
            if !dragging.committing { dragging.cancel() }
            reconcile(profiles.displays, resetVisibility: false)
        }
        settings.settingsDidChange = { [weak self] in
            self?.scheduleShelfSemanticWarmup()
            self?.refreshPanels()
        }
        displayService.didChange = { [weak self] in self?.reconcile($0) }
        catalog.start()
        trash.start()
        shelf.start()
        capsules.start()
        scheduleShelfSemanticWarmup()
        displayService.start()
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshPanels(resetVisibility: true) } }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            suspensionObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated {
                self?.dragging.cancel()
                self?.shelfSemanticWarmup.cancel()
                self?.popovers.closeAll()
                self?.windowPeeks.close(returnFocus: false)
                self?.modePicker.close(returnFocus: false)
                self?.applicationMenus.cancelAllDiscoveries()
                self?.panels.values.forEach { $0.suspendIdleFading() }
            } })
        }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                                         .scrollWheel, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                                         .leftMouseUp, .rightMouseUp, .otherMouseUp]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in self?.updatePointers(eventType: event.type); self?.dragging.observe(event) }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask.union(.keyDown), handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, !dragging.isDragging, let id = focusedID, let panel = panels[id], panel.owns(event.window), panel.handleKey(event) { return nil }
            updatePointers(eventType: event.type)
            dragging.observe(event)
            return event
        }) { monitors.append(monitor) }
    }

    private func reconcile(_ displays: [DisplaySnapshot], resetVisibility: Bool = true) {
        guard started, !reconciling else { return }
        if resetVisibility {
            dragging.cancel()
            modePicker.close(returnFocus: false)
        }
        reconciling = true
        defer { reconciling = false }
        profiles.synchronize(displays) { catalog.service.defaultFavorites() }
        enabledDisplays = DisplayPolicy.enabled(displays) { profiles.document.profiles[$0]?.enabled == true }
        let desired = Set(enabledDisplays.map(\.id))
        for id in Array(panels.keys) where !desired.contains(id) {
            filePicker.cancel(for: id)
            folderStacks.close(for: id, returnFocus: false)
            shelves.close(for: id, returnFocus: false)
            sessionCapsules.close(for: id, returnFocus: false)
            if focusedID == id { endFocus(restore: true) }
            panels.removeValue(forKey: id)?.stop()
        }
        for display in enabledDisplays where panels[display.id] == nil {
            let store = DockStore(displayID: display.id, catalog: catalog, profiles: profiles,
                                  trash: trash, shelf: shelf, capsules: capsules, actions: actionTiles)
            let panel = DockPanelController(store: store, settings: profiles.effectiveSettings(for: display.id))
            panel.interaction.actionTiles = actionTiles
            panel.resignedFocus = { [weak self] in
                guard let self else { return }
                if focusedID == display.id, !folderStacks.isKeyboardActive, !shelves.isOpen, !windowPeeks.isKeyboardActive,
                   !sessionCapsules.isOpen, !modePicker.isKeyboardActive {
                    endFocus(restore: false)
                }
            }
            panel.exclusiveInteractionBegan = { [weak self] in
                self?.windowPeeks.close(returnFocus: false)
                self?.modePicker.close(returnFocus: false)
            }
            panel.modePickerRequested = { [weak self, weak panel] in
                guard let self, let panel, canSwitchModes else { return }
                modePicker.show(modes: profiles.modes.modes,
                                activeModeID: profiles.modes.document.activeModeID,
                                on: panel) { [weak self] id in self?.activateMode(id) ?? false }
            }
            panel.escape = { [weak self] in self?.endFocus(restore: true) }
            store.applicationOpened = { [weak self] in
                self?.windowPeeks.close(returnFocus: false)
                if self?.focusedID == display.id { self?.endFocus(restore: false) }
            }
            panel.connectDragging(dragging)
            panel.interaction.openFiles = { [weak self, weak panel] item in
                guard let self, let panel else { return }
                self.openFiles(for: item, on: panel)
            }
            panel.interaction.applicationMenuSnapshot = { [weak self] item in
                self?.applicationMenus.snapshot(for: item)
                    ?? ApplicationMenuSnapshot(processes: [], windowState: .hidden)
            }
            panel.interaction.beginApplicationWindowDiscovery = { [weak self] item, snapshot, completion in
                self?.applicationMenus.beginDiscovery(for: item, snapshot: snapshot, completion: completion)
            }
            panel.interaction.cancelApplicationWindowDiscovery = { [weak self] sessionID in
                self?.applicationMenus.cancelDiscovery(sessionID)
            }
            panel.interaction.performApplicationMenuAction = { [weak self, weak panel] action, item in
                guard let self, let panel, panels[display.id] === panel else { return }
                applicationMenus.perform(action, for: item) { [weak self, weak panel] error in
                    guard let self, let panel, panels[display.id] === panel else { return }
                    if let error { panel.store.errorMessage = error }
                    else if action.activatesApplication { panel.store.applicationOpened?() }
                }
            }
            panel.interaction.windowPeekHoverChanged = { [weak self, weak panel] item in
                guard let self, let panel else { return }
                windowPeeks.hover(item, on: panel)
            }
            panel.interaction.openWindowPeek = { [weak self, weak panel] item in
                guard let self, let panel else { return }
                windowPeeks.showKeyboard(item, on: panel)
            }
            panel.interaction.openFolder = { [weak self, weak panel] folder, keyboard in
                guard let self, let panel, panels[display.id] === panel else { return }
                folderStacks.show(folder, on: panel, keyboard: keyboard)
            }
            panel.interaction.revealFolder = { [weak panel] folder in
                guard folder.isAvailable else { return }
                let access = FolderResourceAccess(folder.reference)
                guard access.isAvailable else {
                    panel?.store.errorMessage = .folderStackUnavailable
                    return
                }
                NSWorkspace.shared.activateFileViewerSelecting([access.url])
                withExtendedLifetime(access) {}
            }
            store.openShelf = { [weak self, weak panel] in
                guard let self, let panel, panels[display.id] === panel else { return }
                shelves.toggle(on: panel, keyboard: panel.store.keyboardFocus)
            }
            store.openSessionCapsules = { [weak self, weak panel] in
                guard let self, let panel, panels[display.id] === panel else { return }
                sessionCapsules.toggle(on: panel)
            }
            store.openSessionCapsule = { [weak self, weak panel] id in
                guard let self, let panel, panels[display.id] === panel else { return }
                sessionCapsules.show(id, on: panel)
            }
            panel.interaction.openSessionCapsules = { [weak self, weak panel] in
                guard let self, let panel, panels[display.id] === panel else { return }
                sessionCapsules.toggle(on: panel)
            }
            panel.interaction.openSessionCapsule = { [weak self, weak panel] id in
                guard let self, let panel, panels[display.id] === panel else { return }
                sessionCapsules.show(id, on: panel)
            }
            panel.interaction.resumeSessionCapsule = { [weak self, weak panel] id in
                guard let self, let panel, panels[display.id] === panel else { return }
                sessionCapsules.resume(id)
            }
            panel.interaction.deleteSessionCapsule = { [weak self, weak panel] id in
                guard let self, let panel, panels[display.id] === panel else { return }
                sessionCapsules.delete(id)
            }
            panel.interaction.openShelf = { [weak self, weak panel] in
                guard let self, let panel, panels[display.id] === panel else { return }
                shelves.toggle(on: panel, keyboard: false)
            }
            panel.interaction.clearShelf = { [weak panel] in panel?.store.clearShelf() }
            panel.interaction.beginShelfDrag = { [weak self, weak panel] view, event in
                guard let self, let panel, panels[display.id] === panel else { return }
                shelves.beginTileDrag(from: view, event: event, on: panel)
            }
            panel.interaction.prepareSettings = { [weak self] in
                guard let self else { return }
                settingsDisplayRequest = profiles.displays.count > 1
                    && profiles.displays.contains(where: { $0.id == display.id }) ? display.id : nil
            }
            store.copyPin = { [weak self] pin, targetID in
                guard let self, let target = panels[targetID] else { return }
                if !target.store.pins.contains(where: { $0.id == pin.id }) {
                    _ = target.store.insertPins([pin], at: target.store.pins.count)
                }
            }
            panels[display.id] = panel
            if popovers.isOpen { panel.holdPopover(true) }
        }
        dragging.setPanels(panels)
        for (id, panel) in panels {
            panel.store.pinDestinations = enabledDisplays.filter { $0.id != id }.map { DockPinDestination(id: $0.id, name: $0.name) }
        }
        refreshPanels(resetVisibility: resetVisibility)
    }

    private func refreshPanels(resetVisibility: Bool = false) {
        guard started else { return }
        for display in enabledDisplays {
            guard let panel = panels[display.id] else { continue }
            panel.store.refresh()
            panel.update(display: display, settings: profiles.effectiveSettings(for: display.id), resetVisibility: resetVisibility)
        }
        folderStacks.reanchor()
        shelves.reanchor()
        sessionCapsules.reanchor()
        windowPeeks.refresh()
        if let id = zonePreview.displayID {
            if let geometry = panels[id]?.geometry { zonePreview.update(geometry) }
            else { zonePreview.stop() }
        }
        catalog.pruneIcons(items: panels.values.flatMap { $0.store.items },
                           folders: panels.values.flatMap { $0.store.folders })
    }
    private func updatePointers(eventType: NSEvent.EventType) {
        panels.values.forEach { $0.updatePointer(eventType: eventType) }
        windowPeeks.updatePointer()
    }

    /// Only connected enabled desktop surfaces have a live zone to outline.
    func showZone(for id: String) {
        guard let geometry = panels[id]?.geometry else { return }
        zonePreview.show(displayID: id, geometry: geometry)
    }
    /// Explicit picker activation captures focus before AppKit resigns the dock's key panel.
    private func openFiles(for item: DockItem, on panel: DockPanelController) {
        guard item.isAvailable, panels[panel.store.displayID] === panel else { return }
        windowPeeks.close(returnFocus: false)
        let id = panel.store.displayID
        let selection = panel.store.keyboardFocus ? panel.store.selectedTarget : nil
        let previous = previousApplication ?? lastExternalApplication
        filePicker.show(reference: item.reference, displayID: id,
            hold: { [weak panel] in panel?.holdFilePicker($0) },
            submit: { [weak panel] documents, reference in panel?.store.openDocuments(documents, with: reference) },
            cancelled: { [weak self, weak panel] in
                guard let self, let panel, self.panels[id] === panel, NSApp.isActive else { return }
                if let selection {
                    self.endFocus(restore: false)
                    self.previousApplication = previous
                    self.focusedID = id
                    panel.store.selectedTarget = panel.store.entries.contains { $0.target == selection }
                        ? selection : panel.store.entries.first?.target
                    panel.focus()
                } else if let previous, !previous.isTerminated {
                    previous.activate(options: [])
                }
            })
    }

    private func rememberExternal(_ app: NSRunningApplication?) {
        if let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier { lastExternalApplication = app }
    }

    private func scheduleShelfSemanticWarmup() {
        shelfSemanticWarmup.schedule(
            enabled: settings.value.showShelf && shelf.sort == .smart && shelf.items.count >= 4
        )
    }

    func focusDock() {
        guard let id = DisplayPolicy.focusTarget(displays: enabledDisplays, pointer: NSEvent.mouseLocation), let panel = panels[id] else { return }
        endFocus(restore: false)
        previousApplication = lastExternalApplication
        focusedID = id
        panel.focus()
    }

    @discardableResult
    func activateMode(_ id: UUID) -> Bool {
        guard canSwitchModes else { return false }
        popovers.closeAll()
        windowPeeks.close(returnFocus: false)
        modePicker.close(returnFocus: false)
        applicationMenus.cancelAllDiscoveries()
        return profiles.modes.activate(id)
    }

    @discardableResult
    func activatePreviousMode() -> Bool {
        guard let id = profiles.modes.previousMode?.id else { return false }
        return activateMode(id)
    }

    @discardableResult
    func deleteMode(_ id: UUID) -> Bool {
        guard canSwitchModes else { return false }
        popovers.closeAll()
        windowPeeks.close(returnFocus: false)
        modePicker.close(returnFocus: false)
        applicationMenus.cancelAllDiscoveries()
        return profiles.modes.delete(id)
    }

    private func endFocus(restore: Bool) {
        guard let id = focusedID else { return }
        modePicker.close(returnFocus: false)
        focusedID = nil // Clear before resignKey can call back into the coordinator.
        let previous = previousApplication
        previousApplication = nil
        panels[id]?.endFocus()
        if restore, let previous, !previous.isTerminated { previous.activate(options: []) }
    }

    func stop() {
        guard started else { return }
        started = false
        endFocus(restore: true)
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        zonePreview.stop()
        displayIndicator.stop()
        settingsDisplayRequest = nil
        settingsFeaturesRequest = false
        settingsModesRequest = false
        filePicker.stop()
        dragging.stop()
        folderStacks.stop()
        shelves.stop()
        actionTiles.stop()
        sessionCapsules.stop()
        shelfSemanticWarmup.stop()
        popovers.stop()
        shelf.stop()
        capsules.stop()
        windowPeeks.stop()
        modePicker.stop()
        applicationMenus.stop()
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        accessibilityObserver = nil
        suspensionObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        suspensionObservers.removeAll()
        displayService.stop()
        profiles.didChange = nil
        settings.settingsDidChange = nil
        panels.values.forEach { $0.stop() }
        panels.removeAll()
        enabledDisplays = []
        catalog.stop()
        trash.stop()
    }
}
