import AppKit
import Observation

/// Application lifetime owner for display reconciliation, global pointer events, and exclusive keyboard focus.
@MainActor @Observable
final class DockCoordinator {
    let settings: DockSettingsStore
    let profiles: DisplayProfilesStore
    let zonePreview = DockZonePreviewController()
    let displayIndicator = DisplaySelectionIndicatorController()
    /// One-shot navigation consumed by Settings, including when its window is first created.
    var settingsDisplayRequest: String?
    @ObservationIgnored private var suspensionObserver: NSObjectProtocol?
    @ObservationIgnored private var accessibilityObserver: NSObjectProtocol?
    private(set) var enabledDisplays: [DisplaySnapshot] = []
    var canFocus: Bool { !enabledDisplays.isEmpty }
    @ObservationIgnored private let dragging = DockDragCoordinator()
    @ObservationIgnored private let folderStacks = FolderStackCoordinator()
    @ObservationIgnored private let filePicker = DockFilePickerController(makePicker: { DockNativeFilePicker() })
    @ObservationIgnored private let catalog: ApplicationCatalog
    @ObservationIgnored private let applicationMenus: ApplicationMenuController
    @ObservationIgnored private let displayService = DisplayService()
    @ObservationIgnored private var panels: [String: DockPanelController] = [:]
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var focusedID: String?
    @ObservationIgnored private var previousApplication: NSRunningApplication?
    @ObservationIgnored private var lastExternalApplication: NSRunningApplication?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var reconciling = false

    init(windowAccess: WindowAccessController) {
        let settings = DockSettingsStore(repository: DockSettingsRepository())
        self.settings = settings
        profiles = DisplayProfilesStore(defaults: settings, repository: DisplayProfilesRepository())
        let applicationService = ApplicationService()
        catalog = ApplicationCatalog(service: applicationService)
        applicationMenus = ApplicationMenuController(
            access: windowAccess,
            applications: ApplicationMenuService(applications: applicationService),
            windows: AccessibilityApplicationWindowService()
        )
    }

    func start() {
        guard !started else { return }
        started = true
        rememberExternal(NSWorkspace.shared.frontmostApplication)
        folderStacks.keyboardDismissed = { [weak self] displayID in
            guard let self, focusedID == displayID else { return }
            endFocus(restore: false)
        }
        folderStacks.openChanged = { [weak self] open in
            self?.panels.values.forEach { $0.holdFolderStack(open) }
        }
        catalog.didChange = { [weak self] in self?.refreshPanels() }
        catalog.activated = { [weak self] app in
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self?.rememberExternal(app)
            self?.endFocus(restore: false)
        }
        profiles.didChange = { [weak self] in
            guard let self else { return }
            if !dragging.committing { dragging.cancel() }
            reconcile(profiles.displays, resetVisibility: false)
        }
        settings.settingsDidChange = { [weak self] in self?.refreshPanels() }
        displayService.didChange = { [weak self] in self?.reconcile($0) }
        catalog.start()
        displayService.start()
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshPanels(resetVisibility: true) } }
        suspensionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated {
            self?.dragging.cancel()
            self?.folderStacks.close(returnFocus: false)
            self?.applicationMenus.cancelAllDiscoveries()
            self?.panels.values.forEach { $0.suspendIdleFading() }
        } }
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
        if resetVisibility { dragging.cancel() }
        reconciling = true
        defer { reconciling = false }
        profiles.synchronize(displays) { catalog.service.defaultFavorites() }
        enabledDisplays = DisplayPolicy.enabled(displays) { profiles.document.profiles[$0]?.enabled == true }
        let desired = Set(enabledDisplays.map(\.id))
        for id in Array(panels.keys) where !desired.contains(id) {
            filePicker.cancel(for: id)
            folderStacks.close(for: id, returnFocus: false)
            if focusedID == id { endFocus(restore: true) }
            panels.removeValue(forKey: id)?.stop()
        }
        for display in enabledDisplays where panels[display.id] == nil {
            let store = DockStore(displayID: display.id, catalog: catalog, profiles: profiles)
            let panel = DockPanelController(store: store, settings: profiles.effectiveSettings(for: display.id))
            panel.resignedFocus = { [weak self] in
                guard let self else { return }
                if focusedID == display.id, !folderStacks.isKeyboardActive { endFocus(restore: false) }
            }
            panel.escape = { [weak self] in self?.endFocus(restore: true) }
            store.applicationOpened = { [weak self] in
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
            if folderStacks.isOpen { panel.holdFolderStack(true) }
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
        if let id = zonePreview.displayID {
            if let geometry = panels[id]?.geometry { zonePreview.update(geometry) }
            else { zonePreview.stop() }
        }
        catalog.pruneIcons(items: panels.values.flatMap { $0.store.items },
                           folders: panels.values.flatMap { $0.store.folders })
    }
    private func updatePointers(eventType: NSEvent.EventType) { panels.values.forEach { $0.updatePointer(eventType: eventType) } }

    /// Only connected enabled desktop surfaces have a live zone to outline.
    func showZone(for id: String) {
        guard let geometry = panels[id]?.geometry else { return }
        zonePreview.show(displayID: id, geometry: geometry)
    }
    /// Explicit picker activation captures focus before AppKit resigns the dock's key panel.
    private func openFiles(for item: DockItem, on panel: DockPanelController) {
        guard item.isAvailable, panels[panel.store.displayID] === panel else { return }
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

    func focusDock() {
        guard let id = DisplayPolicy.focusTarget(displays: enabledDisplays, pointer: NSEvent.mouseLocation), let panel = panels[id] else { return }
        endFocus(restore: false)
        previousApplication = lastExternalApplication
        focusedID = id
        panel.focus()
    }

    private func endFocus(restore: Bool) {
        guard let id = focusedID else { return }
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
        filePicker.stop()
        dragging.stop()
        folderStacks.stop()
        applicationMenus.stop()
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        accessibilityObserver = nil
        if let suspensionObserver { NSWorkspace.shared.notificationCenter.removeObserver(suspensionObserver) }
        suspensionObserver = nil
        displayService.stop()
        profiles.didChange = nil
        settings.settingsDidChange = nil
        panels.values.forEach { $0.stop() }
        panels.removeAll()
        enabledDisplays = []
        catalog.stop()
    }
}
