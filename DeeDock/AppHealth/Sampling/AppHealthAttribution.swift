import Darwin

/// Decides which watched app a process belongs to. Pure, so the rules are testable without live processes.
///
/// Known limits: processes owned by another user are invisible to libproc, and system-owned helpers that launchd
/// starts from `/System/…` on an app's behalf (such as Safari's WebKit `WebContent` processes) match no app path,
/// so neither is attributed.
nonisolated enum AppHealthAttribution {
    enum Role: Sendable, Equatable {
        case main
        case helper
    }

    struct Owner: Sendable, Equatable {
        let app: String
        let role: Role
    }

    /// Guards the parent walk against a cycle in a parent map read mid-change.
    static let maximumDepth = 64

    /// The owner found by walking the parent chain in this tick's process table.
    ///
    /// A watched app's main process is `main`. Any other process whose ancestry reaches a main process is that
    /// app's `helper`. Nil when the walk ends at launchd (pid 1), at a process missing from the table, or at
    /// `maximumDepth`; the caller then tries `owner(executablePath:bundles:)`.
    ///
    /// - Parameters:
    ///   - parents: pid → parent pid, for this tick's same-user processes.
    ///   - mainProcesses: main pid → bundle identifier, for this tick's watched apps.
    static func owner(of pid: pid_t, parents: [pid_t: pid_t], mainProcesses: [pid_t: String]) -> Owner? {
        if let app = mainProcesses[pid] { return Owner(app: app, role: .main) }
        var current = pid
        for _ in 0..<maximumDepth {
            guard let parent = parents[current], parent > 1, parent != current else { return nil }
            if let app = mainProcesses[parent] { return Owner(app: app, role: .helper) }
            current = parent
        }
        return nil
    }

    /// The app whose bundle contains `path`, for helpers launchd starts from inside an app bundle (embedded XPC
    /// services, login items). The longest bundle path wins, so an app nested inside another app's bundle
    /// claims its own helpers.
    ///
    /// - Parameter bundles: Watched apps' bundle paths, standardized, without a trailing slash.
    static func owner(executablePath path: String, bundles: [(path: String, app: String)]) -> String? {
        var best: (length: Int, app: String)?
        for bundle in bundles where path.hasPrefix(bundle.path + "/") {
            if bundle.path.count > (best?.length ?? -1) { best = (bundle.path.count, bundle.app) }
        }
        return best?.app
    }
}
