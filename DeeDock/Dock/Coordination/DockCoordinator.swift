import AppKit
import Observation

/// Application lifetime owner for display reconciliation, global pointer events, and exclusive keyboard focus.
@MainActor @Observable
final class DockCoordinator {
    let focusSession = FocusSessionController()
    let focusBreathing = FocusBreathingStore.shared
    let localHistory = DockLocalHistoryStore()
    let pinWeather = PinWeatherStore()
    let clipboardMuseum = ClipboardMuseumController()
    let sims = DockSimsStore()
    let timeline: DockTimelineController
    @ObservationIgnored private let focusPopover: FocusSessionCoordinator
    let actionTiles = ActionTilesController()
    let fileDestinations = LauncherFileDestinationsStore()
    let patchBay: PatchBayController
    let recipes: WorkspaceRecipeCoordinator
    @ObservationIgnored private lazy var recipeProgress = WorkspaceRecipeProgressController(recipes: recipes)
    let watchPresets = WindowWatchPresetStore()
    let settings: DockSettingsStore
    let profiles: DisplayProfilesStore
    let atmosphere = AtmosphereController()
    let discovery = DiscoveryController()
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
    #if DIRECT_DISTRIBUTION
    /// Shared with the updater so every dock can draw the waiting-update pip.
    var updateAwareness: UpdateAwarenessStore? {
        didSet { refreshPanels() }
    }

    /// Main-display screen for the update callout. Falls back to `NSScreen.main`.
    var primaryEnabledScreen: NSScreen? {
        let primary = enabledDisplays.first(where: \.isPrimary) ?? enabledDisplays.first
        guard let primary else { return NSScreen.main }
        return NSScreen.screens.first { screen in
            let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            return number == primary.runtimeID
        } ?? NSScreen.main
    }

    /// Strict idle-install gates plus picker, popover, and menu tracking.
    var updateIdleGate: UpdateIdleGate {
        UpdateIdleGate(
            isDragging: dragging.isDragging,
            isFocusSessionPanelOpen: focusPopover.isOpen,
            isFilePickerActive: filePicker.isActive,
            isPopoverOpen: popovers.isOpen,
            isMenuTracking: panels.values.contains(where: \.isMenuTracking),
            secondsSinceInput: UpdateIdleGate.secondsSinceLastInput()
        )
    }

    /// Hides the main-display callout while the pointer is in a dock interaction.
    var isUpdateAwarenessBlocked: Bool {
        dragging.isDragging || focusPopover.isOpen || filePicker.isActive || popovers.isOpen
            || panels.values.contains(where: \.isMenuTracking)
    }
    #endif
    @ObservationIgnored private let dragging = DockDragCoordinator()
    @ObservationIgnored private let popovers = DockPopoverPresenter()
    @ObservationIgnored private let folderStacks: FolderStackCoordinator
    @ObservationIgnored private let shelves: ShelfCoordinator
    @ObservationIgnored private let fusion: FusionCoordinator
    @ObservationIgnored private let sessionCapsules: SessionCapsuleCoordinator
    @ObservationIgnored private let shelfSemanticWarmup: ShelfSemanticWarmupController
    @ObservationIgnored private let filePicker = DockFilePickerController(makePicker: { DockNativeFilePicker() })
    private let badges = DockBadgeController()
    var badgeMemory: BadgeMemoryStore { badges.memory }
    @ObservationIgnored private lazy var badgeMemoryWindow = BadgeMemoryWindowController(memory: badges.memory)
    @ObservationIgnored private let catalog: ApplicationCatalog
    var launcherSuggestions: LauncherSuggestionsStore { catalog.suggestions }
    var launcherApplications: [LauncherApplication] { catalog.launcherLibrary.applications }
    var recipeApplications: any ApplicationServicing { catalog.service }
    @ObservationIgnored private let trash = TrashController()
    @ObservationIgnored private let shelf = ShelfController()
    @ObservationIgnored private let capsules = SessionCapsuleController()
    @ObservationIgnored private let searchShortcut = WindowSearchShortcut()
    private(set) var searchShortcutAvailable = false
    @ObservationIgnored private lazy var windowSearch = WindowSearchController(capsules: capsules)
    @ObservationIgnored private let applicationMenus: ApplicationMenuController
    let peekHistory = PeekHistoryStore.live()
    @ObservationIgnored private let windowPeeks: WindowPeekCoordinator
    @ObservationIgnored private let modePicker = DockModePickerCoordinator()
    @ObservationIgnored private let displayService = DisplayService()
    @ObservationIgnored private let occupancy = DisplayApplicationOccupancy()
    @ObservationIgnored private var panels: [String: DockPanelController] = [:]
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var focusedID: String?
    @ObservationIgnored private var previousApplication: NSRunningApplication?
    @ObservationIgnored private var lastExternalApplication: NSRunningApplication?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var reconciling = false
    @ObservationIgnored private var occupancySuspended = false

