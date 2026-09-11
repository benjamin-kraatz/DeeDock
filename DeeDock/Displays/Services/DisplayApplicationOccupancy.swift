import AppKit
import ScreenCaptureKit

/// Enumerates metadata only. Window titles, screenshots, and native handles are never retained.
actor DisplayApplicationOccupancyService {
    /// Processes owning an on-screen, normal-layer window, grouped by the display showing most of each window.
    func processesByDisplay() async throws -> [UInt32: Set<pid_t>] {
        guard CGPreflightScreenCaptureAccess() else { throw WindowThumbnailServiceError.permissionRequired }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        var result: [UInt32: Set<pid_t>] = [:]
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
            result[display.displayID, default: []].insert(owner.processID)
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
    /// Application identity per window-owning process; `nil` records a process that belongs to no regular
    /// application. A process's bundle never changes, but an owner can quit or change activation policy, so
    /// workspace changes clear this through `invalidate()`.
    private var identities: [pid_t: String?] = [:]

    func configure(enabled: Bool) {
        if !enabled { stop(); return }
        guard task == nil else { return }
        let generation = generation
        task = Task { [weak self, service] in
            while !Task.isCancelled {
                let processes = try? await service.processesByDisplay()
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                let snapshot = processes.map(resolve)
                if applications != snapshot { applications = snapshot; changed?() }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }

    /// Maps window-owning processes to application identities. Only processes with on-screen windows are
    /// resolved, and each only once: `NSRunningApplication` properties are LaunchServices round trips, and
    /// standardizing bundle URLs touches the file system. Hidden applications need no check here, because
    /// their windows are off screen and the enumeration asks for on-screen windows only.
    private func resolve(_ processes: [UInt32: Set<pid_t>]) -> [UInt32: Set<String>] {
        let current = processes.values.reduce(into: Set<pid_t>()) { $0.formUnion($1) }
        identities = identities.filter { current.contains($0.key) }
        var roots: [(pid: pid_t, path: String, identity: String)]?
        for pid in current where identities[pid] == nil {
            if roots == nil { roots = Self.regularRoots() }
            identities[pid] = Self.identity(of: pid, in: roots ?? [])
        }
        return processes.mapValues { pids in Set(pids.compactMap { identities[$0] ?? nil }) }
    }

    private static func regularRoots() -> [(pid: pid_t, path: String, identity: String)] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let url = app.bundleURL?.standardizedFileURL else { return nil }
            return (app.processIdentifier, url.path, app.bundleIdentifier ?? url.path)
        }
    }

    /// Helpers nested inside a regular app bundle share its icon identity. Avoid guessing
    /// ownership from a name or bundle-ID prefix, which can conflate unrelated apps.
    private static func identity(of pid: pid_t, in roots: [(pid: pid_t, path: String, identity: String)]) -> String? {
        if let own = roots.first(where: { $0.pid == pid }) { return own.identity }
        guard let path = NSRunningApplication(processIdentifier: pid)?.bundleURL?.standardizedFileURL.path else {
            return nil
        }
        return roots.first { $0.path == path || path.hasPrefix($0.path + "/") }?.identity
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
        identities = [:]
    }
}
