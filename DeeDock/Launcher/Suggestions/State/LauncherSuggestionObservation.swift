import AppKit

/// Catalog-owned lifecycle adapter. Reads idle duration only, never keyboard or pointer events.
/// Workspace application events are forwarded by the existing app-wide observer.
@MainActor
final class LauncherSuggestionObservation {
    private let store: LauncherSuggestionsStore
    private var observers: [NSObjectProtocol] = []
    private var maintenance: Task<Void, Never>?
    private var dwell: Task<Void, Never>?
    private var started = false
    private enum Suspension: Hashable { case systemSleep, screenSleep, inactiveSession }
    private var suspensions: Set<Suspension> = []
    private var suspended: Bool { !suspensions.isEmpty }

    init(store: LauncherSuggestionsStore) { self.store = store }

    func start() {
        guard !started else { return }
        started = true
        store.activityChanged = { [weak self] in self?.activityChanged() }
        let center = NSWorkspace.shared.notificationCenter
        let boundaries: [(Suspension, Notification.Name, Notification.Name)] = [
            (.systemSleep, NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification),
            (.screenSleep, NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification),
            (.inactiveSession, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification)
        ]
        for (reason, suspend, resume) in boundaries {
            observers.append(center.addObserver(forName: suspend, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.suspensions.insert(reason)
                    self?.dwell?.cancel()
                    self?.store.endSession()
                }
            })
            observers.append(center.addObserver(forName: resume, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // Display wake cannot resume an inactive login session or system sleep.
                    self?.suspensions.remove(reason)
                    self?.activityChanged()
                }
            })
        }
        activityChanged()
        maintenance = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self else { return }
                store.maintenance()
                if store.isActive, isIdle {
                    dwell?.cancel(); store.endSession()
                }
            }
        }
    }

    func workspaceEvent(_ notification: Notification) {
        guard store.isActive, !suspended,
              let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let id = identity(app) else { return }
        if isIdle { store.endSession(); return }
        if notification.name == NSWorkspace.didLaunchApplicationNotification {
            store.observeLaunch(appID: id, runningIDs: runningIDs)
        } else if notification.name == NSWorkspace.didTerminateApplicationNotification {
            store.observeTermination(appID: id, runningIDs: runningIDs)
        }
    }

    func activated(_ app: NSRunningApplication) {
        dwell?.cancel()
        store.maintenance()
        guard store.isActive, !suspended else { return }
        if isIdle { store.endSession(); return }
        if !store.hasSession {
            store.beginSession(foregroundID: identity(app), runningIDs: runningIDs)
        }
        store.observeActivation(appID: identity(app))
        let pid = app.processIdentifier
        dwell = Task { [weak self] in
            try? await Task.sleep(for: .seconds(LauncherSuggestionRecorder.dwell))
            guard !Task.isCancelled, let self, store.isActive, !suspended, !isIdle,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            store.settleActivation()
        }
    }

    private func activityChanged() {
        dwell?.cancel()
        guard started, store.isActive, !suspended, !isIdle else { return }
        store.beginSession(foregroundID: NSWorkspace.shared.frontmostApplication.flatMap(identity), runningIDs: runningIDs)
    }

    private var runningIDs: [String] {
        Array(Set(NSWorkspace.shared.runningApplications.compactMap(identity)))
    }

    private func identity(_ app: NSRunningApplication) -> String? {
        guard app.activationPolicy == .regular, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let id = app.bundleIdentifier, !id.isEmpty else { return nil }
        return id
    }

    private var isIdle: Bool {
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                             eventType: CGEventType(rawValue: UInt32.max)!)
        // An unavailable/invalid duration ends the session instead of inventing activity.
        return !seconds.isFinite || seconds < 0 || seconds >= LauncherSuggestionRecorder.sessionGap
    }

    func stop() {
        started = false
        dwell?.cancel(); dwell = nil
        maintenance?.cancel(); maintenance = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        suspensions.removeAll()
        store.stop()
    }
}
