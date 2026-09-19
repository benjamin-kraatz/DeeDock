import AppKit
import Observation

/// Explicit, presentation-scoped discovery. No polling or app launching is involved.
@MainActor @Observable final class AppMeltWindowPickerState {
    struct Group: Identifiable {
        let id: pid_t
        let name: String
        let windows: [ApplicationWindowSummary]
    }
    var isPresented = false {
        didSet {
            if oldValue != isPresented {
                if !isPresented { cancel() }
                pair?.chromeInteractionChanged?()
            }
        }
    }
    var side = 0
    @ObservationIgnored var discoveryFinished: (() -> Void)?
    @ObservationIgnored var selected: ((ApplicationWindowSummary) -> Void)?
    var preferredApplication: URL?
    var groups: [Group] = []
    var blockedApps: Set<pid_t> = []
    var unavailable: Set<ApplicationWindowToken> = []
    var busy = false
    var message: LocalizedStringResource?
    @ObservationIgnored private weak var pair: AppMeltPair?
    @ObservationIgnored private weak var controller: AppMeltController?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var sessions: [UUID] = []
    @ObservationIgnored private var attempt = UUID()

    init(pair: AppMeltPair, controller: AppMeltController) {
        self.pair = pair; self.controller = controller
    }

    init(controller: AppMeltController) { self.controller = controller }

    func refresh() {
        cancel()
        guard let controller, pair?.canChangeLayout != false else { return }
        busy = true
        message = nil
        blockedApps = Set(controller.pairs.filter { $0.id != pair?.id }.flatMap { $0.windows.map(\.processIdentifier) })
        let id = attempt
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }.sorted {
            let firstPreferred = preferredApplication != nil && $0.bundleURL?.standardizedFileURL == preferredApplication?.standardizedFileURL
            let secondPreferred = preferredApplication != nil && $1.bundleURL?.standardizedFileURL == preferredApplication?.standardizedFileURL
            if firstPreferred != secondPreferred { return firstPreferred }
            let left = controller.recentApplicationUse[$0.processIdentifier] ?? .distantPast
            let right = controller.recentApplicationUse[$1.processIdentifier] ?? .distantPast
            if left != right { return left > right }
            if $0.isActive != $1.isActive { return $0.isActive }
            return ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending
        }
        task = Task { [weak self] in
            guard let self else { return }
            var failed = false
            for app in apps {
                guard !Task.isCancelled, attempt == id else { return }
                let session = UUID()
                sessions.append(session)
                do {
                    let found = try await controller.service.discover(processes: [ApplicationProcessSnapshot(
                        processIdentifier: app.processIdentifier, isHidden: app.isHidden, isActive: app.isActive)],
                        sessionID: session)
                    try Task.checkCancellation()
                    guard attempt == id else { return }
                    for window in found {
                        if try await controller.service.meltIsPaired(window.token, existing: controller.pairs.flatMap(\.tokens)) {
                            unavailable.insert(window.token)
                        }
                    }
                    try Task.checkCancellation()
                    guard attempt == id else { return }
                    if !found.isEmpty {
                        groups.append(Group(id: app.processIdentifier,
                            name: app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? "",
                            windows: found))
                    }
                } catch is CancellationError { return }
                catch { failed = true }
            }
            guard attempt == id else { return }
            busy = false
            if failed { message = .meltReplacementPartial }
            discoveryFinished?()
        }
    }

    func choose(_ window: ApplicationWindowSummary) {
        guard !busy else { return }
        if let selected { selected(window) }
        else if let pair, let controller { controller.replaceWindow(pair, side: side, with: window) }
    }

    func cancel() {
        attempt = UUID()
        task?.cancel(); task = nil
        groups = []; unavailable = []; busy = false
        let old = sessions
        sessions = []
        if let service = controller?.service {
            Task { for session in old { await service.discard(sessionID: session) } }
        }
    }
}
