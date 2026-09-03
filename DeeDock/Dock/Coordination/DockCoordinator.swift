import AppKit
import Observation

/// Application lifetime owner for display reconciliation, global pointer events, and exclusive keyboard focus.
@MainActor @Observable
final class DockCoordinator {
    let settings: DockSettingsStore
    let profiles: DisplayProfilesStore
    private(set) var enabledDisplays: [DisplaySnapshot] = []
    var canFocus: Bool { !enabledDisplays.isEmpty }
    @ObservationIgnored private let catalog: ApplicationCatalog
    @ObservationIgnored private let displayService = DisplayService()
    @ObservationIgnored private var panels: [String: DockPanelController] = [:]
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var focusedID: String?
    @ObservationIgnored private var previousApplication: NSRunningApplication?
    @ObservationIgnored private var lastExternalApplication: NSRunningApplication?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var reconciling = false

    init() {
        let settings = DockSettingsStore(repository: DockSettingsRepository())
        self.settings = settings
        profiles = DisplayProfilesStore(defaults: settings, repository: DisplayProfilesRepository())
        catalog = ApplicationCatalog(service: ApplicationService())
    }

    func start() {
        guard !started else { return }
        started = true
        rememberExternal(NSWorkspace.shared.frontmostApplication)
        catalog.didChange = { [weak self] in self?.refreshPanels() }
        catalog.activated = { [weak self] app in
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self?.rememberExternal(app)
            self?.endFocus(restore: false)
        }
        profiles.didChange = { [weak self] in
            guard let self else { return }
            reconcile(profiles.displays)
        }
        settings.settingsDidChange = { [weak self] in self?.refreshPanels() }
        displayService.didChange = { [weak self] in self?.reconcile($0) }
        catalog.start()
        displayService.start()
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in self?.updatePointers() }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask.union(.keyDown), handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, let id = focusedID, let panel = panels[id], panel.owns(event.window), panel.handleKey(event) { return nil }
            updatePointers()
            return event
        }) { monitors.append(monitor) }
    }

    private func reconcile(_ displays: [DisplaySnapshot]) {
        guard started, !reconciling else { return }
        reconciling = true
        defer { reconciling = false }
        profiles.synchronize(displays) { catalog.service.defaultFavorites() }
        enabledDisplays = DisplayPolicy.enabled(displays) { profiles.document.profiles[$0]?.enabled == true }
        let desired = Set(enabledDisplays.map(\.id))
        for id in Array(panels.keys) where !desired.contains(id) {
            if focusedID == id { endFocus(restore: true) }
            panels.removeValue(forKey: id)?.stop()
        }
        for display in enabledDisplays where panels[display.id] == nil {
            let store = DockStore(displayID: display.id, catalog: catalog, profiles: profiles)
            let panel = DockPanelController(store: store)
            panel.resignedFocus = { [weak self] in
                if self?.focusedID == display.id { self?.endFocus(restore: false) }
            }
            panel.escape = { [weak self] in self?.endFocus(restore: true) }
            store.applicationOpened = { [weak self] in
                if self?.focusedID == display.id { self?.endFocus(restore: false) }
            }
            panels[display.id] = panel
        }
        refreshPanels()
    }

    private func refreshPanels() {
        guard started else { return }
        for display in enabledDisplays {
            guard let panel = panels[display.id] else { continue }
            panel.store.refresh()
            panel.update(display: display, settings: profiles.effectiveSettings(for: display.id))
        }
        catalog.pruneIcons(items: panels.values.flatMap { $0.store.items })
    }
    private func updatePointers() { panels.values.forEach { $0.updatePointer() } }
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
        displayService.stop()
        profiles.didChange = nil
        settings.settingsDidChange = nil
        panels.values.forEach { $0.stop() }
        panels.removeAll()
        enabledDisplays = []
        catalog.stop()
    }
}
