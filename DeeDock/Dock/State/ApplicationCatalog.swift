import AppKit
import Observation

/// Application-wide workspace observation, icon cache, running order, and launch ownership.
@MainActor @Observable
final class ApplicationCatalog {
    private(set) var running: [ApplicationReference] = []
    private(set) var runningIDs: [String] = []
    private(set) var launching: Set<String> = []
    private(set) var documentRequests: [UUID: String] = [:]
    var busyApplications: Set<String> { launching.union(documentRequests.values) }
    let service: any ApplicationServicing
    @ObservationIgnored var didChange: (() -> Void)?
    @ObservationIgnored var activated: ((NSRunningApplication) -> Void)?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var documentTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var generation = UUID()

    init(service: any ApplicationServicing) { self.service = service }

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                             object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self?.activated?(app)
                }
            }
        })
        refresh()
    }

    func refresh() {
        running = DockOrdering.unique(service.runningApplications())
        runningIDs = DockOrdering.runningOrder(previous: runningIDs, current: running)
        didChange?()
    }

    /// Owns app-icon toggle work so all display docks share duplicate suppression and teardown.
    func performPrimaryAction(_ reference: ApplicationReference,
                              completion: @escaping (LocalizedStringResource?) -> Void) {
        submit(reference, operation: { service in try await service.performPrimaryAction(reference) }) { error in
            if error is ApplicationPrimaryActionError {
                completion(.errorHideApp(appName: reference.name))
            } else {
                completion(.errorOpenApp(appName: reference.name, details: error.localizedDescription))
            }
        } completion: {
            completion(nil)
        }
    }

    /// Only this catalog owns cancellation. The initiating dock supplies a weak, session-checked callback.
    func open(_ reference: ApplicationReference, ifCurrent: @escaping () -> Bool = { true },
              completion: @escaping (LocalizedStringResource?) -> Void) {
        submit(reference, ifCurrent: ifCurrent, operation: { service in try await service.open(reference) }) { error in
            completion(.errorOpenApp(appName: reference.name, details: error.localizedDescription))
        } completion: { completion(nil) }
    }

    private func submit(_ reference: ApplicationReference, ifCurrent: @escaping () -> Bool = { true },
                        operation: @escaping (any ApplicationServicing) async throws -> Void,
                        failure: @escaping (any Error) -> Void,
                        completion: @escaping () -> Void) {
        guard tasks[reference.id] == nil else { return }
        let currentGeneration = generation
        launching.insert(reference.id)
        tasks[reference.id] = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == currentGeneration { launching.remove(reference.id); tasks[reference.id] = nil }
            }
            do {
                try Task.checkCancellation()
                guard ifCurrent() else { return }
                try await operation(service)
                guard !Task.isCancelled, generation == currentGeneration else { return }
                completion()
                refresh()
            } catch {
                guard !Task.isCancelled, generation == currentGeneration else { return }
                failure(error)
            }
        }
    }

    /// Uses the same Workspace opening path for running and closed apps. Workspace handles
    /// cooperative activation and reopening windows; a sent activation message alone does not.
    func springOpen(_ reference: ApplicationReference, isCurrent: @escaping () -> Bool,
                    completion: @escaping (LocalizedStringResource?) -> Void) {
        guard isCurrent() else { return }
        open(reference, ifCurrent: isCurrent) { error in
            guard isCurrent() else { return }
            completion(error)
        }
    }

    func pruneIcons(items: [DockItem], folders: [FolderDockItem] = []) {
        let applicationURLs = items.compactMap { service.resolvedURL(for: $0.reference) }
        let folderURLs = folders.compactMap { item -> URL? in
            let access = FolderResourceAccess(item.reference)
            defer { withExtendedLifetime(access) {} }
            return access.isAvailable ? access.url : nil
        }
        service.pruneIcons(keeping: Set(applicationURLs + folderURLs))
    }

    /// Every accepted batch owns a task and its file access, independent of launch suppression.
    /// Removing a panel invalidates only its callback; quitting cancels catalog-owned work.
    func openDocuments(_ documents: DocumentResourceAccess, with reference: ApplicationReference,
                       completion: @escaping (LocalizedStringResource?) -> Void) {
        let id = UUID()
        let currentGeneration = generation
        documentRequests[id] = reference.id
        documentTasks[id] = Task { [weak self] in
            guard let self else { return }
            defer {
                withExtendedLifetime(documents) {}
                if generation == currentGeneration {
                    documentRequests[id] = nil
                    documentTasks[id] = nil
                }
            }
            do {
                try Task.checkCancellation()
                try await service.openDocuments(documents.urls, with: reference)
                guard !Task.isCancelled, generation == currentGeneration else { return }
                completion(nil)
                refresh()
            } catch {
                guard !Task.isCancelled, generation == currentGeneration else { return }
                completion(.errorOpenDocuments(appName: reference.name, details: error.localizedDescription))
            }
        }
    }

    func stop() {
        generation = UUID()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        documentTasks.values.forEach { $0.cancel() }
        documentTasks.removeAll()
        documentRequests.removeAll()
        launching.removeAll()
        didChange = nil
        activated = nil
    }
}
