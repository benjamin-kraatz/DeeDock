import AppKit
import ScreenCaptureKit

/// Enumerates metadata only. Window titles, screenshots, and native handles are never retained.
actor DisplayApplicationOccupancyService {
    func applicationsByDisplay(identities: [pid_t: String]) async throws -> [UInt32: Set<String>] {
        guard CGPreflightScreenCaptureAccess() else { throw WindowThumbnailServiceError.permissionRequired }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        var result: [UInt32: Set<String>] = [:]
        for display in content.displays { result[display.displayID] = [] }
        let displays = content.displays.sorted { $0.displayID < $1.displayID }
        for window in content.windows {
            guard window.isOnScreen, window.windowLayer == 0,
                  window.frame.width > 1, window.frame.height > 1,
                  let owner = window.owningApplication else { continue }
            // Both frames use Quartz coordinates. Largest overlap assigns a spanning window
            // once; display ID breaks equal-area ties deterministically.
            let display = displays.max {
                Self.area(window.frame.intersection($0.frame)) < Self.area(window.frame.intersection($1.frame))
            }
            guard let display, Self.area(window.frame.intersection(display.frame)) > 0 else { continue }
            if let identity = identities[owner.processID] {
                result[display.displayID, default: []].insert(identity)
            }
        }
        return result
    }

    private static func area(_ frame: CGRect) -> CGFloat { frame.isNull ? 0 : frame.width * frame.height }
}

/// One shared refresh loop, active only while satellite filtering is useful.
/// Workspace events request a refresh; a three-second bound also catches window moves
/// without requiring Accessibility. Cancellation rejects results after disabling or teardown.
@MainActor
final class DisplayApplicationOccupancy {
    var changed: (() -> Void)?
    private(set) var applications: [UInt32: Set<String>]?
    private let service = DisplayApplicationOccupancyService()
    private var task: Task<Void, Never>?
    private var generation = UUID()

    func configure(enabled: Bool) {
        if !enabled { stop(); return }
        guard task == nil else { return }
        let generation = generation
        task = Task { [weak self, service] in
            while !Task.isCancelled {
                guard let identities = self?.processIdentities() else { return }
                let snapshot = try? await service.applicationsByDisplay(identities: identities)
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                if applications != snapshot { applications = snapshot; changed?() }
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
        stop()
        // Keep the published snapshot until its replacement arrives. A failed replacement
        // must transition from that snapshot to nil and notify the docks to restore fallback.
        applications = previous
        configure(enabled: active)
    }

    func stop() {
        generation = UUID()
        task?.cancel()
        task = nil
        applications = nil
    }
}
