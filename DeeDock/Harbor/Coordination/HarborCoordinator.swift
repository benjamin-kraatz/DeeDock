import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// What Harbor's views ask for. The coordinator performs them; previews use a stub.
@MainActor
protocol HarborIntents: AnyObject {
    /// Brings a window forward and closes Harbor.
    func activate(_ id: UUID)
    /// Presses the window's Close button and reflows the grid.
    func closeWindow(_ id: UUID)
    /// Handles a click on an app in the strip on `displayID`.
    func stripTapped(_ appID: String, displayID: String)
    /// Closes Harbor without bringing anything forward.
    func dismiss()
    /// Routes Settings to Harbor's page and closes Harbor. The view opens the window.
    func prepareSettings()
}

/// Opens and closes Harbor, the app-grouped window overview.
///
/// People see this feature as **Radar**. "Harbor" is the internal name for types, string keys,
/// and analytics events only; user-facing copy must say Radar.
///
/// One session spans every display: each gets a panel with that display's windows, grouped by app,
/// over its blurred wallpaper. Opening gathers windows (Accessibility for exact control, the window
/// list for the current Space, ScreenCaptureKit for thumbnails), shows the panels at once so the
/// desktop dims and the dock transforms while thumbnails land over their windows, then flies the
/// windows from their desktop frames into the grid once the backdrop covers them. Windows whose
/// thumbnails arrive later fade in place. ``HarborStyle`` holds the timing.
///
/// Ownership: the gathering task, capture task, key monitor, and workspace observers exist only
/// while a session is presented; `close` and `stop` cancel them. A generation token rejects late
/// results from a session that has already ended.
@MainActor @Observable
final class HarborCoordinator: HarborIntents {
    let session = HarborSession()
    /// Whether the global shortcut is registered. False when disabled or owned by another app.
    private(set) var shortcutAvailable = false

    /// Every drawable display, including ones without a DOKK dock, so no window peeks through.
    @ObservationIgnored var displays: () -> [DisplaySnapshot] = { [] }
    /// Running apps in a display's dock order.
    @ObservationIgnored var stripOrder: (String) -> [String] = { _ in [] }
    @ObservationIgnored var dockEdge: (String) -> DockEdge = { _ in .bottom }
    /// The dock as drawn on a display right now, in the coordinates of a Harbor panel with the
    /// given AppKit screen frame. Nil when the dock is hidden; the strip then enters from the edge.
    @ObservationIgnored var dockSeed: (String, CGRect) -> HarborDockSeed? = { _, _ in nil }
    /// Closes the dock's popovers, peeks, and Focus Dock before Harbor covers them.
    @ObservationIgnored var willOpen: () -> Void = {}
    /// The app that was in front before Harbor, for Escape to return to.
    @ObservationIgnored var previousApplication: () -> NSRunningApplication? = { nil }
    @ObservationIgnored var prepareSettingsRoute: () -> Void = {}

    @ObservationIgnored private let service = HarborWindowService()
    @ObservationIgnored private let wallpapers = HarborWallpaperLoader()
    @ObservationIgnored private let shortcut = HarborShortcut()
    @ObservationIgnored private var panels: [String: HarborPanelController] = [:]
    @ObservationIgnored private var gathering: Task<Void, Never>?
    @ObservationIgnored private var capturing: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var returnApplication: NSRunningApplication?
    /// Set while Harbor itself activates another app, so that activation does not dismiss it.
    @ObservationIgnored private var expectedActivations = 0
    @ObservationIgnored private var report = Report()
    /// The service session holding this presentation's window handles.
    @ObservationIgnored private var serviceSession: UUID?

    /// Counts for the close event; never titles or app names.
    private struct Report {
        var openedAt = Date()
        var searched = false
        var filtered = false
        var closedWindows = 0
    }

    /// The longest the flight waits for thumbnails after the panels appear.
    private static let thumbnailWait: Duration = .milliseconds(300)
    private static let captureConcurrency = 4

    // MARK: Lifecycle

