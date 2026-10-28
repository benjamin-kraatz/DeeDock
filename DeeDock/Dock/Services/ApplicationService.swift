import AppKit
import OSLog

/// Main-actor adapter for app discovery, icon caching, and Launch Services operations.
@MainActor
final class ApplicationService: ApplicationServicing {
    private static let logger = Logger(subsystem: "com.deedock", category: "ApplicationHide")
    private let workspace: NSWorkspace
    private var iconCache: [URL: NSImage] = [:]

    /// Uses the supplied workspace; constructing the service does not enumerate or launch apps.
    init(workspace: NSWorkspace = .shared) { self.workspace = workspace }

    /// Returns regular apps plus DDock while it owns an open window. Other accessory apps stay excluded.
    func runningApplications() -> [ApplicationReference] {
        var applications = workspace.runningApplications.compactMap { app -> ApplicationReference? in
            guard app.activationPolicy == .regular,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let url = app.bundleURL else { return nil }
            return ApplicationReference(bundleIdentifier: app.bundleIdentifier, url: url,
                                        name: app.localizedName ?? url.deletingPathExtension().lastPathComponent)
        }
        if AppDockPresence.shared.hasOpenWindows {
            applications.append(ApplicationReference(bundleIdentifier: Bundle.main.bundleIdentifier,
                url: Bundle.main.bundleURL, name: String(localized: .appName)))
        }
        return applications
    }

    /// Resolves the initial pin choices, skipping apps that are not installed.
    func defaultFavorites() -> [ApplicationReference] {
        ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.iCal", "com.apple.systempreferences"]
            .compactMap { identifier in
                guard let url = workspace.urlForApplication(withBundleIdentifier: identifier) else { return nil }
                return ApplicationReference(bundleIdentifier: identifier, url: url,
                                            name: FileManager.default.displayName(atPath: url.path)
                                                .replacingOccurrences(of: ".app", with: ""))
            }
    }

    /// Uses the saved location when present, then resolves moved apps by bundle identifier.
    func resolvedURL(for reference: ApplicationReference) -> URL? {
        let access = ApplicationResourceAccess(reference)
        defer { withExtendedLifetime(access) {} }
        if FileManager.default.fileExists(atPath: access.url.path) { return access.url }
        return reference.bundleIdentifier.flatMap { workspace.urlForApplication(withBundleIdentifier: $0) }
    }

    /// Returns a cached icon, loading it once per resolved URL, or an unavailable-app symbol.
    func icon(for url: URL?) -> NSImage {
        guard let url else { return NSImage(systemSymbolName: "questionmark.app.dashed", accessibilityDescription: nil)! }
        if let image = iconCache[url] { return image }
        let image = workspace.icon(forFile: url.path)
        image.size = NSSize(width: 128, height: 128)
        iconCache[url] = image
        return image
    }

    /// Releases icons no longer referenced by any active dock snapshot.
    func pruneIcons(keeping urls: Set<URL>) { iconCache = iconCache.filter { urls.contains($0.key) } }

    /// Hides the selected app when it is already foreground, otherwise opens or activates it.
    ///
    /// The live foreground process is checked at click time. Dock snapshots intentionally track
    /// only running state and may lag behind activation changes by one main-run-loop turn.
    func performPrimaryAction(_ reference: ApplicationReference) async throws -> ApplicationPrimaryActionOutcome {
        // Hiding ourselves would also hide the user's replacement dock. The self tile always
        // restores the requested app window, even when DDock already owns keyboard focus.
        if AppDockPresence.representsCurrentApplication(reference) {
            try await open(reference)
            return .opened
        }
        if let frontmost = workspace.frontmostApplication, matches(frontmost, reference: reference) {
            try await hide(frontmost)
            return .hidden
        }
        try await open(reference)
        return .opened
    }

    /// Reconciles a rejected request with process-specific evidence before reporting failure.
    /// Observation precedes the request so a synchronous hide notification cannot be missed.
    private func hide(_ application: NSRunningApplication) async throws {
        try Task.checkCancellation()
        let pid = application.processIdentifier
        let hiddenBefore = application.isHidden
        let (events, continuation) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let center = workspace.notificationCenter
        let observer = center.addObserver(forName: NSWorkspace.didHideApplicationNotification,
                                          object: nil, queue: .main) { notification in
            guard let hidden = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  hidden.processIdentifier == pid else { return }
            continuation.yield(true)
        }
        defer {
            center.removeObserver(observer)
            continuation.finish()
        }

        let accepted = application.hide()
        Self.logger.debug("Hide pid=\(pid) accepted=\(accepted) hiddenBefore=\(hiddenBefore) hiddenAfter=\(application.isHidden)")
        if accepted || application.isHidden { return }

        // Only rejected requests need a grace period. Sleeping suspends the task; no thread
        // is blocked and no workspace enumeration or continuous polling is introduced.
        let timeout = Task { @concurrent in
            do {
                try await Task.sleep(for: .milliseconds(250))
                continuation.finish()
            } catch { }
        }
        defer { timeout.cancel() }
        var observedHide = false
        for await _ in events {
            observedHide = true
            break
        }
        try Task.checkCancellation()
        Self.logger.debug("Hide reconciled pid=\(pid) notification=\(observedHide) hidden=\(application.isHidden) terminated=\(application.isTerminated)")
        // Termination also removes the app's windows, so a late hide warning is unhelpful.
        guard observedHide || application.isHidden || application.isTerminated else {
            throw ApplicationPrimaryActionError.hideRejected
        }
    }

    /// Opens or activates the referenced app without requesting a new process instance.
    /// - Throws: A missing-bundle error or the failure reported by Launch Services.
    /// - Note: Cancellation cannot undo a launch already submitted to macOS.
    func open(_ reference: ApplicationReference) async throws {
        if AppDockPresence.representsCurrentApplication(reference),
           let window = AppDockPresence.shared.windowToReopen {
            ExplicitWindowPresenter.shared.present(window)
            return
        }
        let access = ApplicationResourceAccess(reference)
        defer { withExtendedLifetime(access) {} }
        guard let url = resolvedURL(for: reference) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: String(localized: .errorAppNotFound(appName: reference.name))])
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        _ = try await workspace.openApplication(at: url, configuration: configuration)
    }

    func openDocuments(_ urls: [URL], with reference: ApplicationReference) async throws {
        let documents = DocumentResourceAccess(urls)
        let access = ApplicationResourceAccess(reference)
        defer { withExtendedLifetime((documents, access)) {} }
        // Metadata can block on external volumes. Never perform it in native drag callbacks.
        let worker = Task.detached { try DockExternalPayload.validateDocuments(documents.urls) }
        do {
            try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        } catch is DockDocumentValidationError {
            throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: String(localized: .errorInvalidDocuments)])
        }
        try Task.checkCancellation()
        guard let url = resolvedURL(for: reference) else { throw CocoaError(.fileNoSuchFile) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        _ = try await workspace.open(documents.urls, withApplicationAt: url, configuration: configuration)
    }

    /// Bundle identity is primary because an application may move after it was pinned.
    /// URL identity keeps bundle-less application references usable.
    private func matches(_ application: NSRunningApplication, reference: ApplicationReference) -> Bool {
        if let bundleIdentifier = reference.bundleIdentifier {
            return application.bundleIdentifier == bundleIdentifier
        }
        return application.bundleURL?.standardizedFileURL == reference.url.standardizedFileURL
    }

}
