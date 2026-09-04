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
}

/// Resolves every regular process represented by one DeeDock application identity.
@MainActor
final class ApplicationMenuService: ApplicationMenuServicing {
    private let workspace: NSWorkspace
    private let applications: any ApplicationServicing

    init(workspace: NSWorkspace = .shared, applications: any ApplicationServicing) {
        self.workspace = workspace
        self.applications = applications
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
