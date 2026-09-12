import AppKit
import Observation

/// Owns saved cables and a single, unqueued folder action. All triggers are explicit DDock actions.
@MainActor @Observable
final class PatchBayController {
    private(set) var document = PatchBayDocument()
    private(set) var requiresReset = false
    private(set) var message: LocalizedStringResource?
    private(set) var runningCableID: UUID?
    private(set) var lastCableID: UUID?
    @ObservationIgnored private let profiles: DisplayProfilesStore
    @ObservationIgnored private let repository: PatchBayRepository?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    /// A nil repository provides an isolated, nonpersistent controller for previews.
    init(profiles: DisplayProfilesStore, repository: PatchBayRepository? = PatchBayRepository()) {
        self.profiles = profiles
        self.repository = repository
        do { document = try repository?.load() ?? PatchBayDocument() }
        catch { requiresReset = true; message = .patchBayStorageError }
    }

    func setEnabled(_ enabled: Bool) {
        var proposed = document
        proposed.enabled = enabled
        save(proposed)
    }

    /// Rewiring replaces this app's previous output. Saving never runs the cable.
    func connect(appID: String, folderID: String, displayID: String) {
        guard !requiresReset, let pins = availablePins(displayID),
              let app = pins.first(where: { $0.id == appID })?.application,
              let folder = pins.first(where: { $0.id == folderID })?.folder else {
            message = .patchBayUnavailable
            return
        }
        let modeID = profiles.modes.activeMode.id
        var proposed = document
        proposed.cables.removeAll { $0.displayID == displayID && $0.modeID == modeID && $0.appID == appID }
        guard proposed.cables.count < PatchBayDocument.maximumCables else {
            message = .patchBayLimit
            return
        }
        proposed.cables.append(PatchBayCable(id: UUID(), displayID: displayID, modeID: modeID,
                                            appID: appID, folderID: folderID,
                                            appName: app.name, folderName: folder.name))
        save(proposed)
    }

    func disconnect(_ id: UUID) {
        var proposed = document
        proposed.cables.removeAll { $0.id == id }
        save(proposed)
    }

    /// Called only after a successful app open, with the mode captured before that open began.
    func appOpened(_ appID: String, displayID: String, modeID: UUID) {
        guard document.enabled, modeID == profiles.modes.activeMode.id,
              let cable = document.cables.first(where: {
                  $0.displayID == displayID && $0.modeID == modeID && $0.appID == appID
              }) else { return }
        run(cable)
    }

    func isAvailable(_ cable: PatchBayCable) -> Bool { folder(for: cable) != nil }

    /// Runs only the folder action. It does not launch the source app or emit another trigger.
    /// Concurrent triggers are dropped. Disabling, rewiring, or stopping cancels pending work.
    func run(_ cable: PatchBayCable) {
        guard !requiresReset, document.enabled, document.cables.contains(cable) else { return }
        guard runningCableID == nil else { return }
        guard let folder = folder(for: cable) else {
            lastCableID = cable.id
            message = .patchBayUnavailable
            return
        }
        let token = UUID()
        generation = token
        runningCableID = cable.id
        lastCableID = cable.id
        message = .patchBayRunning
        task = Task { [weak self] in
            defer {
                if let self, generation == token {
                    runningCableID = nil
                    task = nil
                }
            }
            do {
                let access = try await Self.resolve(folder)
                defer { withExtendedLifetime(access) {} }
                try Task.checkCancellation()
                guard let self, generation == token, document.enabled,
                      document.cables.contains(cable), isAvailable(cable) else { return }
                // Opening in the background preserves the source app's focus. Finder receives
                // the folder directly, so a user-chosen default folder handler cannot run instead.
                guard let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                _ = try await NSWorkspace.shared.open(access.urls, withApplicationAt: finder, configuration: configuration)
                guard !Task.isCancelled, generation == token else { return }
                finish(.patchBayOpened)
            } catch {
                guard let self, !Task.isCancelled, generation == token else { return }
                finish(.patchBayOpenFailed)
            }
        }
    }

    /// Mode/display changes invalidate pending work before an OS request is issued.
    func reconcile() {
        guard let id = runningCableID,
              let cable = document.cables.first(where: { $0.id == id }), !isAvailable(cable) else { return }
        stop()
    }

    /// Cannot undo a folder-open request already handed to Finder.
    func stop() {
        let wasRunning = runningCableID != nil
        generation = UUID()
        task?.cancel()
        task = nil
        runningCableID = nil
        if wasRunning { message = .patchBayCanceled }
    }

    func reset() {
        stop()
        repository?.reset()
        document = PatchBayDocument()
        requiresReset = false
        lastCableID = nil
        message = nil
    }

    private func save(_ proposed: PatchBayDocument) {
        guard !requiresReset else { return }
        do {
            guard proposed.isValid else { throw CocoaError(.coderInvalidValue) }
            try repository?.save(proposed)
            stop()
            document = proposed
            lastCableID = nil
            message = nil
        } catch { message = .patchBayStorageError }
    }

    private func availablePins(_ displayID: String) -> [DockPin]? {
        guard !profiles.requiresReset, !profiles.modes.requiresReset,
              profiles.pinErrors[displayID] == nil,
              profiles.displays.contains(where: { $0.id == displayID && $0.hostsDock }),
              profiles.document.profiles[displayID]?.enabled == true else { return nil }
        return profiles.pinLists[displayID]
    }

    private func folder(for cable: PatchBayCable) -> FolderReference? {
        guard cable.modeID == profiles.modes.activeMode.id,
              let pins = availablePins(cable.displayID),
              pins.contains(where: { $0.id == cable.appID && $0.application != nil }) else { return nil }
        return pins.first(where: { $0.id == cable.folderID })?.folder
    }

    private func finish(_ result: LocalizedStringResource) {
        message = result
        runningCableID = nil
        task = nil
    }

    /// Bookmark and filesystem work stays off the UI actor. No stale-path fallback is allowed
    /// for automations: a broken bookmark requires the user to pin the folder again.
    @concurrent private static func resolve(_ folder: FolderReference) async throws -> DocumentResourceAccess {
        try Task.checkCancellation()
        var stale = false
        let url = try URL(resolvingBookmarkData: folder.bookmarkData,
                          options: [.withSecurityScope, .withoutUI], relativeTo: nil,
                          bookmarkDataIsStale: &stale)
        guard !stale, url.isFileURL else { throw CocoaError(.fileReadNoPermission) }
        let access = DocumentResourceAccess([url])
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return access
    }
}