    /// Registers or releases the global shortcut.
    func configureShortcut(enabled: Bool) {
        if enabled {
            guard !shortcut.isRegistered else { return }
            shortcutAvailable = shortcut.start { [weak self] in
                Analytics.performing(.hotkey) { self?.toggle() }
            }
        } else {
            shortcut.stop()
            shortcutAvailable = false
        }
    }

    func stop() {
        close(raising: nil, outcome: .interrupted, animated: false)
        shortcut.stop()
        shortcutAvailable = false
    }

    // MARK: Opening and closing

    /// Opens Harbor, or closes it when it is already open.
    func toggle() {
        if session.isPresented || gathering != nil {
            close(raising: nil, outcome: .dismissed)
        } else {
            open()
        }
    }

    func open() {
        guard !session.isPresented, gathering == nil else { return }
        let displays = displays().filter(\.hostsDock)
        guard !displays.isEmpty else { return }
        willOpen()
        returnApplication = previousApplication()
        let generation = UUID()
        self.generation = generation
        report = Report()
        let trigger = Analytics.trigger()
        gathering = Task { [weak self] in
            await self?.gather(displays: displays, generation: generation, trigger: trigger)
        }
    }

    /// Closes Harbor. `raising` brings that window forward as the others fly home.
    ///
    /// - Parameters:
    ///   - animated: False for sleep, display changes, and teardown, where nothing should linger.
    ///   - completion: Runs after the panels are gone, if this session was still current.
    func close(raising window: HarborWindow?, outcome: AnalyticsHarborOutcome, animated: Bool = true,
               completion: (() -> Void)? = nil) {
        gathering?.cancel()
        gathering = nil
        capturing?.cancel()
        capturing = nil
        removeMonitors()
        guard session.isPresented else {
            generation = UUID()
            return
        }
        let generation = UUID()
        self.generation = generation
        let serviceSession = serviceSession
        // A session cancelled while gathering never showed and never reported opening.
        if !panels.isEmpty {
            Analytics.track(.harborClosed(outcome: outcome, duration: Date().timeIntervalSince(report.openedAt),
                                      searched: report.searched || !session.query.isEmpty, filtered: report.filtered,
                                      closedWindows: report.closedWindows))
        }
        if let window { bringForward(window) }
        let returning = window == nil && outcome != .interrupted ? returnApplication : nil
        returnApplication = nil
        let finish = { [weak self] in
            guard let self, self.generation == generation else { return }
            panels.values.forEach { $0.close() }
            panels.removeAll()
            session.end()
            if let serviceSession { Task { await self.service.end(session: serviceSession) } }
            if let returning, !returning.isTerminated, NSApp.isActive { returning.activate(options: []) }
            completion?()
        }
        guard animated else { finish(); return }
        withAnimation(session.reduceMotion ? HarborStyle.fade : HarborStyle.motion) {
            session.leave(raising: window?.id)
        }
        // The backdrop clears on its own, later curve, so the panels go on a fixed clock once the
        // spring has settled and the backdrop is gone, rather than on the spring's completion.
        let wait = session.reduceMotion ? HarborStyle.reducedMotionCloseDuration : HarborStyle.closeDuration
        Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard let self, self.generation == generation else { return }
            finish()
        }
    }

    // MARK: Intents

    func activate(_ id: UUID) {
        guard session.showsGrid, let window = session.window(id) else { return }
        close(raising: window, outcome: window.state == .visible ? (window.token == nil ? .app : .window) : .restored)
    }

    func closeWindow(_ id: UUID) {
        guard session.showsGrid, let window = session.window(id), let token = window.token else { return }
        let displays = actionDisplays()
        let generation = generation
        expectedActivations += 1
        Task { [weak self] in
            guard let self else { return }
            defer { expectedActivations -= 1 }
            do {
                try await service.close(token, displays: displays)
            } catch {
                guard self.generation == generation else { return }
                NSSound.beep()
                reclaimKey()
                return
            }
            guard self.generation == generation else { return }
            report.closedWindows += 1
            // A document with unsaved changes keeps its window and shows a save sheet, which
            // would sit hidden under Harbor. Look again shortly; if it survived, step aside.
            try? await Task.sleep(for: .milliseconds(450))
            guard self.generation == generation else { return }
            if let survivor = await service.survivor(of: window), self.generation == generation {
                let raised = HarborWindow(id: window.id, appID: window.appID, processIdentifier: window.processIdentifier,
                                          title: window.title, frame: window.frame, state: .visible, token: survivor,
                                          captureID: window.captureID, stackOrder: window.stackOrder,
                                          document: window.document)
                close(raising: raised, outcome: .window)
                return
            }
            withAnimation(self.session.reduceMotion ? HarborStyle.fade : HarborStyle.motion) { self.session.remove(id) }
            reclaimKey()
        }
    }

    func stripTapped(_ appID: String, displayID: String) {
        guard session.showsGrid else { return }
        if session.displays[displayID]?.groups.contains(where: { $0.id == appID }) == true {
            report.filtered = true
            withAnimation(session.reduceMotion ? HarborStyle.fade : HarborStyle.motion) { session.toggleFilter(appID) }
        } else if let app = NSRunningApplication.runningApplications(withBundleIdentifier: appID).first
                    ?? NSWorkspace.shared.runningApplications.first(where: { Self.appID($0) == appID }) {
            // A running app with no windows on this display: behave like the dock and bring it forward.
            returnApplication = nil
            close(raising: nil, outcome: .app) {
                app.unhide()
                app.activate(options: [])
            }
        }
    }

    func dismiss() { close(raising: nil, outcome: .dismissed) }

    func prepareSettings() {
        prepareSettingsRoute()
        // Leave after the view has asked for the Settings window, so the request is not torn down with it.
        Task { [weak self] in self?.close(raising: nil, outcome: .interrupted, animated: false) }
    }

    // MARK: Gathering

    private func gather(displays: [DisplaySnapshot], generation: UUID, trigger: AnalyticsTrigger) async {
        defer { if self.generation == generation { gathering = nil } }
        let running = Self.runningApps()
        let apps = running.map(\.app)
        let icons = Dictionary(running.map { ($0.app.id, $0.icon) }, uniquingKeysWith: { first, _ in first })
        let screens = Self.screens(for: displays)
        let service = service
        async let discovered = service.discover(apps: apps)
        var backdrops: [String: CGImage] = [:]
        for (display, screen) in screens {
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { continue }
            backdrops[display.id] = await wallpapers.backdrop(url: url, displaySize: screen.frame.size,
                                                               scale: screen.backingScaleFactor)
        }
        let discovery = await discovered
        serviceSession = discovery.sessionID
        guard self.generation == generation, !Task.isCancelled else { return }

        let bounds = Dictionary(displays.map { ($0.id, CGDisplayBounds($0.runtimeID)) }, uniquingKeysWith: { first, _ in first })
        let runningIDs = Set(apps.map(\.id))
        var contents: [String: HarborDisplayContent] = [:]
        for display in displays {
            guard let quartz = bounds[display.id] else { continue }
            let ordered = stripOrder(display.id).filter(runningIDs.contains)
            let strip = (ordered + apps.map(\.id).filter { !ordered.contains($0) })
                .compactMap { id in apps.first { $0.id == id } }
                .map { HarborStripApp(id: $0.id, name: $0.name, processIdentifier: $0.processIdentifier) }
            let screenFrame = screens.first { $0.0.id == display.id }?.1.frame ?? display.frame
            contents[display.id] = HarborDisplayContent(
                displayID: display.id, size: display.frame.size, quartzOrigin: quartz.origin,
                stripEdge: dockEdge(display.id), wallpaper: backdrops[display.id],
                groups: HarborGrouping.groups(windows: discovery.windows, apps: apps, displayBounds: bounds,
                                              displayID: display.id),
                stripApps: strip, dockSeed: dockSeed(display.id, screenFrame))
        }
        let pointer = NSEvent.mouseLocation
        let keyDisplay = displays.first { $0.frame.contains(pointer) } ?? displays.first(where: \.isPrimary) ?? displays.first
        let workspace = NSWorkspace.shared
        session.begin(displays: contents, keyDisplayID: keyDisplay?.id, access: discovery.access, icons: icons,
                      reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
                      reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency)

        // Front windows first, so the ones most likely to be looked at fly with real content.
        let requests = captureRequests(screens: screens)
        let captures = Task { [weak self] in
            guard let self else { return }
            await capture(requests, generation: generation)
        }
        capturing = captures

        // The panels go up now, before the thumbnails are in: the desktop starts dimming and the
        // dock starts transforming at once, and each thumbnail lands over its own window while
        // that window is still mostly visible beneath it.
        for display in displays {
            guard let screen = screens.first(where: { $0.0.id == display.id })?.1 else { continue }
            let panel = HarborPanelController(displayID: display.id, screenFrame: screen.frame, session: session, intents: self)
            panels[display.id] = panel
        }
        panels.forEach { id, panel in panel.show(key: id == keyDisplay?.id) }
        NSApp.activate()
        if let id = keyDisplay?.id { panels[id]?.show(key: true) }
        installMonitors()
        let windowCount = contents.values.reduce(0) { $0 + $1.groups.reduce(0) { $0 + $1.count } }
        let appCount = Set(contents.values.flatMap { $0.groups.map(\.id) }).count
        Analytics.track(.harborOpened(trigger: trigger, windowCount: windowCount, appCount: appCount,
                                      displayCount: displays.count, access: AnalyticsHarborAccess(discovery.access)))
        // Let the panels draw once with the backdrop clear and the strip in the dock's shape, so
        // both have a start state to animate from.
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(16))
        guard self.generation == generation else { return }
        let dimStart = ContinuousClock.now
        withAnimation(session.reduceMotion ? HarborStyle.fade : HarborStyle.backdropIn) { session.showBackdrop() }

        // Fly when the thumbnails are in or the wait is over, whichever is first, but never before
        // the backdrop has covered the desktop: a thumbnail leaving a still-visible window would
        // show that window behind it.
        let wait = Self.thumbnailWait
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await captures.value }
            group.addTask { try? await Task.sleep(for: wait) }
            await group.next()
            group.cancelAll()
        }
        let elapsed = ContinuousClock.now - dimStart
        if elapsed < HarborStyle.backdropLead {
            try? await Task.sleep(for: HarborStyle.backdropLead - elapsed)
        }
        guard self.generation == generation, !Task.isCancelled else { return }
        withAnimation(session.reduceMotion ? HarborStyle.fade : HarborStyle.motion) { session.reveal() }
    }

    private func captureRequests(screens: [(DisplaySnapshot, NSScreen)]) -> [(UUID, CGWindowID, CGSize)] {
        var requests: [(UUID, CGWindowID, CGSize, Int)] = []
        for (display, screen) in screens {
            guard let content = session.displays[display.id] else { continue }
            let scale = screen.backingScaleFactor
            for group in content.groups {
                for window in group.windows {
                    guard let number = window.captureID, let rect = content.layout.windows[window.id] else { continue }
                    // Large enough to stay sharp at the grid size with hover lift, never larger than the window.
                    let budget = CGSize(width: min(window.frame.width, rect.width * 1.5) * scale,
                                        height: min(window.frame.height, rect.height * 1.5) * scale)
                    requests.append((window.id, number, budget, window.stackOrder))
                }
            }
        }
        return requests.sorted { $0.3 < $1.3 }.map { ($0.0, $0.1, $0.2) }
    }

    /// Captures thumbnails a few at a time and publishes each one as it lands.
    private func capture(_ requests: [(UUID, CGWindowID, CGSize)], generation: UUID) async {
        let service = service
        await withTaskGroup(of: (UUID, CGImage?).self) { group in
            var next = 0
            func enqueue() {
                guard next < requests.count else { return }
                let (id, number, pixels) = requests[next]
                next += 1
                group.addTask { (id, await service.thumbnail(number, fittingPixels: pixels)) }
            }
            for _ in 0..<Self.captureConcurrency { enqueue() }
            while let (id, image) = await group.next() {
                guard self.generation == generation, !Task.isCancelled else { group.cancelAll(); return }
                if let image {
                    if session.showsGrid {
                        // Landing after the flight: fade in over the placeholder in the grid.
                        withAnimation(HarborStyle.fade) { session.setThumbnail(image, for: id) }
                    } else {
                        // Landing before it: appear at once, exactly over the real window. Any
                        // animation here would also slide the tile from its grid slot.
                        var snap = Transaction()
                        snap.disablesAnimations = true
                        withTransaction(snap) { session.setThumbnail(image, for: id) }
                    }
                }
                enqueue()
            }
        }
    }

    // MARK: Helpers

    private func bringForward(_ window: HarborWindow) {
        expectedActivations += 1
        let service = service
        Task { [weak self] in
            defer { self?.expectedActivations -= 1 }
            if window.state == .hidden { NSRunningApplication(processIdentifier: window.processIdentifier)?.unhide() }
            if let token = window.token, (try? await service.raise(token)) != nil { return }
            if let app = NSRunningApplication(processIdentifier: window.processIdentifier) {
                app.unhide()
                app.activate(options: [])
            }
        }
    }

    private func reclaimKey() {
        guard session.showsGrid, let id = session.keyDisplayID else { return }
        panels[id]?.reclaimKey()
    }

    private func actionDisplays() -> [WindowActionDisplay] {
        displays().map { display in
            let quartz = CGDisplayBounds(display.runtimeID)
            return WindowActionDisplay(id: display.id, runtimeID: display.runtimeID, name: display.name,
                                       frame: quartz, usable: quartz)
        }
    }

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, panels.values.contains(where: { $0.owns(event.window) }) else { return event }
            return handleKey(event) ? nil : event
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                            queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                // Command-Tab or a notification click moved on; Harbor must not cover the new app.
                guard let self, self.expectedActivations == 0, pid != ProcessInfo.processInfo.processIdentifier else { return }
                self.close(raising: nil, outcome: .interrupted)
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close(raising: nil, outcome: .interrupted, animated: false) }
        })
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
    }

    /// Escape, Return, and arrows. Other keys reach the search field.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard session.showsGrid else { return true }
        switch event.keyCode {
        case 53: // Escape steps back: search, then app filter, then Harbor itself.
            if !session.query.isEmpty {
                report.searched = true
                withAnimation(HarborStyle.motion) { session.query = "" }
            } else if session.appFilter != nil {
                withAnimation(HarborStyle.motion) { session.clearFilter() }
            } else {
                dismiss()
            }
            return true
        case 36, 76:
            if let id = session.selected ?? session.hovered ?? session.keyboardOrder.first { activate(id) }
            return true
        case 125: session.moveSelection(.down); return true
        case 126: session.moveSelection(.up); return true
        case 123, 124:
            // Left and Right edit the search text until a window is selected.
            guard session.query.isEmpty || session.selected != nil else { return false }
            session.moveSelection(event.keyCode == 123 ? .left : .right)
            return true
        default:
            return false
        }
    }

    private static func screens(for displays: [DisplaySnapshot]) -> [(DisplaySnapshot, NSScreen)] {
        displays.compactMap { display in
            NSScreen.screens.first { screen in
                (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                    == display.runtimeID
            }.map { (display, $0) }
        }
    }

    private static func appID(_ app: NSRunningApplication) -> String {
        app.bundleIdentifier ?? app.bundleURL?.standardizedFileURL.path ?? "pid:\(app.processIdentifier)"
    }

    private static func runningApps() -> [(app: HarborRunningApp, icon: NSImage)] {
        let own = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, !app.isTerminated, app.processIdentifier != own else { return nil }
            let running = HarborRunningApp(id: appID(app), name: app.localizedName ?? "",
                                           processIdentifier: app.processIdentifier, isHidden: app.isHidden,
                                           isActive: app.isActive)
            return (running, app.icon ?? NSWorkspace.shared.icon(for: .application))
        }
    }
}
