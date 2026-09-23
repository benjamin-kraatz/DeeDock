import AppKit
import ApplicationServices

/// One retained pair-member element. Identity is the AX object the session already owns.
/// Title and frame are not consulted. The reference crosses to the main actor only so
/// notification registration can name that same object; this path does not set attributes
/// or the element's messaging timeout.
nonisolated struct AppMeltObservationTarget: @unchecked Sendable {
    let processIdentifier: pid_t
    let element: AXUIElement
}

/// Wakes minimize and layout readback after a move, resize, or minimize notification.
/// The closures are sendable and only touch main-actor state by awaiting it.
nonisolated struct AppMeltSettleWait: Sendable {
    let generation: @Sendable () async -> UInt64
    let wait: @Sendable (UInt64, Duration) async -> Bool
}

/// AX sources are installed only on the main run loop and removed before releasing the callback
/// context. Notifications are hints: the service revalidates exact source identity before acting.
/// Unchecked Sendable lets a settle wait hop back from the window-service actor. Mutable state
/// stays on the main actor.
@MainActor final class AppMeltObservation: @unchecked Sendable {
    private struct Waiter {
        let baseline: UInt64
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var observers: [AXObserver] = []
    private var registrations: [(AXObserver, AXUIElement)] = []
    private var observed: [AXUIElement] = []
    private var processes: Set<pid_t> = []
    private var epoch: UInt64 = 0
    private var settleGenerationValue: UInt64 = 0
    private var settleWaiters: [UUID: Waiter] = []
    private var signalQueued = false
    private var settleQueued = false
    var changed: (() -> Void)?

    private static let requiredWindowEvents = [
        kAXMovedNotification as String, kAXResizedNotification as String, kAXUIElementDestroyedNotification as String
    ]
    private static let windowEvents = requiredWindowEvents + [
        kAXWindowMiniaturizedNotification as String, kAXWindowDeminiaturizedNotification as String
    ]
    private static let applicationEvents = [
        kAXFocusedWindowChangedNotification as String, kAXWindowCreatedNotification as String
    ]
    private static let settleEvents: Set<String> = [
        kAXMovedNotification as String, kAXResizedNotification as String,
        kAXWindowMiniaturizedNotification as String, kAXWindowDeminiaturizedNotification as String
    ]

    var settleWait: AppMeltSettleWait {
        AppMeltSettleWait(
            generation: { [weak self] in
                guard let self else { return 0 }
                return await self.settleGeneration()
            },
            wait: { [weak self] baseline, timeout in
                guard let self else { return false }
                return await self.waitForSettle(after: baseline, timeout: timeout)
            }
        )
    }

    func settleGeneration() -> UInt64 { settleGenerationValue }

