import AppKit
import ApplicationServices
import Observation
import UniformTypeIdentifiers

/// Explicit launch and window selection. Discovery never silently chooses an app's first window.
@MainActor @Observable final class AppMeltSetupState: NSObject, NSWindowDelegate {
    let windowPicker: AppMeltWindowPickerState
    var windowPickerSide: Int?
    var urls: [URL?] = [nil, nil]
    var candidates: [[ApplicationWindowSummary]] = [[], []]
    var selection: [ApplicationWindowToken?] = [nil, nil]
    var createdPair: AppMeltPair?
    var accessEnabled = false
    var busy = false
    var message: LocalizedStringResource?
    @ObservationIgnored private weak var controller: AppMeltController?
    @ObservationIgnored private var sessionID = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?

    init(controller: AppMeltController) {
        self.controller = controller
        windowPicker = AppMeltWindowPickerState(controller: controller)
        super.init()
        windowPicker.selected = { [weak self] window in self?.selectExistingWindow(window) }
    }

    /// Context-menu and icon-drop entry points keep explicit window choice for multi-window apps.
    func seed(first: URL, second: URL?) {
        stop()
        createdPair = nil
        urls = [first, second]
        message = nil
        if second != nil { launchAndRefresh() }
        else { choose(0) }
    }

    func canAcceptDockApplication(_ pasteboard: NSPasteboard, at index: Int) -> Bool {
        guard !busy, createdPair == nil, urls.indices.contains(index),
              controller?.readDockApplication?(pasteboard) != nil else { return false }
        return true
    }

    func acceptDockApplication(_ pasteboard: NSPasteboard, at index: Int) -> Bool {
        guard canAcceptDockApplication(pasteboard, at: index),
              let app = controller?.readDockApplication?(pasteboard) else { return false }
        urls[index] = app.url
        candidates = [[], []]; selection = [nil, nil]; message = nil
        // Mark the native source consumed before its ended callback can interpret this as unpin.
        controller?.finishDockApplicationDrop?()
        if urls.allSatisfy({ $0 != nil }) { launchAndRefresh() }
        return true
    }

    func choose(_ index: Int) {
        guard !busy, createdPair == nil else { return }
        windowPicker.preferredApplication = urls[index]
        windowPickerSide = index
    }

    /// Retain a chosen exact handle in setup's own session before the menu releases discovery.
    private func selectExistingWindow(_ window: ApplicationWindowSummary) {
        guard let controller, let index = windowPickerSide, !busy,
              let app = NSRunningApplication(processIdentifier: window.processIdentifier),
              let url = app.bundleURL else { return }
        let session = sessionID
        busy = true
        task = Task { [weak self] in
            guard let self else { return }
            do {
                if let other = selection[1 - index],
                   try await controller.service.meltIsPaired(window.token, existing: [other]) {
                    windowPicker.message = .meltSetupDistinctWindows
                } else {
                    let adopted = try await controller.service.meltAdopt(window.token, sessionID: session)
                    guard !Task.isCancelled, sessionID == session else {
                        await controller.service.meltRelease(adopted.token)
                        return
                    }
                    let previous = selection[index]
                    urls[index] = url
                    candidates[index] = [adopted]
                    selection[index] = adopted.token
                    windowPickerSide = nil
                    message = nil
                    // Launch discovery can share candidate tokens between both sides of a
                    // same-app setup. Keep them alive until the setup session is discarded.
                    if let previous, !candidates[1 - index].contains(where: { $0.token == previous }) {
                        await controller.service.meltRelease(previous)
                    }
                }
            } catch {
                if !Task.isCancelled { windowPicker.message = .meltReplacementUnavailable }
            }
            if sessionID == session { busy = false }
        }
    }

    /// Dock menus retain discovery until this handoff has copied the partner into setup.
    func seedPartner(_ window: ApplicationWindowSummary) async {
        guard let controller, let app = NSRunningApplication(processIdentifier: window.processIdentifier),
              let url = app.bundleURL, !busy else { return }
        let session = sessionID
        busy = true
        defer { if sessionID == session { busy = false } }
        do {
            let adopted = try await controller.service.meltAdopt(window.token, sessionID: session)
            guard !Task.isCancelled, sessionID == session else {
                await controller.service.meltRelease(adopted.token)
                return
            }
            urls[1] = url
            candidates[1] = [adopted]
            selection[1] = adopted.token
        } catch { if sessionID == session { message = .meltReplacementUnavailable } }
    }

