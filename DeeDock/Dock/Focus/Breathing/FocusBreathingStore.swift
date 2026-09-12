import AppKit
import AppIntents
import Observation

/// App-wide opt-in preferences and the current public Focus filter signal.
/// System Focus state is queried afresh, never restored from a cached preference.
@MainActor @Observable
final class FocusBreathingStore {
    /// App Intents and the dock share this instance. Previews use an in-memory instance instead.
    static let shared = FocusBreathingStore(defaults: .standard)
    static let defaultIntensity = 30.0
    private(set) var enabled: Bool
    private(set) var intensity: Double
    private(set) var usesFocusSessions: Bool
    private(set) var modeIDs: Set<String>
    private(set) var systemFocusActive = false
    private(set) var suspended = false
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var revision = 0
    private static let prefix = "dock.focus-breathing."

    /// Nil defaults keep previews and injected instances independent of real preferences.
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        enabled = defaults?.bool(forKey: Self.prefix + "enabled") ?? false
        let saved = defaults?.object(forKey: Self.prefix + "intensity") as? Double
        intensity = Self.clamp(saved ?? Self.defaultIntensity)
        usesFocusSessions = defaults?.object(forKey: Self.prefix + "sessions") as? Bool ?? true
        modeIDs = Set(defaults?.stringArray(forKey: Self.prefix + "modes") ?? [])
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        defaults?.set(value, forKey: Self.prefix + "enabled")
        if value { refreshSystemFocus() }
        else { cancelRefresh(); systemFocusActive = false }
    }

    func setIntensity(_ value: Double) {
        intensity = Self.clamp(value)
        defaults?.set(intensity, forKey: Self.prefix + "intensity")
    }

    func setUsesFocusSessions(_ value: Bool) {
        usesFocusSessions = value
        defaults?.set(value, forKey: Self.prefix + "sessions")
    }

    func setMode(_ id: UUID, enabled: Bool) {
        if enabled { modeIDs.insert(id.uuidString) }
        else { modeIDs.remove(id.uuidString) }
        defaults?.set(modeIDs.sorted(), forKey: Self.prefix + "modes")
    }

    /// Only explicitly selected modes count. Every installation has a default active mode.
    func isActive(modeID: UUID?, sessionRunning: Bool) -> Bool {
        enabled && !suspended && (systemFocusActive
            || (usesFocusSessions && sessionRunning)
            || modeID.map { modeIDs.contains($0.uuidString) } == true)
    }

    /// Receives both configured values and the default false value on Focus exit.
    func receiveSystemFocus(_ active: Bool) {
        cancelRefresh()
        systemFocusActive = enabled && active
    }

    func start() {
        guard observers.isEmpty else { return }
        suspended = false
        observe(.default, NSApplication.didBecomeActiveNotification) { $0.refreshSystemFocus() }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observe(workspace, name) { store in
                store.suspended = true
                store.cancelRefresh()
                store.systemFocusActive = false
            }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(workspace, name) { store in
                store.suspended = false
                store.refreshSystemFocus()
            }
        }
        refreshSystemFocus()
    }

    func stop() {
        suspended = true
        cancelRefresh()
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        systemFocusActive = false
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping @MainActor (FocusBreathingStore) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !observers.isEmpty else { return }
                action(self)
            }
        }
        observers.append((center, token))
    }

    private func refreshSystemFocus() {
        cancelRefresh()
        guard enabled, !suspended, defaults != nil else { return }
        let requestedRevision = revision
        refreshTask = Task { [weak self] in
            let filter = try? await DockFocusFilterIntent.current
            guard !Task.isCancelled, let self, revision == requestedRevision else { return }
            systemFocusActive = filter?.breathe ?? false
            refreshTask = nil
        }
    }

    private func cancelRefresh() {
        // A delivered intent must win over an older asynchronous current-filter query.
        revision += 1
        refreshTask?.cancel()
        refreshTask = nil
    }

    private static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(100, max(0, value)) : defaultIntensity
    }
}