    init(windowAccess: WindowAccessController, screenCapture: ScreenCaptureAccessController) {
        let settings = DockSettingsStore(repository: DockSettingsRepository())
        self.settings = settings
        profiles = DisplayProfilesStore(defaults: settings, repository: DisplayProfilesRepository(),
                                         modesRepository: DockModesRepository())
        patchBay = PatchBayController(profiles: profiles)
        let applicationService = ApplicationService()
        catalog = ApplicationCatalog(service: applicationService, launcherHistory: LauncherHistory(),
                                     suggestions: LauncherSuggestionsStore())
        recipes = WorkspaceRecipeCoordinator(applications: catalog.service, actions: actionTiles)
        let menus = ApplicationMenuController(
            access: windowAccess,
            applications: ApplicationMenuService(applications: applicationService),
            windows: AccessibilityApplicationWindowService()
        )
        applicationMenus = menus
        windowPeeks = WindowPeekCoordinator(menus: menus, screenCapture: screenCapture, applications: catalog.service,
                                            watchPresets: watchPresets, actions: actionTiles, history: peekHistory)
        let semanticStacks = CoalescingSemanticStackOrganizer(
            base: FoundationModelsSemanticStackOrganizer()
        )
        timeline = DockTimelineController(history: localHistory)
        focusPopover = FocusSessionCoordinator(focus: focusSession, presenter: popovers)
        folderStacks = FolderStackCoordinator(presenter: popovers, organizer: semanticStacks)
        fusion = FusionCoordinator(shelf: shelf)
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
        timeline.applyPreview = { [weak self] id, pins in
            self?.panels[id]?.store.applyTimelinePreview(pins)
        }
        timeline.clearPreview = { [weak self] id in
            self?.panels[id]?.store.clearTimelinePreview()
        }
        localHistory.replayEnabledDidChange = { [weak self] in
            self?.timeline.replayPreferenceDidChange()
        }
        timeline.onEnd = { [weak self] in
            self?.panels.values.forEach { $0.refreshLayout() }
            self?.endFocus(restore: true)
        }
    }

