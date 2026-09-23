import AppKit
import SwiftUI
import Observation

/// Owns App Fusion sessions, their exact AX handles, and all chrome/observer/task lifetimes.
@MainActor @Observable final class AppMeltController {
    private(set) var pairs: [AppMeltPair] = []
    // Group restoration can wake a minimized app. Keep its AX timeout bounded, but allow
    // more than the short discovery budget; this service runs off the UI actor.
    @ObservationIgnored let service = AccessibilityApplicationWindowService(messagingTimeout: 1)
    @ObservationIgnored var compareWindows: ((AppMeltPair, [ApplicationWindowSummary]) -> Void)?
    @ObservationIgnored var changed: (() -> Void)?
    @ObservationIgnored private lazy var proximity = AppMeltProximityController(controller: self)
    @ObservationIgnored var readDockApplication: ((NSPasteboard) -> ApplicationReference?)?
    @ObservationIgnored var finishDockApplicationDrop: (() -> Void)?
    @ObservationIgnored private var composer: NSWindow?
    @ObservationIgnored private var composerState: AppMeltSetupState?
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored var recentApplicationUse: [pid_t: Date] = [:]
    @ObservationIgnored private var displayObserver: NSObjectProtocol?

    func showSetup() {
        installObservers()
        if let composer {
            composerState?.beginPresentation()
            composer.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let state = AppMeltSetupState(controller: self)
        composerState = state
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = String(localized: .meltTitle)
        window.isReleasedWhenClosed = false
        window.delegate = state
        window.contentView = NSHostingView(rootView: AppMeltSetupView(state: state))
        window.center()
        composer = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func observePointer(_ event: NSEvent, dockDragging: Bool) {
        installObservers()
        proximity.observe(event, dockDragging: dockDragging)
    }

    func showSetup(first: URL, second: URL? = nil) {
        showSetup()
        composerState?.seed(first: first, second: second)
    }

    /// Keep the dock app on the left and the explicitly chosen partner on the right.
    func showSetup(first: URL, partner: ApplicationWindowSummary) async {
        showSetup(first: first)
        await composerState?.seedPartner(partner)
    }

    func showSetup(window: ApplicationWindowSummary) {
        guard let app = NSRunningApplication(processIdentifier: window.processIdentifier),
              let url = app.bundleURL else { return }
        showSetup()
        composerState?.seed(first: url, second: nil)
    }

    func showRecovery(_ pair: AppMeltPair) {
        showSetup()
        composerState?.createdPair = pair
    }

    /// Transfers this discovery session to a visible pair before any writes. A partial failure
    /// stays reachable through the dock and menu instead of discarding the source handles.
    func create(sessionID: UUID, windows: [ApplicationWindowSummary], names: [String], icons: [NSImage]) async throws -> AppMeltPair {
        guard windows.count == 2, names.count == 2, icons.count == 2,
              windows[0].token != windows[1].token,
              !pairs.contains(where: { pair in
                  pair.windows.contains { existing in windows.contains { $0.processIdentifier == existing.processIdentifier } }
              }),
              windows.allSatisfy({ $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }),
              !(try await service.meltOverlaps(windows.map(\.token), existing: pairs.flatMap(\.tokens))),
              let firstFrame = try await service.meltSummary(windows[0].token).frame,
              let secondFrame = try await service.meltSummary(windows[1].token).frame,
              firstFrame.width > 0, secondFrame.width > 0,
              let display = WindowPlacementPolicy.current(firstFrame.union(secondFrame), displays: AppMeltGeometry.displays)
                else { throw WindowActionError.unsupported }
        try Task.checkCancellation()
        // The service awaits above yield the main actor. Recheck app ownership immediately
        // before publishing the pair so two concurrent setup sessions cannot claim one app.
        guard !pairs.contains(where: { pair in
            pair.windows.contains { existing in
                windows.contains { $0.processIdentifier == existing.processIdentifier }
            }
        }) else { throw WindowActionError.unsupported }
        let usable = display.usable.insetBy(dx: 12, dy: 12)
        guard usable.width >= 640, usable.height >= 360 else { throw WindowActionError.constrained }
        let frame = AppMeltGeometry.initialFrame(first: firstFrame, second: secondFrame, usable: usable)
        let pair = AppMeltPair(sessionID: sessionID, windows: windows, names: names, icons: icons, frame: frame)
        pair.ratio = min(0.75, max(0.25, firstFrame.width / (firstFrame.width + secondFrame.width)))
        // Record the group before mutating so a partial AX write still has a visible recovery path.
        pairs.append(pair)
        pair.chrome = AppMeltChrome(pair: pair, controller: self)
        pair.observation.changed = { [weak self, weak pair] in
            guard let pair else { return }; self?.scheduleRefresh(pair)
        }
        changed?()
        restore(pair)
        // Creation is complete only after native placement and chrome presentation finish.
        // Keep failed groups reachable, but keep their failure visible in the composer too.
        let placementTask = pair.task
        let sealedService = service
        await withTaskCancellationHandler {
            await placementTask?.value
        } onCancel: {
            placementTask?.cancel()
            // Seal before the placement task resumes so its next AX call cannot commit
            // or reinstall observation after setup cancellation.
            sealedService.seal(sessionID: sessionID)
        }
        if Task.isCancelled { unpair(pair); throw CancellationError() }
        guard pairs.contains(where: { $0.id == pair.id }) else { throw WindowActionError.stale }
        if !pair.suspended, pair.message == nil { composer?.orderOut(nil) }
        return pair
    }

    func restore(_ pair: AppMeltPair) {
        guard pairs.contains(where: { $0.id == pair.id }), !pair.busy, !pair.invalidated else { return }
        guard let display = WindowPlacementPolicy.current(pair.frame, displays: AppMeltGeometry.displays),
              display.usable.width >= 640, display.usable.height >= 360 else {
            suspend(pair, message: .meltSizeConstraint)
            return
        }
        pair.frame.size.width = min(pair.frame.width, display.usable.width)
        pair.frame.size.height = min(pair.frame.height, display.usable.height)
        pair.frame = WindowPlacementPolicy.fit(pair.frame, into: display.usable)
        run(pair) { [self] in
            let settle = pair.observation.settleWait
            guard try await pair.observation.start(tokens: pair.layoutTokens, service: service) else {
                suspend(pair, message: .meltObservationFailed)
                return
            }
            try ensureActive(pair)
            pair.suspended = false
            for token in pair.layoutTokens {
                try await service.meltSetMinimized(false, token: token, settle: settle)
                try ensureActive(pair)
            }
            pair.minimized = false
            let accepted = try await service.meltLayout(pair.layoutTokens,
                frames: AppMeltGeometry.windows(in: pair.frame, ratio: pair.ratio), displays: AppMeltGeometry.displays,
                settle: settle)
            try ensureActive(pair)
            pair.accept(accepted)
            try await service.meltRaise(pair.layoutTokens)
            try ensureActive(pair)
            if let pid = pair.windows.first?.processIdentifier {
                NSRunningApplication(processIdentifier: pid)?.activate(options: [])
            }
            if pair.needsReveal {
                try await pair.chrome?.reveal()
                try ensureActive(pair)
                pair.needsReveal = false
            }
            else { pair.chrome?.update(show: true) }
        }
    }

    func minimize(_ pair: AppMeltPair) {
        guard !pair.busy, !pair.invalidated else { return }
        pair.finderTools?.dismiss()
        run(pair) { [self] in
            // Preflight both members. If an app rejects the second write, retain the pair and its
            // error so Restore can repair the partial minimize without losing either source.
            let settle = pair.observation.settleWait
            for token in pair.layoutTokens {
                if !(try await service.meltSummary(token).isMinimized) {
                    guard try await service.capabilities(token).canMinimize else { throw WindowActionError.unsupported }
                }
                try ensureActive(pair)
            }
            for token in pair.layoutTokens {
                try await service.meltSetMinimized(true, token: token, settle: settle)
                try ensureActive(pair)
            }
            pair.minimized = true
            pair.chrome?.hide()
        }
    }

    func close(_ pair: AppMeltPair) {
        guard !pair.busy else { return }
        pair.finderTools?.dismiss()
        run(pair) { [self] in
            pair.chrome?.hide()
            try await service.meltClose(pair.layoutTokens)
            // Save dialogs belong to the source apps. Never put our chrome in front of them.
            suspend(pair, message: .meltClosePending)
        }
    }

    /// Unpair leaves current positions and native minimized state intact, with no extra AX writes.
    /// The session is sealed before cancellation so a resumed create or replace cannot register
    /// observers or adopt handles after this returns.
    func unpair(_ pair: AppMeltPair) {
        guard pairs.contains(where: { $0.id == pair.id }) else { return }
        pair.invalidated = true
        service.seal(sessionID: pair.sessionID)
        pair.operationEpoch &+= 1
        pair.task?.cancel()
        pair.refreshPending = false
        pair.refreshTask?.cancel()
        pair.replacement?.isPresented = false
        pair.observation.stop()
        pair.observation.changed = nil
        pair.comparison?.stop()
        pair.comparison = nil
        pair.chrome?.stop()
        pair.chrome = nil
        pair.pendingFrame = nil
        pairs.removeAll { $0.id == pair.id }
        let session = pair.sessionID
        Task { await service.meltEndMove(session); await service.discard(sessionID: session) }
        changed?()
    }

    func beginDrag(_ pair: AppMeltPair) {
        guard pair.canChangeLayout else { return }
        pair.layoutPopover = false
        pair.finderTools?.invalidateLayout()
        pair.gestureStart = AppMeltLayoutSnapshot(pair)
        pair.isDragging = true
        pair.refreshPending = false
        pair.refreshTask?.cancel()
    }

    func endDrag(_ pair: AppMeltPair) {
        pair.isDragging = false
        finishGestureHistory(pair)
        guard !pair.busy else { return }
        Task { await service.meltEndMove(pair.sessionID) }
        scheduleRefresh(pair)
    }

    /// Coalesce drag requests while AX work is in flight. Never queue every mouse sample.
    func layout(_ pair: AppMeltPair, frame: CGRect? = nil) {
        guard !pair.suspended, !pair.minimized, pair.finderTools?.busy != true,
              pair.finderTools?.isChoosingFolder != true else { return }
        var requested = frame ?? pair.frame
        guard requested.width >= 640, requested.height >= 360,
              let display = WindowPlacementPolicy.current(requested, displays: AppMeltGeometry.displays),
              display.usable.width >= 640, display.usable.height >= 360 else { return }
        requested.size.width = min(requested.width, display.usable.width)
        requested.size.height = min(requested.height, display.usable.height)
        requested = WindowPlacementPolicy.fit(requested, into: display.usable)
        pair.pendingFrame = requested
        guard !pair.busy, !pair.invalidated else { return }
        pair.operationEpoch &+= 1
        pair.busy = true
        pair.refreshPending = false
        pair.refreshTask?.cancel()
        pair.task = Task { [weak self, weak pair] in
            guard let self, let pair else { return }
            while let next = pair.pendingFrame, !Task.isCancelled, !pair.invalidated {
                pair.pendingFrame = nil
                pair.frame = next
                await performLayout(pair)
                if pair.suspended || pair.invalidated { pair.pendingFrame = nil }
            }
            pair.operationEpoch &+= 1
            pair.busy = false
            pair.task = nil
            guard !pair.invalidated, pairs.contains(where: { $0.id == pair.id }) else { return }
            finishGestureHistory(pair)
            if !pair.isDragging { await service.meltEndMove(pair.sessionID) }
            // Geometry does not change dock membership. Refreshing every dock here used to
            // reload app icons and window state on every mouse sample.
            if pair.message != nil { changed?() }
            if !pair.isDragging { scheduleRefresh(pair) }
        }
    }

    private func performLayout(_ pair: AppMeltPair) async {
        do {
            try ensureActive(pair)
            let frames = AppMeltGeometry.windows(in: pair.frame, ratio: pair.ratio)
            let translationOnly = pair.acceptedFrames.count == frames.count
                && zip(pair.acceptedFrames, frames).allSatisfy { old, new in old.size == new.size }
            let accepted: [CGRect]
            if translationOnly {
                accepted = try await service.meltMove(pair.layoutTokens, sessionID: pair.sessionID, frames: frames)
            } else {
                await service.meltEndMove(pair.sessionID)
                try ensureActive(pair)
                accepted = try await service.meltLayout(pair.layoutTokens, frames: frames, displays: AppMeltGeometry.displays,
                    settle: pair.observation.settleWait)
            }
            try Task.checkCancellation()
            try ensureActive(pair)
            pair.accept(accepted)
            pair.message = nil
            pair.chrome?.update(show: true)
        } catch is CancellationError { return }
        catch { fail(pair, error: error) }
    }

    /// Owns one explicit operation until completion. Callers must gate entry on pair availability.
    func run(_ pair: AppMeltPair, operation: @escaping @MainActor () async throws -> Void) {
        guard pairs.contains(where: { $0.id == pair.id }), !pair.busy, !pair.invalidated else { return }
        pair.operationEpoch &+= 1
        pair.busy = true
        pair.message = nil
        pair.task = Task { [weak self, weak pair] in
            guard let self, let pair else { return }
            pair.showsOperationProgress = true
            var cancelled = false
            do {
                try await operation()
                try Task.checkCancellation()
                if pair.invalidated { throw CancellationError() }
            } catch is CancellationError {
                cancelled = true
                // Create-cancel seals the session before this task resumes. Drop observers and
                // chrome before busy clears so a queued notification cannot refresh the pair.
                pair.observation.stop()
                pair.chrome?.hide()
            } catch { fail(pair, error: error) }
            pair.showsOperationProgress = false
            pair.operationEpoch &+= 1
            pair.busy = false
            pair.task = nil
            guard !pair.invalidated, pairs.contains(where: { $0.id == pair.id }) else { return }
            if !cancelled, !pair.suspended, pair.message == nil, composerState?.createdPair?.id == pair.id {
                composer?.orderOut(nil)
            }
            changed?()
            if !cancelled { scheduleRefresh(pair) }
        }
    }

    func ensureActive(_ pair: AppMeltPair) throws {
        guard !pair.invalidated, pairs.contains(where: { $0.id == pair.id }) else { throw CancellationError() }
    }

    private func fail(_ pair: AppMeltPair, error: Error) {
        guard !(error is CancellationError), pairs.contains(where: { $0.id == pair.id }) else { return }
        suspend(pair, message: AppMeltFailure.message(for: error))
    }

    private func finishGestureHistory(_ pair: AppMeltPair) {
        guard !pair.isDragging, !pair.busy, let start = pair.gestureStart else { return }
        pair.gestureStart = nil
        if !pair.suspended && !AppMeltGeometry.nearlyEqual(start.frame, pair.frame) {
            pair.undoLayout = start
            pair.fittedFrom = nil
        }
    }

    private func scheduleRefresh(_ pair: AppMeltPair) {
        guard pairs.contains(where: { $0.id == pair.id }), !pair.invalidated, !pair.suspended,
              !pair.isDragging, !pair.busy, pair.task == nil else { return }
        pair.refreshPending = true
        guard pair.refreshTask == nil else { return }
        pair.refreshTask = Task { [weak self, weak pair] in
            guard let self, let pair else { return }
            await drainRefresh(pair)
        }
    }

    /// One trailing refresh per pair. Further hints set `refreshPending` instead of cancelling
    /// the in-flight read, so a burst of AX notifications cannot restart capability work forever.
    private func drainRefresh(_ pair: AppMeltPair) async {
        while pair.refreshPending, !Task.isCancelled, !pair.invalidated {
            pair.refreshPending = false
            do { try await Task.sleep(for: .milliseconds(180)) } catch { break }
            guard !Task.isCancelled, !pair.invalidated, pairs.contains(where: { $0.id == pair.id }) else { break }
            guard !pair.busy, pair.task == nil, !pair.isDragging, !pair.suspended else { continue }
            await refresh(pair, epoch: pair.operationEpoch)
        }
        pair.refreshTask = nil
        if pair.refreshPending, !Task.isCancelled, !pair.invalidated { scheduleRefresh(pair) }
    }

    private func refresh(_ pair: AppMeltPair, epoch: UInt64) async {
        do {
            var values: [ApplicationWindowSummary] = []
            for token in pair.layoutTokens { values.append(try await service.meltSummary(token)) }
            try Task.checkCancellation()
            guard refreshCanMutate(pair, epoch: epoch) else { return }
            let anyMinimized = values.contains(where: \.isMinimized)
            let anyRestored = values.contains(where: { !$0.isMinimized })
            if pair.minimized && anyRestored { restore(pair); return }
            if !pair.minimized && anyMinimized { minimize(pair); return }
            guard !anyMinimized else { return }
            let framesMatch = values.count == pair.acceptedFrames.count && values.count == 2
                && zip(values, pair.acceptedFrames).allSatisfy { value, accepted in
                    value.frame.map { AppMeltGeometry.nearlyEqual($0, accepted) } == true
                }
            if framesMatch {
                let focused = try await service.meltContainsFocusedWindow(pair.layoutTokens)
                try Task.checkCancellation()
                guard refreshCanMutate(pair, epoch: epoch) else { return }
                // Notification-driven refresh must never raise windows: AXRaise emits another
                // focus notification, which can cancel this task before its state is recorded
                // and start an endless raise/cancel cycle between members of the same app.
                // Only deliberate creation/Restore changes stacking; refresh follows user focus.
                pair.foreground = focused
                pair.chrome?.update(show: focused || ownsChromeInteraction(pair))
                return
            }
            for token in pair.layoutTokens {
                let capabilities = try await service.capabilities(token)
                try Task.checkCancellation()
                guard refreshCanMutate(pair, epoch: epoch) else { return }
                guard capabilities.canMove else {
                    suspend(pair, message: .meltSuspended)
                    return
                }
            }
            // A native title-bar drag translates the shared frame. Native resizes adjust the
            // outer size and split while keeping the other member adjacent.
            if pair.finderTools?.busy != true, pair.finderTools?.isChoosingFolder != true,
               pair.acceptedFrames.count == 2,
               let index = values.indices.first(where: { index in
                   values[index].frame.map { !AppMeltGeometry.nearlyEqual($0, pair.acceptedFrames[index]) } == true
               }),
               let actual = values[index].frame {
                try Task.checkCancellation()
                guard refreshCanMutate(pair, epoch: epoch) else { return }
                let previous = pair.acceptedFrames[index]
                var frame = pair.frame
                frame.origin.x += actual.minX - previous.minX
                frame.origin.y += actual.minY - previous.minY
                frame.size.width += actual.width - previous.width
                frame.size.height += actual.height - previous.height
                let widths = [index == 0 ? actual.width : pair.acceptedFrames[0].width,
                              index == 1 ? actual.width : pair.acceptedFrames[1].width]
                pair.ratio = min(0.75, max(0.25, widths[0] / (widths[0] + widths[1])))
                layout(pair, frame: frame)
                return
            }
            let focused = try await service.meltContainsFocusedWindow(pair.layoutTokens)
            try Task.checkCancellation()
            guard refreshCanMutate(pair, epoch: epoch) else { return }
            pair.foreground = focused
            pair.chrome?.update(show: focused || ownsChromeInteraction(pair))
        } catch is CancellationError { return }
        catch WindowActionError.stale { fail(pair, error: WindowActionError.stale) }
        catch { fail(pair, error: error) }
    }

    /// Refresh may follow focus and geometry. It must not start minimize, restore, or layout
    /// while another pair operation is still finishing or the pointer is dragging.
    private func refreshCanMutate(_ pair: AppMeltPair, epoch: UInt64) -> Bool {
        epoch == pair.operationEpoch && !pair.invalidated && !pair.busy && pair.task == nil
            && !pair.isDragging && !pair.suspended && pairs.contains(where: { $0.id == pair.id })
    }

    /// Header controls and their popovers can own key focus while the source app has no
    /// AX focused window. Keep that pair visible, but never cover a different frontmost app.
    /// Scoped panel key notifications recheck visibility when focus leaves the toolbar.
    private func ownsChromeInteraction(_ pair: AppMeltPair) -> Bool {
        guard pair.isTrackingToolbarMenu || pair.chrome?.ownsKeyWindow == true || pair.layoutPopover || pair.replacement?.isPresented == true
            || pair.finderTools?.isPresented == true
            || pair.finderTools?.isChoosingFolder == true else { return false }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return front == ProcessInfo.processInfo.processIdentifier
            || pair.windows.contains { $0.processIdentifier == front }
    }

    func refreshAfterTools(_ pair: AppMeltPair) {
        guard pairs.contains(where: { $0.id == pair.id }) else { return }
        scheduleRefresh(pair)
    }

    private func updateVisibility() {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for pair in pairs {
            let visible = !pair.minimized && !pair.suspended
                && (pair.windows.contains { $0.processIdentifier == front } || ownsChromeInteraction(pair))
            if !visible { pair.foreground = false; pair.chrome?.hide() }
            // Showing waits for exact focused-window validation in refresh().
        }
    }

    private func suspend() {
        proximity.cancel()
        for pair in pairs {
            pair.task?.cancel()
            Task { await service.meltEndMove(pair.sessionID) }
            suspend(pair, message: .meltSuspended)
        }
    }

    /// Pauses pair-owned UI and ancillary work without cancelling the operation that detected
    /// the failure. Global lifecycle suspension cancels that operation before calling here.
    private func suspend(_ pair: AppMeltPair, message: LocalizedStringResource) {
        pair.comparison?.suspend()
        pair.finderTools?.dismiss()
        pair.refreshPending = false
        pair.refreshTask?.cancel()
        pair.observation.stop()
        pair.pendingFrame = nil
        pair.gestureStart = nil
        pair.isDragging = false
        pair.suspended = true
        pair.message = message
        pair.chrome?.hide()
    }

    private func installObservers() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if name == NSWorkspace.didActivateApplicationNotification,
                       let app = NSWorkspace.shared.frontmostApplication {
                        self?.recentApplicationUse[app.processIdentifier] = Date()
                    }
                    self?.updateVisibility()
                    self?.pairs.forEach { self?.scheduleRefresh($0) }
                }
            })
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspend() }
            })
        }
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.suspend() } }
    }

    func stop() {
        proximity.cancel()
        for pair in pairs { unpair(pair) }
        composerState?.stop()
        composer?.close()
        composer = nil
        composerState = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        displayObserver = nil
        Task { await service.stop() }
    }
}

private extension NSEvent {
    static var mouseLocationAX: CGPoint {
        AppMeltGeometry.quartz(fromAppKit: mouseLocation)
    }
}
