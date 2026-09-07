import AppKit
import Observation

/// Resolves saved references on demand without capturing pixels, polling, or retaining AX handles.
/// A matching app/title is best effort. Duplicate titles must never select an arbitrary window.
@MainActor @Observable
final class SessionCapsuleSourceNavigator {
    enum Status { case checking, available, unavailable, unverified, ambiguous }
    private(set) var statuses: [UUID: Status] = [:]
    @ObservationIgnored var failure: ((String) -> Void)?
    @ObservationIgnored private let windows: any ApplicationWindowServicing
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var actionTask: Task<Void, Never>?

    init(windows: any ApplicationWindowServicing = AccessibilityApplicationWindowService()) {
        self.windows = windows
    }

    func refresh(_ references: [SessionCapsuleWindowReference]) {
        actionTask?.cancel()
        refreshTask?.cancel()
        statuses = Dictionary(uniqueKeysWithValues: references.map { ($0.id, .checking) })
        // Window actions must not interrupt availability checks for the remaining source cards.
        refreshTask = Task { [weak self] in
            guard let self else { return }
            for reference in references {
                guard !Task.isCancelled else { return }
                let result = await resolve(reference, show: false)
                guard !Task.isCancelled else { return }
                statuses[reference.id] = result
            }
        }
    }

    func showWindow(_ reference: SessionCapsuleWindowReference) {
        actionTask?.cancel()
        actionTask = Task { [weak self] in
            guard let self else { return }
            let result = await resolve(reference, show: true)
            guard !Task.isCancelled else { return }
            statuses[reference.id] = result
            if result != .available { failure?(String(localized: .breadcrumbWindowUnavailable)) }
        }
    }

    func openApp(_ reference: SessionCapsuleWindowReference) {
        actionTask?.cancel()
        guard let identifier = reference.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
            failure?(String(localized: .breadcrumbAppUnavailable)); return
        }
        actionTask = Task { [weak self] in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = false
            do {
                try Task.checkCancellation()
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            } catch {
                guard !Task.isCancelled else { return }
                self?.failure?(String(localized: .breadcrumbAppUnavailable))
            }
        }
    }

    func openLink(_ reference: SessionCapsuleWindowReference) {
        actionTask?.cancel()
        guard let url = reference.reopeningURL, NSWorkspace.shared.open(url) else {
            failure?(String(localized: .breadcrumbLinkUnavailable)); return
        }
    }

    func openDocument(_ reference: SessionCapsuleWindowReference) {
        actionTask?.cancel()
        guard let data = reference.documentBookmark else { return }
        actionTask = Task { [weak self] in
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                                  relativeTo: nil, bookmarkDataIsStale: &stale)
                // Stale bookmarks need an explicit re-selection in Edit; do not silently broaden access.
                guard !stale else { throw CocoaError(.fileReadNoPermission) }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileNoSuchFile) }
                try Task.checkCancellation()
                _ = try await NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                guard !Task.isCancelled else { return }
                self?.failure?(String(localized: .breadcrumbDocumentUnavailable))
            }
        }
    }

    func cancel() {
        actionTask?.cancel()
        refreshTask?.cancel()
        actionTask = nil
        refreshTask = nil
        statuses = [:]
    }

    func stop() {
        cancel()
        failure = nil
    }

    private func resolve(_ reference: SessionCapsuleWindowReference, show: Bool) async -> Status {
        guard let bundleID = reference.bundleIdentifier, let title = reference.windowTitle,
              !title.isEmpty else { return .unverified }
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID && !$0.isTerminated
        }
        guard !running.isEmpty else { return .unavailable }
        let processes = running.map {
            ApplicationProcessSnapshot(processIdentifier: $0.processIdentifier, isHidden: $0.isHidden, isActive: $0.isActive)
        }
        let sessionID = UUID()
        do {
            let summaries = try await windows.discover(processes: processes, sessionID: sessionID)
            try Task.checkCancellation()
            let matches = summaries.filter { $0.title == title }
            guard matches.count == 1, let match = matches.first else {
                await windows.discard(sessionID: sessionID)
                return matches.isEmpty ? .unavailable : .ambiguous
            }
            if show { try await windows.selectWindow(match.token) }
            await windows.discard(sessionID: sessionID)
            return .available
        } catch {
            await windows.discard(sessionID: sessionID)
            return show ? .unavailable : .unverified
        }
    }
}