    func start() {
        guard !started else { return }
        started = true
        atmosphere.start()
        occupancy.changed = { [weak self] in self?.refreshPanels() }
        actionTiles.changed = { [weak self] in self?.refreshPanels() }
        actionTiles.start()
        fileDestinations.start()
        recipes.didChange = { [weak self] in
            guard let self, recipes.run != nil else { return }
            recipeProgress.show()
        }
        recipeProgress.openSettings = { [weak self] in self?.settingsModesRequest = true }
        watchPresets.start()
        badges.focusSession = { [weak self] in self?.focusSession.session }
        focusPopover.showDigest = { [weak self] in self?.showBadgeMemory(digest: true) }
        focusPopover.saveCapsule = { [weak self] panel in self?.sessionCapsules.beginFromFocus(on: panel) }
        focusPopover.keyboardDismissed = { [weak self] id in
            guard let self, focusedID == id else { return }
            endFocus(restore: false)
        }
        focusSession.start()
        focusBreathing.start()
        localHistory.start(session: focusSession.session)
        pinWeather.start()
        clipboardMuseum.start()
        clipboardMuseum.didUse = { [weak self] in self?.discovery.markUsed(.clipboardMuseum) }
        if clipboardMuseum.store.captureEnabled || !clipboardMuseum.store.exhibits.isEmpty {
            discovery.markUsed(.clipboardMuseum)
        }
        discovery.interactionBlocked = { [weak self] in
            guard let self else { return true }
            return !canSwitchModes || popovers.isOpen || focusedID != nil || focusSession.isActive
        }
        discovery.targetScreen = { [weak self] in
            guard let self else { return nil }
            let screens = NSScreen.screens.filter { screen in
                let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                return self.enabledDisplays.contains { $0.runtimeID == id }
            }
            return screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? screens.first
        }
        discovery.openDestination = { [weak self] destination in
            switch destination { case .clipboardMuseum: self?.showClipboardMuseum() }
        }
        discovery.start()
        sims.start()
        DeprecatedFeaturesRetirement.disableEnabledFlags(
            sims: sims,
            focusBreathing: focusBreathing,
            focusSession: focusSession,
            pinWeather: pinWeather,
            quarantine: .shared,
            patchBay: patchBay
        )
        badgeMemory.start(session: focusSession.session)
        focusSession.changed = { [weak self] in
            guard let self else { return }
            localHistory.noteSession(focusSession.session)
            badgeMemory.synchronize(session: focusSession.session)
            refreshPanels()
        }
        rememberExternal(NSWorkspace.shared.frontmostApplication)
        dragging.openSpringFolder = { [weak self] folder, panel in
            self?.folderStacks.show(folder, on: panel, keyboard: false, spring: true)
        }
        dragging.dropInFolder = { [weak self] info, folder, panel in
            self?.folderStacks.receive(info, folder: folder, on: panel) ?? false
        }
        dragging.documentHoverChanged = { [weak self] item, panel, documents in
            self?.windowPeeks.hoverFiles(item, on: panel, documents: documents)
        }
        dragging.deliverToLauncher = { [weak self] documents, panel in
            self?.popovers.closeAll()
            panel.openLauncher(files: .owned(documents, source: .drop))
        }
        shelves.useInLauncher = { [weak self] adoption, panel in
            self?.popovers.closeAll()
            panel.openLauncher(files: adoption)
        }
        dragging.chooseDocumentDestination = { [weak self] documents, item, panel in
            guard let self, item.isRunning,
                  panel.windowPeekContext(for: item.id)?.settings.windowPeekEnabled == true else {
                panel.store.errorMessage = .fileRouteDestinationUnavailable
                return
            }
            guard documents.urls.count <= WindowFileHandoffController.maximumFiles else {
                panel.store.errorMessage = .fileRouteInvalid
                return
            }
            windowPeeks.showKeyboard(item, on: panel, documents: documents)
        }
        dragging.magnetismEnabled = { [weak self] in self?.settings.value.magneticEdges ?? true }
        dragging.springDragEnded = { [weak self] in
            self?.folderStacks.dragEnded()
            self?.windowPeeks.endFileDrag()
        }
        windowPeeks.actionDisplays = { [weak self] in self?.profiles.displays ?? [] }
        windowPeeks.validatedFileDrop = { [weak self] in self?.dragging.peekDocuments($0) }
        windowPeeks.fileDropAccepted = { [weak self] in self?.dragging.cancel() }
        windowPeeks.fileDragEnded = { [weak self] in self?.dragging.externalEnded() }
        windowPeeks.chooseFiles = { [weak self] item, panel in
            self?.openFiles(for: item, on: panel, routeThroughPeek: true)
        }
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
        windowPeeks.addToFusion = { [weak self] window, panel, keyboard in
            self?.fusion.show(from: panel, keyboard: keyboard, matching: window)
        }
        fusion.restoreDockFocus = { [weak self] panel in
            guard let self, panels[panel.store.displayID] === panel else { return }
            endFocus(restore: false)
            previousApplication = lastExternalApplication
            focusedID = panel.store.displayID
            panel.focus()
        }
        windowPeeks.prepareSettings = { [weak self] _ in
            self?.settingsFeaturesRequest = true
        }
        catalog.didChange = { [weak self] in self?.occupancy.invalidate(); self?.refreshPanels() }
        trash.didChange = { [weak self] in self?.refreshPanels() }
        // One shared Shelf: an edit on any display re-renders every dock and the open panel.
        shelf.didChange = { [weak self] in
            self?.scheduleShelfSemanticWarmup()
            self?.shelves.reload()
            self?.refreshPanels()
        }
        capsules.didChange = { [weak self] in
            self?.sessionCapsules.reload()
            self?.windowSearch.reloadCapsules()
            self?.refreshPanels()
        }
        catalog.activated = { [weak self] app in
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            if app.bundleIdentifier == "com.apple.finder" { self?.trash.refreshAfterFinderActivity() }
            self?.rememberExternal(app)
            self?.occupancy.invalidate()
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
        displayService.didChange = { [weak self] in
            self?.occupancySuspended = false
            self?.reconcile($0)
        }
        catalog.suggestions.modeProvider = { [weak self] in self?.profiles.modes.activeMode.id.uuidString }
        catalog.start()
        trash.start()
        shelf.start()
        capsules.start()
        searchShortcutAvailable = searchShortcut.start { [weak self] in self?.searchWindows() }
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
                self?.occupancySuspended = true
                self?.occupancy.stop()
                self?.dragging.cancel()
                self?.shelfSemanticWarmup.cancel()
                self?.fusion.suspend()
                self?.timeline.end()
                self?.popovers.closeAll()
                self?.windowPeeks.dismissFileHandoff()
                self?.windowPeeks.close(returnFocus: false)
                self?.modePicker.close(returnFocus: false)
                self?.applicationMenus.cancelAllDiscoveries()
                self?.patchBay.stop()
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
        occupancy.invalidate()
        if resetVisibility {
            dragging.cancel()
            modePicker.close(returnFocus: false)
        }
        reconciling = true
        defer { reconciling = false }
        profiles.synchronize(displays) { catalog.service.defaultFavorites() }
        patchBay.reconcile()
        atmosphere.update(displays: displays)
        enabledDisplays = DisplayPolicy.enabled(displays) { profiles.document.profiles[$0]?.enabled == true }
        let desired = Set(enabledDisplays.map(\.id))
        for id in Array(panels.keys) where !desired.contains(id) {
            filePicker.cancel(for: id)
            folderStacks.close(for: id, returnFocus: false)
            shelves.close(for: id, returnFocus: false)
            focusPopover.close(for: id)
            sessionCapsules.close(for: id, returnFocus: false)
            if focusedID == id { endFocus(restore: true) }
            if timeline.displayID == id { timeline.end() }
            panels.removeValue(forKey: id)?.stop()
        }
        for display in enabledDisplays where panels[display.id] == nil {
            let store = DockStore(displayID: display.id, catalog: catalog, profiles: profiles,
                                  trash: trash, shelf: shelf, capsules: capsules, actions: actionTiles,
                                  focusSession: focusSession, history: localHistory, pinWeather: pinWeather)
            let panel = DockPanelController(store: store, settings: profiles.effectiveSettings(for: display.id))
            configureLauncherSearch(on: panel)
            panel.launcher.fileActions.configure(destinations: fileDestinations, actions: actionTiles, catalog: catalog)
            panel.launcher.suggestionModeID = { [weak self] in self?.profiles.modes.activeMode.id.uuidString }
            panel.launcher.suggestionVisibility = { [weak self] in
                self?.profiles.modes.effectiveVisibility(for: display.id) ?? .showAll
            }
            panel.interaction.actionTiles = actionTiles
            panel.interaction.timeline = timeline
            panel.interaction.pinWeather = pinWeather
            panel.interaction.focusBreathing = focusBreathing
            panel.interaction.focusSession = focusSession
            panel.interaction.dockModes = profiles.modes
            panel.interaction.sims = sims
            store.openFocusSession = { [weak self, weak panel] in
                guard let self, let panel else { return }
                focusPopover.toggle(on: panel)
            }
            panel.interaction.openFocusSession = store.openFocusSession
            panel.resignedFocus = { [weak self] in
                guard let self else { return }
                if focusedID == display.id, !folderStacks.isKeyboardActive, !shelves.isOpen, !windowPeeks.isKeyboardActive,
                   !sessionCapsules.isOpen, !focusPopover.isOpen, !modePicker.isKeyboardActive {
                    endFocus(restore: false)
                }
            }
            panel.launcherWillOpen = { [weak self, weak panel] in
                guard let self, let panel else { return nil }
                let previous = previousApplication ?? lastExternalApplication
                popovers.closeAll()
                windowPeeks.close(returnFocus: false)
                modePicker.close(returnFocus: false)
                timeline.end()
                endFocus(restore: false)
                for other in panels.values where other !== panel { other.closeLauncher() }
                return previous
            }
            panel.exclusiveInteractionBegan = { [weak self] in
                guard let self else { return }
                // Document Peek is part of this drag, so dock feedback must not dismiss it
                // on every native draggingUpdated callback.
                if !dragging.isDragging || !windowPeeks.isFileDragActive {
                    windowPeeks.close(returnFocus: false)
                }
                modePicker.close(returnFocus: false)
            }
            panel.windowSearchRequested = { [weak self] in self?.searchWindows() }
            panel.modePickerRequested = { [weak self, weak panel] in
                guard let self, let panel, canSwitchModes else { return }
                modePicker.show(modes: profiles.modes.modes,
                                activeModeID: profiles.modes.document.activeModeID,
                                on: panel,
                                choose: { [weak self] id in self?.activateMode(id) ?? false },
                                prepare: { [weak self] id in
                                    guard let self, let mode = profiles.modes.modes.first(where: { $0.id == id }) else { return }
                                    prepareWorkspace(mode)
                                })
            }
            panel.timelineRequested = { [weak self] in self?.browseLocalHistory() }
            panel.escape = { [weak self] in
                guard let self else { return }
                if timeline.isActive { timeline.end() }
                else { endFocus(restore: true) }
            }
            store.applicationOpened = { [weak self] in
                self?.windowPeeks.close(returnFocus: false)
                if self?.focusedID == display.id { self?.endFocus(restore: false) }
            }
            store.patchBayAppOpened = { [weak self] appID, modeID in
                self?.patchBay.appOpened(appID, displayID: display.id, modeID: modeID)
            }
            store.soapBubblePlay = { [weak panel] itemID in
                panel?.interaction.soapBubbles.play(
                    itemID: itemID,
                    reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                )
            }
            panel.connectDragging(dragging)
            panel.interaction.openFiles = { [weak self, weak panel] item in
                guard let self, let panel else { return }
                self.openFiles(for: item, on: panel)
            }
            panel.interaction.openBadgeMemory = { [weak self] item in
                self?.showBadgeMemory(path: (item.resolvedURL ?? item.reference.url).standardizedFileURL.path)
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
                guard !dragging.isDragging else { return }
                windowPeeks.hover(item, on: panel)
            }
            panel.interaction.openWindowPeek = { [weak self, weak panel] item in
                guard let self, let panel else { return }
                windowPeeks.showKeyboard(item, on: panel)
            }
            panel.interaction.openFolder = { [weak self, weak panel] folder, keyboard in
                guard let self, let panel, panels[display.id] === panel else { return }
                if !folder.isDownloads { pinWeather.recordUse(folder.id) }
                folderStacks.show(folder, on: panel, keyboard: keyboard)
            }
            panel.interaction.revealFolder = { [weak self, weak panel] folder in
                guard folder.isAvailable else { return }
                if !folder.isDownloads { self?.pinWeather.recordUse(folder.id) }
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
            panel.interaction.canPasteToShelf = { [weak self] in
                self?.shelves.canPaste == true
            }
            panel.interaction.pasteToShelf = { [weak self, weak panel] in
                guard let self, let panel, panels[display.id] === panel else { return }
                shelves.paste(on: panel)
            }
            panel.interaction.beginShelfDrag = { [weak self, weak panel] view, event in
                guard let self, let panel, panels[display.id] === panel else { return }
                shelves.beginTileDrag(from: view, event: event, on: panel)
            }
            panel.interaction.prepareSettings = { [weak self] in
                guard let self else { return }
                settingsDisplayRequest = profiles.displays.count > 1
                    && profiles.displays.contains(where: { $0.id == display.id }) ? display.id : nil
            }
            panel.launcher.createCapsule = { [weak self, weak panel] application in
                guard let self, let panel, panels[display.id] === panel else { return }
                panel.closeLauncher()
                sessionCapsules.beginFromApplication(application, on: panel)
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
            panel.store.willMutateFavoriteIDs = { [weak self] ids in
                self?.dragging.forgetPlacements(ids, on: id)
            }
        }
        refreshPanels(resetVisibility: resetVisibility)
    }

    private func refreshPanels(resetVisibility: Bool = false) {
        guard started else { return }
        // If the primary dock is disabled, keep the remaining docks complete.
        let satelliteMode = settings.value.secondaryDisplayAppsOnly
            && enabledDisplays.count > 1 && enabledDisplays.contains(where: \.isPrimary)
        badges.configure(enabled: settings.value.showAppBadges && !enabledDisplays.isEmpty)
        occupancy.configure(enabled: satelliteMode && !occupancySuspended)
        dragging.applyMagneticPinHiding()
        for display in enabledDisplays {
            guard let panel = panels[display.id] else { continue }
            panel.interaction.badges = badges
            panel.interaction.sims = sims
            #if DIRECT_DISTRIBUTION
            panel.interaction.updateAwareness = updateAwareness
            #endif
            panel.store.visibleApplicationIDs = satelliteMode && !display.isPrimary
                ? occupancy.applications?[display.runtimeID] : nil
            panel.store.refresh()
            panel.update(display: display, settings: profiles.effectiveSettings(for: display.id), resetVisibility: resetVisibility)
        }
        folderStacks.reanchor()
        shelves.reanchor()
        focusPopover.reanchor()
        sessionCapsules.reanchor()
        windowPeeks.refresh()
        if let id = zonePreview.displayID {
            if let geometry = panels[id]?.geometry { zonePreview.update(geometry) }
            else { zonePreview.stop() }
        }
        catalog.pruneIcons(items: panels.values.flatMap { $0.store.items },
                           folders: panels.values.flatMap { $0.store.folders })
        pinWeather.synchronize(pinIDs: Set(profiles.pinLists.values.flatMap { $0.map(\.id) }))
        dragging.syncMagneticChrome()
    }
    private func updatePointers(eventType: NSEvent.EventType) {
        let wasOverDock = panels.values.contains { $0.interaction.pointer != nil }
        panels.values.forEach { $0.updatePointer(eventType: eventType) }
        windowPeeks.updatePointer()
        if !wasOverDock, panels.values.contains(where: { $0.interaction.pointer != nil }) {
            trash.refreshForDockAttention()
        }
    }

    /// Only connected enabled desktop surfaces have a live zone to outline.
    func showZone(for id: String) {
        guard let geometry = panels[id]?.geometry else { return }
        zonePreview.show(displayID: id, geometry: geometry)
    }
    /// Explicit picker activation captures focus before AppKit resigns the dock's key panel.
    private func openFiles(for item: DockItem, on panel: DockPanelController, routeThroughPeek: Bool = false) {
        guard item.isAvailable, panels[panel.store.displayID] === panel else { return }
        windowPeeks.close(returnFocus: false)
        let id = panel.store.displayID
        let selection = panel.store.keyboardFocus ? panel.store.selectedTarget : nil
        let previous = previousApplication ?? lastExternalApplication
        filePicker.show(reference: item.reference, displayID: id,
            hold: { [weak panel] in panel?.holdFilePicker($0) },
            submit: { [weak self, weak panel] documents, reference in
                guard let self, let panel, panels[id] === panel else { return }
                if routeThroughPeek {
                    guard documents.urls.count <= WindowFileHandoffController.maximumFiles else {
                        panel.store.errorMessage = .fileRouteInvalid
                        return
                    }
                    windowPeeks.showKeyboard(item, on: panel, documents: documents)
                } else { panel.store.openDocuments(documents, with: reference) }
            },
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

    func focusNextPortal() { windowPeeks.focusNextPortal() }

    /// Opens metadata search only after a menu or keyboard action.
    func searchWindows() {
        popovers.closeAll()
        windowPeeks.close(returnFocus: false)
        timeline.end()
        endFocus(restore: false)
        windowSearch.show(returningTo: lastExternalApplication)
    }

    func focusDock() {
        guard let id = DisplayPolicy.focusTarget(displays: enabledDisplays, pointer: NSEvent.mouseLocation), let panel = panels[id] else { return }
        endFocus(restore: false)
        previousApplication = lastExternalApplication
        focusedID = id
        panel.focus()
    }

    var canBrowseLocalHistory: Bool { canFocus }

    /// Reveals the dock under the pointer and treats its chrome as a local-history time axis.
    func browseLocalHistory() {
        guard let id = DisplayPolicy.focusTarget(displays: enabledDisplays, pointer: NSEvent.mouseLocation),
              panels[id] != nil else { return }
        if timeline.isActive(on: id) {
            timeline.end()
            return
        }
        popovers.closeAll()
        windowPeeks.close(returnFocus: false)
        modePicker.close(returnFocus: false)
        endFocus(restore: false)
        previousApplication = lastExternalApplication
        focusedID = id
        let pins = panels[id]?.store.persistedPins ?? []
        timeline.begin(on: id, currentPins: pins, archive: localHistory.pinArchive)
        panels[id]?.refreshLayout()
        panels[id]?.focus()
    }

    var canStartFocus: Bool { canSwitchModes && !focusSession.isActive && !focusSession.requiresReset }
    /// Prepare stays available so a blocked drag or menu can be reported before any side effect.
    var canPrepareWorkspace: Bool { profiles.modes.canEdit }

    func startFocus(_ mode: DockMode) {
        guard canStartFocus, let current = profiles.modes.modes.first(where: { $0.id == mode.id }) else { return }
        // Activating the already-active mode is a no-op in DockModesStore, not a failed start.
        if current.id != profiles.modes.document.activeModeID, !activateMode(current.id) { return }
        focusSession.begin(modeID: current.id, name: current.name)
    }

    func prepareWorkspace(_ mode: DockMode) {
        guard let current = profiles.modes.modes.first(where: { $0.id == mode.id }) else { return }
        recipes.prepare(mode: current, canActivate: canSwitchModes) { [weak self] id in
            guard let self else { return false }
            if id == profiles.modes.document.activeModeID { return true }
            return activateMode(id)
        }
        if recipes.run != nil { recipeProgress.show() }
    }

    /// Called only from a badge click, menu/keyboard command, Settings or the Focus panel.
    func showBadgeMemory(path: String? = nil, digest: Bool = false) {
        popovers.closeAll()
        windowPeeks.close(returnFocus: false)
        modePicker.close(returnFocus: false)
        endFocus(restore: false)
        badgeMemory.synchronize(session: focusSession.session)
        badgeMemoryWindow.show(path: path, digest: digest, returningTo: lastExternalApplication)
    }

    /// Called only from a menu command or Settings. Never opened by hover or a clipboard change.
    func showClipboardMuseum() {
        popovers.closeAll()
        windowPeeks.close(returnFocus: false)
        modePicker.close(returnFocus: false)
        endFocus(restore: false)
        clipboardMuseum.show(returningTo: lastExternalApplication)
    }

    /// Shared search borrows stored metadata; native actions stay with the same owners as the dock tiles.
    private func configureLauncherSearch(on panel: DockPanelController) {
        let search = panel.launcher.search
        search.shelf = shelf; search.capsules = capsules; search.actions = actionTiles; search.modes = profiles.modes
        search.explicitSearch = { [weak self, weak panel] in
            panel?.closeLauncher()
            self?.searchWindows()
        }
        search.dispatch = { [weak self, weak panel] result, reveal in
            guard let self, let panel else { return }
            let launcher = panel.launcher
            let search = launcher.search
            switch result.id {
            case .application(let id):
                guard let app = launcher.library.applications.first(where: { $0.id == id }) else {
                    search.actionError = String(localized: .unifiedStale); return
                }
                if reveal { launcher.showInFinder(app) } else { launcher.open(app) }
            case .window:
                guard let source = result.window else { return }
                search.activateWindow(source) { [weak panel] in panel?.launcher.didOpen?() }
            case .capsule(let id):
                guard capsules.capsules.contains(where: { $0.id == id }) else {
                    search.actionError = String(localized: .unifiedStale); return
                }
                panel.closeLauncher()
                sessionCapsules.show(id, on: panel, anchor: .launcher)
            case .shelf(let id):
                search.performOwnedAction({ [shelves] completion in
                    shelves.openReference(id, reveal: reveal, completion: completion)
                }, completion: { [weak panel] in panel?.launcher.didOpen?() })
            case .shortcut(let id):
                guard actionTiles.run(id) else {
                    search.actionError = String(localized: .unifiedShortcutUnavailable); return
                }
                // Keep completion or failure visible. The action owner enforces one run per UUID.
            case .mode(let id):
                guard profiles.modes.modes.contains(where: { $0.id == id }), activateMode(id) else {
                    search.actionError = String(localized: .unifiedModeUnavailable); return
                }
                launcher.close?()
            }
        }
    }

    @discardableResult
    func activateMode(_ id: UUID) -> Bool {
        guard canSwitchModes else { return false }
        popovers.closeAll()
        windowPeeks.close(returnFocus: false)
        modePicker.close(returnFocus: false)
        timeline.end()
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
        if recipes.run?.modeID == id { recipes.cancel() }
        popovers.closeAll()
        windowPeeks.close(returnFocus: false)
        modePicker.close(returnFocus: false)
        timeline.end()
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

    func showFusion() { fusion.show() }

    func stop() {
        discovery.stop()
        clipboardMuseum.didUse = nil
        atmosphere.stop()
        guard started else { return }
        started = false
        occupancy.stop()
        occupancy.changed = nil
        endFocus(restore: true)
        timeline.onEnd = nil
        timeline.end()
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
        focusPopover.stop()
        focusSession.stop()
        focusBreathing.stop()
        actionTiles.stop()
        patchBay.stop()
        recipes.stop()
        recipeProgress.stop()
        watchPresets.stop()
        fusion.stop()
        sessionCapsules.stop()
        shelfSemanticWarmup.stop()
        popovers.stop()
        shelf.stop()
        searchShortcut.stop()
        windowSearch.stop()
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
        badges.stop()
        badgeMemoryWindow.stop()
        clipboardMuseum.stop()
        badges.focusSession = nil
        catalog.stop()
        trash.stop()
        #if DIRECT_DISTRIBUTION
        updateAwareness = nil
        #endif
    }
}
