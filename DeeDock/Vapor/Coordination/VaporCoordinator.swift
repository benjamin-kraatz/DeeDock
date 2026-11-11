import AppKit
import Observation

/// Vapor's lifetime owner: on/off state, launch recovery, displays, windows, Finder
/// suggestions, drag proximity and event monitors. ``DockCoordinator`` owns one and calls
/// ``start()``, ``stop()`` and ``updateDisplays(_:)``.
///
/// While Vapor is off, only launch recovery runs: no windows, monitors or observers exist.
/// Turning it on builds them; turning it off or quitting tears every one down.
@MainActor @Observable
final class VaporCoordinator {
    let store: VaporStore
    let controller: VaporController

    /// Whether Vapor is on. The menu bar's toggle binds to this through ``setEnabled(_:)``.
    var isEnabled: Bool { store.isEnabled }

    @ObservationIgnored private let deleter: VaporDeletionEngine
    @ObservationIgnored private let home: URL
    @ObservationIgnored private let finderObserver = VaporFinderObserver()
    @ObservationIgnored private let finderReader = VaporFinderReader()
    @ObservationIgnored private let dragTracker = VaporDragTracker()
    @ObservationIgnored private var windows: VaporWindows?
    @ObservationIgnored private var displays: [VaporDisplay] = []
    @ObservationIgnored private var orbDisplay: VaporDisplay?
    @ObservationIgnored private var orbCenter: CGPoint?
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var accessibilityObserver: NSObjectProtocol?
    @ObservationIgnored private var finderTask: Task<Void, Never>?
    @ObservationIgnored private var recoveryTask: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var presenting = false
    /// Bumped on every teardown so a stale observation callback does nothing.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastMotion: (point: CGPoint, time: TimeInterval, velocity: CGVector)?
    @ObservationIgnored private var outsidePress: CGPoint?

    init() {
        let store = VaporStore()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let location = VaporStagingLocation.standard
        let deleter = VaporDeletionEngine(ledger: .standard, location: location)
        self.store = store
        self.home = home
        self.deleter = deleter
        controller = VaporController(dependencies: .init(
            store: store, home: home,
            policy: VaporDropPolicy(home: home, stagingRoots: location.knownStagingRoots()),
            measurer: VaporFileMeasurer(), deleter: deleter,
            analytics: { event in
                if let analytics = AnalyticsEvent.vapor(event) { Analytics.track(analytics) }
            }))
    }

    // MARK: Lifecycle

    /// Finishes removals left by an earlier run (even while Vapor is off) and shows the orb when on.
    func start() {
        guard !started else { return }
        started = true
        let deleter = deleter
        recoveryTask = Task(priority: .utility) { await deleter.recover() }
        controller.requestFinderAccess = { [weak self] in self?.requestFinderAccess() }
        if store.isEnabled { present() }
    }

    func stop() {
        guard started else { return }
        started = false
        dismantle()
        controller.requestFinderAccess = nil
    }

    /// Turns Vapor on or off. Off hides the orb and keeps its folders.
    func setEnabled(_ enabled: Bool) {
        guard enabled != store.isEnabled else { return }
        store.setEnabled(enabled)
        Analytics.track(.vaporToggled(enabled: enabled))
        guard started else { return }
        enabled ? present() : dismantle()
    }

    /// The display arrangement changed, or the Mac woke. Re-places the orb and its windows.
    func updateDisplays(_ snapshots: [DisplaySnapshot]) {
        displays = snapshots.filter(\.hostsDock).map {
            VaporDisplay(id: $0.id, frame: $0.frame, visibleFrame: $0.visibleFrame, isPrimary: $0.isPrimary)
        }
        guard presenting else { return }
        placeOrb(animated: false)
    }

    // MARK: Presenting