    /// Returns when `settleGeneration` moves past `baseline`, or when `timeout` elapses.
    /// A true result means a settle notification arrived. It does not mean the attribute is ready.
    func waitForSettle(after baseline: UInt64, timeout: Duration) async -> Bool {
        if settleGenerationValue != baseline { return true }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                settleWaiters[id] = Waiter(baseline: baseline, continuation: continuation)
                if settleGenerationValue != baseline {
                    completeSettleWait(id)
                    return
                }
                Task { @concurrent in
                    try? await Task.sleep(for: timeout)
                    await self.completeSettleWait(id)
                }
            }
        } onCancel: {
            Task { @MainActor in self.completeSettleWait(id) }
        }
    }

    /// Resolves retained handles on the window-service actor, then registers notifications for
    /// those elements only. Registration stays on the main run loop because that is the thread
    /// the callbacks are delivered on. `forceRestart` reinstalls even when the process ids match,
    /// which is required when a same-app replacement keeps the pid and changes the element.
    func start(tokens: [ApplicationWindowToken], service: AccessibilityApplicationWindowService,
               forceRestart: Bool = false) async throws -> Bool {
        let started = epoch
        let targets = try await service.meltObservationTargets(tokens)
        guard started == epoch, !Task.isCancelled else { throw CancellationError() }
        return install(targets, forceRestart: forceRestart)
    }

    func stop() {
        epoch &+= 1
        signalQueued = false
        settleQueued = false
        cancelSettleWaiters()
        for observer in observers {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        let names = Self.windowEvents + Self.applicationEvents
        for (observer, element) in registrations {
            for name in names { AXObserverRemoveNotification(observer, element, name as CFString) }
        }
        observers.removeAll()
        registrations.removeAll()
        observed.removeAll()
        processes.removeAll()
    }

    private func install(_ targets: [AppMeltObservationTarget], forceRestart: Bool) -> Bool {
        let requested = Set(targets.map(\.processIdentifier))
        guard !requested.isEmpty, !hasDuplicateElements(targets) else { stop(); return false }
        if !forceRestart, requested == processes, observers.count == requested.count, sameElements(targets) {
            return true
        }
        stop()
        let context = Unmanaged.passUnretained(self).toOpaque()
        for pid in requested {
            let members = targets.filter { $0.processIdentifier == pid }
            var observer: AXObserver?
            let status = AXObserverCreate(pid, { _, _, notification, rawContext in
                guard let rawContext else { return }
                let name = notification as String
                MainActor.assumeIsolated {
                    Unmanaged<AppMeltObservation>.fromOpaque(rawContext).takeUnretainedValue().scheduleSignal(name)
                }
            }, &observer)
            guard status == .success, let observer else { stop(); return false }
            for member in members {
                var supported = Set<String>()
                for event in Self.windowEvents {
                    if AXObserverAddNotification(observer, member.element, event as CFString, context) == .success {
                        supported.insert(event)
                    }
                }
                // Each retained member must accept the notifications itself. A sibling window
                // that supports them does not cover this element.
                guard Self.requiredWindowEvents.allSatisfy({ supported.contains($0) }) else { stop(); return false }
                registrations.append((observer, member.element))
            }
            let application = AXUIElementCreateApplication(pid)
            for event in Self.applicationEvents {
                if AXObserverAddNotification(observer, application, event as CFString, context) == .success {
                    registrations.append((observer, application))
                }
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            observers.append(observer)
        }
        processes = requested
        observed = targets.map(\.element)
        return true
    }

    private func hasDuplicateElements(_ targets: [AppMeltObservationTarget]) -> Bool {
        for index in targets.indices {
            for other in targets.indices where other > index {
                if CFEqual(targets[index].element, targets[other].element) { return true }
            }
        }
        return false
    }

    private func sameElements(_ targets: [AppMeltObservationTarget]) -> Bool {
        targets.count == observed.count && targets.allSatisfy { target in
            observed.contains { CFEqual($0, target.element) }
        }
    }

    /// Defer out of the AX callback. Resuming a settle wait from inside the callback can re-enter AX.
    private func scheduleSignal(_ name: String) {
        if Self.settleEvents.contains(name) { settleQueued = true }
        guard !signalQueued else { return }
        signalQueued = true
        let captured = epoch
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, captured == self.epoch else { return }
                self.signalQueued = false
                if self.settleQueued {
                    self.settleQueued = false
                    self.noteSettle()
                }
                self.changed?()
            }
        }
    }

    private func noteSettle() {
        settleGenerationValue &+= 1
        let pending = settleWaiters
        settleWaiters.removeAll()
        for waiter in pending.values { waiter.continuation.resume(returning: true) }
    }

    private func completeSettleWait(_ id: UUID) {
        guard let waiter = settleWaiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume(returning: settleGenerationValue != waiter.baseline)
    }

    private func cancelSettleWaiters() {
        let pending = settleWaiters
        settleWaiters.removeAll()
        for waiter in pending.values { waiter.continuation.resume(returning: false) }
    }
}

extension AccessibilityApplicationWindowService {
    /// Looks up the pair's retained elements on this actor. It does not copy `AXWindows`.
    func meltObservationTargets(_ tokens: [ApplicationWindowToken]) throws -> [AppMeltObservationTarget] {
        try Task.checkCancellation()
        guard !tokens.isEmpty else { throw WindowActionError.unsupported }
        for token in tokens { try ensureSessionOpen(token.sessionID) }
        guard AXIsProcessTrusted() else { throw WindowActionError.permission }
        return try tokens.map { token in
            let handle = try validatedHandle(token, allowRetainedWindow: true)
            return AppMeltObservationTarget(processIdentifier: handle.processIdentifier, element: handle.element)
        }
    }
}
