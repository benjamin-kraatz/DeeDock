import ExtensionFoundation
import Foundation
import os

/// What the system reports about DOKK's plugins: the enabled ones by identity, the rest as counts.
///
/// ExtensionKit names only enabled plugins. A plugin waiting for approval or turned off in the
/// system window is counted but never identified, so DOKK can say "2 waiting" but not which.
struct DockPluginInventory: Equatable {
    var enabled: [AppExtensionIdentity] = []
    /// Installed plugins the person has not turned on yet.
    var waiting = 0
    /// Plugins the person turned off.
    var disabled = 0

    static let empty = DockPluginInventory()
}

/// Watches DOKK's extension point and reports every change to its plugins.
///
/// A running `AppExtensionPoint.Monitor` publishes approval changes but not installs or removals
/// (the plugin spike saw neither while the host ran), so ``rescan()`` replaces the monitor with a
/// fresh one. The owner calls it when DOKK comes to the front and when the Plugins page opens.
/// Owns its monitor task; ``stop()`` cancels it.
@MainActor
final class DockPluginDiscovery {
    /// Receives every inventory, starting with the first one each monitor reports.
    var changed: ((DockPluginInventory) -> Void)?

    private var task: Task<Void, Never>?
    /// Kept so the monitor outlives the task's first suspension.
    private var monitor: AppExtensionPoint.Monitor?
    /// Each rescan bumps this, so a slow monitor that finishes after a newer one never reports.
    private var generation = 0
    private var lastScan: ContinuousClock.Instant?
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DOKK", category: "Plugins")

    /// Starts watching. Calling it again rescans.
    func start() { rescan(force: true) }

    /// Replaces the monitor so installs and removals since the last scan show up.
    /// - Parameter force: Rescans even when the last scan was moments ago. App activation can
    ///   arrive in bursts, so unforced rescans are spaced at least two seconds apart.
    func rescan(force: Bool = false) {
        let now = ContinuousClock.now
        if !force, let lastScan, now - lastScan < .seconds(2) { return }
        lastScan = now
        generation += 1
        let generation = generation
        task?.cancel()
        task = Task { [weak self] in
            do {
                let point = try AppExtensionPoint.dokkPlugin()
                let monitor = try await AppExtensionPoint.Monitor(appExtensionPoint: point)
                guard !Task.isCancelled, self?.generation == generation else { return }
                self?.monitor = monitor
                // Observations re-reads `state` after each change the monitor publishes; no polling.
                for await state in Observations({ monitor.state }) {
                    guard !Task.isCancelled, let self, self.generation == generation else { return }
                    self.changed?(DockPluginInventory(enabled: state.identities, waiting: state.unapprovedCount,
                                                      disabled: state.disabledCount))
                }
            } catch {
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                Self.logger.error("Plugin discovery failed: \(String(describing: error), privacy: .public)")
                // A failed rescan keeps the last known inventory: reporting empty would end every
                // running plugin. Before the first scan, empty lets Settings stop showing "looking".
                if self.monitor == nil { self.changed?(.empty) }
            }
        }
    }

    func stop() {
        generation += 1
        task?.cancel()
        task = nil
        monitor = nil
        changed = nil
    }
}
