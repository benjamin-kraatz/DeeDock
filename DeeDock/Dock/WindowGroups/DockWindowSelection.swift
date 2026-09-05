import AppKit
import ScreenCaptureKit

/// Resolves a fresh, unambiguous Accessibility handle at click time. A stale tile must never
/// activate an arbitrary sibling window. AX sessions are independent of menus and Peek.
actor DockWindowSelectionService {
    private let windows = AccessibilityApplicationWindowService()

    func select(_ snapshot: DockWindowSnapshot) async throws {
        guard CGPreflightScreenCaptureAccess() else { throw WindowThumbnailServiceError.permissionRequired }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        guard content.windows.contains(where: {
            $0.windowID == snapshot.id && $0.owningApplication?.processID == snapshot.processIdentifier
        }) else { throw ApplicationWindowServiceError.windowUnavailable }
        let candidates = content.windows.compactMap { window -> WindowCaptureCandidate? in
            guard window.owningApplication?.processID == snapshot.processIdentifier else { return nil }
            return WindowCaptureCandidate(id: window.windowID, processIdentifier: snapshot.processIdentifier,
                title: window.title, frame: window.frame, isOnScreen: window.isOnScreen)
        }
        let session = UUID()
        do {
            let summaries = try await windows.discover(processes: [ApplicationProcessSnapshot(
                processIdentifier: snapshot.processIdentifier, isHidden: false, isActive: false)], sessionID: session)
            try Task.checkCancellation()
            let matches = WindowThumbnailMatcher.matches(summaries: summaries, candidates: candidates)
                .filter { $0.value == snapshot.id }
            guard matches.count == 1, let token = matches.keys.first else {
                throw ApplicationWindowServiceError.windowUnavailable
            }
            try Task.checkCancellation()
            try await windows.selectWindow(token)
            await windows.discard(sessionID: session)
        } catch {
            await windows.discard(sessionID: session)
            throw error
        }
    }
}

/// One panel-owned selection task, cancelled on replacement, disable, and panel teardown.
@MainActor
final class DockWindowSelection {
    private let service = DockWindowSelectionService()
    private var task: Task<Void, Never>?

    func select(_ window: DockWindowSnapshot, completion: @escaping (Bool) -> Void) {
        stop()
        task = Task { [weak self, service] in
            guard self != nil else { return }
            let succeeded: Bool
            do { try await service.select(window); succeeded = true }
            catch { succeeded = false }
            guard !Task.isCancelled else { return }
            self?.task = nil
            completion(succeeded)
        }
    }

    func stop() { task?.cancel(); task = nil }
}
