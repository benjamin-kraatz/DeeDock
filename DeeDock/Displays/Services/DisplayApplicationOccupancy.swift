import AppKit
import ScreenCaptureKit

/// Enumerates metadata only; no screenshots or native handles leave this actor.
actor DisplayApplicationOccupancyService {
    struct Snapshot: Equatable, Sendable {
        let applications: [UInt32: Set<String>]
        let windows: [DockWindowSnapshot]
    }

    func snapshot(identities: [pid_t: String], includeWindows: Bool) async throws -> Snapshot {
        guard CGPreflightScreenCaptureAccess() else { throw WindowThumbnailServiceError.permissionRequired }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        var result: [UInt32: Set<String>] = [:]
        var windows: [DockWindowSnapshot] = []
        for display in content.displays { result[display.displayID] = [] }
        let displays = Dictionary(uniqueKeysWithValues: content.displays.map { ($0.displayID, $0.frame) })
        for window in content.windows {
            guard window.isOnScreen, window.windowLayer == 0,
                  window.frame.width > 1, window.frame.height > 1,
                  let owner = window.owningApplication else { continue }
            guard let displayID = DockWindowDisplayAssignment.display(for: window.frame, among: displays) else { continue }
            if let identity = identities[owner.processID] {
                result[displayID, default: []].insert(identity)
                if includeWindows {
                    windows.append(DockWindowSnapshot(id: window.windowID, processIdentifier: owner.processID,
                        applicationID: identity, displayID: displayID,
                        title: (window.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines), frame: window.frame))
                }
            }
        }
        // Window-server stacking order changes on activation. Stable IDs prevent reshuffling
        // the group every time its user selects another window.
        return Snapshot(applications: result, windows: windows.sorted { $0.id < $1.id })
    }
}

/// One shared refresh loop for satellite filtering and optional window groups.
/// Workspace events request a refresh; a three-second bound also catches window moves
/// without requiring Accessibility. Cancellation rejects results after disabling or teardown.
@MainActor
final class DisplayApplicationOccupancy {
    var changed: (() -> Void)?
    private(set) var applications: [UInt32: Set<String>]?
    private(set) var windows: [DockWindowSnapshot] = []
    private var includesWindows = false
    private let service = DisplayApplicationOccupancyService()
    private var task: Task<Void, Never>?
    private var generation = UUID()

    func configure(enabled: Bool, includeWindows: Bool = false) {
        if !enabled { stop(); return }
        if includesWindows != includeWindows { stop(); includesWindows = includeWindows }
        guard task == nil else { return }
        let generation = generation
        task = Task { [weak self, service] in
            while !Task.isCancelled {
                guard let identities = self?.processIdentities() else { return }
                let snapshot = try? await service.snapshot(identities: identities, includeWindows: self?.includesWindows == true)
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                if applications != snapshot?.applications || windows != (snapshot?.windows ?? []) {
                    applications = snapshot?.applications
                    windows = snapshot?.windows ?? []
                    changed?()
                }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }

    /// Helpers nested inside a regular app bundle share its icon identity. Avoid guessing
    /// ownership from a name or bundle-ID prefix, which can conflate unrelated apps.
    private func processIdentities() -> [pid_t: String] {
        let processes = NSWorkspace.shared.runningApplications
        let regular = processes.filter { $0.activationPolicy == .regular && $0.bundleURL != nil }
        var result: [pid_t: String] = [:]
        for process in processes {
            guard !process.isHidden, let url = process.bundleURL?.standardizedFileURL else { continue }
            let owner = regular.first { candidate in
                guard let root = candidate.bundleURL?.standardizedFileURL else { return false }
                return candidate.processIdentifier == process.processIdentifier
                    || root == url || url.path.hasPrefix(root.path + "/")
            }
            guard let owner, !owner.isHidden, let root = owner.bundleURL else { continue }
            result[process.processIdentifier] = owner.bundleIdentifier ?? root.standardizedFileURL.path
        }
        return result
    }

    func invalidate() {
        let active = task != nil
        let previous = applications
        let previousWindows = windows
        stop()
        // Keep the published snapshot until its replacement arrives. A failed replacement
        // must transition from that snapshot to nil and notify the docks to restore fallback.
        applications = previous
        windows = previousWindows
        configure(enabled: active, includeWindows: includesWindows)
    }

    func stop() {
        generation = UUID()
        task?.cancel()
        task = nil
        applications = nil
        windows = []
    }
}