    func chooseApplication(_ index: Int) {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.application]
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false
        guard picker.runModal() == .OK, let url = picker.url else { return }
        urls[index] = url
        candidates = [[], []]
        selection = [nil, nil]
        message = nil
    }

    func beginPresentation() {
        refreshAccess()
        if createdPair?.message == nil, createdPair?.busy != true { createdPair = nil }
    }

    func refreshAccess() { accessEnabled = SystemWindowAccessService().status == .enabled }

    func retryPair() {
        guard let pair = createdPair else { return }
        controller?.restore(pair)
    }

    func discardPair() {
        if let pair = createdPair { controller?.unpair(pair) }
        createdPair = nil
        message = nil
    }

    func launchAndRefresh() {
        guard let controller, let left = urls[0], let right = urls[1], !busy else { return }
        windowPickerSide = nil
        windowPicker.cancel()
        refreshAccess()
        candidates = [[], []]
        selection = [nil, nil]
        busy = true
        message = nil
        let oldSession = sessionID
        sessionID = UUID()
        let session = sessionID
        task = Task { [weak self] in
            guard let self else { return }
            await controller.service.discard(sessionID: oldSession)
            do {
                try Task.checkCancellation()
                // Both launch requests are issued before awaiting window discovery.
                let applications: [NSRunningApplication]
                if left.standardizedFileURL == right.standardizedFileURL {
                    let app = try await launch(left)
                    applications = [app, app]
                } else {
                    async let first = launch(left)
                    async let second = launch(right)
                    applications = try await [first, second]
                }
                var found: [ApplicationWindowSummary] = []
                // A bounded launch-only wait accommodates apps creating their initial windows.
                for attempt in 0..<20 {
                    try Task.checkCancellation()
                    do {
                        found = try await controller.service.discover(processes: applications.map {
                            ApplicationProcessSnapshot(processIdentifier: $0.processIdentifier,
                                isHidden: $0.isHidden, isActive: $0.isActive)
                        }, sessionID: session)
                    } catch ApplicationWindowServiceError.accessibility(let code)
                        where attempt < 19 && (code == AXError.cannotComplete.rawValue || code == AXError.invalidUIElement.rawValue) {
                        // A launched process may not yet serve AX requests. Retry within the
                        // existing bounded startup wait instead of misreporting missing consent.
                        try await Task.sleep(for: .milliseconds(250))
                        continue
                    }
                    if applications.allSatisfy({ app in found.contains { $0.processIdentifier == app.processIdentifier } }) { break }
                    try await Task.sleep(for: .milliseconds(250))
                }
                try Task.checkCancellation()
                guard sessionID == session else { return }
                candidates = applications.map { app in found.filter { $0.processIdentifier == app.processIdentifier } }
                selection = candidates.map { $0.count == 1 ? $0.first?.token : nil }
                if selection[0] == selection[1] { selection[1] = nil }
                if candidates.contains(where: \.isEmpty) { message = .meltNoWindows }
            } catch is CancellationError { return }
            catch {
                if sessionID == session {
                    refreshAccess()
                    if let failure = error as? ApplicationWindowServiceError {
                        message = failure == .permissionRequired ? .meltPermissionRequired
                            : failure == .sandboxRestricted ? .meltSandboxRestricted : .meltDiscoveryFailed
                    } else { message = .meltLaunchFailed }
                }
            }
            if sessionID == session { busy = false }
        }
    }

    func create() {
        guard let controller, !busy,
              let first = candidates[0].first(where: { $0.token == selection[0] }),
              let second = candidates[1].first(where: { $0.token == selection[1] }),
              first.token != second.token else { return }
        busy = true
        let session = sessionID
        let names = urls.map { $0.map { FileManager.default.displayName(atPath: $0.path) } ?? "" }
        let icons = urls.compactMap { $0.map { NSWorkspace.shared.icon(forFile: $0.path) } }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let pair = try await controller.create(sessionID: session, windows: [first, second],
                    names: names, icons: icons)
                guard sessionID == session, !Task.isCancelled else {
                    controller.unpair(pair)
                    return
                }
                createdPair = pair
                // The pair owns these handles now. A subsequent composer refresh gets a new session.
                sessionID = UUID()
                candidates = [[], []]
                selection = [nil, nil]
            } catch is CancellationError { return }
            catch {
                guard sessionID == session else { return }
                message = AppMeltFailure.message(for: error)
            }
            busy = false
        }
    }

    private func launch(_ url: URL) async throws -> NSRunningApplication {
        try Task.checkCancellation()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        return try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    func windowWillClose(_ notification: Notification) { stop() }

    func stop() {
        windowPickerSide = nil
        windowPicker.cancel()
        task?.cancel()
        task = nil
        candidates = [[], []]
        selection = [nil, nil]
        busy = false
        let session = sessionID
        sessionID = UUID()
        if let service = controller?.service { Task { await service.discard(sessionID: session) } }
    }
}
