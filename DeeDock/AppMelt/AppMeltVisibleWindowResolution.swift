import AppKit

extension AccessibilityApplicationWindowService {
    /// Initial pointer-based selection must resolve uniquely. From then on the pair owns exact
    /// retained AX tokens; no title guessing or replacement-window fallback is allowed.
    func meltResolveVisible(_ visible: [AppMeltVisibleWindow], sessionID: UUID) async throws -> [ApplicationWindowSummary] {
        let found = try await discover(processes: visible.map {
            ApplicationProcessSnapshot(processIdentifier: $0.pid, isHidden: false, isActive: false)
        }, sessionID: sessionID)
        return try visible.map { requested in
            let matches = found.filter {
                $0.processIdentifier == requested.pid && $0.frame.map { AppMeltGeometry.nearlyEqual($0, requested.frame) } == true
            }
            guard matches.count == 1, let window = matches.first,
                  !window.isMinimized, try actionCapabilities(window.token).canMove,
                  try actionCapabilities(window.token).canResize else { throw WindowActionError.unsupported }
            return window
        }
    }
}