    private func present() {
        guard !presenting else { return }
        presenting = true
        controller.start()
        readAccessibilityOptions()
        let windows = VaporWindows(controller: controller)
        self.windows = windows
        windows.orbClicked = { [weak self] in self?.controller.togglePanel() }
        windows.orbMoved = { [weak self] center, time in self?.orbMoved(to: center, time: time) }
        windows.orbMoveEnded = { [weak self] center in self?.orbMoveEnded(at: center) }
        windows.makeMenu = { [weak self] in self?.makeMenu() ?? NSMenu() }
        windows.dragMoved = { [weak self] point, overPanel in self?.dragMoved(point, overPanel: overPanel) }
        windows.dropped = { [weak self] urls in self?.drop(urls) ?? false }
        windows.needsLayout = { [weak self] in self?.layoutWindows() }
        dragTracker.changed = { [weak self] point in self?.dragMoved(point, overPanel: false) }
        dragTracker.start()
        finderObserver.changed = { [weak self] in self?.readFinder() }
        finderObserver.finderResigned = { [weak self] in
            self?.finderTask?.cancel()
            self?.controller.clearFinderFolder()
        }
        finderObserver.start()
        installMonitors()
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.readAccessibilityOptions() } }
        placeOrb(animated: false)
        trackState(generation: generation)
        refreshPermission()
    }

    private func dismantle() {
        guard presenting else { return }
        presenting = false
        generation &+= 1
        finderTask?.cancel()
        finderTask = nil
        finderObserver.stop()
        finderObserver.changed = nil
        finderObserver.finderResigned = nil
        dragTracker.stop()
        dragTracker.changed = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        accessibilityObserver = nil
        controller.stop()
        windows?.tearDown()
        windows = nil
        orbCenter = nil
        orbDisplay = nil
        lastMotion = nil
    }

    private func readAccessibilityOptions() {
        controller.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        controller.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    /// Re-runs window placement whenever state the windows depend on changes. Observation fires
    /// once, so each change registers the next; a teardown bumps `generation` to end the chain.
    private func trackState(generation: Int) {
        guard presenting, generation == self.generation else { return }
        withObservationTracking {
            _ = controller.isPanelOpen
            _ = controller.callout
            _ = controller.bubbleSuggestions.map(\.id)
            _ = controller.folders.count
        } onChange: { [weak self] in
            // Copies the weak reference into the task; the task holds it only until it runs.
            Task { @MainActor [self] in
                guard let self, generation == self.generation else { return }
                self.layoutWindows()
                self.trackState(generation: generation)
            }
        }
        layoutWindows()
    }

    // MARK: Placement

    private func placeOrb(animated: Bool) {
        guard let windows, let resolved = VaporGeometry.resolve(store.state, displays: displays) else { return }
        orbDisplay = resolved.display
        orbCenter = resolved.center
        windows.showOrb(at: resolved.center, animated: animated)
        updateOrbDecoration()
        layoutWindows()
    }

    private func layoutWindows() {
        guard let windows, let orbCenter, let orbDisplay else { return }
        windows.layout(orbCenter: orbCenter, visibleFrame: orbDisplay.visibleFrame)
    }

    /// Lighting, badge corner and opening side change only when the orb moves.
    private func updateOrbDecoration() {
        guard let orbCenter, let orbDisplay else { return }
        controller.lighting = VaporGeometry.lighting(orbCenter: orbCenter, displayFrame: orbDisplay.frame)
        controller.badgeCorner = VaporGeometry.badgeCorner(orbCenter: orbCenter, visibleFrame: orbDisplay.visibleFrame)
        controller.opensLeft = VaporGeometry.opensLeft(orbCenter: orbCenter, visibleFrame: orbDisplay.visibleFrame)
    }

    private func orbMoved(to center: CGPoint, time: TimeInterval) {
        orbCenter = center
        if let display = VaporGeometry.display(at: center, in: displays) { orbDisplay = display }
        // Velocity and acceleration in SwiftUI's y-down axes, for the slosh.
        var velocity = CGVector.zero, acceleration = CGVector.zero
        if let last = lastMotion, time > last.time {
            let dt = time - last.time
            velocity = CGVector(dx: (center.x - last.point.x) / dt, dy: -(center.y - last.point.y) / dt)
            acceleration = CGVector(dx: (velocity.dx - last.velocity.dx) / dt, dy: (velocity.dy - last.velocity.dy) / dt)
        }
        lastMotion = (center, time, velocity)
        controller.orbMotion = VaporOrbMotion(isDragging: true, velocity: velocity, acceleration: acceleration)
        updateOrbDecoration()
        layoutWindows()
    }

    private func orbMoveEnded(at center: CGPoint) {
        lastMotion = nil
        controller.orbMotion = .still
        guard let display = VaporGeometry.display(at: center, in: displays) else { return }
        let clamped = VaporGeometry.clampedCenter(center, in: display.visibleFrame)
        store.setPlacement(VaporGeometry.placement(center: clamped, in: display.visibleFrame), displayID: display.id)
        orbDisplay = display
        orbCenter = clamped
        windows?.showOrb(at: clamped, animated: true)
        updateOrbDecoration()
        layoutWindows()
    }

    // MARK: Drops

    private func dragMoved(_ point: CGPoint?, overPanel: Bool) {
        guard let point, let orbCenter else {
            controller.dropHover = .none
            return
        }
        let panelHit = overPanel || (windows?.panelFrame?.contains(point) ?? false)
        controller.dropHover = VaporDropHover(proximity: VaporGeometry.dropProximity(point: point, orbCenter: orbCenter),
                                              isOverPanel: panelHit)
    }

    private func drop(_ urls: [URL]) -> Bool {
        controller.dropHover = .none
        return controller.add(urls, source: .drop)
    }

    // MARK: Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let empty = controller.folders.isEmpty
        menu.addItem(VaporMenuItem(.vaporMenuOpen) { [weak self] in self?.controller.openPanel() })
        menu.addItem(VaporMenuItem(.vaporMenuDeleteAll, enabled: !empty) { [weak self] in self?.controller.nudgeDelete() })
        menu.addItem(VaporMenuItem(.vaporMenuClear, enabled: !empty) { [weak self] in self?.controller.clear() })
        menu.addItem(.separator())
        menu.addItem(VaporMenuItem(.vaporMenuHide) { [weak self] in self?.setEnabled(false) })
        return menu
    }

    // MARK: Panel dismissal

    /// Escape over the open panel, or a click outside Vapor's windows, closes the panel.
    ///
    /// The panel can't be key, so Escape is read from key monitors; the global one only receives
    /// events while DOKK has Accessibility trust. A click outside counts on mouse-up without
    /// movement, so pressing in Finder to start a drag onto the panel keeps it open.
    private func installMonitors() {
        let keyHandler: (NSEvent) -> Void = { [weak self] event in
            guard event.keyCode == 53, let self, self.controller.isPanelOpen,
                  self.windows?.panelFrame?.contains(NSEvent.mouseLocation) == true else { return }
            self.controller.closePanel()
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
            MainActor.assumeIsolated { keyHandler(event) }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            keyHandler(event)
            return event
        }) { monitors.append(monitor) }
        let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .rightMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mouseMask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.pointerEvent(type, inVapor: false) }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mouseMask, handler: { [weak self] event in
            let inVapor = self?.windows?.visibleFrames.contains { $0.contains(NSEvent.mouseLocation) } ?? false
            self?.pointerEvent(event.type, inVapor: inVapor)
            return event
        }) { monitors.append(monitor) }
    }

    private func pointerEvent(_ type: NSEvent.EventType, inVapor: Bool) {
        guard controller.isPanelOpen, !inVapor else {
            outsidePress = nil
            return
        }
        let location = NSEvent.mouseLocation
        switch type {
        case .leftMouseDown:
            outsidePress = location
        case .leftMouseUp:
            if let press = outsidePress, hypot(location.x - press.x, location.y - press.y) < 4 { controller.closePanel() }
            outsidePress = nil
        case .rightMouseDown:
            controller.closePanel()
        default:
            break
        }
    }

    // MARK: Finder

    private func refreshPermission() {
        let reader = finderReader
        Task { [weak self] in
            let permission = await reader.permission(ask: false)
            self?.controller.automationPermission = permission
        }
    }

    /// Reads Finder's front folder and scans it. Cancels a read or scan still running.
    private func readFinder() {
        guard presenting, finderObserver.isFinderFrontmost else { return }
        finderTask?.cancel()
        let reader = finderReader, home = home
        finderTask = Task { [weak self] in
            let permission = await reader.permission(ask: false)
            guard !Task.isCancelled, let self else { return }
            self.controller.automationPermission = permission
            guard permission == .granted, let folder = try? await reader.frontFolder() else {
                self.controller.clearFinderFolder()
                return
            }
            let items = await Self.scan(folder, home: home)
            guard !Task.isCancelled else { return }
            self.controller.setFinderFolder(folder, items: items)
        }
    }

    @concurrent private static func scan(_ folder: URL, home: URL) async -> [VaporSuggestion] {
        VaporSuggestionScanner.scan(folder, home: home)
    }

    /// The panel's Turn On: the only place Vapor lets macOS ask for Automation permission.
    private func requestFinderAccess() {
        let reader = finderReader
        Task { [weak self] in
            let permission = await reader.permission(ask: true)
            guard let self else { return }
            self.controller.automationPermission = permission
            if permission == .granted { self.readFinder() }
        }
    }
}

/// An `NSMenuItem` that runs a closure.
private final class VaporMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: LocalizedStringResource, enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: String(localized: title), action: #selector(run), keyEquivalent: "")
        target = self
        isEnabled = enabled
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}
