import Foundation

/// Owns dynamic menu discovery and commands without borrowing application-launch busy state.
@MainActor
final class ApplicationMenuController {
    private let access: WindowAccessController
    private let applications: any ApplicationMenuServicing
    private let windows: any ApplicationWindowServicing
    private var discoveryTasks: [UUID: Task<Void, Never>] = [:]
    private var actionTasks: [UUID: Task<Void, Never>] = [:]
    private var generation = UUID()

    init(access: WindowAccessController,
         applications: any ApplicationMenuServicing,
         windows: any ApplicationWindowServicing) {
        self.access = access
        self.applications = applications
        self.windows = windows
    }

    func snapshot(for item: DockItem) -> ApplicationMenuSnapshot {
        access.refresh()
        let processes = applications.processes(for: item.reference)
        let state: ApplicationWindowMenuState = access.status == .enabled && !processes.isEmpty ? .loading : .hidden
        return ApplicationMenuSnapshot(processes: processes, windowState: state)
    }

    /// Returns a menu-scoped identifier whose completion is ignored after cancellation or shutdown.
    func beginDiscovery(for item: DockItem,
                        snapshot: ApplicationMenuSnapshot,
                        completion: @escaping (ApplicationWindowMenuState) -> Void) -> UUID? {
        guard snapshot.windowState == .loading else { return nil }
        let sessionID = UUID()
        let currentGeneration = generation
        let windows = windows
        discoveryTasks[sessionID] = Task { [weak self] in
            let state: ApplicationWindowMenuState
            do {
                let summaries = try await windows.discover(processes: snapshot.processes, sessionID: sessionID)
                state = .loaded(summaries)
            } catch is CancellationError {
                return
            } catch {
                await windows.discard(sessionID: sessionID)
                state = .unavailable
            }
            guard let self, !Task.isCancelled, generation == currentGeneration,
                  discoveryTasks[sessionID] != nil else { return }
            discoveryTasks[sessionID] = nil
            completion(state)
        }
        return sessionID
    }

    func cancelDiscovery(_ sessionID: UUID) {
        discoveryTasks.removeValue(forKey: sessionID)?.cancel()
        Task { await windows.discard(sessionID: sessionID) }
    }

    func cancelAllDiscoveries() {
        let sessionIDs = Array(discoveryTasks.keys)
        discoveryTasks.values.forEach { $0.cancel() }
        discoveryTasks.removeAll()
        for sessionID in sessionIDs {
            Task { await windows.discard(sessionID: sessionID) }
        }
    }

    func perform(_ action: ApplicationMenuAction,
                 for item: DockItem,
                 completion: @escaping (LocalizedStringResource?) -> Void) {
        switch action {
        case .showInFinder, .setHidden, .bringAllToFront, .quit:
            do {
                switch action {
                case .showInFinder: try applications.showInFinder(item.reference)
                case .setHidden(let hidden): try applications.setHidden(hidden, for: item.reference)
                case .bringAllToFront: try applications.bringAllToFront(item.reference)
                case .quit: try applications.quit(item.reference)
                case .selectWindow: break
                }
                completion(nil)
            } catch {
                completion(.applicationMenuActionFailed(
                    appName: item.reference.name,
                    details: String(localized: action.failureDescription)
                ))
            }
        case .selectWindow(let token):
            let id = UUID()
            let currentGeneration = generation
            let windows = windows
            actionTasks[id] = Task { [weak self] in
                do {
                    try await windows.selectWindow(token)
                    guard let self, !Task.isCancelled, generation == currentGeneration else { return }
                    actionTasks[id] = nil
                    completion(nil)
                } catch is CancellationError {
                    return
                } catch {
                    guard let self, !Task.isCancelled, generation == currentGeneration else { return }
                    actionTasks[id] = nil
                    completion(.applicationMenuActionFailed(
                        appName: item.reference.name,
                        details: String(localized: action.failureDescription)
                    ))
                }
            }
        }
    }

    func stop() {
        generation = UUID()
        cancelAllDiscoveries()
        actionTasks.values.forEach { $0.cancel() }
        actionTasks.removeAll()
        Task { await windows.stop() }
    }
}

private extension ApplicationMenuAction {
    var failureDescription: LocalizedStringResource {
        switch self {
        case .showInFinder: .applicationMenuShowInFinderFailed
        case .setHidden(true): .applicationMenuHideFailed
        case .setHidden(false): .applicationMenuShowFailed
        case .bringAllToFront: .applicationMenuBringAllFailed
        case .quit: .applicationMenuQuitFailed
        case .selectWindow: .applicationMenuWindowFailed
        }
    }
}
