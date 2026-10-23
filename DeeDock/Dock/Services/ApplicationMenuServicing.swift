import AppKit

/// Failures from application-wide context-menu commands.
nonisolated enum ApplicationMenuServiceError: Error, Equatable, Sendable {
    case applicationUnavailable
    case operationRejected
}

/// Main-actor AppKit boundary for live process resolution and application-wide commands.
@MainActor
protocol ApplicationMenuServicing: AnyObject {
    func processes(for reference: ApplicationReference) -> [ApplicationProcessSnapshot]
    func showInFinder(_ reference: ApplicationReference) throws
    func setHidden(_ hidden: Bool, for reference: ApplicationReference) throws
    func bringAllToFront(_ reference: ApplicationReference) throws
    func quit(_ reference: ApplicationReference) throws
    /// Whether macOS 27 reports the app as running in background. False when that state cannot be read.
    func isRunningInBackground(_ reference: ApplicationReference) -> Bool
    /// Requests that the app's remaining processes end. Returns whether a stop was requested.
    /// Never throws: the feature is silent, and a stop that cannot be requested does nothing.
    func stopRunningInBackground(_ reference: ApplicationReference) -> Bool
}

/// Resolves every regular process represented by one DeeDock application identity.
@MainActor
final class ApplicationMenuService: ApplicationMenuServicing {
    private let workspace: NSWorkspace
    private let applications: any ApplicationServicing
    /// Owns the background state and its stop. Nil turns Stop Running in Background off.
    private weak var catalog: ApplicationCatalog?

    init(workspace: NSWorkspace = .shared, applications: any ApplicationServicing, catalog: ApplicationCatalog? = nil) {
        self.workspace = workspace
        self.applications = applications
        self.catalog = catalog
    }

    func processes(for reference: ApplicationReference) -> [ApplicationProcessSnapshot] {
        matchingApplications(reference).map {
            ApplicationProcessSnapshot(processIdentifier: $0.processIdentifier, isHidden: $0.isHidden, isActive: $0.isActive)
        }
    }

    func showInFinder(_ reference: ApplicationReference) throws {
        let access = ApplicationResourceAccess(reference)
        defer { withExtendedLifetime(access) {} }
        guard let url = applications.resolvedURL(for: reference) else {
            throw ApplicationMenuServiceError.applicationUnavailable
        }
        workspace.activateFileViewerSelecting([url])
    }

    func setHidden(_ hidden: Bool, for reference: ApplicationReference) throws {
        try perform(for: reference) { hidden ? $0.hide() : $0.unhide() }
    }

    func bringAllToFront(_ reference: ApplicationReference) throws {
        try perform(for: reference) { application in
            let unhidden = !application.isHidden || application.unhide()
            return unhidden && application.activate(options: .activateAllWindows)
        }
    }

    func quit(_ reference: ApplicationReference) throws {
        try perform(for: reference) { $0.terminate() }
    }

    func isRunningInBackground(_ reference: ApplicationReference) -> Bool {
        catalog?.isRunningInBackground(reference) ?? false
    }

    func stopRunningInBackground(_ reference: ApplicationReference) -> Bool {
        catalog?.stopRunningInBackground(reference) ?? false
    }

    private func perform(for reference: ApplicationReference, action: (NSRunningApplication) -> Bool) throws {
        let matches = matchingApplications(reference)
        guard !matches.isEmpty else { throw ApplicationMenuServiceError.applicationUnavailable }
        var accepted = true
        for application in matches where !application.isTerminated {
            if !action(application) { accepted = false }
        }
        if !accepted { throw ApplicationMenuServiceError.operationRejected }
    }

    private func matchingApplications(_ reference: ApplicationReference) -> [NSRunningApplication] {
        workspace.runningApplications.filter { application in
            guard application.activationPolicy == .regular,
                  !application.isTerminated,
                  application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }
            let bundleMatches = reference.bundleIdentifier.map { application.bundleIdentifier == $0 } ?? false
            let locationMatches = application.bundleURL?.standardizedFileURL == reference.url.standardizedFileURL
            return bundleMatches || locationMatches
        }
    }
}
